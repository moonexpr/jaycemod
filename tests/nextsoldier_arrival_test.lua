local T = dofile("tests/harness.lua")
local Locomotion = nextsoldier.locomotion

local function P(x, y, z) return { x = x, y = y, z = z } end

local GOAL = P(0, 0, 0)
local WITHIN, HEIGHT = 48, 176

T.test("a body within reach of its goal across the ground has arrived", function()
	T.eq(Locomotion.Arrived(P(WITHIN - 1, 0, 0), GOAL, WITHIN, HEIGHT), true)
	T.eq(Locomotion.Arrived(P(WITHIN + 1, 0, 0), GOAL, WITHIN, HEIGHT), false)
end)

T.test("a body riding a slope above its goal has arrived, its goal under it", function()
	T.eq(Locomotion.Arrived(P(14, 12, HEIGHT - 1), GOAL, WITHIN, HEIGHT), true)
end)

T.test("a body further above its goal than its height stands over it, on a deck", function()
	T.eq(Locomotion.Arrived(P(0, 0, HEIGHT + 1), GOAL, WITHIN, HEIGHT), false)
end)

T.test("a body below its goal arrives only within reach of it", function()
	T.eq(Locomotion.Arrived(P(0, 0, -WITHIN + 1), GOAL, WITHIN, HEIGHT), true)
	T.eq(Locomotion.Arrived(P(0, 0, -WITHIN - 1), GOAL, WITHIN, HEIGHT), false)
end)

T.finish()
