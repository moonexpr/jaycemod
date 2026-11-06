-- The dev workbench's placement of one body before another, which ENTITY:Teleport (sv_entity.lua)
-- puts an entity at; points are { x, y, z } tables or Vectors, yaws in degrees:
--   Before(at, yaw, reach, ownReach) -> where a body reaching ownReach across the ground stands
--     before one at `at` facing yaw and reaching reach: along its facing, the two GAP apart, on
--     its floor
--   Yaw(yaw, facingTowards) -> the yaw a body put before one facing yaw takes: turned to face it,
--     or the way it faces
--   Reach(mins, maxs) -> a body's reach across the ground from its middle: its widest side
local Geometry = math.geometry
local abs, max, rad = math.abs, math.max, math.rad
module(...)

-- How far apart the two bodies stand.
GAP = 16

function Before(at, yaw, reach, ownReach)
	local ahead = Geometry.Polar(at, reach + ownReach + GAP, rad(yaw))
	return { x = ahead.x, y = ahead.y, z = at.z or 0 }
end

function Yaw(yaw, facingTowards)
	if not facingTowards then return yaw end
	return (yaw + 180) % 360
end

function Reach(mins, maxs)
	return max(abs(mins.x), abs(maxs.x), abs(mins.y), abs(maxs.y))
end
