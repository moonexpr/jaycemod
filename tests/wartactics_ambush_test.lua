-- wartactics.ambush (.devtools/bin/test_ambush.py the reference): plain
-- geometry over the incursion's crossings and walks, given here by hand.
local T = dofile("tests/harness.lua")
local Ambush = wartactics.ambush

local RED, BLU = "RED", "BLU"
local CELL = 100

-- BLU's spawn 1, a corridor 2-3-4 (the approach), a doorway at 5 into a hall
-- 6-7-8, RED's spawn 9 behind it; areas 1-5 corridor, 6-9 the room.
local CORRIDOR, ROOM = { id = 1, kind = "corridor" }, { id = 1, kind = "room" }
local function region(a) return (a >= 6 and a <= 9) and ROOM or (a >= 1 and a <= 5) and CORRIDOR or nil end

local function Crossings()
	local crossings = {}
	for i = 1, 9 do crossings[i] = {} end
	for i = 1, 8 do
		local via = { x = (i + 0.5) * CELL, y = 0, z = 0 }
		crossings[i][i + 1] = { cost = CELL, via = via, width = CELL }
		crossings[i + 1][i] = { cost = CELL, via = via, width = CELL }
	end
	return crossings
end

local PATH = { team = BLU, areas = { 1, 2, 3, 4, 5, 6, 7, 8, 9 } }

local function Walk(from)
	return { Distance = function(_, n) return math.abs(n - from) * CELL end }
end

local FIELDS = { [BLU] = Walk(1), [RED] = Walk(9) }
local G = { node = setmetatable({}, { __index = function(_, a) return a end }) }

local function Spot(area, sees, x, y)
	local set = {}
	for _, a in ipairs(sees) do set[a] = true end
	return { pos = { x = (x or area) * CELL, y = (y or 1) * CELL, z = 0 }, area = area, sees = set }
end

local function Door()
	return Ambush.Entrances({ PATH }, Crossings(), region, 2.5 * CELL)[1]
end

local function Marks(spots, regionOf)
	return Ambush.Ambushes({ Door() }, spots, FIELDS, G, regionOf or region, 0.5 * CELL, 3 * CELL)
end

T.test("an entrance is where an enemy path steps into a room, its approach the walk before", function()
	local entrances = Ambush.Entrances({ PATH }, Crossings(), region, 2.5 * CELL)
	T.eq(#entrances, 1)
	local door = entrances[1]
	T.eq(door.outside, 5)
	T.eq(door.inside, 6)
	T.eq(door.room, ROOM)
	T.eq(#door.approach, 2)
	T.eq(door.approach[1].x, 3.5 * CELL, "the farthest first")
	T.eq(door.approach[2].x, 4.5 * CELL)
	T.eq(door.via.x, 5.5 * CELL)
	T.eq(door.width, CELL)
	T.eq(door.heading.x, 1)
	T.eq(door.heading.y, 0)
end)

T.test("paths through one entrance are counted once an entrance", function()
	T.eq(Ambush.Entrances({ PATH, PATH }, Crossings(), region, CELL)[1].paths, 2)
end)

T.test("stepping into a corridor, or into a room straight from the spawn, is no entrance", function()
	local function corridors(a) return { id = a < 6 and 1 or 2, kind = "corridor" } end
	T.eq(#Ambush.Entrances({ PATH }, Crossings(), corridors, CELL), 0)
	T.eq(#Ambush.Entrances({ { team = BLU, areas = { 5, 6 } } }, Crossings(), region, CELL), 0)
end)

T.test("a spot beside the door, out of the approach's sight through it, is an ambush for the defenders", function()
	local found = Marks({ Spot(6, { 6 }, 6, 1.5) })
	T.eq(#found, 1)
	T.eq(found[1].team, RED)
	T.eq(found[1].spot.area, 6)
end)

T.test("a spot ahead of the door is in the wedge the squad sees through it", function()
	T.eq(#Marks({ Spot(7, { 6 }, 7, 0.6) }), 0)
	T.eq(#Marks({ Spot(6, { 6 }, 6.5, 0.9) }), 0, "seen from the doorway's mouth")
end)

T.test("a spot with no line of fire, outside the room, or out of range is none", function()
	T.eq(#Marks({ Spot(6, { 7, 8 }, 6, 1.5) }), 0, "does not see inside the entrance")
	T.eq(#Marks({ Spot(4, { 6 }, 4.5, 1.5) }), 0, "on the squad's side of the door")
	T.eq(#Marks({ Spot(6, { 6 }, 5.6, 0.3) }), 0, "too near the doorway")
	T.eq(#Marks({ Spot(9, { 6 }, 9, 3) }), 0, "too far from it")
end)

T.test("the defenders must reach the spot before the enemy reaches the entrance", function()
	local function far(a) return a == 2 and ROOM or region(a) end
	T.eq(#Marks({ Spot(2, { 6 }, 6, 1.5) }, far), 0, "BLU is there first")
end)

T.test("hidden: behind the wall the doorway is cut in, from every point of the approach", function()
	local door = Door()
	T.eq(Ambush.Hidden({ x = 6 * CELL, y = 1.5 * CELL }, door), true)
	T.eq(Ambush.Hidden({ x = 7 * CELL, y = 0.2 * CELL }, door), false)
	T.eq(Ambush.Hidden({ x = 5 * CELL, y = 2 * CELL }, door), false, "not through the door")
end)

T.finish()
