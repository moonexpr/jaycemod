-- foundation.list.ring: the last values pushed, up to a capacity.
local T = dofile("tests/harness.lua")
local Ring = list.ring

local function Joined(list) return table.concat(list, " ") end

T.test("a ring keeps its values oldest first until it is full", function()
	local ring = Ring.New(3)
	T.eq(ring:Size(), 0, "empty")
	T.eq(Joined(ring:Ordered()), "", "nothing")
	ring:Push(1)
	ring:Push(2)
	T.eq(ring:Size(), 2, "two")
	T.eq(Joined(ring:Ordered()), "1 2", "oldest first")
end)

T.test("a full ring drops its oldest value for each new one", function()
	local ring = Ring.New(3)
	for v = 1, 5 do ring:Push(v) end
	T.eq(ring:Size(), 3, "at capacity")
	T.eq(Joined(ring:Ordered()), "3 4 5", "the last three")
	ring:Push(6)
	T.eq(Joined(ring:Ordered()), "4 5 6", "and on")
end)

T.test("a ring needs a whole capacity of at least one", function()
	T.eq(pcall(Ring.New, 0), false, "zero")
	T.eq(pcall(Ring.New, 1.5), false, "a fraction")
end)

T.test("Newest is the last value pushed, nil for an empty ring", function()
	local ring = Ring.New(3)
	T.eq(ring:Newest(), nil, "empty")
	ring:Push("a")
	T.eq(ring:Newest(), "a", "one")
	for _, v in ipairs({ "b", "c", "d", "e" }) do ring:Push(v) end
	T.eq(ring:Newest(), "e", "after it has wrapped")
	T.eq(ring:Size(), 3, "reading it takes nothing")
end)

T.test("a table pushed is the table Newest gives, to be changed in place", function()
	local ring = Ring.New(2)
	local entry = { count = 1 }
	ring:Push(entry)
	ring:Newest().count = 2
	T.eq(ring:Ordered()[1].count, 2, "the ring holds the same table")
end)

T.finish()
