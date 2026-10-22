-- foundation.analysis.analytics: timers of CPU time, counters, memory and
-- pressure against the tick's budget.
local T = dofile("tests/harness.lua")
local Analytics = T.require("foundation.analysis.analytics")

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

-- What wsprofile.Stop() returns: samples by VM state and by stack, frames
-- outermost first, separated by ";".
local function Sampled()
	return {
		samples = 10,
		states = {
			compiled = 2,
			interpreted = 5,
			gc = 1,
			compiler = 2,
		},
		stacks = {
			["Think;Update;Cost"] = 4,
			["Think;Update"] = 3,
			["Think;Search;Cost"] = 2,
			["Tick"] = 1,
		},
	}
end

local function Find(rows, name)
	for _, row in ipairs(rows) do
		if row.name == name then return row end
	end
end

T.test("a sample report gives each VM state's share, largest first", function()
	local report = Analytics.SampleReport(Sampled(), 10)
	T.eq(report.samples, 10, "samples")
	T.eq(report.states[1].name, "interpreted", "largest first")
	T.near(report.states[1].share, 0.5, 1e-9, "half interpreted")
	T.near(Find(report.states, "compiler").share, 0.2, 1e-9, "compiler share")
end)

T.test("self time is the leaf frame's; inclusive time counts a frame once per stack", function()
	local report = Analytics.SampleReport(Sampled(), 10)
	T.eq(Find(report.self, "Cost").count, 6, "Cost is the leaf of 4 + 2")
	T.eq(Find(report.self, "Update").count, 3, "Update's own")
	T.eq(Find(report.self, "Think"), nil, "Think is never a leaf")
	T.eq(Find(report.inclusive, "Think").count, 9, "Think is under 9 samples")
	T.eq(Find(report.inclusive, "Update").count, 7, "Update under 4 + 3")
	T.eq(report.self[1].name, "Cost", "hottest self first")
end)

T.test("a recursive frame counts once in a stack's inclusive time", function()
	local report = Analytics.SampleReport({
		samples = 2,
		states = { interpreted = 2 },
		stacks = { ["Walk;Walk;Walk"] = 2 },
	}, 10)
	T.eq(Find(report.inclusive, "Walk").count, 2, "once per stack")
end)

T.test("a sample report keeps the top n of each list", function()
	local report = Analytics.SampleReport(Sampled(), 2)
	T.eq(#report.stacks, 2, "stacks")
	T.eq(report.stacks[1].name, "Think;Update;Cost", "hottest stack first")
	T.eq(#report.self, 2, "self")
end)

T.test("an empty sample window reports nothing, not an error", function()
	local report = Analytics.SampleReport({
		samples = 0,
		states = {},
		stacks = {},
	}, 10)
	T.eq(report.samples, 0, "none")
	T.eq(#report.states, 0, "no states")
	T.eq(#Analytics.FormatSamples(report) > 0, true, "still formats")
end)

T.test("the sample format names the states and the hottest functions", function()
	local text = table.concat(Analytics.FormatSamples(Analytics.SampleReport(Sampled(), 10)), "\n")
	T.eq(text:find("interpreted", 1, true) ~= nil, true, "states")
	T.eq(text:find("Cost", 1, true) ~= nil, true, "functions:\n" .. text)
end)

T.finish()
