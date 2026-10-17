-- foundation.core.structs.queue: a double-ended queue.
local T = dofile("tests/harness.lua")
local Queue = T.require("foundation.core.structs.queue")

T.test("a queue gives values back first in, first out", function()
	local q = Queue.New()
	q:PushBack("a")
	q:PushBack("b")
	q:PushBack("c")
	T.eq(q:Size(), 3, "three")
	T.eq(q:Front(), "a", "the front, left in")
	T.eq(q:PopFront(), "a", "first")
	T.eq(q:PopFront(), "b", "second")
	T.eq(q:Size(), 1, "one left")
end)

T.test("both ends push and pop", function()
	local q = Queue.New()
	q:PushBack(2)
	q:PushFront(1)
	q:PushBack(3)
	T.eq(q:Back(), 3, "the back")
	T.eq(q:PopBack(), 3, "from the back")
	T.eq(q:PopFront(), 1, "from the front")
	T.eq(q:PopFront(), 2, "the last")
end)

T.test("an empty queue pops and peeks nil, and stays usable", function()
	local q = Queue.New()
	T.eq(q:PopFront(), nil, "front")
	T.eq(q:PopBack(), nil, "back")
	T.eq(q:Front(), nil, "peek")
	q:PushBack("x")
	T.eq(q:PopFront(), "x", "after")
	T.eq(q:Size(), 0, "empty again")
end)

T.test("values come out in order over many wraps", function()
	local q = Queue.New()
	local out = {}
	for i = 1, 1000 do
		q:PushBack(i)
		if i % 3 == 0 then out[#out + 1] = q:PopFront() end
	end
	while q:Size() > 0 do out[#out + 1] = q:PopFront() end
	local ordered = true
	for i = 1, 1000 do ordered = ordered and out[i] == i end
	T.eq(ordered, true, "1 to 1000")
end)

T.test("a queue iterates front to back without changing", function()
	local q = Queue.New()
	q:PushBack("b")
	q:PushFront("a")
	q:PushBack("c")
	local seen = {}
	for _, v in q:Values() do seen[#seen + 1] = v end
	T.eq(table.concat(seen), "abc", "in order")
	T.eq(q:Size(), 3, "untouched")
end)

T.finish()
