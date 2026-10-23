-- A polyline: a path of points { x, y, z }, measured along its length.
--   New(points), line:Length(), line:Leg(d) -> the leg holding distance d
--   and how far along it, line:PointAt(d), line:Offset(d, lateral),
--   line:DistanceOf(p) -> how far along the point nearest p lies
local setmetatable, sqrt = setmetatable, math.sqrt
local Distance = math.geometry.Distance
module(...)

local Polyline = {}
Polyline.__index = Polyline

function New(points)
	local at, total = { 0 }, 0
	for i = 2, #points do
		total = total + Distance(points[i - 1], points[i])
		at[i] = total
	end
	return setmetatable({ points = points, at = at, total = total }, Polyline)
end

function Polyline:Length()
	return self.total
end

-- The leg holding distance d (clamped to the line), and how far along it.
function Polyline:Leg(d)
	local points, at = self.points, self.at
	if d <= 0 or #points == 1 then return 1, 0 end
	for i = 2, #points do
		if d <= at[i] then
			local length = at[i] - at[i - 1]
			return i - 1, length > 0 and (d - at[i - 1]) / length or 0
		end
	end
	return #points - 1, 1
end

function Polyline:PointAt(d)
	local i, t = self:Leg(d)
	local a, b = self.points[i], self.points[i + 1] or self.points[i]
	return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t }
end

-- The point at d moved `lateral` units sideways, left of the direction of
-- travel for a positive lateral.
function Polyline:Offset(d, lateral)
	local point = self:PointAt(d)
	local i = self:Leg(d)
	local a, b = self.points[i], self.points[i + 1] or self.points[i]
	local dx, dy = b.x - a.x, b.y - a.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return point end
	point.x = point.x - dy / length * lateral
	point.y = point.y + dx / length * lateral
	return point
end

-- How far along the line the point nearest p lies: p projected onto the
-- nearest leg.
function Polyline:DistanceOf(p)
	local points, at = self.points, self.at
	if #points == 1 then return 0 end
	local best, bestSq = 0, nil
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local lengthSq = dx * dx + dy * dy + dz * dz
		local t = 0
		if lengthSq > 0 then
			t = ((p.x - a.x) * dx + (p.y - a.y) * dy + (p.z - a.z) * dz) / lengthSq
			if t < 0 then t = 0 elseif t > 1 then t = 1 end
		end
		local nx, ny, nz = a.x + dx * t - p.x, a.y + dy * t - p.y, a.z + dz * t - p.z
		local dSq = nx * nx + ny * ny + nz * nz
		if not bestSq or dSq < bestSq then
			best, bestSq = at[i] + (at[i + 1] - at[i]) * t, dSq
		end
	end
	return best
end
