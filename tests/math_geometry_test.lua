-- foundation.math.geometry: distances and points along the way between points { x, y, z },
-- where a missing z counts as 0.
local T = dofile("tests/harness.lua")
local Geometry = math.geometry

T.test("the distance between two 3D points", function()
	T.eq(Geometry.Distance({ x = 0, y = 0, z = 0 }, { x = 2, y = 3, z = 6 }), 7, "0,0,0 to 2,3,6")
end)

T.test("a missing z counts as 0", function()
	T.eq(Geometry.Distance({ x = 0, y = 0 }, { x = 3, y = 4 }), 5, "both flat")
	T.eq(Geometry.Distance({ x = 0, y = 0, z = 0 }, { x = 3, y = 4 }), 5, "one flat")
	T.eq(Geometry.Distance({ x = 3, y = 4 }, { x = 0, y = 0, z = 0 }), 5, "the other flat")
end)

T.test("swapping the points gives the same distance", function()
	local a, b = { x = 1, y = -2, z = 5 }, { x = -4, y = 7, z = 0.5 }
	T.eq(Geometry.Distance(a, b), Geometry.Distance(b, a), "symmetric")
end)

T.test("a point is no distance from itself", function()
	local a = { x = 12.5, y = -3, z = 40 }
	T.eq(Geometry.Distance(a, a), 0, "itself")
end)

T.test("toward stops at the target", function()
	local p = Geometry.Toward({ x = 0, y = 0 }, { x = 100, y = 0 }, 300)
	T.eq(p.x, 100, "not past it")
	p = Geometry.Toward({ x = 0, y = 0 }, { x = 1000, y = 0 }, 300)
	T.near(p.x, 300, 1e-6, "the distance along")
end)

local function V(x, y, z) return { x = x, y = y, z = z } end
local function Same(p, x, y, z, what)
	T.near(p.x, x, 1e-12, what .. " x")
	T.near(p.y, y, 1e-12, what .. " y")
	T.near(p.z, z, 1e-12, what .. " z")
end

T.test("vectors add, subtract and scale as new points", function()
	local a, b = V(1, 2, 3), V(4, 5, 6)
	Same(Geometry.Add(a, b), 5, 7, 9, "sum")
	Same(Geometry.Sub(b, a), 3, 3, 3, "difference")
	Same(Geometry.Scale(a, 2), 2, 4, 6, "scaled")
	Same(Geometry.Add(V(1, 1), V(1, 1)), 2, 2, 0, "a missing z is 0")
	Same(a, 1, 2, 3, "the operands are untouched")
end)

T.test("dot and cross products", function()
	T.eq(Geometry.Dot(V(1, 2, 3), V(4, 5, 6)), 32, "dot")
	Same(Geometry.Cross(V(1, 0, 0), V(0, 1, 0)), 0, 0, 1, "x cross y is z")
	T.eq(Geometry.Dot(Geometry.Cross(V(1, 2, 3), V(4, 5, 6)), V(1, 2, 3)), 0, "the cross is perpendicular")
end)

T.test("a vector's length, and its direction", function()
	T.eq(Geometry.Length(V(2, 3, 6)), 7, "length")
	Same(Geometry.Normalize(V(0, 3, 4)), 0, 0.6, 0.8, "unit")
	T.eq(Geometry.Normalize(V(0, 0, 0)), nil, "the zero vector has no direction")
end)

T.test("the distance across the ground leaves height out", function()
	T.eq(Geometry.Distance2D(V(0, 0, 0), V(3, 4, 100)), 5, "a ledge above is as far across")
	T.eq(Geometry.Distance2D({ x = 0, y = 0 }, { x = 6, y = 8 }), 10, "points without a z")
end)

-- GMod's Vector: a userdata answering x, y and z through its metatable
-- (newproxy stands in for one under plain LuaJIT).
local function Vector(x, y, z)
	local v = newproxy(true)
	getmetatable(v).__index = { x = x, y = y, z = z }
	return v
end

