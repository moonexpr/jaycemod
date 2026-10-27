-- A route walked waypoint by waypoint, by a body that plans its own way
-- (the AI war's bot soldiers: features/aiwar/sv_bot_soldier.lua), as the
-- orders walk theirs (features.aiwar.orders' Travel:Advance): a waypoint
-- within RADIUS is passed when the next is in a clear line, and one round a
-- corner only once it is within ON (the engine's route points sit on area
-- edges, by walls: cutting toward the next from RADIUS out ran bots into
-- the corner); the farthest of the next LOOKAHEAD in a clear line is made
-- for, and the last is held until reached.
local min = math.min
local Distance = math.geometry.Distance
local setmetatable = setmetatable
module(...)

RADIUS = 48
ON = 32
LOOKAHEAD = 3

local Walk = {}
Walk.__index = Walk

-- points: the route's waypoints, { x, y, z } each, in order.
function New(points)
	return setmetatable({
		points = points,
		index = 1,
	}, Walk)
end

-- The waypoint to make for from pos, or nil once the last is reached.
-- canWalk(point): whether a straight walk there is clear.
function Walk:Next(pos, canWalk)
	local points = self.points
	local index = self.index
	while index <= #points do
		local distance = Distance(pos, points[index])
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
	return points[index]
end

function Walk:Done()
	return self.index > #self.points
end
