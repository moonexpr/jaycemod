-- nextsoldier.locomotion.ladder: a walker's climb of a nav ladder as a line it is moved
-- along: to the ladder's foot or head, along the ladder, onto the far area.
local T = dofile ("tests/harness.lua")
local Ladder = nextsoldier.locomotion.ladder

T.defined (Ladder.UP, "UP")
T.defined (Ladder.DOWN, "DOWN")
T.defined (Ladder.SPEED, "SPEED")
T.defined (Ladder.REACH, "REACH")
T.defined (Ladder.LIP, "LIP")

local function P (x, y, z) return { x = x, y = y, z = z } end

-- A ladder on a wall facing -y, 100 tall, its upper floor behind the wall.
local BOTTOM, TOP, NORMAL = P (0, 0, 0), P (0, 0, 100), P (0, -1, 0)
local HALF_WIDTH = 10

local function Up (from, landing)
	return Ladder.Climb (
		{
			from = from,
			bottom = BOTTOM,
			top = TOP,
			normal = NORMAL,
			halfWidth = HALF_WIDTH,
			landing = landing,
			down = false
		}
	)
end

local function Down (from, landing)
	return Ladder.Climb (
		{
			from = from,
			bottom = BOTTOM,
			top = TOP,
			normal = NORMAL,
			halfWidth = HALF_WIDTH,
			landing = landing,
			down = true
		}
	)
end

T.test ("a climb up runs to the foot, up the ladder clear of the wall, over the lip and onto the landing", function ()
	local plan = Up (P (30, -60, 0), P (0, 20, 100))
	local foot, high = plan.points [2], plan.points [3]
	T.eq (plan.points [1].y, -60, "from where it stands")
	T.eq (foot.y, -HALF_WIDTH, "its hull against the wall at the foot")
	T.eq (foot.x, 0, "before the ladder")
	T.eq (foot.z, 0, "still on the floor")
	T.eq (high.y, -HALF_WIDTH, "straight up the ladder")
	T.eq (high.z, 100 + Ladder.LIP, "its feet above the lip")
	T.eq (plan.points [4].y, 20, "ends on the landing")
	T.eq (plan.points [4].z, 100, "on its floor")
end)

T.test ("a landing higher than the ladder's top raises the climb over it", function ()
	local plan = Up (P (0, -30, 0), P (0, 20, 130))
	T.eq (plan.points [3].z, 130 + Ladder.LIP, "feet above the landing before crossing")
end)

T.test ("a climb down runs to the head, over the lip, down the ladder and onto the floor below", function ()
	local plan = Down (P (0, 40, 100), P (0, -40, 0))
	local high, foot = plan.points [2], plan.points [3]
	T.eq (high.y, -HALF_WIDTH, "out over the ladder")
	T.eq (high.z, 100 + Ladder.LIP, "clear of the lip")
	T.eq (foot.y, -HALF_WIDTH, "straight down the ladder")
	T.eq (foot.z, 0, "to the lower floor")
	T.eq (plan.points [4].y, -40, "ends on the landing")
end)

T.test ("a climb takes as long as its length at the ladder's speed", function ()
	local plan = Up (P (0, -10, 0), P (0, -10, 100))
	local length = 100 + Ladder.LIP + Ladder.LIP
	T.eq (plan.duration, length / Ladder.SPEED)
end)

T.test ("a climb's position starts at its first point, ends at its last, and passes along the ladder", function ()
	local plan = Up (P (0, -10, 0), P (0, -10, 100))
	local start, finish = plan:At (0), plan:At (1)
	T.eq (start.z, 0, "starts on the floor")
	T.eq (finish.z, 100, "ends on the landing")
	local midway = plan:At (0.5)
	T.eq (midway.y, -HALF_WIDTH, "on the ladder")
	T.eq (midway.z > 0 and midway.z < 100, true, "partway up")
end)

T.test ("a walker mounts within reach of the move's waypoint, on its floor", function ()
	local waypoint, height = P (0, -32, 0), 72
	T.eq (Ladder.CanMount (P (0, -32 - Ladder.REACH + 1, 0), waypoint, height), true, "before the waypoint")
	T.eq (Ladder.CanMount (P (0, -32 + Ladder.REACH - 1, 0), waypoint, height), true, "past it")
	T.eq (Ladder.CanMount (P (0, -32 - Ladder.REACH - 1, 0), waypoint, height), false, "too far")
	T.eq (Ladder.CanMount (P (0, -32, height + 1), waypoint, height), false, "on a floor above it")
	T.eq (Ladder.CanMount (P (0, -32, -height - 1), waypoint, height), false, "on a floor below it")
end)

T.test ("a landing is the closest point moved in from the edge toward the area's centre, no farther than the centre", function ()
	local landing = Ladder.Landing (P (0, 0, 8), P (0, 100, 8), HALF_WIDTH)
	T.eq (landing.y, HALF_WIDTH, "its hull clear of the edge")
	T.eq (landing.z, 8, "on the floor")
	local small = Ladder.Landing (P (0, 0, 8), P (0, 4, 8), HALF_WIDTH)
	T.eq (small.y, 4, "stops at the centre of a small area")
	local same = Ladder.Landing (P (5, 5, 8), P (5, 5, 8), HALF_WIDTH)
	T.eq (same.x, 5, "already at the centre")
end)

-- Acts as a body's model has them.
local function Has (...)
	local held = {}
	for _, act in ipairs ({ ... }) do held [act] = true end
	return function (act) return held [act] == true end
end
local CLIMB_DOWN, LOOP, HL2, FLOAT = 1, 2, 3, 4
local CLIMBS = { LOOP, HL2, FLOAT }

T.test ("a body climbs up by the first climb its model has", function ()
	T.eq (Ladder.Animation (Has (LOOP, HL2, FLOAT), CLIMB_DOWN, CLIMBS, false), LOOP, "a player model's")
	T.eq (Ladder.Animation (Has (HL2, FLOAT), CLIMB_DOWN, CLIMBS, false), HL2, "an NPC's")
	local act, rate = Ladder.Animation (Has (FLOAT), CLIMB_DOWN, CLIMBS, false)
	T.eq (act, FLOAT, "a TF2 body's")
	T.eq (rate, 1)
end)

T.test ("a body climbs down by its own climb down, else its climb up played backward", function ()
	local act, rate = Ladder.Animation (Has (CLIMB_DOWN, LOOP), CLIMB_DOWN, CLIMBS, true)
	T.eq (act, CLIMB_DOWN)
	T.eq (rate, 1)
	act, rate = Ladder.Animation (Has (LOOP), CLIMB_DOWN, CLIMBS, true)
	T.eq (act, LOOP)
	T.eq (rate, -1)
end)

T.test ("a body with no climb has no ladder animation, and keeps its usual one", function ()
	T.eq (Ladder.Animation (Has (), CLIMB_DOWN, CLIMBS, false), nil)
	T.eq (Ladder.Animation (Has (), CLIMB_DOWN, CLIMBS, true), nil)
end)

T.finish ()
