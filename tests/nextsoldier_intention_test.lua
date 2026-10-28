-- nextsoldier.intention: what a soldier with an enemy does about it (TF2's
-- IIntention for base_nextsoldier): the stage of fighting it by distance,
-- whether it attacks, and which of two threats is the more dangerous.
local T = dofile("tests/harness.lua")
local Intention = nextsoldier.intention

local RANGES = Intention.Ranges({ reach = 600, avoid = 150, range = 1500, melee = 60 })

T.test("the stage by the enemy's distance: chase past reach, avoid inside avoid, else hold", function()
	T.eq(Intention.Stage(800, RANGES), Intention.CHASE)
	T.eq(Intention.Stage(100, RANGES), Intention.AVOID)
	T.eq(Intention.Stage(400, RANGES), Intention.HOLD)
	T.eq(Intention.Stage(600, RANGES), Intention.HOLD, "at reach: holds")
end)

T.test("no avoid range: it never avoids", function()
	T.eq(Intention.Stage(10, Intention.Ranges({ reach = 600, avoid = 0, range = 1500, melee = 60 })), Intention.HOLD)
end)

T.test("it attacks only an enemy it sees: in melee reach with a melee weapon, else in range", function()
	T.eq(Intention.Attack(40, RANGES, true, true), Intention.MELEE)
	T.eq(Intention.Attack(40, RANGES, true, false), Intention.RANGED, "a gun at close quarters fires")
	T.eq(Intention.Attack(900, RANGES, true, false), Intention.RANGED)
	T.eq(Intention.Attack(2000, RANGES, true, false), nil, "out of range")
	T.eq(Intention.Attack(40, RANGES, false, true), nil, "not seen")
	T.eq(Intention.Attack(900, RANGES, true, true), nil, "a melee weapon out of reach")
end)

T.test("the more dangerous threat: the class's answer first", function()
	local ask = function(a, b) return a == "b" end
	T.eq(Intention.Better("b", "a", ask, function() return 0 end, function() return 0 end), true)
	T.eq(Intention.Better("a", "b", ask, function() return 0 end, function() return 0 end), false)
end)

T.test("no answer: the higher priority, then the nearer", function()
	local none = function() return nil end
	local priority = { a = 1, b = 5, c = 5 }
	local distance = { a = 10, b = 900, c = 300 }
	local P, D = function(x) return priority[x] end, function(x) return distance[x] end
	T.eq(Intention.Better("b", "a", none, P, D), true, "priority")
	T.eq(Intention.Better("c", "b", none, P, D), true, "equal priority: nearer")
	T.eq(Intention.Better("b", "c", none, P, D), false)
end)

T.test("ranges are made once, refused missing a part or not a number", function()
	T.eq(pcall(Intention.Ranges, { reach = 600 }), false)
	T.eq(pcall(Intention.Ranges, { reach = 600, avoid = 0, range = "far", melee = 60 }), false)
end)

T.finish()
