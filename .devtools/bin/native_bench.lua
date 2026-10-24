-- Whether a native twin of a foundation module pays: each module's cases run
-- through its Lua twin and its native one, with the JIT on and off. A module
-- with no native twin has its Lua operation measured against the floor, what
-- a call into the native module costs (probe.Add), which no native twin of
-- an operation that cheap could beat.
--
-- Under plain LuaJIT (the native twins from the built native/foundation):
--   luajit .devtools/bin/native_bench.lua [module ...]
-- On the dedicated server (native twins installed over the globals, the Lua
-- twins compiled beside them; the floor is unmeasured there, as GMod has no
-- package.loadlib for the probe):
--   dt lua -f .devtools/bin/native_bench.lua
--   dt lua 'return WSNativeBench.Run()'           or Run({ "tree.heap" })
-- Prints ns per operation, best of ROUNDS, JIT on and off.
local ROUNDS = 5
local clock = SysTime or os.clock
local SERVER_SIDE = SERVER ~= nil

local Bench = {}

-- Twins ------------------------------------------------------------------------------

local native, floor

local function Path(module)
	return "foundation/" .. module:gsub("%.", "/") .. ".lua"
end

-- The Lua twin of `module` ("tree.heap", or a root module: "nodegraph")
-- and its native twin, or nil.
-- Whether any of a module's functions is native: replaced whole (`New`)
-- or patched function by function.
local function HasNative(installed)
	if type(installed) ~= "table" then return false end
	for _, value in pairs(installed) do
		if type(value) == "function" and debug.getinfo(value, "S").what == "C" then return true end
	end
	return false
end

local function Twins(module)
	local ns, name = module:match("^([%w_]+)%.([%w_]+)$")
	if SERVER_SIDE then
		local installed
		if ns then installed = _G[ns] and _G[ns][name] else installed = _G[module] end
		local env = setmetatable({}, { __index = _G })
		local chunk = CompileFile(GAMEMODE.FolderName .. "/gamemode/" .. Path(module))
		setfenv(chunk, env)("ws_native_bench." .. module)
		local lua = package.loaded["ws_native_bench." .. module]
		return lua, HasNative(installed) and installed or nil
	end
	if not ns then return _G[module], native[module] end
	return _G[ns][name], native[ns] and native[ns][name] or nil
end

-- Cases: module -> { label, ops, run(M) } -------------------------------------------

local N = 20000

local function Keys(n, span)
	local keys, x = {}, 12345
	for i = 1, n do
		x = (x * 1103515245 + 12345) % 2147483648
		keys[i] = x % span
	end
	return keys
end

local KEYS = Keys(N + 3, 100000)

-- At a TF2 map's scale (cp_spookeyridge: 2003 areas, 353 hiding spots,
-- the seams between): what nodegraph's build runs between its yields,
-- built once so only the call is timed.
local NODEGRAPH = { areas = {}, positions = {}, zones = {} }
for i = 1, 6000 do
	NODEGRAPH.areas[i] = { pos = { x = KEYS[i] % 8000, y = KEYS[i + 1] % 8000, z = KEYS[i + 2] % 400 }, size = KEYS[i] % 900 }
end
for i = 1, 1500 do
	NODEGRAPH.positions[i] = { x = KEYS[i] % 8000, y = KEYS[i + 1] % 8000, z = KEYS[i + 2] % 400 }
	NODEGRAPH.zones[i] = 4 + math.floor(NODEGRAPH.positions[i].x / 1000)
end

