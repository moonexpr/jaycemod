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

T.finish()
