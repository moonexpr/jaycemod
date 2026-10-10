-- foundation.npc.profile: the path-search measurements ws_path_profile
-- and ws_path_bench collect, their summary, and what the numbers say.
local T = dofile("tests/harness.lua")
local Profile = T.require("foundation.npc.profile")

local TICK = 0.015 -- a 66-tick server

local function Sample(label, ms, calls, costMs, found)
	return {
		label = label,
		seconds = ms / 1000,
		costCalls = calls,
		costSeconds = costMs / 1000,
		found = found ~= false,
	}
end

local function Has(lines, text)
	for _, line in ipairs(lines) do
		if string.find(line, text, 1, true) then return true end
	end
	return false
end

T.test("an empty window reports nothing recorded", function()
	local report = Profile.New(10):Report(20)
	T.eq(report.count, 0, "count")
	T.eq(Profile.Verdict(report, TICK), Profile.VERDICT_NONE, "verdict")
	T.eq(Has(Profile.Format(report, TICK), "no path was computed"), true, "said so")
end)

T.test("the summary counts, sums and ranks every compute", function()
	local p = Profile.New(10)
	for ms = 1, 10 do p:Record(Sample("zombie", ms, 100, ms / 2)) end
	p:Record(Sample("hatman", 20, 300, 5, false))
	local r = p:Report(20)
	T.eq(r.window, 10, "window")
	T.eq(r.count, 11, "count")
	T.eq(r.failed, 1, "failed")
	T.near(r.totalSeconds, 0.075, 1e-9, "total")
	T.near(r.mean, 0.075 / 11, 1e-9, "mean")
	T.near(r.p50, 0.006, 1e-9, "median (nearest rank)")
	T.near(r.p95, 0.020, 1e-9, "p95")
	T.near(r.max, 0.020, 1e-9, "max")
	T.eq(r.costCalls, 1300, "cost calls")
	T.near(r.costShare, (0.0275 + 0.005) / 0.075, 1e-9, "cost share")
	T.near(r.perSecond, 1.1, 1e-9, "computes per second")
	T.near(r.frameShare, 0.0075, 1e-9, "share of server time")
end)

T.test("labels are listed by the time they took, most first", function()
	local p = Profile.New(0)
	p:Record(Sample("zombie", 1, 10, 0))
	p:Record(Sample("zombie", 1, 10, 0))
	p:Record(Sample("hatman", 5, 10, 0))
	local labels = p:Report(1).labels
	T.eq(labels[1].label, "hatman", "first")
	T.eq(labels[2].label, "zombie", "second")
	T.eq(labels[2].count, 2, "zombie count")
	T.near(labels[2].totalSeconds, 0.002, 1e-9, "zombie total")
	T.near(labels[1].max, 0.005, 1e-9, "hatman max")
end)

T.test("cheap, infrequent searches say keep the engine's search", function()
	local p = Profile.New(0)
	for _ = 1, 20 do p:Record(Sample("zombie", 0.5, 50, 0.3)) end
	T.eq(Profile.Verdict(p:Report(10), TICK), Profile.VERDICT_KEEP, "0.1% of server time")
end)

T.test("searches mostly spent in the Lua cost callback point at the cost function", function()
	local p = Profile.New(0)
	for _ = 1, 100 do p:Record(Sample("zombie", 6, 900, 5)) end
	T.eq(Profile.Verdict(p:Report(10), TICK), Profile.VERDICT_COST, "6% of time, 83% in the callback")
end)

T.test("searches mostly spent in the engine point at moving the search off the main thread", function()
	local p = Profile.New(0)
	for _ = 1, 100 do p:Record(Sample("zombie", 6, 900, 1)) end
	T.eq(Profile.Verdict(p:Report(10), TICK), Profile.VERDICT_SEARCH, "6% of time, 17% in the callback")
end)

T.test("one search that stalls a whole tick is over the line however rare", function()
	local p = Profile.New(0)
	p:Record(Sample("hatman", 20, 5000, 2))
	T.eq(Profile.Verdict(p:Report(600), TICK), Profile.VERDICT_SEARCH, "a 20 ms hitch")
end)

T.test("the printed report carries the figures and the thresholds it judged by", function()
	local p = Profile.New(0)
	p:Record(Sample("zombie", 2, 100, 1))
	local lines = Profile.Format(p:Report(4), TICK)
	T.eq(Has(lines, "1 computes in 4.0 s"), true, "count line")
	T.eq(Has(lines, "zombie"), true, "label line")
	T.eq(Has(lines, "50%"), true, "cost share")
	T.eq(Has(lines, "5%"), true, "the time threshold")
end)

T.test("a bench pairs each goal under the engine's cost and the Lua cost, and judges no share of time", function()
	local p = Profile.New(0, true)
	for _ = 1, 4 do
		p:Record(Sample(Profile.BENCH_ENGINE_LABEL, 1, 0, 0))
		p:Record(Sample("zombie", 3, 200, 1.5))
	end
	local r = p:Report(100)
	T.eq(r.bench, true, "bench")
	T.near(r.labels[1].mean, 0.003, 1e-9, "Lua cost mean")
	T.near(r.labels[2].mean, 0.001, 1e-9, "engine cost mean")
	local lines = Profile.Format(r, TICK)
	T.eq(Has(lines, "path bench: 8 computes"), true, "bench header")
	T.eq(Has(lines, "the Lua cost adds 2.000 ms per compute"), true, "the paired difference")
	T.eq(Has(lines, "verdict"), false, "no verdict from a bench")
	T.eq(Has(lines, "of server time ("), false, "no share of server time")
end)

T.finish()
