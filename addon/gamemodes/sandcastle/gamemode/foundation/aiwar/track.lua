-- A cart's path as geometry: the path_track chain a team_train_watcher
-- follows, as points { x, y, z }, measured along its length the way the
-- watcher measures the cart's progress. The orders pick their goals on it.
local setmetatable, sqrt = setmetatable, math.sqrt
module(...)

function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)
end

local Track = {}
Track.__index = Track

function New(points)
	local at, total = { 0 }, 0
	for i = 2, #points do
		total = total + Distance(points[i - 1], points[i])
		at[i] = total
	end
	return setmetatable({ points = points, at = at, total = total }, Track)
end

function Track:Length()
	return self.total
end

-- The leg holding distance d (clamped to the track), and how far along it.
function Track:Leg(d)
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

function Track:PointAt(d)
	local i, t = self:Leg(d)
	local a, b = self.points[i], self.points[i + 1] or self.points[i]
	return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t }
end

-- The point at d moved `lateral` units sideways, left of the direction of
-- travel for a positive lateral.
function Track:Offset(d, lateral)
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
