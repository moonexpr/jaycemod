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

-- The Lua twin of `module` ("tree.heap") and its native twin, or nil.
local function Twins(module)
	local ns, name = module:match("^([%w_]+)%.([%w_]+)$")
	if SERVER_SIDE then
		local installed = _G[ns] and _G[ns][name]
		local env = setmetatable({}, { __index = _G })
		local chunk = CompileFile(GAMEMODE.FolderName .. "/gamemode/" .. Path(module))
		setfenv(chunk, env)("ws_native_bench." .. module)
		local lua = package.loaded["ws_native_bench." .. module]
		local isNative = installed and type(installed.New) == "function" and debug.getinfo(installed.New, "S").what == "C"
		return lua, isNative and installed or nil
	end
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

local KEYS = Keys(N, 100000)

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
