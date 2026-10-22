-- games.system.features runs a feature's sv.lua or cl.lua and refuses one
-- that returns no table ("returned nil, not its table"): every such part
-- ends by returning it. Found by a client joining a payload map.
--
-- A feature's realm root runs its parts: the structural checks (a)-(h) below run over the real tree, and
-- each is shown to bite on a fixture feature in a temp directory, never
-- under the gamemode.
local T = dofile("tests/harness.lua")
local Features = T.require("games.system.features")

local FEATURES = "addons/sandcastle/gamemodes/sandcastle/gamemode/features"

local function LastLine(path)
	local last
	for line in io.lines(path) do
		if line:match("%S") then last = line end
	end
	return last
end

T.test("every feature's own part ends by returning its table", function()
	local list = assert(io.popen("find " .. FEATURES .. " -name sv.lua -o -name cl.lua"))
	local count = 0
	for path in list:lines() do
		count = count + 1
		T.eq(LastLine(path):match("^return [%w_{]") ~= nil, true, path)
	end
	list:close()
	T.eq(count > 10, true, "found the features' parts")
end)

-- The tree on disk -------------------------------------------------------------

local REALMS = { Features.SERVER, Features.CLIENT, Features.SHARED }
local MAX_LINES = 600 -- a realm file's longest; past it, split into parts
-- Realm files still over MAX_LINES; a split that lands removes its entry.
local PENDING_SPLIT = {}

