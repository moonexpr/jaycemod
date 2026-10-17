-- Geometry on plain points { x, y, z }, as map entities and the nav mesh give
-- them; a point without a z lies on the z = 0 plane.
local sqrt = math.sqrt
module(...)

-- The straight-line distance between two points.
function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-- The point `distance` from `from` toward `to`, on the ground plane (z
-- from `from`); `to` itself when nearer.
function Toward(from, to, distance)
	local dx, dy = to.x - from.x, to.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	if length <= distance or length == 0 then return { x = to.x, y = to.y, z = to.z } end
	local t = distance / length
	return { x = from.x + dx * t, y = from.y + dy * t, z = from.z }
end
