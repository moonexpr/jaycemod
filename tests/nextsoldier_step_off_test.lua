local T = dofile ("tests/harness.lua")

local Locomotion = nextsoldier.locomotion
local FROM = { x = 0, y = 0, z = 100 }
local LANDING = { x = 10, y = 0, z = -100 }

local function Open () return true end

T.test ("a route's point far below and near is a drop; one on its level or far off is not", function ()
	T.eq (Locomotion.DropBelow (FROM, LANDING, 40, 48), true, "right below")
	T.eq (Locomotion.DropBelow (FROM, { x = 10, y = 0, z = 80 }, 40, 48), false, "a step down")
	T.eq (Locomotion.DropBelow (FROM, { x = 500, y = 0, z = -100 }, 40, 48), false, "not there yet")
	T.eq (Locomotion.DropBelow (FROM, { x = 10, y = 0, z = 400 }, 40, 48), false, "above it")
end)

T.test ("it heads for where its body falls, past that point, at its own height", function ()
	local point = Locomotion.StepOff (FROM, LANDING, Open, function (q) return q.x >= 40 end)
	T.eq (point.z, FROM.z, "its own height")
	T.eq (point.x > 40, true, "past where it falls, so it is still walking as it does")
end)

T.test ("of the ways it could fall, the one nearest the landing", function ()
	local point = Locomotion.StepOff (FROM, { x = -30, y = 0, z = -100 }, Open, function (q) return math.abs (q.x) >= 40 end)
	T.eq (point.x < 0, true, "toward the landing")
end)

T.test ("a way a wall closes before it falls is no way", function ()
	local point = Locomotion.StepOff (FROM, LANDING, function (q) return q.x < 16 end, function (q) return q.x >= 40 or q.x <= -40 end)
	T.eq (point.x < 0, true, "round the other side")
end)

T.test ("nowhere to fall within reach is no step", function ()
	T.eq (Locomotion.StepOff (FROM, LANDING, Open, function () return false end), nil, "nothing to walk to")
end)

-- A route along x = 0 past a pillar the body cannot stand within 24 of, as a route's
-- points are laid for a narrower width than the body walking them.
local function ClearOfPillar (q) return math.abs (q.x) >= 24 or math.abs (q.y) >= 24 end
local function Unwalled () return true end
local PAST_PILLAR =
{
	{ x = 0, y = -200, z = 0 },
	{ x = 0, y = 0, z = 0 },
	{ x = 0, y = 200, z = 0 }
}

T.test ("a route's point its body cannot stand on moves to where it can", function ()
	local moved = Locomotion.StandPoints (PAST_PILLAR, ClearOfPillar, Unwalled)
	T.eq (ClearOfPillar (moved [2]), true, "the body fits there")
	T.eq (moved [2].z, 0, "at the point's height")
	T.eq (math.abs (moved [2].x) + math.abs (moved [2].y) < 96, true, "near the point it replaces")
end)

T.test ("a point its body can stand on stays, and so do a route's two ends", function ()
	local fits =
	{
		{ x = 0, y = -200, z = 0 },
		{ x = 0, y = 50, z = 0 },
		{ x = 0, y = 200, z = 0 }
	}
	T.eq (Locomotion.StandPoints (fits, ClearOfPillar, Unwalled) [2], fits [2], "kept")
	local ends = { { x = 0, y = 0, z = 0 }, { x = 5, y = 0, z = 0 } }
	local kept = Locomotion.StandPoints (ends, ClearOfPillar, Unwalled)
	T.eq (kept [1], ends [1], "its start")
	T.eq (kept [2], ends [2], "its end")
end)

T.test ("of the places as near, the one keeping the route shortest", function ()
	-- The way on bends east, so east of the pillar is the shorter way round.
	local moved = Locomotion.StandPoints (
		{
			{ x = 0, y = -200, z = 0 },
			{ x = 0, y = 0, z = 0 },
			{ x = 300, y = 200, z = 0 }
		}, ClearOfPillar, Unwalled)
	T.eq (moved [2].x > 0, true, "toward the way on")
end)

T.test ("a place across a wall is no place to move to", function ()
	local function NotAcrossEast (_, q) return q.x <= 0 end
	local moved = Locomotion.StandPoints (
		{
			{ x = 0, y = -200, z = 0 },
			{ x = 0, y = 0, z = 0 },
			{ x = 300, y = 0, z = 0 }
		}, ClearOfPillar, NotAcrossEast)
	T.eq (moved [2].x <= 0, true, "stays on its side")
	T.eq (ClearOfPillar (moved [2]), true, "and fits")
end)

T.test ("with nowhere near to stand, the point stays as planned", function ()
	local moved = Locomotion.StandPoints (PAST_PILLAR, function () return false end, Unwalled)
	T.eq (moved [2], PAST_PILLAR [2], "kept")
end)

-- Heading along +x from the origin, whose left is +y.
local AHEAD = { x = 500, y = 0, z = 0 }
local ORIGIN = { x = 0, y = 0, z = 0 }

local function WallOn (side)
	return function (from) return (from.y > 0) == (side == "left") end
end

T.test ("a jamb on one side veers it to the other", function ()
	local veered = Locomotion.Avoid (ORIGIN, AHEAD, 24, WallOn ("left"))
	T.eq (veered.y < 0, true, "away from the wall on its left")
	T.eq (veered.x > 0, true, "and still on its way")
	veered = Locomotion.Avoid (ORIGIN, AHEAD, 24, WallOn ("right"))
	T.eq (veered.y > 0, true, "away from the wall on its right")
end)

T.test ("a way clear on both sides, or shut on both, is left as it is", function ()
	T.eq (Locomotion.Avoid (ORIGIN, AHEAD, 24, function () return false end), AHEAD, "nothing to avoid")
	T.eq (Locomotion.Avoid (ORIGIN, AHEAD, 24, function () return true end), AHEAD, "no side is better")
end)

T.test ("feelers start from its shoulders, level with it, and look ahead", function ()
	local seen = {}
	Locomotion.Avoid (ORIGIN, AHEAD, 24, function (from, to) seen [#seen + 1] = { from = from, to = to } return false end)
	T.eq (#seen, 2, "one a side")
	T.eq (seen [1].from.y * seen [2].from.y < 0, true, "on either side of it")
	T.eq (seen [1].to.x > seen [1].from.x, true, "the way it is going")
end)

T.test ("a target it stands on is left as it is", function ()
	T.eq (Locomotion.Avoid (ORIGIN, ORIGIN, 24, function () return true end), ORIGIN, "no way to feel along")
end)

T.finish ()
