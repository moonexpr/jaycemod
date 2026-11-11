-- A walker's climb of a nav ladder as a line it is moved along (the base's
-- ClimbPathLadder), not left to the engine: GMod's locomotion takes hold of a
-- ladder a PathFollower reaches, and never moves up it. Up: to the foot, up
-- the ladder with its hull against the wall, over the lip, onto the landing.
-- Down: the same line reversed from the head. What a climb reads of a ladder
-- is plain numbers, so it holds { x, y, z } points and Vectors alike.
local max, sqrt = math.max, math.sqrt
local Polyline = math.polyline
local setmetatable = setmetatable
module ("nextsoldier.locomotion.ladder")

-- Path::SegmentType's ladder moves (NextBotPath.h).
UP, DOWN = 4, 5
-- A player's speed on a ladder (HL2's MAX_CLIMB_SPEED).
SPEED = 200
-- A climb begins this near the move's waypoint, which the engine sets 32 out
-- from the ladder on the walker's side: before its follower takes hold of the
-- ladder, or, going down, passes the waypoint by (about 11 short of it).
REACH = 32
-- How far above the lip its feet cross it.
LIP = 2

local function Out (point, normal, distance, z)
	return { x = point.x + normal.x * distance, y = point.y + normal.y * distance, z = z }
end

local Climb_ = {}
Climb_.__index = Climb_

-- Where the walker is at t, the share of the climb gone.
function Climb_:At (t)
	return self.line:PointAt (self.line:Length () * t)
end

-- q = { from, bottom, top, normal, halfWidth, landing, down }: the climb from
-- where the walker stands onto the landing, a point of the far area:
-- { points, duration, At(t) }.
function Climb (q)
	local standoff, points = q.halfWidth, nil
	if q.down then
		local high = Out (q.top, q.normal, standoff, max (q.top.z, q.from.z) + LIP)
		local foot = Out (q.bottom, q.normal, standoff, q.landing.z)
		points = { q.from, high, foot, q.landing }
	else
		local foot = Out (q.bottom, q.normal, standoff, q.from.z)
		local high = Out (q.top, q.normal, standoff, max (q.top.z, q.landing.z) + LIP)
		points = { q.from, foot, high, q.landing }
	end
	local line = Polyline.New (points)
	return setmetatable ({ points = points, line = line, duration = line:Length () / SPEED }, Climb_)
end

-- Whether a walker of this height at `from` may start the ladder move whose
-- waypoint is `waypoint`: within REACH of it, across, on its floor.
function CanMount (from, waypoint, height)
	local dx, dy = waypoint.x - from.x, waypoint.y - from.y
	if dx * dx + dy * dy > REACH * REACH then return false end
	local dz = from.z - waypoint.z
	return dz > -height and dz < height
end

-- What a body plays on a ladder -> act, rate: going down, its own climb down;
-- else the first of climbs its model has (has(act)), played backward going
-- down; nil for a body with none.
function Animation (has, climbDown, climbs, down)
	if down and has (climbDown) then return climbDown, 1 end
	for i = 1, #climbs do
		if has (climbs [i]) then return climbs [i], down and -1 or 1 end
	end
	return nil
end

-- A point of the far area to land on: the point closest to the ladder, moved
-- in from the edge by inset toward the area's centre, and no farther.
function Landing (closest, center, inset)
	local dx, dy = center.x - closest.x, center.y - closest.y
	local reach = sqrt (dx * dx + dy * dy)
	if reach <= inset then return { x = center.x, y = center.y, z = center.z } end
	return { x = closest.x + dx / reach * inset, y = closest.y + dy / reach * inset, z = closest.z }
end
