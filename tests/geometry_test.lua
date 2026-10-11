-- foundation.geometry: straight-line distance between points { x, y, z },
-- where a missing z counts as 0.
local T = dofile("tests/harness.lua")
local Geometry = T.require("foundation.geometry")

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

T.finish()
