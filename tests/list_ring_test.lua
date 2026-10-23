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

T.finish()
