-- foundation.math.polyline: a path of points, measured along its length.
local T = dofile("tests/harness.lua")
local Polyline = T.require("foundation.math.polyline")

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

-- (0,0) -> (100,0) -> (100,50): 150 long.
local function Ell() return Polyline.New({ P(0, 0), P(100, 0), P(100, 50) }) end

T.test("a polyline's length is the sum of its legs", function()
	T.eq(Ell():Length(), 150, "100 + 50")
	T.eq(Polyline.New({ P(5, 5) }):Length(), 0, "a single point")
end)

T.test("a distance falls on a leg, clamped to the ends", function()
	local line = Ell()
	local leg, t = line:Leg(50)
	T.eq(leg, 1, "the first leg")
	T.eq(t, 0.5, "halfway along it")
	leg, t = line:Leg(125)
	T.eq(leg, 2, "the second")
	T.eq(t, 0.5, "halfway")
	T.eq(line:Leg(-10), 1, "before the start")
	leg, t = line:Leg(999)
	T.eq(leg, 2, "past the end: the last leg")
	T.eq(t, 1, "at its end")
end)

T.test("the point at a distance along the line", function()
	local p = Ell():PointAt(125)
	T.eq(p.x, 100, "x")
	T.eq(p.y, 25, "y")
end)

T.test("an offset point lies left of the direction of travel for a positive lateral", function()
	local p = Ell():Offset(50, 10)
	T.eq(p.x, 50, "along")
	T.eq(p.y, 10, "left of +x is +y")
end)

T.test("a point's distance along is its projection on the nearest leg", function()
	local line = Ell()
	T.eq(line:DistanceOf(P(40, -20)), 40, "beside the first leg")
	T.eq(line:DistanceOf(P(130, 30)), 130, "beside the second")
	T.eq(line:DistanceOf(P(-50, 0)), 0, "before the start")
end)

T.finish()
