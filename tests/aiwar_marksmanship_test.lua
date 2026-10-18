-- foundation.aiwar.marksmanship: how well the AI war's soldiers shoot, by
-- TF2's bot difficulty (tf_bot_difficulty: 0 easy, 1 normal, 2 hard, 3
-- expert). Expert is the soldiers as they were: dead-on aim, their guns'
-- own spread, firing the moment they have an enemy. Below it they aim off
-- by up to an error cone, their spread widens, and they wait a reaction
-- time before the first shot at a new enemy (TF2's IVision recognize time).
local T = dofile("tests/harness.lua")
local M = T.require("foundation.aiwar.marksmanship")
local Geometry = T.require("foundation.core.math.geometry")

local function Angle(a, b)
	local cos = Geometry.Dot(Geometry.Normalize(a), Geometry.Normalize(b))
	return math.deg(math.acos(math.max(-1, math.min(1, cos))))
end

T.test("four levels, TF2's, normal by default", function()
	T.eq(M.EASY, 0, "easy")
	T.eq(M.NORMAL, 1, "normal")
	T.eq(M.HARD, 2, "hard")
	T.eq(M.EXPERT, 3, "expert")
	T.eq(M.DEFAULT, M.NORMAL, "normal by default")
end)

T.test("expert shoots as the soldiers always have", function()
	local expert = M.For(M.EXPERT)
	T.eq(expert.aimError, 0, "no aim error")
	T.eq(expert.spreadScale, 1, "the gun's own spread")
	T.eq(expert.reaction, 0, "no reaction time")
end)

T.test("each level down aims worse, spreads wider and reacts slower; normal greatly so", function()
	for level = M.EASY, M.HARD do
		local this, harder = M.For(level), M.For(level + 1)
		T.eq(this.aimError > harder.aimError, true, level .. ": more aim error")
		T.eq(this.spreadScale > harder.spreadScale, true, level .. ": more spread")
		T.eq(this.reaction > harder.reaction, true, level .. ": slower")
	end
	local normal = M.For(M.NORMAL)
	T.eq(normal.spreadScale >= 2, true, "normal at least doubles the spread")
	T.eq(normal.aimError >= 4, true, "and misses by degrees")
	T.eq(normal.reaction >= 0.5, true, "and takes half a second to react")
end)

T.test("an unknown level is clamped to the nearest", function()
	T.eq(M.For(-4), M.For(M.EASY), "below easy")
	T.eq(M.For(9), M.For(M.EXPERT), "above expert")
	T.eq(M.For(1.6), M.For(M.HARD), "rounded")
end)

T.test("aim error turns the shot within its cone, and no further", function()
	local dir = { x = 1, y = 0, z = 0 }
	for _, r in ipairs({ { 0, 0 }, { 1, 0.25 }, { 0.5, 0.5 }, { 1, 1 }, { 0.999, 0.75 } }) do
		local aimed = M.Aim(dir, 6, r[1], r[2])
		T.eq(Angle(dir, aimed) <= 6 + 1e-6, true, "within 6 degrees: " .. Angle(dir, aimed))
		T.eq(math.abs(Geometry.Length(aimed) - 1) < 1e-9, true, "a unit direction")
	end
	T.eq(Angle(dir, M.Aim(dir, 6, 1, 0)) > 5.9, true, "the cone's edge reached")
	local straight = M.Aim(dir, 0, 0.7, 0.3)
	T.eq(Angle(dir, straight) < 1e-6, true, "no error: straight")
	local up = { x = 0, y = 0, z = 1 }
	T.eq(Angle(up, M.Aim(up, 6, 1, 0.5)) <= 6 + 1e-6, true, "straight up too")
end)

T.test("spread scales on both axes", function()
	local s = M.Spread({ x = 0.02, y = 0.03, z = 0 }, 2.5)
	T.eq(math.abs(s.x - 0.05) < 1e-9 and math.abs(s.y - 0.075) < 1e-9 and s.z == 0, true, "scaled")
end)

T.finish()