local function Lines(command)
	local list = assert(io.popen(command))
	local lines = {}
	for line in list:lines() do lines[#lines + 1] = line end
	list:close()
	table.sort(lines)
	return lines
end

local function ReadFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

-- A gamemode tree: `gamemode` is the folder holding features/ (ends in "/");
-- `scan` the folders whose every .lua file checks (c) and (d) read.
local function Tree(gamemode, scan)
	local tree = {
		gamemode = gamemode,
		features = gamemode .. Features.ROOT,
	}
	function tree:Features()
		local names = {}
		for _, path in ipairs(Lines("find " .. self.features .. " -mindepth 1 -maxdepth 1 -type d")) do
			names[#names + 1] = path:match("([^/]+)$")
		end
		return names
	end
	-- The base names of the .lua files directly in the feature's folder.
	function tree:Files(name)
		local names = {}
		for _, path in ipairs(Lines("find " .. self.features .. name .. " -mindepth 1 -maxdepth 1 -type f -name '*.lua'")) do
			names[#names + 1] = path:match("([^/]+)$")
		end
		return names
	end
	-- The .lua files in the feature's subfolders, relative to its folder.
	function tree:Nested(name)
		local folder = self.features .. name .. "/"
		local paths = {}
		for _, path in ipairs(Lines("find " .. folder .. " -mindepth 2 -type f -name '*.lua'")) do
			paths[#paths + 1] = path:sub(#folder + 1)
		end
		return paths
	end
	function tree:Read(name, fileName)
		return ReadFile(self.features .. name .. "/" .. fileName)
	end
	function tree:Scanned()
		local paths = {}
		for _, dir in ipairs(scan) do
			for _, path in ipairs(Lines("find " .. dir .. " -type f -name '*.lua'")) do paths[#paths + 1] = path end
		end
		return paths
	end
	return tree
end

local GAMEMODE = Tree(T.ROOT, { T.ROOT, "addons/sandcastle/gamemodes/sandcastle/entities/" })

-- Lua source without its comments, so commented-out code is not counted.
local function Code(text)
	return (text:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", ""))
end

-- One realm of a feature: its root's text (nil when it has none) and its
-- parts, { stem, text } in name order.
local function RealmOf(tree, name, realm)
	local parts = {}
	for _, fileName in ipairs(tree:Files(name)) do
		local stem = fileName:match("^(" .. realm .. "_.*)%.lua$")
		if stem then parts[#parts + 1] = { stem = stem, text = tree:Read(name, fileName) } end
	end
	return { root = tree:Read(name, realm .. ".lua"), parts = parts }
end

-- Every file of a feature realm, root first: { label, text }.
local function RealmFiles(tree, name, realm)
	local r = RealmOf(tree, name, realm)
	local files = {}
	if r.root then files[1] = { label = name .. "/" .. realm .. ".lua", text = r.root } end
	for _, p in ipairs(r.parts) do files[#files + 1] = { label = name .. "/" .. p.stem .. ".lua", text = p.text } end
	return files
end

local function EachRealm(tree, fn)
	for _, name in ipairs(tree:Features()) do
		for _, realm in ipairs(REALMS) do fn(name, realm) end
	end
end

-- The keys counted more than once, as "<feature> <realm>: <key> <what> <n> times", sorted.
local function Repeats(counts, prefix, what)
	local problems = {}
	for key, n in pairs(counts) do
		if n > 1 then problems[#problems + 1] = string.format("%s: %s %s %d times", prefix, key, what, n) end
	end
	table.sort(problems)
	return problems
end

local function Append(list, more)
	for _, item in ipairs(more) do list[#list + 1] = item end
end

-- The checks: each returns its problems, a list of strings ---------------------

-- (a) Every <realm>_*.lua is named by exactly one Part("<stem>" in that
-- realm's root, and the root names no part that is not there.
local function OrphanParts(tree)
	local problems = {}
	EachRealm(tree, function(name, realm)
		local r = RealmOf(tree, name, realm)
		local named, present = {}, {}
		for stem in Code(r.root or ""):gmatch('Part%(%s*"([^"]+)"') do named[stem] = (named[stem] or 0) + 1 end
		for _, p in ipairs(r.parts) do
			present[p.stem] = true
			local n = named[p.stem] or 0
			if n ~= 1 then problems[#problems + 1] = string.format("%s/%s.lua is named %d times by its root", name, p.stem, n) end
		end
		for stem in pairs(named) do
			if not present[stem] then problems[#problems + 1] = string.format("%s/%s.lua: its root names a part that is not there", name, stem) end
		end
	end)
	table.sort(problems)
	return problems
end

-- (b) No realm-prefixed file sits in a feature's subfolder.
local function NestedParts(tree)
	local problems = {}
	for _, name in ipairs(tree:Features()) do
		for _, path in ipairs(tree:Nested(name)) do
			if Features.Realm(path:match("([^/]+)$")) then
				problems[#problems + 1] = name .. "/" .. path .. " is a realm file in a subfolder"
			end
		end
	end
	return problems
end

-- (c) Only a realm root calls WS.FeatureParts, as
-- WS.FeatureParts(getfenv(1), "<its own folder name>").
local function PartsCallers(tree)
	local problems = {}
	for _, path in ipairs(tree:Scanned()) do
		local code = Code(ReadFile(path))
		local _, calls = code:gsub("FeatureParts%s*%(", "")
		local _, definitions = code:gsub("function%s+WS%.FeatureParts%s*%(", "")
		calls = calls - definitions
		if calls > 0 then
			local feature, fileName = path:sub(#tree.features + 1):match("^([%w_]+)/([^/]+)$")
			local isRoot = path:sub(1, #tree.features) == tree.features and fileName and fileName:match("^%a%a%.lua$")
				and Features.Realm(fileName)
			if not isRoot then
				problems[#problems + 1] = path .. " calls WS.FeatureParts but is not a feature's realm root"
			else
				local own = 0
				for passed in code:gmatch('WS%.FeatureParts%(%s*getfenv%(%s*1%s*%)%s*,%s*"([^"]*)"%s*%)') do
					if passed == feature then own = own + 1 end
				end
				if own ~= calls then
					problems[#problems + 1] = path .. ' must call WS.FeatureParts(getfenv(1), "' .. feature .. '")'
				end
			end
		end
	end
	return problems
end

-- (d) Nothing requires a part (or a root): no WS.require or require of
-- features.<name>.<realm file>.
local function RequiredParts(tree)
	local problems = {}
	for _, path in ipairs(tree:Scanned()) do
		for target in Code(ReadFile(path)):gmatch("require%s*%(?%s*[\"']features%.([%w_]+%.[%w_%.]+)[\"']") do
			if Features.Realm(target:match("([%w_]+)$") .. ".lua") then
				problems[#problems + 1] = path .. " requires features." .. target
			end
		end
	end
	return problems
end

-- (e) Each method (function <T>[:.]<Name>) is defined once per feature
-- realm, across the root and its parts.
local function DuplicateMethods(tree)
	local problems = {}
	EachRealm(tree, function(name, realm)
		local counts = {}
		for _, file in ipairs(RealmFiles(tree, name, realm)) do
			for method in Code(file.text):gmatch("%f[%w_]function%s+([%w_]+[%.:][%w_%.:]+)%s*%(") do
				method = method:gsub(":", ".")
				counts[method] = (counts[method] or 0) + 1
			end
		end
		Append(problems, Repeats(counts, name .. " " .. realm, "defined"))
	end)
	return problems
end

-- The literal wiring keys a file registers, in order.
local function WiringKeys(text)
	local code = Code(text)
	local constants = {}
	for constant, value in code:gmatch('local%s+([%a_][%w_]*)%s*=%s*"([^"]*)"') do constants[constant] = value end
	local keys = {}
	local function Add(...) keys[#keys + 1] = table.concat({ ... }, " ") end
	for event, id in code:gmatch('hook%.Add%(%s*"([^"]+)"%s*,%s*"([^"]+)"') do Add("hook", event, id) end
	for command in code:gmatch('concommand%.Add%(%s*"([^"]+)"') do Add("concommand", command) end
	for args in code:gmatch("cvars%.AddChangeCallback(%b())") do
		local cvar, id = args:match('^%(%s*"([^"]+)"'), args:match(',%s*"([^"]+)"%s*%)$')
		if cvar and id then Add("cvars", cvar, id) end
	end
	for timerName in code:gmatch('timer%.Create%(%s*"([^"]+)"') do Add("timer", timerName) end
	for constant in code:gmatch("timer%.Create%(%s*([%a_][%w_]*)%s*,") do
		if constants[constant] then Add("timer", constants[constant]) end
	end
	for _, listen in ipairs({ "Events%.Listen", "%f[%w_]E%.Listen" }) do
		for event, id in code:gmatch(listen .. '%(%s*"([^"]+)"%s*,%s*"([^"]+)"') do Add("listen", event, id) end
	end
	return keys
end

-- (f) Literal wiring keys are unique per feature realm, across the root and
-- all its parts.
local function DuplicateWiring(tree)
	local problems = {}
	EachRealm(tree, function(name, realm)
		local counts = {}
		for _, file in ipairs(RealmFiles(tree, name, realm)) do
			for _, key in ipairs(WiringKeys(file.text)) do counts[key] = (counts[key] or 0) + 1 end
		end
		Append(problems, Repeats(counts, name .. " " .. realm, "registered"))
	end)
	return problems
end

local function LineCount(text)
	local _, n = text:gsub("\n", "")
	return n
end

-- (g) No realm file is over MAX_LINES unless pending a split, and every
-- pending entry is still there and still over.
local function OversizeFiles(tree, pending)
	local problems, isPending = {}, {}
	for _, path in ipairs(pending) do
		isPending[path] = true
		local text = tree:Read(path:match("^([^/]+)/(.+)$"))
		if not text then
			problems[#problems + 1] = path .. " is pending a split but is not there"
		elseif LineCount(text) <= MAX_LINES then
			problems[#problems + 1] = path .. " is no longer over " .. MAX_LINES .. " lines: remove it from PENDING_SPLIT"
		end
	end
	EachRealm(tree, function(name, realm)
		for _, file in ipairs(RealmFiles(tree, name, realm)) do
			if not isPending[file.label] and LineCount(file.text) > MAX_LINES then
				problems[#problems + 1] = string.format("%s has %d lines, over %d", file.label, LineCount(file.text), MAX_LINES)
			end
		end
	end)
	return problems
end

-- (h) In a split feature realm, every self.<lowercase> field a
-- Controller method assigns, in the root or any part, is declared by the
-- root's `local Controller = {` literal.

-- The keys a root's Controller literal declares: those at its top level, and
-- those listed on a `-- name = nil` comment line; nil when it has none.
local function DeclaredFields(root)
	local literal = root:match("local%s+Controller%s*=%s*(%b{})")
	if not literal then return nil end
	local declared, depth = {}, 0
	for line in literal:sub(2, -2):gmatch("[^\n]+") do
		if depth == 0 then
			local key = Code(line):match("^%s*([%a_][%w_]*)%s*=%f[^=]") or line:match("^%s*%-%-%s*([%a_][%w_]*)%s*=%s*nil%f[^%w_]")
			if key then declared[key] = true end
		end
		local _, opens = Code(line):gsub("{", "")
		local _, closes = Code(line):gsub("}", "")
		depth = depth + opens - closes
	end
	return declared
end

-- Each Controller method in a file's code, as { name, body }: its first line,
-- then every line up to the `end` at column 0 that closes it; a method on
-- one line is that line.
local function ControllerMethods(code)
	local methods, lines = {}, {}
	for line in (code .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
	for i, line in ipairs(lines) do
		local name = line:match("^function%s+(Controller[:.][%w_]+)%s*%(")
		if name then
			local body = { line }
			for j = i + 1, #lines do
				local following = lines[j]
				if following:match("^%S") then
					if following:match("^end%f[^%w_]") then body[#body + 1] = following else body = { line } end
					break
				end
				body[#body + 1] = following
			end
			methods[#methods + 1] = { name = name, body = table.concat(body, "\n") }
		end
	end
	return methods
end

-- The self.<lowercase> fields code assigns, `self.a, self.b = ...` included.
local function AssignedFields(code)
	local fields = {}
	for targets in code:gmatch("([%w_%.,%s]*)=%f[^=]") do
		local rest = targets
		while true do
			local before, field = rest:match("^(.-)self%.(%l[%w_]*)%s*$")
			if not field then break end
			fields[#fields + 1] = field
			rest = before:match("^(.-),%s*$")
			if not rest then break end
		end
	end
	return fields
end

local function UndeclaredFields(tree)
	local problems, seen = {}, {}
	EachRealm(tree, function(name, realm)
		local r = RealmOf(tree, name, realm)
		if not r.root or #r.parts == 0 then return end
		local declared = DeclaredFields(r.root)
		for _, file in ipairs(RealmFiles(tree, name, realm)) do
			for _, method in ipairs(ControllerMethods(Code(file.text))) do
				if not declared then
					local problem = string.format("%s/%s.lua has parts with Controller methods but declares no local Controller = { table", name, realm)
					if not seen[problem] then problems[#problems + 1] = problem end
					seen[problem] = true
				else
					for _, field in ipairs(AssignedFields(method.body)) do
						local problem = string.format("%s: %s assigns self.%s, which the root's Controller table does not declare", file.label, method.name, field)
						if not declared[field] and not seen[problem] then problems[#problems + 1] = problem end
						seen[problem] = true
					end
				end
			end
		end
	end)
	table.sort(problems)
	return problems
end

-- Fixtures: features in a temp directory, never under the gamemode --------------

local FIXTURE_PREFIX = "fixture_"
local TEMP = assert(io.popen('mktemp -d "${TMPDIR:-/tmp}/sandcastle_fixture.XXXXXX"')):read("*l")
assert(TEMP and TEMP:match("/sandcastle_fixture%.[%w]+$"), "made a temp directory")
local FIXTURE_ROOT = TEMP .. "/gamemode/"
local fixtureCount = 0

-- A fresh fixture tree holding `files`: { ["features/fixture_x/sv.lua"] = text }.
local function FixtureTree(files)
	fixtureCount = fixtureCount + 1
	local root = FIXTURE_ROOT .. fixtureCount .. "/"
	assert(os.execute("mkdir -p '" .. root .. Features.ROOT .. "'") == 0)
	for path, text in pairs(files) do
		assert(os.execute("mkdir -p '" .. (root .. path):match("^(.*)/") .. "'") == 0)
		local f = assert(io.open(root .. path, "wb"))
		f:write(text)
		f:close()
	end
	return Tree(root, { root })
end

local function Same(actual, expected, what)
	T.eq(table.concat(actual, "\n"), table.concat(expected, "\n"), what)
end

-- The harness helpers --------------------------------------------------------

T.test("T.RealmSource is the root's text, then every part of its realm in name order", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = "root",
		["features/fixture_a/sv_b.lua"] = "part b",
		["features/fixture_a/sv_a.lua"] = "part a",
		["features/fixture_a/cl.lua"] = "view",
		["features/fixture_a/cl_hud.lua"] = "view part",
		["features/fixture_a/model.lua"] = "model",
		["features/fixture_a/scenario/sv_z.lua"] = "nested",
	})
	local source = T.FeatureTree(tree.gamemode).RealmSource
	T.eq(source("fixture_a", Features.SERVER), "root\npart a\npart b", "server")
	T.eq(source("fixture_a", Features.CLIENT), "view\nview part", "client")
end)

T.test("T.RealmSource of a feature with no parts is its root", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = "root only",
		["features/fixture_a/model.lua"] = "model",
	})
	T.eq(T.FeatureTree(tree.gamemode).RealmSource("fixture_a", Features.SERVER), "root only")
end)

T.test("T.RealmSource refuses a realm with no root, naming it", function()
	local tree = FixtureTree({ ["features/fixture_a/sv.lua"] = "root" })
	local ok, err = pcall(T.FeatureTree(tree.gamemode).RealmSource, "fixture_a", Features.CLIENT)
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("features/fixture_a/cl.lua", 1, true) ~= nil, true, "names it: " .. tostring(err))
end)

T.test("T.RealmSource and T.FeatureParts read the gamemode", function()
	T.eq(T.RealmSource("koth", Features.SERVER), ReadFile(T.ROOT .. "features/koth/sv.lua"), "koth's root")
	local Part = T.FeatureParts({}, "koth")
	T.eq(type(Part), "function", "a part runner")
end)

T.test("T.FeatureParts runs a part from disk in the env given, with the arguments", function()
	local tree = FixtureTree({
		["features/fixture_a/sv_map.lua"] = "local Controller, n = ...\nController.marker = MARKER\nreturn n + 1, 'map'\n",
		["features/fixture_a/sv_broken.lua"] = "this is not lua",
	})
	local Part = T.FeatureTree(tree.gamemode).FeatureParts({ MARKER = "the root's env" }, "fixture_a")
	local controller = {}
	local n, map = Part("sv_map", controller, 1)
	T.eq(n, 2, "returned")
	T.eq(map, "map", "second value")
	T.eq(controller.marker, "the root's env", "read from the env")
	for _, part in ipairs({ "sv_broken", "sv_missing" }) do
		local ok, err = pcall(Part, part)
		T.eq(ok, false, part)
		T.eq(tostring(err), "features/fixture_a/" .. part .. ".lua did not compile", part)
	end
end)

T.test("T.Wiring: the same key registered twice is one duplicate", function()
	local w = T.Wiring()
	w.hook.Add("Think", "ws_x", function() end)
	w.hook.Add("Think", "ws_x", function() end)
	Same(w:Duplicates(), { "hook Think ws_x" })
	Same(w:Registered(), { "hook Think ws_x", "hook Think ws_x" }, "every registration, in order")
end)

T.test("T.Wiring: one event under two ids is no duplicate", function()
	local w = T.Wiring()
	w.hook.Add("Think", "ws_x", function() end)
	w.hook.Add("Think", "ws_y", function() end)
	w.Events.Listen("round_win", "ws_x", function() end)
	w.Events.Listen("round_win", "ws_y", function() end)
	w.cvars.AddChangeCallback("mp_x", function() end, "ws_x")
	w.cvars.AddChangeCallback("mp_x", function() end, "ws_y")
	Same(w:Duplicates(), {})
end)

T.test("T.Wiring: commands, callbacks, timers and listeners each count their key", function()
	local w = T.Wiring()
	for _ = 1, 2 do
		w.concommand.Add("ws_x_report", function() end)
		w.cvars.AddChangeCallback("mp_x", function() end, "ws_x")
		w.timer.Create("ws_x_tick", 1, 0, function() end)
		w.Events.Listen("round_win", "ws_x", function() end)
	end
	Same(w:Duplicates(), { "concommand ws_x_report", "cvars mp_x ws_x", "timer ws_x_tick", "listen round_win ws_x" })
end)

T.test("T.Wiring: a convar callback without an id adds, so it has no key", function()
	local w = T.Wiring()
	w.cvars.AddChangeCallback("mp_x", function() end)
	w.cvars.AddChangeCallback("mp_x", function() end)
	Same(w:Duplicates(), {})
end)

-- Each check bites on a fixture ----------------------------------------------

T.test("(a) a part no root names, one named twice, and a named part not there all fail", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = 'local Part = WS.FeatureParts(getfenv(1), "fixture_a")\nPart("sv_twice")\nPart("sv_twice")\nPart("sv_gone")\nPart("sv_ok")\nreturn {}\n',
		["features/fixture_a/sv_twice.lua"] = "",
		["features/fixture_a/sv_ok.lua"] = "",
		["features/fixture_a/sv_orphan.lua"] = "",
		["features/fixture_a/cl_orphan.lua"] = "",
	})
	Same(OrphanParts(tree), {
		"fixture_a/cl_orphan.lua is named 0 times by its root",
		"fixture_a/sv_gone.lua: its root names a part that is not there",
		"fixture_a/sv_orphan.lua is named 0 times by its root",
		"fixture_a/sv_twice.lua is named 2 times by its root",
	})
end)

T.test("(b) a realm file in a feature's subfolder fails", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = "return {}",
		["features/fixture_a/scenario/sv_koth.lua"] = "",
		["features/fixture_a/scenario/koth.lua"] = "",
	})
	Same(NestedParts(tree), { "fixture_a/scenario/sv_koth.lua is a realm file in a subfolder" })
end)

T.test("(c) a part, a non-root, or a root passing another name calling WS.FeatureParts fails", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = 'local Part = WS.FeatureParts(getfenv(1), "fixture_b")\nreturn {}',
		["features/fixture_a/sv_x.lua"] = 'local Part = WS.FeatureParts(getfenv(1), "fixture_a")',
		["features/fixture_b/sv.lua"] = 'local Part = WS.FeatureParts(getfenv(2), "fixture_b")\nreturn {}',
		["features/fixture_c/sv.lua"] = 'local Part = WS.FeatureParts(getfenv(1), "fixture_c")\nreturn {}',
		["ws/sh_core.lua"] = "function WS.FeatureParts(env, name) end",
		["ws/sv_x.lua"] = 'WS.FeatureParts(getfenv(1), "fixture_a")',
	})
	local root = tree.gamemode
	Same(PartsCallers(tree), {
		root .. 'features/fixture_a/sv.lua must call WS.FeatureParts(getfenv(1), "fixture_a")',
		root .. "features/fixture_a/sv_x.lua calls WS.FeatureParts but is not a feature's realm root",
		root .. 'features/fixture_b/sv.lua must call WS.FeatureParts(getfenv(1), "fixture_b")',
		root .. "ws/sv_x.lua calls WS.FeatureParts but is not a feature's realm root",
	})
end)

T.test("(d) requiring a part, with WS.require or require, in an underscored feature, fails", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = table.concat({
			'local A = WS.require("features.fixture_boss_timer.sv_x")',
			"local B = require('features.fixture_a.cl_hud')",
			'local C = WS.require("features.fixture_a.sh")',
			'local D = WS.require("features.fixture_a.on_holiday")',
			'local E = WS.require("features.fixture_a.scenario.koth")',
			'-- WS.require("features.fixture_a.sv_commented")',
			"return {}",
		}, "\n"),
	})
	local path = tree.gamemode .. "features/fixture_a/sv.lua"
	Same(RequiredParts(tree), {
		path .. " requires features.fixture_boss_timer.sv_x",
		path .. " requires features.fixture_a.cl_hud",
		path .. " requires features.fixture_a.sh",
	})
end)

T.test("(e) a method defined twice across a root and its parts fails, each realm apart", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = "function Controller:Think() end\nfunction Soldier:RouteStale() end\n-- function Controller:Old() end\nreturn {}",
		["features/fixture_a/sv_soldier.lua"] = "function Soldier:RouteStale() return false end\nfunction Controller.Think() end",
		["features/fixture_a/cl.lua"] = "function Controller:Think() end\nreturn {}",
		["features/fixture_a/sv_old.lua"] = "function Controller:Old() end",
	})
	Same(DuplicateMethods(tree), {
		"fixture_a sv: Controller.Think defined 2 times",
		"fixture_a sv: Soldier.RouteStale defined 2 times",
	})
end)

T.test("(f) two parts adding the same hook key fail", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = 'hook.Add("Think", "ws_y", function() end)\nreturn {}',
		["features/fixture_a/sv_a.lua"] = 'hook.Add("Think", "ws_x", function() end)',
		["features/fixture_a/sv_b.lua"] = 'hook.Add("Think", "ws_x", function() end)\nhook.Add("Tick", "ws_x", function() end)',
	})
	Same(DuplicateWiring(tree), { "fixture_a sv: hook Think ws_x registered 2 times" })
end)

T.test("(f) a root and a part adding the same command fail", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = 'concommand.Add("ws_x_report", function() end)\nreturn {}',
		["features/fixture_a/sv_commands.lua"] = 'concommand.Add("ws_x_report", function() end)',
	})
	Same(DuplicateWiring(tree), { "fixture_a sv: concommand ws_x_report registered 2 times" })
end)

T.test("(f) callbacks, timers (named by a file constant) and listeners are keyed", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = table.concat({
			'cvars.AddChangeCallback("mp_x", function(_, _, v) print(v, "ws_x") end, "ws_x")',
			'cvars.AddChangeCallback("mp_y", function() end, "ws_x")',
			'local TICK = "ws_x_tick"',
			"timer.Create(TICK, 1, 0, function() end)",
			'WS.Events.Listen("round_win", "ws_x", function() end)',
			"return {}",
		}, "\n"),
		["features/fixture_a/sv_a.lua"] = table.concat({
			'cvars.AddChangeCallback("mp_x", function() end, "ws_x")',
			'timer.Create("ws_x_tick", 1, 0, function() end)',
			"local E = WS.Events",
			'E.Listen("round_win", "ws_x", function() end)',
			'E.Listen("round_win", "ws_y", function() end)',
		}, "\n"),
		["features/fixture_a/sh.lua"] = 'WS.Events.Listen("round_win", "ws_x", function() end)',
	})
	Same(DuplicateWiring(tree), {
		"fixture_a sv: cvars mp_x ws_x registered 2 times",
		"fixture_a sv: listen round_win ws_x registered 2 times",
		"fixture_a sv: timer ws_x_tick registered 2 times",
	})
end)

T.test("(g) a realm file over the limit fails, and so does a stale pending entry", function()
	local long = string.rep("x = 1\n", MAX_LINES + 1)
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = long,
		["features/fixture_a/sv_big.lua"] = long,
		["features/fixture_a/model.lua"] = long,
		["features/fixture_b/sv.lua"] = "return {}\n",
		["features/fixture_c/cl.lua"] = long,
	})
	local over = string.format("has %d lines, over %d", MAX_LINES + 1, MAX_LINES)
	Same(OversizeFiles(tree, { "fixture_a/sv.lua", "fixture_b/sv.lua", "fixture_gone/sv.lua" }), {
		"fixture_b/sv.lua is no longer over " .. MAX_LINES .. " lines: remove it from PENDING_SPLIT",
		"fixture_gone/sv.lua is pending a split but is not there",
		"fixture_a/sv_big.lua " .. over,
		"fixture_c/cl.lua " .. over,
	})
end)

T.test("(h) a field a split controller's method assigns that its root does not declare fails", function()
	local tree = FixtureTree({
		["features/fixture_a/sv.lua"] = table.concat({
			"local Controller = {",
			"\twar = nil, -- running",
			'\ttracks = setmetatable({}, { mode = "k" }),',
			"\t-- slots = nil, -- read when first needed",
			"}",
			'local Part = WS.FeatureParts(getfenv(1), "fixture_a")',
			'Part("sv_a", Controller)',
			"function Controller:Stop()",
			"\tself.war = nil",
			"\tself.stopped = true",
			"end",
			"return Controller",
		}, "\n"),
		["features/fixture_a/sv_a.lua"] = table.concat({
			"local Controller = ...",
			"function Controller:Start()",
			"\tself.war = {}",
			"\tself.slots = {}",
			"\tself.tracks[1] = true",
			"\tif self.paused == true then return end",
			'\tself.mode, self.extra = "k", 1',
			"\tself.Soldier = {}",
			"end",
			"function Controller.Reset(self) self.cleared = true end",
			"function Soldier:Move() self.moved = true end",
			"-- function Controller:Old() self.old = true end",
		}, "\n"),
		-- unsplit: its root alone is not checked
		["features/fixture_b/sv.lua"] = "local Controller = {}\nfunction Controller:Start() self.war = 1 end\nreturn Controller",
		-- split, with no Controller table in its root
		["features/fixture_c/sv.lua"] = 'local Part = WS.FeatureParts(getfenv(1), "fixture_c")\nPart("sv_x")\nreturn {}',
		["features/fixture_c/sv_x.lua"] = "function Controller:Start() end",
	})
	local undeclared = "which the root's Controller table does not declare"
	Same(UndeclaredFields(tree), {
		"fixture_a/sv.lua: Controller:Stop assigns self.stopped, " .. undeclared,
		"fixture_a/sv_a.lua: Controller.Reset assigns self.cleared, " .. undeclared,
		"fixture_a/sv_a.lua: Controller:Start assigns self.extra, " .. undeclared,
		"fixture_a/sv_a.lua: Controller:Start assigns self.mode, " .. undeclared,
		"fixture_c/sv.lua has parts with Controller methods but declares no local Controller = { table",
	})
end)

-- The checks over the gamemode -----------------------------------------------

T.test("(a) every part is named by exactly one Part call in its realm's root", function()
	Same(OrphanParts(GAMEMODE), {})
end)

T.test("(b) parts sit at the top of their feature's folder", function()
	Same(NestedParts(GAMEMODE), {})
end)

T.test("(c) only realm roots call WS.FeatureParts, each with its own name", function()
	Same(PartsCallers(GAMEMODE), {})
end)

T.test("(d) nothing requires a part", function()
	Same(RequiredParts(GAMEMODE), {})
end)

T.test("(e) each method is defined once per feature realm", function()
	Same(DuplicateMethods(GAMEMODE), {})
end)

T.test("(f) literal wiring keys are unique per feature realm", function()
	Same(DuplicateWiring(GAMEMODE), {})
end)

T.test("(g) no realm file is over the limit but those pending a split, which still are", function()
	Same(OversizeFiles(GAMEMODE, PENDING_SPLIT), {})
end)

T.test("(h) every field a split controller's method assigns is declared in its root", function()
	Same(UndeclaredFields(GAMEMODE), {})
end)

-- Fixtures leave nothing behind --------------------------------------------------

T.test("no fixture is under the gamemode, and the temp directory is gone", function()
	T.eq(fixtureCount > 0, true, "fixtures were made")
	T.eq(TEMP:sub(1, 1), "/", "the temp directory is absolute, outside the repo")
	T.eq(TEMP:find(T.ROOT, 1, true), nil, "the temp directory is not in the gamemode")
	Same(Lines("find " .. T.ROOT .. " -name '" .. FIXTURE_PREFIX .. "*'"), {}, "fixture paths under T.ROOT")
	T.eq(os.execute("rm -rf '" .. TEMP .. "'"), 0, "removed")
	T.eq(ReadFile(TEMP), nil, "the temp directory is gone")
end)

T.finish()
