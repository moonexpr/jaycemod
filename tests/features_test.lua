local T = dofile("tests/harness.lua")
local Features = T.require("foundation.features")

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

T.finish()
