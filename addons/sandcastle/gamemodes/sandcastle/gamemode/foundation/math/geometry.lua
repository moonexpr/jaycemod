-- Geometry on plain points { x, y, z }, as map entities and the nav mesh give
-- them; a point without a z lies on the z = 0 plane. Points double as
-- vectors: Add, Sub, Scale, Dot, Cross, Length and Normalize (nil for the
-- zero vector, which has no direction) return new points. The ground-plane
-- ones (Normalize2D, Left2D, Offset2D, Polar, Circle) leave height out of the
-- direction and keep a point's own z.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local cos, error, floor, sin, sqrt, tostring, type = math.cos, error, math.floor, math.sin, math.sqrt, tostring, type
local pi = math.pi
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

-- The squared straight-line distance: to compare distances without a root.
function DistanceSquared(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return dx * dx + dy * dy + dz * dz
end

-- The direction of a vector across the ground, height left out, as a unit
-- point with z of 0; nil when it has none.
function Normalize2D(a)
	local length = sqrt(a.x * a.x + a.y * a.y)
	if length == 0 then return nil end
	return { x = a.x / length, y = a.y / length, z = 0 }
end

-- A vector turned a quarter turn to the left across the ground (z of 0).
function Left2D(a)
	return { x = -a.y, y = a.x, z = 0 }
end

-- p moved `along` the way from `from` to it (away from `from` for a positive
-- one) and `across` it, to the left of that way for a positive one, on the
-- ground plane; p's own z. p itself, as a new point, when p is not across
-- the ground from `from`.
function Offset2D(p, from, along, across)
	local dx, dy = p.x - from.x, p.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	local z = p.z or 0
	if length == 0 then return { x = p.x, y = p.y, z = z } end
	local ux, uy = dx / length, dy / length
	return { x = p.x + ux * along + -uy * across, y = p.y + uy * along + ux * across, z = z }
end

-- The point of the segment a-b nearest p.
function ClosestOnSegment(p, a, b)
	local abx, aby, abz = b.x - a.x, b.y - a.y, (b.z or 0) - (a.z or 0)
	local length2 = abx * abx + aby * aby + abz * abz
	local t = 0
	if length2 > 0 then
		t = ((p.x - a.x) * abx + (p.y - a.y) * aby + ((p.z or 0) - (a.z or 0)) * abz) / length2
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
	end
	return { x = a.x + abx * t, y = a.y + aby * t, z = (a.z or 0) + abz * t }
end

-- The point `radius` from center at angle (radians, counterclockwise from
-- east), on the ground plane at center's height.
function Polar(center, radius, angle)
	return { x = center.x + cos(angle) * radius, y = center.y + sin(angle) * radius, z = center.z or 0 }
end

-- `count` points evenly around center, the first at angle `start`.
function Circle(center, radius, count, start)
	if type(count) ~= "number" or count < 1 or floor(count) ~= count then
		error("a circle's count is a whole number of at least 1, not " .. tostring(count), 2)
	end
	local points = {}
	for i = 0, count - 1 do points[i + 1] = Polar(center, radius, start + i * (2 * pi) / count) end
	return points
end
