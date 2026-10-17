-- foundation.core.structs.heap: a binary heap ordered by the caller's rule.
local T = dofile("tests/harness.lua")
local Heap = T.require("foundation.core.structs.heap")

local function Less(a, b) return a < b end

local function Drain(heap)
	local out = {}
	while heap:Size() > 0 do out[#out + 1] = heap:Pop() end
	return table.concat(out, " ")
end

T.test("values come out in the order the rule puts first", function()
	local heap = Heap.New(Less)
	for _, v in ipairs({ 5, 3, 8, 1, 9, 2, 7 }) do heap:Push(v) end
	T.eq(heap:Size(), 7, "all pushed")
	T.eq(heap:Peek(), 1, "the first, left in")
	T.eq(heap:Size(), 7, "peeking takes nothing")
	T.eq(Drain(heap), "1 2 3 5 7 8 9", "smallest first")
end)

T.test("an empty heap pops and peeks nil", function()
	local heap = Heap.New(Less)
	T.eq(heap:Pop(), nil, "pop")
	T.eq(heap:Peek(), nil, "peek")
	T.eq(heap:Size(), 0, "still empty")
end)

T.test("values the rule calls equal keep no order of their own: the rule must break ties", function()
	local seq = 0
	local function Entry(key, name)
		seq = seq + 1
		return { key = key, name = name, seq = seq }
	end
	local function Before(a, b)
		if a.key ~= b.key then return a.key < b.key end
		return a.seq < b.seq
	end
	local heap = Heap.New(Before)
	for _, e in ipairs({ Entry(2, "b1"), Entry(1, "a1"), Entry(2, "b2"), Entry(1, "a2"), Entry(2, "b3") }) do heap:Push(e) end
	local out = {}
	while heap:Size() > 0 do out[#out + 1] = heap:Pop().name end
	T.eq(table.concat(out, " "), "a1 a2 b1 b2 b3", "pushed first among equals comes out first")
end)

T.test("pushes and pops interleaved keep the order", function()
	local heap = Heap.New(Less)
	heap:Push(4)
	heap:Push(2)
	T.eq(heap:Pop(), 2, "smallest")
	heap:Push(1)
	heap:Push(3)
	T.eq(Drain(heap), "1 3 4", "the rest")
end)

T.finish()
