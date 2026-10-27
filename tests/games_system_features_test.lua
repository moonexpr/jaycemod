local T = dofile("tests/harness.lua")
local Features = system.features

local SH, SV, CL = Features.SHARED, Features.SERVER, Features.CLIENT

-- A fake file port: `files` maps a feature path to the function its file runs.
-- Records every file run and every feature the server tells clients about.
local function FakePort(files)
	local port = {
		runs = {},
		told = {},
	}
	function port:Exists(path)
		return files[path] ~= nil
	end
	function port:Run(path)
		self.runs[#self.runs + 1] = path
		return files[path]()
	end
	function port:TellClients(name)
		self.told[#self.told + 1] = name
	end
	return port
end

local function Returns(value)
	return function() return value end
end

local function List(t)
	local parts = {}
	for i, v in ipairs(t) do parts[i] = tostring(v) end
	return table.concat(parts, ",")
end

local function ErrorOf(fn)
	local ok, err = pcall(fn)
	T.eq(ok, false, "call errors")
	return tostring(err)
end

local function Has(text, fragment, what)
	if not text:find(fragment, 1, true) then
		error(string.format("%s: %q not in %q", what or "text", fragment, text), 2)
	end
end

local P = Features.PartPath

T.test("part paths follow features/<name>/<part>.lua", function()
	T.eq(P("npc", SV), "features/npc/sv.lua")
	T.eq(P("npc", CL), "features/npc/cl.lua")
	T.eq(P("npc", SH), "features/npc/sh.lua")
end)

-- Server ------------------------------------------------------------------

T.test("server: first call loads sh then sv and returns the controller", function()
	local controller = {}
	local port = FakePort({
		[P("npc", SH)] = Returns(true),
		[P("npc", SV)] = Returns(controller),
	})
	local loader = Features.New(SV, port)
	T.eq(loader:Feature("npc"), controller, "controller")
	T.eq(List(port.runs), P("npc", SH) .. "," .. P("npc", SV), "runs")
	T.eq(List(loader:Loaded()), "npc", "loaded")
end)

T.test("server: later calls return the same controller without loading again", function()
	local controller = {}
	local port = FakePort({ [P("npc", SV)] = Returns(controller) })
	local loader = Features.New(SV, port)
	loader:Feature("npc")
	T.eq(loader:Feature("npc"), controller, "same controller")
	T.eq(#port.runs, 1, "sv ran once")
	T.eq(List(loader:Loaded()), "npc", "recorded once")
end)

T.test("whether a feature is loaded can be asked without loading it", function()
	local port = FakePort({ [P("npc", SV)] = Returns({}) })
	local loader = Features.New(SV, port)
	T.eq(loader:IsLoaded("npc"), false, "not yet")
	T.eq(#port.runs, 0, "and asking loads nothing")
	loader:Feature("npc")
	T.eq(loader:IsLoaded("npc"), true, "loaded")
end)

T.test("server: the shared part is optional", function()
	local port = FakePort({ [P("combat", SV)] = Returns({}) })
	Features.New(SV, port):Feature("combat")
	T.eq(List(port.runs), P("combat", SV), "only sv ran")
end)

T.test("server: an unknown feature errors naming its missing sv.lua", function()
	local port = FakePort({})
	local loader = Features.New(SV, port)
	Has(ErrorOf(function() loader:Feature("nope") end), P("nope", SV), "error")
	T.eq(#loader:Loaded(), 0, "nothing recorded")
end)

T.test("server: a feature with a client part but no sv.lua is unknown to the server", function()
	local port = FakePort({
		[P("hud", SH)] = Returns(true),
		[P("hud", CL)] = Returns({}),
	})
	local loader = Features.New(SV, port)
	Has(ErrorOf(function() loader:Feature("hud") end), P("hud", SV), "error")
	T.eq(#port.runs, 0, "sh did not run either")
end)

T.test("server: an sv.lua that returns no table errors naming the file", function()
	local port = FakePort({ [P("npc", SV)] = Returns(nil) })
	local loader = Features.New(SV, port)
	Has(ErrorOf(function() loader:Feature("npc") end), P("npc", SV), "error")
end)

T.test("server: tells clients about each new feature with a client part, once, in load order", function()
	local port = FakePort({
		[P("npc", SV)] = Returns({}),
		[P("npc", CL)] = Returns({}),
		[P("combat", SV)] = Returns({}),
		[P("holiday", SV)] = Returns({}),
		[P("holiday", SH)] = Returns(true),
	})
	local loader = Features.New(SV, port)
	loader:Feature("npc")
	loader:Feature("combat")
	loader:Feature("holiday")
	loader:Feature("npc")
	T.eq(List(port.told), "npc,holiday", "told")
end)

T.test("server: a joining client receives every loaded feature with a client part, in load order", function()
	local port = FakePort({
		[P("npc", SV)] = Returns({}),
		[P("npc", CL)] = Returns({}),
		[P("combat", SV)] = Returns({}),
		[P("spells", SV)] = Returns({}),
		[P("spells", CL)] = Returns({}),
	})
	local loader = Features.New(SV, port)
	T.eq(#loader:ClientFeatures(), 0, "none before any load")
	loader:Feature("spells")
	loader:Feature("combat")
	loader:Feature("npc")
	T.eq(List(loader:ClientFeatures()), "spells,npc", "client features")
	T.eq(List(loader:Loaded()), "spells,combat,npc", "all loaded")
end)

-- Dependencies -------------------------------------------------------------

T.test("a feature that depends on another loads it first, and it loads once", function()
	local loader
	local port = FakePort({
		[P("combat", SV)] = Returns({}),
		[P("combat", CL)] = Returns({}),
		[P("npc", SV)] = function() loader:Feature("combat"); return {} end,
		[P("npc", CL)] = Returns({}),
		[P("spells", SH)] = function() loader:Feature("combat"); return true end,
		[P("spells", SV)] = function() loader:Feature("npc"); return {} end,
		[P("spells", CL)] = Returns({}),
	})
	loader = Features.New(SV, port)
	loader:Feature("spells")
	T.eq(List(loader:Loaded()), "combat,npc,spells", "dependencies first")
	T.eq(List(port.told), "combat,npc,spells", "clients told in the same order")
	T.eq(List(port.runs), List({ P("spells", SH), P("combat", SV), P("spells", SV), P("npc", SV) }), "each server file ran once, in start order")
end)

T.test("a feature that requires itself while loading errors, naming it", function()
	local loader
	local port = FakePort({
		[P("a", SV)] = function() loader:Feature("b"); return {} end,
		[P("b", SV)] = function() loader:Feature("a"); return {} end,
	})
	loader = Features.New(SV, port)
	Has(ErrorOf(function() loader:Feature("a") end), '"a"', "error")
	T.eq(#loader:Loaded(), 0, "neither recorded")
end)

T.test("a feature whose load failed names its own error on every later call, and runs no part again", function()
	local port = FakePort({
		[P("war", SV)] = function() error("the war needs the speech addon", 0) end,
	})
	local loader = Features.New(SV, port)
	Has(ErrorOf(function() loader:Feature("war") end), "the war needs the speech addon", "the first call")
	local later = ErrorOf(function() loader:Feature("war") end)
	Has(later, "the war needs the speech addon", "a later call")
	Has(later, '"war"', "naming the feature")
	T.eq(#port.runs, 1, "its part ran once")
	T.eq(loader:IsLoaded("war"), false, "not loaded")
end)

-- Client ------------------------------------------------------------------

T.test("client: loads sh then cl once and returns the view", function()
	local view = {}
	local port = FakePort({
		[P("npc", SH)] = Returns(true),
		[P("npc", CL)] = Returns(view),
	})
	local loader = Features.New(CL, port)
	T.eq(loader:Feature("npc"), view, "view")
	T.eq(loader:Feature("npc"), view, "same view")
	T.eq(List(port.runs), P("npc", SH) .. "," .. P("npc", CL), "runs")
	T.eq(List(loader:Loaded()), "npc", "loaded")
end)

T.test("client: a feature with only a shared part loads it and has no view", function()
	local port = FakePort({ [P("holiday", SH)] = Returns(true) })
	local loader = Features.New(CL, port)
	T.eq(loader:Feature("holiday"), nil, "no view")
	loader:Feature("holiday")
	T.eq(List(port.runs), P("holiday", SH), "sh ran once")
	T.eq(List(loader:Loaded()), "holiday", "loaded")
end)

T.test("client: a feature with neither cl.lua nor sh.lua errors naming both", function()
	local loader = Features.New(CL, FakePort({}))
	local err = ErrorOf(function() loader:Feature("combat") end)
	Has(err, P("combat", CL), "error")
	Has(err, P("combat", SH), "error")
end)

T.test("client: a cl.lua that returns no table errors naming the file", function()
	local loader = Features.New(CL, FakePort({ [P("npc", CL)] = Returns(nil) }))
	Has(ErrorOf(function() loader:Feature("npc") end), P("npc", CL), "error")
end)

T.test("client: never tells anyone", function()
	local port = FakePort({ [P("npc", CL)] = Returns({}) })
	Features.New(CL, port):Feature("npc")
	T.eq(#port.told, 0, "told")
end)

-- Records -----------------------------------------------------------------

T.test("the loaded list is a copy", function()
	local loader = Features.New(SV, FakePort({ [P("npc", SV)] = Returns({}) }))
	loader:Feature("npc")
	loader:Loaded()[2] = "forged"
	loader:ClientFeatures()[1] = "forged"
	T.eq(List(loader:Loaded()), "npc", "loaded")
	T.eq(#loader:ClientFeatures(), 0, "client features")
end)

T.test("the memory report gives KB and the loaded features in order", function()
	local loader = Features.New(SV, FakePort({
		[P("combat", SV)] = Returns({}),
		[P("npc", SV)] = Returns({}),
	}))
	loader:Feature("npc")
	loader:Feature("combat")
	local report = loader:MemoryReport(2048.25, 1024.5)
	Has(report, "2048 KB", "report")
	Has(report, "1024 KB", "report")
	Has(report, "npc, combat", "report")
	Has(Features.New(CL, FakePort({})):MemoryReport(1, 1), "none", "empty report")
end)

-- A feature on Features.OFF is switched off: asking for it refuses by name
-- and runs none of its files.
T.test("a feature that is off is refused and none of its files run", function()
	local port = FakePort({ [Features.PartPath("nodegraph", SV)] = Returns({}) })
	local loader = Features.New(SV, port)
	T.eq(Features.OFF.nodegraph, true, "the node graph is off for now")
	T.eq(ErrorOf(function() loader:Feature("nodegraph") end), 'feature "nodegraph" is switched off (games.system.features OFF)')
	T.eq(#port.runs, 0, "nothing ran")
	T.eq(loader:IsLoaded("nodegraph"), false)
end)

-- Realms and shipping --------------------------------------------------------

T.test("a file's realm is its exact root name or its realm prefix", function()
	T.eq(Features.Realm("sv.lua"), SV, "sv.lua")
	T.eq(Features.Realm("sv_soldier.lua"), SV, "sv_soldier.lua")
	T.eq(Features.Realm("sv_.lua"), SV, "a malformed sv_ name is still server")
	T.eq(Features.Realm("cl.lua"), CL, "cl.lua")
	T.eq(Features.Realm("cl_hud.lua"), CL, "cl_hud.lua")
	T.eq(Features.Realm("sh.lua"), SH, "sh.lua")
	T.eq(Features.Realm("sh_events.lua"), SH, "sh_events.lua")
end)

T.test("a file with no realm prefix is a module", function()
	T.eq(Features.Realm("model.lua"), nil, "model.lua")
	T.eq(Features.Realm("on_holiday.lua"), nil, "on_holiday.lua")
	T.eq(Features.Realm("sound_paths.lua"), nil, "sound_paths.lua")
	T.eq(Features.Realm("svc.lua"), nil, "svc.lua starts with sv but not sv_")
end)

T.test("every file ships except a server one", function()
	T.eq(Features.Ships("sv.lua"), false, "sv.lua")
	T.eq(Features.Ships("sv_soldier.lua"), false, "sv_soldier.lua")
	T.eq(Features.Ships("cl.lua"), true, "cl.lua")
	T.eq(Features.Ships("sh_events.lua"), true, "sh_events.lua")
	T.eq(Features.Ships("model.lua"), true, "model.lua")
end)

-- A fake folder port: `tree` maps a folder ("features/a/") to its file names
-- and its subfolder names, as file.Find returns them.
local function TreePort(tree)
	local port = {}
	function port:Find(dir)
		local entry = tree[dir] or {
			files = {},
			dirs = {},
		}
		return entry.files, entry.dirs
	end
	return port
end

T.test("client files: every shipping .lua file under the folders, recursively, sorted", function()
	local port = TreePort({
		["foundation/"] = {
			files = { "sample.lua" },
			dirs = {},
		},
		["features/"] = {
			files = {},
			dirs = { "b", "a" },
		},
		["features/a/"] = {
			files = { "sv.lua", "sv_x.lua", "sh.lua", "cl.lua", "cl_x.lua", "model.lua", "notes.txt" },
			dirs = { "scenario" },
		},
		["features/a/scenario/"] = {
			files = { "koth.lua" },
			dirs = {},
		},
		["features/b/"] = {
			files = { "sv.lua" },
			dirs = {},
		},
		["ws/"] = {
			files = { "sv_world.lua", "sound_paths.lua", "sh_core.lua" },
			dirs = {},
		},
	})
	T.eq(List(Features.ClientFiles(port, { "ws/", "features/", "foundation/" })), List({
		"features/a/cl.lua",
		"features/a/cl_x.lua",
		"features/a/model.lua",
		"features/a/scenario/koth.lua",
		"features/a/sh.lua",
		"foundation/sample.lua",
		"ws/sh_core.lua",
		"ws/sound_paths.lua",
	}))
end)

T.test("client files walk the gamemode's six folders", function()
	T.eq(List(Features.CLIENT_DIRS), "foundation/,games/,nextsoldier/,features/,ws/,vendor/")
end)

-- Realm parts ----------------------------------------------------------------

T.test("a part's file sits beside its root", function()
	T.eq(Features.PartFile("aiwar", "sv_map"), "features/aiwar/sv_map.lua")
	T.eq(Features.PartFile("boss_timer", "cl_hud_bar"), "features/boss_timer/cl_hud_bar.lua")
	T.eq(Features.PartFile("rounds", "sh_events"), "features/rounds/sh_events.lua")
end)

T.test("a name that is not <realm>_<part> is refused as a part", function()
	for _, part in ipairs({ "soldier", "../x", "sv_a.b", "sv_", "sv", "on_holiday", "sv_../x" }) do
		T.eq(ErrorOf(function() Features.PartFile("aiwar", part) end), "not a feature part: " .. part, part)
	end
end)

-- A fake compile port: `chunks` maps a path to its chunk; records each path
-- compiled.
local function CompilePort(chunks)
	local port = { compiled = {} }
	function port:Compile(path)
		self.compiled[#self.compiled + 1] = path
		return chunks[path]
	end
	return port
end

T.test("a part runs its file's chunk in the env it was given, with the arguments, and returns its values", function()
	local seen = {}
	local chunk = function(...)
		seen.marker = MARKER -- a global: read from the chunk's env
		seen.args = { ... }
		return "map", "extra"
	end
	local port = CompilePort({ ["features/aiwar/sv_map.lua"] = chunk })
	local env = { MARKER = "the root's env" }
	local Part = Features.Parts(port, env, "aiwar")
	local controller = {}
	local a, b = Part("sv_map", controller, 7)
	T.eq(List(port.compiled), "features/aiwar/sv_map.lua", "compiled exactly the part")
	T.eq(seen.marker, "the root's env", "ran in the env")
	T.eq(seen.args[1], controller, "first argument")
	T.eq(seen.args[2], 7, "second argument")
	T.eq(#seen.args, 2, "no other arguments")
	T.eq(a, "map", "first value")
	T.eq(b, "extra", "second value")
end)

T.test("a part whose file is missing or does not compile raises naming its path", function()
	local Part = Features.Parts(CompilePort({}), {}, "aiwar")
	T.eq(ErrorOf(function() Part("sv_map") end), "features/aiwar/sv_map.lua did not compile")
end)

T.test("a part name is checked before anything compiles", function()
	local port = CompilePort({})
	local Part = Features.Parts(port, {}, "aiwar")
	T.eq(ErrorOf(function() Part("map") end), "not a feature part: map")
	T.eq(#port.compiled, 0, "nothing compiled")
end)

-- Resources ------------------------------------------------------------------
-- A feature names what it brings to preload (features/<name>/resources.lua:
-- kind -> names); the loader hands each kind to the handler this realm
-- registered for it, as the feature loads.

T.test("a feature's resources path is resources.lua beside its parts", function()
	T.eq(Features.ResourcesPath("wheel"), "features/wheel/resources.lua")
end)

-- A handler that keeps what it was handed: "feature:name" in order.
local function Keeper()
	local kept = {}
	return kept, function(names, feature)
		for _, name in ipairs(names) do kept[#kept + 1] = feature .. ":" .. name end
	end
end

T.test("a feature's resources go to each kind's handler as it loads, before its parts run", function()
	local port = FakePort({
		[Features.ResourcesPath("wheel")] = Returns({
			soundscapes = { "Halloween.WheelofFate" },
			models = { "models/props_lakeside_event/wof_plane2.mdl" },
		}),
		[P("wheel", CL)] = Returns({}),
	})
	local loader = Features.New(CL, port)
	local sounds, keepSounds = Keeper()
	local models, keepModels = Keeper()
	loader:Handle(Features.SOUNDSCAPES, keepSounds)
	loader:Handle(Features.MODELS, keepModels)
	loader:Feature("wheel")
	T.eq(List(sounds), "wheel:Halloween.WheelofFate", "soundscapes")
	T.eq(List(models), "wheel:models/props_lakeside_event/wof_plane2.mdl", "models")
	T.eq(List(port.runs), Features.ResourcesPath("wheel") .. "," .. P("wheel", CL), "resources first")
end)

T.test("a handler registered after a feature loaded is handed that feature's resources", function()
	local port = FakePort({
		[Features.ResourcesPath("wheel")] = Returns({ soundscapes = { "Halloween.WheelofFate" } }),
		[P("wheel", CL)] = Returns({}),
	})
	local loader = Features.New(CL, port)
	loader:Feature("wheel")
	local sounds, keepSounds = Keeper()
	loader:Handle(Features.SOUNDSCAPES, keepSounds)
	T.eq(List(sounds), "wheel:Halloween.WheelofFate", "handed late")
end)

T.test("a kind no handler takes on this realm is skipped; a feature without resources loads as before", function()
	local port = FakePort({
		[Features.ResourcesPath("wheel")] = Returns({ soundscapes = { "Halloween.WheelofFate" } }),
		[P("wheel", SV)] = Returns({}),
		[P("rounds", SV)] = Returns({}),
	})
	local loader = Features.New(SV, port)
	T.eq(type(loader:Feature("wheel")), "table", "the server takes no soundscapes, and loads it")
	T.eq(type(loader:Feature("rounds")), "table", "no resources.lua")
end)

T.test("a resource kind the loader does not know is refused, naming the feature and the kind", function()
	local port = FakePort({
		[Features.ResourcesPath("wheel")] = Returns({ sounds = { "Halloween.WheelofFate" } }),
		[P("wheel", SV)] = Returns({}),
	})
	local loader = Features.New(SV, port)
	local err = ErrorOf(function() loader:Feature("wheel") end)
	Has(err, "wheel", "the feature")
	Has(err, "sounds", "the kind")
	T.eq(ErrorOf(function() loader:Handle("sounds", function() end) end):find("sounds", 1, true) ~= nil, true,
		"a handler for it too")
end)

T.finish()
