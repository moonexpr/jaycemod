-- What a call into the native foundation module costs against the Lua it
-- would replace, with the JIT on and off, under plain LuaJIT (GMod has no
-- package.loadlib, and the module installs nothing there yet):
--   luajit .devtools/bin/native_boundary_bench.lua native/foundation/target/release/libfoundation.dylib
-- Prints one line per case: ns per operation, JIT on and off.
local path = assert((...) or arg and arg[1], "usage: native_boundary_bench.lua <path to the built module>")
local native = assert(package.loadlib(path, "luaopen_foundation"))()

local Heap = tree and tree.heap
if not Heap then
	local root = "addons/sandcastle/gamemodes/sandcastle/gamemode/foundation/"
	assert(loadfile(root .. "tree/heap.lua"))("foundation.tree.heap")
	Heap = foundation.tree.heap
end

local clock = SysTime or os.clock
local CALLS = 2e6
local HEAP_SIZE = 2e4
local ROUNDS = 5

-- The best of ROUNDS runs of fn(), in ns per operation of `ops`.
local function Time(fn, ops)
	local best = math.huge
	for _ = 1, ROUNDS do
		local start = clock()
		fn()
		best = math.min(best, clock() - start)
	end
	return best / ops * 1e9
end

local function Empty() end
local function Add(a, b) return a + b end

local nothing, add = native.probe.Nothing, native.probe.Add

-- Keys from a fixed linear congruential sequence, so each run sees the same.
local keys = {}
do
	local x = 12345
	for i = 1, HEAP_SIZE do
		x = (x * 1103515245 + 12345) % 2147483648
		keys[i] = x % 100000
	end
end

local function Before(a, b) return a.key < b.key end

local cases = {
	{ "call: Lua function, empty", CALLS, function()
		for _ = 1, CALLS do Empty() end
	end },
	{ "call: native, empty", CALLS, function()
		for _ = 1, CALLS do nothing() end
	end },
	{ "call: Lua add", CALLS, function()
		local s = 0
		for i = 1, CALLS do s = Add(s, i) end
	end },
	{ "call: native add", CALLS, function()
		local s = 0
		for i = 1, CALLS do s = add(s, i) end
	end },
	{ "heap: tree.heap of { key, value }, push+pop", HEAP_SIZE * 2, function()
		local heap = Heap.New(Before)
		for i = 1, HEAP_SIZE do heap:Push({ key = keys[i], value = i }) end
		for _ = 1, HEAP_SIZE do heap:Pop() end
	end },
	{ "heap: native, push+pop", HEAP_SIZE * 2, function()
		local heap = native.heap.New()
		for i = 1, HEAP_SIZE do heap:Push(keys[i], i) end
		for _ = 1, HEAP_SIZE do heap:Pop() end
	end },
}

local results = {}
for _, mode in ipairs({ "on", "off" }) do
	jit.flush()
	if mode == "on" then jit.on() else jit.off() end
	for i, case in ipairs(cases) do
		results[i] = results[i] or {}
		results[i][mode] = Time(case[3], case[2])
	end
end
jit.on()

local lines = {}
for i, case in ipairs(cases) do
	lines[#lines + 1] = string.format("%-48s JIT on %8.1f ns   off %8.1f ns", case[1], results[i].on, results[i].off)
end
local report = table.concat(lines, "\n")
print(report)
return report
