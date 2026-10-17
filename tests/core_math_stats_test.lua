-- foundation.core.math.stats: summary figures of a list of numbers.
local T = dofile("tests/harness.lua")
local Stats = T.require("foundation.core.math.stats")

T.test("the mean of a list, and 0 for none", function()
	T.eq(Stats.Mean({ 1, 2, 3, 6 }), 3, "mean")
	T.eq(Stats.Mean({}), 0, "empty")
end)

T.test("a percentile is the nearest-rank value, and 0 for none", function()
	local list = { 5, 1, 4, 2, 3, 10, 9, 8, 7, 6 }
	T.eq(Stats.Percentile(list, 0.95), 10, "p95 of ten")
	T.eq(Stats.Percentile(list, 0.5), 5, "the median rank")
	T.eq(Stats.Percentile(list, 0), 1, "the least")
	T.eq(Stats.Percentile({}, 0.95), 0, "empty")
	T.eq(list[1], 5, "the list is left in its order")
end)

T.finish()
