-- foundation.math.box: axis-aligned boxes by their two corners { x, y, z }; a
-- missing z is 0.
local T = dofile("tests/harness.lua")
local Box = math.box

local function P(x, y, z) return { x = x, y = y, z = z } end

T.test("boxes overlap when they do on all three axes; touching counts", function()
	T.eq(Box.Overlaps(P(0, 0, 0), P(10, 10, 10), P(5, 5, 5), P(15, 15, 15)), true, "partly")
	T.eq(Box.Overlaps(P(0, 0, 0), P(10, 10, 10), P(10, 10, 10), P(20, 20, 20)), true, "at a corner")
	T.eq(Box.Overlaps(P(0, 0, 0), P(10, 10, 10), P(5, 5, 11), P(15, 15, 15)), false, "apart in z only")
	T.eq(Box.Overlaps(P(0, 0, 0), P(10, 10, 10), P(11, 5, 5), P(15, 15, 15)), false, "apart in x only")
	T.eq(Box.Overlaps(P(0, 0, 0), P(10, 10, 10), P(5, 11, 5), P(15, 15, 15)), false, "apart in y only")
	T.eq(Box.Overlaps({ x = 0, y = 0 }, { x = 10, y = 10 }, { x = 5, y = 5 }, { x = 6, y = 6 }), true, "a missing z is 0")
end)

T.test("Contains is whether a point is in the box, its faces included", function()
	T.eq(Box.Contains(P(0, 0, 0), P(10, 10, 10), P(5, 5, 5)), true, "inside")
	T.eq(Box.Contains(P(0, 0, 0), P(10, 10, 10), P(10, 0, 10)), true, "on an edge")
	T.eq(Box.Contains(P(0, 0, 0), P(10, 10, 10), P(5, 5, 10.5)), false, "above")
	T.eq(Box.Contains(P(0, 0, 0), P(10, 10, 10), { x = 5, y = 5 }), true, "a missing z is 0")
end)

T.test("Extent is the smallest box around the points; nothing for none", function()
	local mins, maxs = Box.Extent({ P(3, -2, 5), P(-1, 8, 0), P(4, 1, 9) })
	T.eq(mins.x .. " " .. mins.y .. " " .. mins.z, "-1 -2 0", "mins")
	T.eq(maxs.x .. " " .. maxs.y .. " " .. maxs.z, "4 8 9", "maxs")
	mins, maxs = Box.Extent({ { x = 2, y = 3 } })
	T.eq(mins.z .. " " .. maxs.x, "0 2", "one point, a missing z is 0")
	T.eq(Box.Extent({}), nil, "no points")
end)

T.test("LongestAxis2D is the longer of x and y across the ground; x on a tie", function()
	T.eq(Box.LongestAxis2D(P(0, 0, 0), P(10, 4, 100)), "x", "wider")
	T.eq(Box.LongestAxis2D(P(0, 0, 0), P(4, 10, 0)), "y", "deeper")
	T.eq(Box.LongestAxis2D(P(0, 0, 0), P(7, 7, 0)), "x", "a tie")
end)

T.finish()
