-- foundation.math.interval: ranges [low, high] of one number line.
local T = dofile("tests/harness.lua")
local Interval = math.interval

T.test("two intervals overlap when neither lies wholly past the other; touching counts", function()
	T.eq(Interval.Overlaps(0, 10, 5, 15), true, "partly")
	T.eq(Interval.Overlaps(0, 10, 2, 3), true, "inside")
	T.eq(Interval.Overlaps(2, 3, 0, 10), true, "around")
	T.eq(Interval.Overlaps(0, 10, 10, 20), true, "touching at one point")
	T.eq(Interval.Overlaps(0, 10, 10.5, 20), false, "apart")
	T.eq(Interval.Overlaps(20, 30, 0, 10), false, "apart, the other way")
end)

T.test("Intersect is the highest low and the lowest high; low is above high when they are apart", function()
	local lo, hi = Interval.Intersect(0, 10, 5, 15)
	T.eq(lo, 5, "low")
	T.eq(hi, 10, "high")
	lo, hi = Interval.Intersect(2, 3, 0, 10)
	T.eq(lo .. " " .. hi, "2 3", "one inside the other")
	lo, hi = Interval.Intersect(0, 4, 10, 20)
	T.eq(lo .. " " .. hi, "10 4", "apart: low above high")
	lo, hi = Interval.Intersect(0, 10, 10, 20)
	T.eq(lo .. " " .. hi, "10 10", "touching: a point")
end)

T.finish()
