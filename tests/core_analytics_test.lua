-- foundation.core.analytics: timers of CPU time, counters, memory and
-- pressure against the tick's budget.
local T = dofile("tests/harness.lua")
local Analytics = T.require("foundation.core.analytics")

local function Clock()
	local clock = { time = 0 }
	function clock:Now() return self.time end
	return clock
end

local function Memory()
	local memory = { kb = 1000 }
	function memory:Kilobytes() return self.kb end
	return memory
end

local function Setup()
	local clock, memory = Clock(), Memory()
	return Analytics.New(clock, memory), clock, memory
end

-- Spend seconds of clock time inside a timed span.
local function Spend(a, clock, name, seconds)
	local started = a:Start()
	clock.time = clock.time + seconds
	a:Stop(name, started)
end

T.test("a timer keeps count, total, mean, least, most and last of its samples", function()
	local a, clock = Setup()
	Spend(a, clock, "think", 0.002)
	Spend(a, clock, "think", 0.004)
	Spend(a, clock, "think", 0.003)
	local think = a:Report().timers.think
	T.eq(think.count, 3, "count")
	T.near(think.total, 0.009, 1e-9, "total")
	T.near(think.mean, 0.003, 1e-9, "mean")
	T.near(think.min, 0.002, 1e-9, "min")
	T.near(think.max, 0.004, 1e-9, "max")
	T.near(think.last, 0.003, 1e-9, "last")
end)

T.test("a timer's high percentile reads its recent window", function()
	local a, clock = Setup()
	for i = 1, Analytics.WINDOW do Spend(a, clock, "path", i == Analytics.WINDOW and 1 or 0.001) end
	local path = a:Report().timers.path
	T.near(path.p95, 0.001, 1e-9, "one outlier is above the 95th percentile")
	for _ = 1, Analytics.WINDOW do Spend(a, clock, "path", 0.5) end
	T.near(a:Report().timers.path.p95, 0.5, 1e-9, "old samples leave the window")
	T.near(a:Report().timers.path.max, 1, 1e-9, "the most is all-time")
end)

T.test("Time measures a call and hands back its results", function()
	local a, clock = Setup()
	local x, y = a:Time("call", function(p, q)
		clock.time = clock.time + 0.25
		return p + q, "done"
	end, 1, 2)
	T.eq(x, 3, "first result")
	T.eq(y, "done", "second result")
	T.near(a:Report().timers.call.total, 0.25, 1e-9, "timed")
end)

T.test("counters add up, by one unless told", function()
	local a = Setup()
	a:Count("spawns")
	a:Count("spawns", 4)
	T.eq(a:Report().counters.spawns, 5, "five")
end)

T.test("pressure is a frame's timed work over its budget, nested spans counted once", function()
	local a, clock = Setup()
	local outer = a:Start()
	Spend(a, clock, "inner", 0.010)
	clock.time = clock.time + 0.005
	a:Stop("outer", outer)
	a:Frame(0.030)
	local pressure = a:Report().pressure
	T.near(pressure.last, 0.5, 1e-9, "15 ms of a 30 ms tick")
	T.eq(pressure.frames, 1, "one frame")
	T.eq(pressure.overBudget, 0, "within budget")
	Spend(a, clock, "outer", 0.045)
	a:Frame(0.030)
	pressure = a:Report().pressure
	T.near(pressure.last, 1.5, 1e-9, "over")
	T.near(pressure.peak, 1.5, 1e-9, "peak")
	T.near(pressure.mean, 1.0, 1e-9, "mean of the window")
	T.eq(pressure.overBudget, 1, "one frame over")
end)

T.test("memory keeps the latest, the least and the most, and its growth per second", function()
	local a, clock, memory = Setup()
	a:Frame(0.03)
	clock.time = 10
	memory.kb = 3000
	a:Frame(0.03)
	clock.time = 20
	memory.kb = 2000
	a:Frame(0.03)
	local m = a:Report().memory
	T.eq(m.kb, 2000, "latest")
	T.eq(m.min, 1000, "least")
	T.eq(m.peak, 3000, "most")
	T.near(m.growthPerSecond, 50, 1e-9, "1000 kB over 20 s")
end)

T.test("a report before any sample is empty, not missing", function()
	local a = Setup()
	local report = a:Report()
	T.eq(next(report.timers), nil, "no timers")
	T.eq(report.pressure.frames, 0, "no frames")
	T.eq(report.memory.kb, nil, "no memory sample")
	T.eq(#Analytics.Format(report) > 0, true, "still formats")
end)

T.test("stopping a span never started is an error", function()
	local a = Setup()
	T.eq(pcall(a.Stop, a, "orphan", 0), false, "raises")
end)

T.test("Reset forgets everything measured", function()
	local a, clock = Setup()
	Spend(a, clock, "think", 0.01)
	a:Count("x")
	a:Frame(0.03)
	a:Reset()
	local report = a:Report()
	T.eq(next(report.timers), nil, "timers")
	T.eq(next(report.counters), nil, "counters")
	T.eq(report.pressure.frames, 0, "frames")
end)

T.test("the format names every timer and counter, slowest first", function()
	local a, clock = Setup()
	Spend(a, clock, "fast", 0.001)
	Spend(a, clock, "slow", 0.010)
	a:Count("spawns", 2)
	local text = table.concat(Analytics.Format(a:Report()), "\n")
	local slow, fast = text:find("slow", 1, true), text:find("fast", 1, true)
	T.eq(slow ~= nil and fast ~= nil and slow < fast, true, "slow before fast:\n" .. text)
	T.eq(text:find("spawns", 1, true) ~= nil, true, "counter listed")
end)

T.finish()
