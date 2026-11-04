local T = dofile("tests/harness.lua")

local Locomotion = nextsoldier.locomotion
local FROM = { x = 0, y = 0, z = 100 }
local LANDING = { x = 10, y = 0, z = -100 }

local function Open() return true end

T.test("a route's point far below and near is a drop; one on its level or far off is not", function()
	T.eq(Locomotion.DropBelow(FROM, LANDING, 40, 48), true, "right below")
	T.eq(Locomotion.DropBelow(FROM, { x = 10, y = 0, z = 80 }, 40, 48), false, "a step down")
	T.eq(Locomotion.DropBelow(FROM, { x = 500, y = 0, z = -100 }, 40, 48), false, "not there yet")
	T.eq(Locomotion.DropBelow(FROM, { x = 10, y = 0, z = 400 }, 40, 48), false, "above it")
end)

T.test("it heads for where its body falls, past that point, at its own height", function()
	local point = Locomotion.StepOff(FROM, LANDING, Open, function(q) return q.x >= 40 end)
	T.eq(point.z, FROM.z, "its own height")
	T.eq(point.x > 40, true, "past where it falls, so it is still walking as it does")
end)

T.test("of the ways it could fall, the one nearest the landing", function()
	local point = Locomotion.StepOff(FROM, { x = -30, y = 0, z = -100 }, Open, function(q) return math.abs(q.x) >= 40 end)
	T.eq(point.x < 0, true, "toward the landing")
end)

T.test("a way a wall closes before it falls is no way", function()
	local point = Locomotion.StepOff(FROM, LANDING, function(q) return q.x < 16 end, function(q) return q.x >= 40 or q.x <= -40 end)
	T.eq(point.x < 0, true, "round the other side")
end)

T.test("nowhere to fall within reach is no step", function()
	T.eq(Locomotion.StepOff(FROM, LANDING, Open, function() return false end), nil, "nothing to walk to")
end)

T.finish()
