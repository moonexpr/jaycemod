-- Geometry on plain points { x, y, z }, as map entities and the nav mesh give
-- them; a point without a z lies on the z = 0 plane. Points double as
-- vectors: Add, Sub, Scale, Dot, Cross, Length and Normalize (nil for the
-- zero vector, which has no direction) return new points.
local sqrt = math.sqrt
module(...)

-- The straight-line distance between two points.
function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-- The distance across the ground, height left out (a walker's reach).
function Distance2D(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return sqrt(dx * dx + dy * dy)
end

-- The point `distance` from `from` toward `to`, on the ground plane (z
-- from `from`); `to` itself when nearer.
function Toward(from, to, distance)
	local length = Distance2D(from, to)
	if length <= distance or length == 0 then return { x = to.x, y = to.y, z = to.z } end
	local t = distance / length
	return { x = from.x + (to.x - from.x) * t, y = from.y + (to.y - from.y) * t, z = from.z }
end

function Add(a, b)
	return { x = a.x + b.x, y = a.y + b.y, z = (a.z or 0) + (b.z or 0) }
end

function Sub(a, b)
	return { x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }
end

function Scale(a, s)
	return { x = a.x * s, y = a.y * s, z = (a.z or 0) * s }
end

function Dot(a, b)
	return a.x * b.x + a.y * b.y + (a.z or 0) * (b.z or 0)
end

function Cross(a, b)
	local az, bz = a.z or 0, b.z or 0
	return { x = a.y * bz - az * b.y, y = az * b.x - a.x * bz, z = a.x * b.y - a.y * b.x }
end

function Length(a)
	return sqrt(Dot(a, a))
end

function Normalize(a)
	local length = Length(a)
	if length == 0 then return nil end
	return Scale(a, 1 / length)
end
