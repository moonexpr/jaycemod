-- A route walked waypoint by waypoint, by a body that plans its own way
-- (the AI war's bot soldiers: features/aiwar/sv_bot_soldier.lua), as the
-- orders walk theirs (features.aiwar.orders' Travel:Advance): a waypoint
-- within RADIUS is passed when the next is in a clear line, and one round a
-- corner only once it is within ON, as near as the body comes when it
-- arrives (nextsoldier.player_body's ARRIVE: the engine's route points sit
-- on area edges, by walls, and nextsoldier.corners pushes a turn's off the
-- inside wall just enough for the body, so leaving for the next from
-- farther short of it runs the body into the corner); the farthest of the
-- next LOOKAHEAD in a clear line is made for, and the last is held until
-- reached.
--
-- A clear line has a floor all along it, not only room to pass: a line
-- beside a log the route climbs (dev_watchtower_ns_locomotion's) is clear
-- of anything, over thin air. Footing gives where the caller looks for it.
local abs, floor, max, min, sqrt = math.abs, math.floor, math.max, math.min, math.sqrt
local Distance, Distance2D = math.geometry.Distance, math.geometry.Distance2D
local setmetatable = setmetatable
local HUGE = math.huge
local ARRIVE = nextsoldier.player_body.ARRIVE
module(...)

RADIUS = 48
ON = ARRIVE
LOOKAHEAD = 3
-- A waypoint is stood on, or within RADIUS, across the ground, as the body
-- arrives (nextsoldier.player_body's ARRIVE), with this much height either
-- way (a TF2 crouch jump): one on an area's edge lies below a bot already
-- up the log it leads onto, and in 3D it was never reached.
REACH_HEIGHT = 72
-- With no clear line to the waypoint it makes for and standing more than
-- LINE_OFF off the route's line there (from the last waypoint to it), it is
-- led back onto that line, to the point LINE_LEAD beyond where it stands
-- along it, as TF2's path follower makes for a point ahead on its path: a
-- log is walked along, not stepped onto from the side.
LINE_OFF = 16
LINE_LEAD = 48
-- No nearer its waypoint by PROGRESS in STALL_TIME seconds, the walk has
-- stalled (Stalled): fallen off a log beneath its route, or wedged.
PROGRESS = 32
STALL_TIME = 4
-- The floor under a straight walk is looked for this far apart, at most
-- FOOTING_MAX times: narrower than the narrowest beam walked (a 32-unit log).
FOOTING_SPACING = 24
FOOTING_MAX = 12

-- Where the floor under a straight walk from `from` to `to` is looked for:
-- points between the ends, evenly, FOOTING_SPACING apart (or fewer and
-- wider, FOOTING_MAX at most), each at the line's height there.
function Footing(from, to)
	local count = min(FOOTING_MAX, floor(Distance(from, to) / FOOTING_SPACING) - 1)
	local points = {}
	for i = 1, count do
		local t = i / (count + 1)
		points[i] = {
			x = from.x + (to.x - from.x) * t,
			y = from.y + (to.y - from.y) * t,
			z = from.z + (to.z - from.z) * t,
		}
	end
	return points
end

local Walk = {}
Walk.__index = Walk

-- points: the route's waypoints, { x, y, z } each, in order.
function New(points)
	return setmetatable({
		points = points,
		index = 1,
	}, Walk)
end

-- The point LINE_LEAD beyond pos's along the line from a to b (at most b),
-- across the ground and at the line's height there; nil when pos stands
-- within LINE_OFF of the line (to either side, across it).
local function Lead(pos, a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return nil end
	local along = ((pos.x - a.x) * dx + (pos.y - a.y) * dy) / length
	local off = abs((pos.x - a.x) * dy - (pos.y - a.y) * dx) / length
	if off <= LINE_OFF then return nil end
	local u = min(1, max(0, along + LINE_LEAD) / length)
	return { x = a.x + dx * u, y = a.y + dy * u, z = a.z + (b.z - a.z) * u }
end

-- The waypoint to make for from pos, or nil once the last is reached; off
-- the route's line with no clear line to it, the lead back onto the line.
-- canWalk(point): whether a straight walk there is clear.
function Walk:Next(pos, canWalk)
	local points = self.points
	local index = self.index
	while index <= #points do
		local point = points[index]
		local distance = abs(pos.z - point.z) <= REACH_HEIGHT and Distance2D(pos, point) or HUGE
		local passed = distance <= ON or (distance <= RADIUS and (index == #points or canWalk(points[index + 1])))
		if not passed then break end
		index = index + 1
	end
	if index <= #points then
		for k = min(#points, index + LOOKAHEAD), index + 1, -1 do
			if canWalk(points[k]) then
				index = k
				break
			end
		end
	end
	self.index = index
	local point = points[index]
	if index > 1 and point then
		local lead = Lead(pos, points[index - 1], point)
		if lead and not canWalk(point) then return lead end
	end
	return point
end

-- Whether the walk has stalled at pos by now: no nearer its waypoint by
-- PROGRESS in STALL_TIME seconds, counted afresh from each new waypoint.
function Walk:Stalled(pos, now)
	local point = self.points[self.index]
	if not point then return false end
	local distance = Distance(pos, point)
	if self.bestIndex ~= self.index or distance <= self.best - PROGRESS then
		self.bestIndex, self.best, self.bestAt = self.index, distance, now
	end
	return now - self.bestAt >= STALL_TIME
end

function Walk:Done()
	return self.index > #self.points
end