local CASES = {
	["tree.heap"] = {
		{ "push and pop 20k (numbers)", 2 * N, function(Heap)
			local heap = Heap()
			for i = 1, N do heap:Push(KEYS[i], i) end
			for _ = 1, N do heap:Pop() end
		end },
		{ "search-like: 3 pushes a pop, 6k", 4 * 6000, function(Heap)
			local heap, entry = Heap(), {}
			heap:Push(0, entry)
			for i = 1, 6000 do
				local _, key = heap:Pop()
				key = key or 0
				heap:Push(key + KEYS[i] % 97, entry)
				heap:Push(key + KEYS[i + 1] % 89, entry)
				heap:Push(key + KEYS[i + 2] % 83, entry)
			end
		end },
	},
	["tree.avl"] = {
		{ "insert 20k keys", N, function(Avl)
			local tree = Avl()
			for i = 1, N do tree:Insert(KEYS[i], i) end
		end },
		{ "insert 20k, get each", 2 * N, function(Avl)
			local tree = Avl()
			for i = 1, N do tree:Insert(KEYS[i], i) end
			for i = 1, N do tree:Get(KEYS[i]) end
		end },
		{ "insert 20k, 20k floors", 2 * N, function(Avl)
			local tree = Avl()
			for i = 1, N do tree:Insert(KEYS[i], i) end
			for i = 1, N do tree:Floor(KEYS[i] + 0.5) end
		end },
		{ "insert 20k, walk in order", 2 * N, function(Avl)
			local tree = Avl()
			for i = 1, N do tree:Insert(KEYS[i], i) end
			for _ in tree:Pairs() do end
		end },
		{ "insert 20k, remove each", 2 * N, function(Avl)
			local tree = Avl()
			for i = 1, N do tree:Insert(KEYS[i], i) end
			for i = 1, N do tree:Remove(KEYS[i]) end
		end },
	},
	["list.queue"] = {
		{ "push back, pop front", 2 * N, function(Queue)
			local q = Queue.New()
			for i = 1, N do q:PushBack(i) end
			for _ = 1, N do q:PopFront() end
		end },
	},
	["list.ring"] = {
		{ "push into 64", N, function(Ring)
			local ring = Ring.New(64)
			for i = 1, N do ring:Push(i) end
		end },
	},
	["list.slots"] = {
		{ "alloc then free", 2 * N, function(Slots)
			local pool, got = Slots.New(), {}
			for i = 1, N do got[i] = pool:Alloc() end
			for i = 1, N do pool:Free(got[i]) end
		end },
	},
	["list.chain"] = {
		{ "push back, move front, unlink", 3 * N, function(Chain)
			local chain = Chain.New()
			for i = 1, N do chain:PushBack(i) end
			for i = 1, N do chain:MoveFront(KEYS[i] % N + 1) end
			for i = 1, N do chain:Unlink(i) end
		end },
	},
	["world.pairmap"] = {
		{ "set then get", 2 * N, function(PairMap)
			local map = PairMap.New()
			for i = 1, N do map:Set(i, KEYS[i] % 5000, i) end
			for i = 1, N do map:Get(i, KEYS[i] % 5000) end
		end },
	},
	["world.lease"] = {
		{ "take, holder, release", 3 * N, function(Lease)
			local leases, holder = Lease.New(), {}
			for i = 1, N do leases:Take(KEYS[i] % 500, holder, i, 10) end
			for i = 1, N do leases:Holder(KEYS[i] % 500, i) end
			for i = 1, N do leases:Release(KEYS[i] % 500, holder) end
		end },
	},
	["world.sets"] = {
		{ "named set Has", N, function(Sets)
			local set = Sets.Named("bench", { "alpha", "beta", "gamma", "delta" })
			local words = { "alpha", "beta", "omega", "delta" }
			for i = 1, N do set:Has(words[i % 4 + 1]) end
		end },
	},
	["math.geometry"] = {
		{ "Distance of two points", N, function(Geometry)
			local a, b = { x = 1, y = 2, z = 3 }, { x = 4, y = 6, z = 8 }
			for _ = 1, N do Geometry.Distance(a, b) end
		end },
		{ "Normalize (a new point)", N, function(Geometry)
			local a = { x = 1, y = 2, z = 3 }
			for _ = 1, N do Geometry.Normalize(a) end
		end },
	},
	["math.scalar"] = {
		{ "Clamp", N, function(Scalar)
			for i = 1, N do Scalar.Clamp(KEYS[i], 100, 90000) end
		end },
	},
	["math.weighted"] = {
		{ "PickWeighted of 10", N, function(Weighted)
			local items = {}
			for i = 1, 10 do items[i] = { w = i } end
			local function Weight(item) return item.w end
			for i = 1, N do Weighted.PickWeighted(items, Weight, (KEYS[i] % 1000) / 1000) end
		end },
	},
	["math.polynomial"] = {
		{ "Evaluate a cubic", N, function(Polynomial)
			local c = { 1, -2, 3, 0.5 }
			for i = 1, N do Polynomial.Evaluate(c, i / N) end
		end },
		{ "Roots of a cubic", N, function(Polynomial)
			local c = { -6, 11, -6, 1 }
			for _ = 1, N do Polynomial.Roots(c) end
		end },
	},
	["math.stats"] = {
		{ "Percentile of 1000 (one call)", 1, function(Stats)
			local list = {}
			for i = 1, 1000 do list[i] = KEYS[i] end
			Stats.Percentile(list, 0.9)
		end },
		{ "Mean of 1000 (one call)", 1, function(Stats)
			local list = {}
			for i = 1, 1000 do list[i] = KEYS[i] end
			Stats.Mean(list)
		end },
	},
	["math.matrix"] = {
		{ "8x8 multiply (one call)", 1, function(Matrix)
			local rows = {}
			for i = 1, 8 do rows[i] = {} for j = 1, 8 do rows[i][j] = (KEYS[i * 8 + j] % 100) / 7 end end
			local m = Matrix.New(rows)
			m:Multiply(m)
		end },
		{ "32x32 inverse (one call)", 1, function(Matrix)
			local rows = {}
			for i = 1, 32 do rows[i] = {} for j = 1, 32 do rows[i][j] = (KEYS[i * 32 + j] % 100) / 7 + (i == j and 50 or 0) end end
			Matrix.New(rows):Inverse()
		end },
	},
	["math.polyline"] = {
		{ "DistanceOf on 200 points", N / 10, function(Polyline)
			local points = {}
			for i = 1, 200 do points[i] = { x = i * 50, y = (KEYS[i] % 300), z = 0 } end
			local line = Polyline.New(points)
			for i = 1, N / 10 do line:DistanceOf({ x = KEYS[i] % 10000, y = 100, z = 0 }) end
		end },
		{ "PointAt on 200 points", N, function(Polyline)
			local points = {}
			for i = 1, 200 do points[i] = { x = i * 50, y = (KEYS[i] % 300), z = 0 } end
			local line = Polyline.New(points)
			local length = line:Length()
			for i = 1, N do line:PointAt((KEYS[i] % 1000) / 1000 * length) end
		end },
	},
	["nodegraph"] = {
		{ "PickNodes of 6000 at 96 (one call)", 1, function(Graph)
			Graph.PickNodes(NODEGRAPH.areas, 96, math.huge)
		end },
		{ "Candidates of 1500 within 512 (one call)", 1, function(Graph)
			Graph.Candidates(NODEGRAPH.positions, 512, 16)
		end },
		{ "Bridges of 1500 within 720 (one call)", 1, function(Graph)
			Graph.Bridges(NODEGRAPH.positions, NODEGRAPH.zones, 720, 4)
		end },
	},
	["world.grid"] = {
		{ "Thin 5000 points (one call)", 1, function(Grid)
			local points = {}
			for i = 1, 5000 do points[i] = { x = KEYS[i] % 4000, y = KEYS[i + 1] % 4000, z = KEYS[i + 2] % 300 } end
			Grid.Thin(points, 64)
		end },
		{ "Put 5000, Near each", 5000, function(Grid)
			local grid, points = Grid.New(128), {}
			for i = 1, 5000 do points[i] = { x = KEYS[i] % 4000, y = KEYS[i + 1] % 4000 } grid:Put(points[i], i) end
			for i = 1, 5000 do grid:Near(points[i], function() end) end
		end },
	},
}

