-- foundation's twins answer to one interface. A server installs each native
-- twin (native/foundation, native/wetsands) over the Lua one its clients
-- run, so a name only one twin answers to is code that works in one realm
-- and breaks in the other. Twin (core.namespace) refuses a native twin
-- lacking a key of the Lua module's; this suite holds the rest of the
-- interface both ways:
--   every Twin line has a native twin in a built binary, and on a server
--     (the native pass) the published global is that binary's own
--   a module's keys, the tables they hold (classes, constant tables) and its
--     metamethods are the same in both, of the same kinds, constants equal
--   a preloaded native part holds its Lua module's keys and no others
--   what the constructors make (every Twin module has a recipe, or is a
--     library of plain functions) answers to the same methods and
--     metamethods, and to the data fields its contract names
-- The comparisons run in the Lua pass: there the Lua twins stand on Lua
-- globals and the binaries are loaded apart, as T.native gives them. In the
-- native pass a Lua twin loaded here would stand on native globals.
local T = dofile("tests/harness.lua")

local CRATES = { "foundation", "wetsands" }

-- module(...)'s own keys, which a Lua twin's table holds and its native
-- twin does not take.
local MODULE_KEYS = { _M = true, _NAME = true, _PACKAGE = true }

-- Metamethods the two realms need differently, not part of what a caller
-- sees: a userdata's lifetime and how its methods are found.
local MECHANICS = { __gc = true, __index = true, __newindex = true, __mode = true, __metatable = true, __name = true }

-- Native-only names: seams the native suites price or probe the binary
-- through, which no gamemode code reads.
local NATIVE_ONLY = {
	["wetsands.navsearch.Walker"] = "tests/wetsands_path_model_test.lua prices a strategy's model natively",
}

-- How deep a module's tables are compared: HULLS[0].mins[1] is four down.
local MODULE_DEPTH = 4

