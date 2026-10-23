-- foundation.analysis.memory: estimated bytes held by named roots.
local T = dofile("tests/harness.lua")
local Memory = analysis.memory

local function Bytes(report, name)
	for _, row in ipairs(report.rows) do
		if row.name == name then return row.bytes end
	end
	return nil
end

T.test("a table's estimate grows with its array, its hash and its strings", function()
	local empty = Bytes(Memory.Measure({ { "t", {} } }), "t")
	T.eq(empty, Memory.TABLE, "an empty table is its header")
	local array = Bytes(Memory.Measure({ { "t", { 1, 2, 3 } } }), "t")
	T.eq(array, Memory.TABLE + 3 * Memory.ARRAY_SLOT, "three array slots")
	local hashed = Bytes(Memory.Measure({ { "t", { a = 1 } } }), "t")
	T.eq(hashed, Memory.TABLE + Memory.HASH_NODE + Memory.STRING + #"a" + 1, "one node and its key")
end)

T.test("a hash part is a power of two nodes", function()
	local three = Bytes(Memory.Measure({ { "t", { a = true, b = true, c = true } } }), "t")
	T.eq(three, Memory.TABLE + 4 * Memory.HASH_NODE + 3 * (Memory.STRING + 2), "three keys take four nodes")
end)

T.test("nested tables count, each object once, credited to the first root to reach it", function()
	local shared = { 1, 2, 3, 4 }
	local report = Memory.Measure({ { "a", { shared } }, { "b", { shared } } })
	local sharedBytes = Memory.TABLE + 4 * Memory.ARRAY_SLOT
	T.eq(Bytes(report, "a"), Memory.TABLE + Memory.ARRAY_SLOT + sharedBytes, "a holds it")
	T.eq(Bytes(report, "b"), Memory.TABLE + Memory.ARRAY_SLOT, "b only points at it")
	T.eq(report.total, Bytes(report, "a") + Bytes(report, "b"), "the total")
end)

T.test("cycles end, and metatables count", function()
	local t = {}
	t[1] = t
	local cyclic = Bytes(Memory.Measure({ { "t", t } }), "t")
	T.eq(cyclic, Memory.TABLE + Memory.ARRAY_SLOT, "itself once")
	local meta = {}
	local withMeta = Bytes(Memory.Measure({ { "t", setmetatable({}, meta) } }), "t")
	T.eq(withMeta, 2 * Memory.TABLE, "its metatable too")
end)

T.test("functions count as closures, their upvalues not followed", function()
	local big = {}
	for i = 1, 100 do big[i] = i end
	local f = function() return big end
	T.eq(Bytes(Memory.Measure({ { "f", f } }), "f") < Memory.TABLE, true, "the closure alone")
end)

T.test("a report formats the largest roots first", function()
	local lines = Memory.Format(Memory.Measure({ { "small", {} }, { "large", { 1, 2, 3 } } }), 10)
	T.eq(lines[2]:find("large", 1, true) ~= nil, true, "large first")
	T.eq(lines[3]:find("small", 1, true) ~= nil, true, "then small")
end)

T.finish()