T.test("a point may be any value answering x, y and z, as GMod's Vector does", function()
	T.eq(Geometry.Distance(Vector(0, 0, 0), Vector(3, 4, 0)), 5, "two Vectors")
	T.eq(Geometry.Distance({ x = 0, y = 0, z = 0 }, Vector(0, 0, 2)), 2, "a table and a Vector")
	T.eq(Geometry.Distance2D(Vector(0, 0, 9), { x = 6, y = 8 }), 10, "across")
	T.eq(Geometry.Add(Vector(1, 2, 3), Vector(1, 1, 1)).z, 4, "added")
	T.eq(Geometry.Toward(Vector(0, 0, 5), Vector(10, 0, 0), 4).x, 4, "toward")
end)

T.test("the squared distance is the distance squared, with no root taken", function()
	T.eq(Geometry.DistanceSquared(V(0, 0, 0), V(2, 3, 6)), 49, "0,0,0 to 2,3,6")
	T.eq(Geometry.DistanceSquared({ x = 0, y = 0 }, { x = 3, y = 4 }), 25, "a missing z is 0")
	T.eq(Geometry.DistanceSquared(V(1, 2, 3), V(1, 2, 3)), 0, "itself")
	T.eq(Geometry.DistanceSquared(V(1, -2, 5), V(-4, 7, 0.5)), Geometry.DistanceSquared(V(-4, 7, 0.5), V(1, -2, 5)), "symmetric")
end)

T.test("Normalize2D is the direction across the ground, height left out; nil with none", function()
	Same(Geometry.Normalize2D(V(3, 4, 12)), 0.6, 0.8, 0, "3,4 with a height")
	Same(Geometry.Normalize2D({ x = 0, y = -2 }), 0, -1, 0, "a missing z")
	T.eq(Geometry.Normalize2D(V(0, 0, 5)), nil, "straight up has no direction on the ground")
end)

T.test("Left2D turns a direction a quarter turn to the left, across the ground", function()
	Same(Geometry.Left2D(V(1, 0, 7)), 0, 1, 0, "east is turned to north")
	Same(Geometry.Left2D(V(0, 1, 0)), -1, 0, 0, "north to west")
	Same(Geometry.Left2D({ x = 2, y = 3 }), -3, 2, 0, "any vector, length kept")
end)

T.test("Offset2D moves p along the way from `from` to it and across, to the left", function()
	local p, from = V(10, 0, 5), V(0, 0, 0)
	Same(Geometry.Offset2D(p, from, 3, 0), 13, 0, 5, "along: further from `from`")
	Same(Geometry.Offset2D(p, from, -4, 0), 6, 0, 5, "a negative along: nearer")
	Same(Geometry.Offset2D(p, from, 0, 2), 10, 2, 5, "across: to the left of east is north")
	Same(Geometry.Offset2D(p, from, 0, -2), 10, -2, 5, "a negative across: to the right")
	Same(Geometry.Offset2D(p, from, 3, 2), 13, 2, 5, "both")
	Same(Geometry.Offset2D(V(0, 5, 1), V(0, 0, 9), 0, 1), -1, 5, 1, "north: left is west; p's height, not from's")
	Same(p, 10, 0, 5, "p is untouched")
end)

T.test("Offset2D with p on `from` (no direction on the ground) is p, as a new point", function()
	local p = V(4, 4, 4)
	local out = Geometry.Offset2D(p, V(4, 4, 90), 5, 5)
	Same(out, 4, 4, 4, "where it was")
	T.eq(out ~= p, true, "a new table")
end)

T.test("ClosestOnSegment is the point of the segment nearest p", function()
	local a, b = V(0, 0, 0), V(10, 0, 0)
	Same(Geometry.ClosestOnSegment(V(5, 3, 0), a, b), 5, 0, 0, "beside it")
	Same(Geometry.ClosestOnSegment(V(-4, 3, 0), a, b), 0, 0, 0, "before a: a")
	Same(Geometry.ClosestOnSegment(V(14, 3, 0), a, b), 10, 0, 0, "past b: b")
	Same(Geometry.ClosestOnSegment(V(6, 6, 6), V(0, 0, 0), V(10, 10, 10)), 6, 6, 6, "in 3D, on it")
	Same(Geometry.ClosestOnSegment(V(9, 9, 9), V(2, 2, 2), V(2, 2, 2)), 2, 2, 2, "a segment of no length is its point")
end)

