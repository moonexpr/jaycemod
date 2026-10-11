-- Geometry on plain points { x, y, z }, as map entities and the nav mesh give
-- them; a point without a z lies on the z = 0 plane.
local sqrt = math.sqrt
module(...)

-- The straight-line distance between two points.
function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end