-- Running ----------------------------------------------------------------------------

local function Time(fn, M, ops)
	local best = math.huge
	for _ = 1, ROUNDS do
		local start = clock()
		fn(M)
		best = math.min(best, clock() - start)
	end
	return best / ops * 1e9
end

local function Measure(fn, M, ops)
	local result = {}
	for _, mode in ipairs({ "on", "off" }) do
		jit.flush()
		if mode == "on" then jit.on() else jit.off() end
		result[mode] = Time(fn, M, ops)
	end
	jit.on()
	return result
end

local function Floor()
	if not floor then return nil end
	local add = floor.Add
	return Measure(function()
		local s = 0
		for i = 1, 1e6 do s = add(s, i) end
	end, nil, 1e6)
end

function Bench.Run(modules)
	if not modules then
		modules = {}
		for module in pairs(CASES) do modules[#modules + 1] = module end
		table.sort(modules)
	end
	local lines = {}
	local f = Floor()
	if f then lines[#lines + 1] = string.format("%-46s JIT on %8.1f ns   off %8.1f ns", "floor: a native call (probe.Add)", f.on, f.off) end
	for _, module in ipairs(modules) do
		local lua, twin = Twins(module)
		for _, case in ipairs(CASES[module] or {}) do
			local label, ops, run = case[1], case[2], case[3]
			local l = Measure(run, lua, ops)
			local line = string.format("%-12s %-33s Lua on %7.1f off %7.1f", module, label, l.on, l.off)
			if twin then
				local n = Measure(run, twin, ops)
				line = line .. string.format(" | native on %7.1f off %7.1f ns (%.2fx, %.2fx)", n.on, n.off, l.on / n.on, l.off / n.off)
			end
			lines[#lines + 1] = line
		end
	end
	local report = table.concat(lines, "\n")
	print(report)
	return report
end

if SERVER_SIDE then
	WSNativeBench = Bench
else
	dofile("tests/harness.lua")
	local loaded = assert(package.loadlib("native/foundation/target/release/libfoundation.dylib", "luaopen_foundation"))()
	native, floor = loaded, loaded.probe
	local modules = #arg > 0 and arg or nil
	Bench.Run(modules)
end