T.test("Polar is the point at an angle (radians, from east, counterclockwise) on a circle", function()
	Same(Geometry.Polar(V(1, 2, 3), 2, 0), 3, 2, 3, "east, at the centre's height")
	Same(Geometry.Polar(V(1, 2, 3), 2, math.pi / 2), 1, 4, 3, "north")
	Same(Geometry.Polar({ x = 0, y = 0 }, 5, math.pi), -5, 0, 0, "west, a missing z is 0")
end)

T.test("Circle is count points around a centre, evenly, from the start angle", function()
	local ring = Geometry.Circle(V(1, 1, 2), 1, 4, 0)
	T.eq(#ring, 4, "count points")
	Same(ring[1], 2, 1, 2, "the start")
	Same(ring[2], 1, 2, 2, "a quarter on")
	Same(ring[3], 0, 1, 2, "a half on")
	Same(ring[4], 1, 0, 2, "three quarters on")
	Same(Geometry.Circle(V(0, 0, 0), 2, 1, math.pi / 2)[1], 0, 2, 0, "one point, at the start")
end)

T.test("Circle refuses a count that is not a whole number of at least 1", function()
	T.eq(pcall(Geometry.Circle, V(0, 0, 0), 1, 0, 0), false, "none")
	T.eq(pcall(Geometry.Circle, V(0, 0, 0), 1, 2.5, 0), false, "a fraction")
end)

T.test("Sphere is count points spread over a sphere round a centre, from its top down", function()
	local center = V(10, -20, 30)
	local points = Geometry.Sphere(center, 50, 64)
	T.eq(#points, 64, "count of them")
	local sx, sy, sz = 0, 0, 0
	for i, p in ipairs(points) do
		T.near(Geometry.Distance(p, center), 50, 1e-9, "point " .. i .. " on the sphere")
		sx, sy, sz = sx + p.x, sy + p.y, sz + p.z
	end
	T.near(sx / 64, 10, 2, "spread evenly: their middle is the centre's, across")
	T.near(sy / 64, -20, 2, "and along")
	T.near(sz / 64, 30, 1e-9, "and up")
	T.eq(points[1].z > points[64].z, true, "the first at the top")
	T.eq(pcall(Geometry.Sphere, center, 50, 0), false, "no points is refused")
	T.eq(pcall(Geometry.Sphere, center, 50, 2.5), false, "nor part of one")
end)

T.test("Frustum is a grid of points on its far plane, top row first, left to right", function()
	local eye, ahead = V(0, 0, 0), V(1, 0, 0)
	local points = Geometry.Frustum(eye, ahead, math.pi / 2, math.pi / 2, 100, 3, 3)
	T.eq(#points, 9, "rows by columns")
	Same(points[5], 100, 0, 0, "the middle straight ahead, the range away")
	Same(points[1], 100, 100, 100, "the first top left: left is +y")
	Same(points[9], 100, -100, -100, "the last bottom right")
	Same(points[2], 100, 0, 100, "the top row's middle")
end)

T.test("Frustum of one point looks straight ahead, whichever way", function()
	local points = Geometry.Frustum(V(1, 2, 3), V(0, 0, 2), 1, 1, 10, 1, 1)
	Same(points[1], 1, 2, 13, "straight up, the range away")
end)

T.test("Frustum refuses a forward with no direction and a grid of no points", function()
	T.eq(pcall(Geometry.Frustum, V(0, 0, 0), V(0, 0, 0), 1, 1, 10, 2, 2), false, "no direction")
	T.eq(pcall(Geometry.Frustum, V(0, 0, 0), V(1, 0, 0), 1, 1, 10, 0, 2), false, "no columns")
	T.eq(pcall(Geometry.Frustum, V(0, 0, 0), V(1, 0, 0), 1, 1, 10, 2, 1.5), false, "part of a row")
end)

T.finish()
