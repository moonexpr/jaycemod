-- features.aiwar.punt: a soldier's gravity gun gadget punts the nearest
-- enemy within the gravity gun's reach (physcannon_tracelength) with
-- nothing solid between them.
local T = dofile("tests/harness.lua")
local Punt = T.require("features.aiwar.punt")

local function C(name, distance, enemy, clear)
	return { name = name, distance = distance, enemy = enemy, clear = clear }
end

T.test("the punt reaches as far as HL2's gravity gun", function()
	T.eq(Punt.REACH, 250, "physcannon_tracelength")
end)

T.test("it punts the nearest enemy in reach it can see", function()
	local picked = Punt.Pick({ C("far", 200, true, true), C("near", 90, true, true) })
	T.eq(picked.name, "near", "the nearest")
end)

T.test("never a teammate, one behind a wall, or one out of reach", function()
	T.eq(Punt.Pick({ C("mate", 50, false, true) }), nil, "a teammate")
	T.eq(Punt.Pick({ C("hidden", 50, true, false) }), nil, "behind a wall")
	T.eq(Punt.Pick({ C("far", Punt.REACH + 1, true, true) }), nil, "out of reach")
	T.eq(Punt.Pick({}), nil, "nobody")
	T.eq(Punt.Pick({ C("mate", 40, false, true), C("foe", 120, true, true) }).name, "foe", "past the teammate")
end)

T.finish()