local function ReadFile(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

-- The modules the indexes publish with Twin, in index order.
local function Twins()
	local modules = {}
	for _, path in ipairs(T.Indexes()) do
		for module in ReadFile(T.ROOT .. path):gmatch('Twin%(%s*[%w_]+%s*,%s*"[%w_]+"%s*,%s*require%(%s*"([%w_.]+)"%s*%)%s*%)') do
			modules[#modules + 1] = module
		end
	end
	return modules
end

local function At(root, global)
	local value = root
	for part in global:gmatch("[^.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

-- The native twin of a published global, and the crate holding it.
local function NativeOf(global)
	for _, crate in ipairs(CRATES) do
		local value = At(T.native(crate), global)
		if value ~= nil then return value, crate end
	end
	return nil
end

local function Kind(value)
	local kind = type(value)
	if kind == "table" or kind == "userdata" then return "object" end
	return kind
end

-- What value[name] reads, through any __index; nil when it reads nothing
-- or refuses the name (a constant set refuses an unknown one).
local function Answer(value, name)
	local ok, found = pcall(function() return value[name] end)
	if ok then return found end
	return nil
end

-- The names a value answers to that can be listed: its own keys (strings,
-- and numbers when `numbers`), then those of each __index table up its
-- metatables; `own` false leaves its own lower-case keys out (a Lua twin's
-- storage). The metamethods its metatable defines, mechanics aside.
local function Surface(value, numbers, own)
	local names, metamethods, seen = {}, {}, {}
	local function Listed(key)
		if type(key) == "number" then return numbers end
		return type(key) == "string" and not key:match("^__") and not MODULE_KEYS[key]
	end
	local function Walk(t, depth)
		if seen[t] then return end
		seen[t] = true
		if type(t) == "table" then
			for key in pairs(t) do
				if Listed(key) and (depth > 0 or own or type(key) ~= "string" or key:match("^%u")) then names[key] = true end
			end
		end
		local meta = getmetatable(t)
		if type(meta) ~= "table" then return end
		if depth == 0 then
			for key in pairs(meta) do
				if type(key) == "string" and key:match("^__") and not MECHANICS[key] then metamethods[key] = true end
			end
		end
		if type(meta.__index) == "table" then Walk(meta.__index, depth + 1) end
	end
	Walk(value, 0)
	return names, metamethods
end

local function Sorted(set)
	local list = {}
	for key in pairs(set) do list[#list + 1] = key end
	table.sort(list, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	return list
end

local function Same(a, b)
	return a == b or (a ~= a and b ~= b)
end

-- The differences between a Lua twin's value and the native one's, as
-- "<path>: ..." lines appended to problems. fields: names the contract
-- holds beyond the listed ones (a search's status). depth: how far into
-- the tables both answer with under a capitalised or number key; numbers:
-- whether number keys are listed.
local function Compare(lua, native, path, options, problems, seen)
	seen = seen or {}
	if seen[lua] and seen[lua][native] then return end
	seen[lua] = seen[lua] or {}
	seen[lua][native] = true
	-- a table on both sides is the interface whole; against a userdata the
	-- Lua table's own lower-case keys are its storage
	local whole = type(lua) == "table" and type(native) == "table"
	local luaNames, luaMeta = Surface(lua, options.numbers, whole)
	local nativeNames, nativeMeta = Surface(native, options.numbers, true)
	local names = {}
	for name in pairs(luaNames) do names[name] = true end
	for name in pairs(nativeNames) do names[name] = true end
	for _, name in ipairs(options.fields or {}) do names[name] = true end
	for _, name in ipairs(Sorted(names)) do
		local at = path .. "." .. tostring(name)
		local l, n = Answer(lua, name), Answer(native, name)
		if l == nil and n ~= nil then
			if not NATIVE_ONLY[at] then problems[#problems + 1] = at .. ": only the native twin's (a " .. Kind(n) .. ")" end
		elseif n == nil and l ~= nil then
			problems[#problems + 1] = at .. ": only the Lua twin's (a " .. Kind(l) .. ")"
		elseif l == nil then
			problems[#problems + 1] = at .. ": a field of the contract, answered by neither twin"
		elseif Kind(l) ~= Kind(n) then
			problems[#problems + 1] = at .. ": a " .. Kind(l) .. " in the Lua twin, a " .. Kind(n) .. " in the native"
		elseif Kind(l) == "object" then
			-- a class, a constant or a constant table's entry is followed; a
			-- lower-case field holds data (a port's methods), the same kind
			if options.depth > 0 and (type(name) == "number" or name:match("^%u")) then
				Compare(l, n, at, { depth = options.depth - 1, numbers = options.numbers }, problems, seen)
			end
		elseif Kind(l) ~= "function" and not Same(l, n) then
			problems[#problems + 1] = at .. ": " .. tostring(l) .. " in the Lua twin, " .. tostring(n) .. " in the native"
		end
	end
	for _, name in ipairs(Sorted(luaMeta)) do
		if not nativeMeta[name] then problems[#problems + 1] = path .. " " .. name .. ": only the Lua twin's" end
	end
	for _, name in ipairs(Sorted(nativeMeta)) do
		if not luaMeta[name] then problems[#problems + 1] = path .. " " .. name .. ": only the native twin's" end
	end
end

local function Report(problems)
	if #problems > 0 then error("\n  " .. table.concat(problems, "\n  "), 2) end
end

-- What each constructor makes, from one module and the same arguments:
-- Make(module) -> { name = a value }, and the data fields each value's
-- contract names (fields[name]). Modules of plain functions, with nothing
-- to construct, are LIBRARIES.
local function Clock()
	return { t = 0, Now = function(self) return self.t end }
end

local function Graph()
	local adjacent = { a = { "b" }, b = { "a" } }
	return {
		Neighbors = function(_, node) return adjacent[node] end,
		Cost = function(_, _, _, costSoFar) return costSoFar + 1 end,
		Estimate = function() return 0 end,
	}
end

local function Mesh(NavSearch)
	local mesh = NavSearch.Mesh()
	mesh:Area(1, 0, 0, 0, 0)
	mesh:Area(2, 100, 0, 0, 0)
	mesh:Link(1, 2, 100, 0)
	mesh:Link(2, 1, 100, 0)
	mesh:Seal()
	return mesh
end

local function Bot()
	return { entIndex = 12, now = 30, team = 2, route = 0, miniBoss = false, roundWon = false, winningTeam = 0, penalized = {} }
end

local SEARCH_FIELDS = { "status", "expanded", "maxExpanded", "start", "goal", "closest", "parent" }

local RECIPES = {
	["foundation.list.queue"] = { Make = function(M) return { queue = M.New() } end },
	["foundation.list.ring"] = { Make = function(M) return { ring = M.New(4) } end },
	["foundation.list.slots"] = { Make = function(M) return { slots = M.New() } end },
	["foundation.list.chain"] = { Make = function(M) return { chain = M.New() } end },
	["foundation.list.schedule"] = { Make = function(M) return { scheduler = M.New(Clock()) } end },
	["foundation.list.window"] = { Make = function(M) return { window = M.New(5) } end },
	["foundation.tree.heap"] = { Make = function(M) return { heap = M.New() } end },
	["foundation.tree.avl"] = { Make = function(M) return { tree = M.New() } end },
	["foundation.world.pairmap"] = { Make = function(M) return { pairmap = M.New(), unordered = M.Unordered() } end },
	["foundation.world.lease"] = { Make = function(M) return { leases = M.New() } end },
	["foundation.world.grid"] = { Make = function(M) return { grid = M.New(100) } end },
	["foundation.world.sets"] = { Make = function(M) return { set = M.Named("colours", { "red", "blue" }) } end },
	["foundation.cache.base"] = { Make = function(M) return { cache = M.New({}) } end },
	["foundation.cache.lru"] = { Make = function(M) return { cache = M.New({ capacity = 2 }) } end },
	["foundation.cache.expiring"] = { Make = function(M) return { cache = M.New({ clock = Clock(), term = 5 }) } end },
	["foundation.cache.memo"] = { Make = function(M) return { cache = M.New({}) } end },
	["foundation.configstore"] = {
		Make = function(M)
			local store = M.New("the options")
			store:Range("volume", 0, 10, "listener")
			store:Switch("muted", "listener")
			return { store = store, range = store.volume, switch = store.muted }
		end,
		fields = { range = { "min", "max", "guard" }, switch = { "min", "max", "guard" } },
	},
	["foundation.core.class"] = {
		Make = function(M)
			local Base = M.Extend(nil, { Init = function() end })
			local Derived = M.Extend(Base, {})
			return { base = Base, derived = Derived, instance = M.Construct(Derived) }
		end,
	},
	["foundation.core.port"] = {
		Make = function(M)
			local port = M.New("Clock", { "Now" })
			return { port = port, facade = port:Facade(Clock()) }
		end,
	},
	["foundation.core.constants"] = { Make = function(M) return { set = M.New("sizes", { SMALL = 1, LARGE = 2 }) } end },
	["foundation.core.enum"] = { Make = function(M) return { enum = M.New("hit sound", 0, { "DEFAULT", "ELECTRO" }) } end },
	["foundation.core.namespace"] = {
		Make = function(M)
			local globals = {}
			return { namespace = M.Namespace(globals, "things"), environment = M.Environment(globals, function() end) }
		end,
	},
	["foundation.encoding.cursor"] = { Make = function(M) return { cursor = M.New("hello") } end },
	["foundation.file.buffer"] = { Make = function(M) return { writer = M.Writer(), reader = M.Reader("\1") } end },
	["foundation.math.matrix"] = { Make = function(M) return { matrix = M.New({ { 1, 2 }, { 3, 4 } }), identity = M.Identity(2) } end },
	["foundation.math.polyline"] = { Make = function(M) return { line = M.New({ { x = 0, y = 0 }, { x = 1, y = 0 } }) } end },
	["foundation.graph.pathfinder"] = {
		Make = function(M) return { search = M.New(Graph(), "a", "b") } end,
		fields = { search = SEARCH_FIELDS },
	},
	["foundation.generator.state_machine"] = {
		Make = function(M)
			local definition = M.Define({ name = "door", states = { "closed", "open" }, transitions = { closed = { "open" }, open = { "closed" } } })
			return { definition = definition, machine = definition:New("closed") }
		end,
	},
	["foundation.generator.state_chart"] = {
		Make = function(M)
			local chart = M.Chart({
				name = "Watch",
				port = core.port.New("Guard", { "Note" }),
				events = { "OnNoise" },
				queries = { "IsCalm" },
				initial = function(states) return states.Watch:New() end,
			})
			local states = { Watch = chart:State("Watch") }
			local machine = chart:New({ Note = function() end }, states)
			return { chart = chart, state = states.Watch, action = states.Watch:New(), machine = machine }
		end,
	},
	["foundation.transaction"] = { Make = function(M) return { transaction = M.New(), ledger = M.Ledger() } end },
	["foundation.analysis.analytics"] = {
		Make = function(M) return { analytics = M.New(Clock(), { Kilobytes = function() return 1000 end }) } end,
	},
	["foundation.wetsands.navsearch"] = {
		Make = function(M)
			local HL2 = T.require("foundation.wetsands.path.hl2")
			local mesh = Mesh(M)
			return {
				mesh = mesh,
				search = M.New(mesh, HL2, HL2.SOLDIER_LIMITS, Bot(), 1, 2, { x = 100, y = 0, z = 0 }, 100),
				told = M.Told(mesh, nil),
				calculator = M.Calculator(M.Told(mesh, nil), HL2, HL2.SOLDIER_LIMITS, Bot()),
			}
		end,
		fields = { search = SEARCH_FIELDS },
	},
}

local LIBRARIES = {
	["foundation.math.geometry"] = true,
	["foundation.math.scalar"] = true,
	["foundation.math.interval"] = true,
	["foundation.math.box"] = true,
	["foundation.math.choice"] = true,
	["foundation.list.select"] = true,
	["foundation.math.stats"] = true,
	["foundation.math.weighted"] = true,
	["foundation.math.polynomial"] = true,
	["foundation.graph.search"] = true,
	["foundation.encoding.utf16"] = true,
	["foundation.encoding.keyvalues"] = true,
	["foundation.encoding.consolecfg"] = true,
	["foundation.encoding.cvarfile"] = true,
	["foundation.encoding.gma"] = true,
	["foundation.analysis.memory"] = true,
	["foundation.wetsands.path"] = true,
	["foundation.nodegraph"] = true,
}

local TWINS = Twins()

T.test("the indexes publish twins", function()
	T.eq(#TWINS > 0, true, "Twin lines found")
end)

T.test("every Twin line has a native twin in a built binary", function()
	local missing = {}
	for _, module in ipairs(TWINS) do
		if NativeOf(T.Published.global[module]) == nil then missing[#missing + 1] = module end
	end
	T.eq(table.concat(missing, ", "), "", "modules a server would run in Lua")
end)

T.test("every Twin module has a recipe or is a library, and nothing else does", function()
	local twins, problems = {}, {}
	for _, module in ipairs(TWINS) do
		twins[module] = true
		if RECIPES[module] and LIBRARIES[module] then problems[#problems + 1] = module .. ": both a recipe and a library" end
		if not RECIPES[module] and not LIBRARIES[module] then problems[#problems + 1] = module .. ": neither a recipe nor a library" end
	end
	for module in pairs(RECIPES) do
		if not twins[module] then problems[#problems + 1] = module .. ": a recipe for no Twin" end
	end
	for module in pairs(LIBRARIES) do
		if not twins[module] then problems[#problems + 1] = module .. ": a library that is no Twin" end
	end
	table.sort(problems)
	Report(problems)
end)

T.test("each native-only name is still native, and no gamemode code reads it", function()
	local problems = {}
	local files = assert(io.popen("find addons -name '*.lua'"))
	local sources = {}
	for path in files:lines() do sources[#sources + 1] = path end
	files:close()
	for _, at in ipairs(Sorted(NATIVE_ONLY)) do
		local global, name = at:match("^(.+)%.([%w_]+)$")
		if Answer(NativeOf(global) or {}, name) == nil then problems[#problems + 1] = at .. ": no longer native; drop it from NATIVE_ONLY" end
		for _, path in ipairs(sources) do
			if ReadFile(path):find("[%.:]" .. name .. "%f[^%w_]") then problems[#problems + 1] = at .. ": read by " .. path end
		end
	end
	Report(problems)
end)

if T.NATIVE then
	T.test("on a server every Twin global is its binary's native twin", function()
		local problems = {}
		for _, module in ipairs(TWINS) do
			local global = T.Published.global[module]
			if not rawequal(At(_G, global), NativeOf(global)) then problems[#problems + 1] = global .. " is not the native twin" end
		end
		Report(problems)
	end)
	T.finish()
end

for _, module in ipairs(TWINS) do
	local global = T.Published.global[module]
	T.test(global .. ": the module's keys, tables and metamethods are the same in both", function()
		local problems = {}
		Compare(T.require(module), NativeOf(global), global, { depth = MODULE_DEPTH, numbers = true }, problems)
		Report(problems)
	end)
end

for _, crate in ipairs(CRATES) do
	for _, name in ipairs(Sorted(T.native(crate).preload or {})) do
		T.test(name .. ": the preloaded native part is its Lua module's keys", function()
			local problems = {}
			Compare(T.require(name), T.native(crate).preload[name], name, { depth = MODULE_DEPTH, numbers = true }, problems)
			Report(problems)
		end)
	end
end

for _, module in ipairs(TWINS) do
	local recipe, global = RECIPES[module], T.Published.global[module]
	if recipe then
		T.test(global .. ": what its constructors make answers to the same methods", function()
			local lua, native = recipe.Make(T.require(module)), recipe.Make(NativeOf(global))
			local problems = {}
			for _, name in ipairs(Sorted(lua)) do
				if native[name] == nil then
					problems[#problems + 1] = global .. " " .. name .. ": the native recipe made nothing"
				else
					Compare(lua[name], native[name], global .. " " .. name, { depth = 0, fields = (recipe.fields or {})[name] }, problems)
				end
			end
			Report(problems)
		end)
	end
end

T.finish()
