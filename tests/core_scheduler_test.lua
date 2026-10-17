-- foundation.core.scheduler: cooperative tasks that share a slice of time.
local T = dofile("tests/harness.lua")
local Scheduler = T.require("foundation.core.scheduler")

-- A clock the test moves: each Now() call advances it by `step`.
local function Clock(step)
	local clock = { t = 0, step = step or 0 }
	function clock:Now()
		self.t = self.t + self.step
		return self.t
	end
	return clock
end

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

T.test("a task runs to its end within the slice when it fits", function()
	local scheduler = Scheduler.New(Clock(0))
	local log = {}
	scheduler:Spawn(function(a, b) log[#log + 1] = a + b end, 2, 3)
	T.eq(scheduler:Count(), 1, "waiting")
	scheduler:Run(1)
	T.eq(log[1], 5, "ran with its arguments")
	T.eq(scheduler:Count(), 0, "done")
end)

T.test("a task yields at a check once the slice is spent, and goes on next run", function()
	local clock = Clock(0)
	local scheduler = Scheduler.New(clock)
	local steps = 0
	scheduler:Spawn(function()
		for _ = 1, 10 do
			steps = steps + 1
			clock.t = clock.t + 1
			scheduler:CheckYield()
		end
	end)
	scheduler:Run(3)
	T.eq(steps, 3, "stopped when three seconds were spent")
	scheduler:Run(3)
	T.eq(steps, 6, "went on from there")
	scheduler:Run(100)
	T.eq(steps, 10, "finished")
	T.eq(scheduler:Count(), 0, "gone")
end)

T.test("a check before the slice is spent does not yield", function()
	local scheduler = Scheduler.New(Clock(0))
	local yielded
	scheduler:Spawn(function() yielded = scheduler:CheckYield() end)
	scheduler:Run(1)
	T.eq(yielded, false, "time left")
end)

T.test("tasks take turns: one that yields goes behind the others", function()
	local clock = Clock(0)
	local scheduler = Scheduler.New(clock)
	local order = {}
	local function Worker(name)
		return function()
			for _ = 1, 2 do
				order[#order + 1] = name
				clock.t = clock.t + 1
				scheduler:CheckYield()
			end
		end
	end
	scheduler:Spawn(Worker("a"))
	scheduler:Spawn(Worker("b"))
	scheduler:Run(1)
	scheduler:Run(1)
	scheduler:Run(1)
	scheduler:Run(1)
	T.eq(table.concat(order, " "), "a b a b", "round robin")
end)

T.test("a task may give up its turn before the slice is spent", function()
	local scheduler = Scheduler.New(Clock(0))
	local order = {}
	scheduler:Spawn(function()
		order[#order + 1] = "a1"
		scheduler:Yield()
		order[#order + 1] = "a2"
	end)
	scheduler:Spawn(function() order[#order + 1] = "b" end)
	scheduler:Run(1)
	T.eq(table.concat(order, " "), "a1 b a2", "b ran in a's gap, a finished in the same run")
end)

T.test("a waiting task is parked until its condition holds, without spinning the slice", function()
	local clock = Clock(0)
	local scheduler = Scheduler.New(clock)
	local ready, log = false, {}
	scheduler:Spawn(function()
		scheduler:Wait(function() return ready end)
		log[#log + 1] = "woke"
	end)
	local calls = 0
	local counting = { Now = function() calls = calls + 1; return 0 end }
	scheduler.clock = counting
	scheduler:Run(1)
	scheduler:Run(1)
	T.eq(#log, 0, "still parked")
	T.eq(calls < 10, true, "a run with only parked tasks returns at once")
	ready = true
	scheduler:Run(1)
	T.eq(log[1], "woke", "woken once its condition held")
	T.eq(scheduler:Count(), 0, "and done")
end)

T.test("a parked task does not keep the others from running", function()
	local scheduler = Scheduler.New(Clock(0))
	local log = {}
	scheduler:Spawn(function() scheduler:Wait(function() return false end) end)
	scheduler:Spawn(function() log[#log + 1] = "ran" end)
	scheduler:Run(1)
	T.eq(log[1], "ran", "the second ran")
	T.eq(scheduler:Count(), 1, "the parked one waits on")
end)

T.test("waiting outside a task is our bug", function()
	local scheduler = Scheduler.New(Clock(0))
	T.eq(pcall(scheduler.Wait, scheduler, function() return true end), false, "refused")
end)

T.test("outside a task, checks and yields do nothing", function()
	local scheduler = Scheduler.New(Clock(0))
	T.eq(scheduler:CheckYield(), false, "check")
	T.eq(scheduler:Yield(), false, "yield")
end)

T.test("a task's error reaches the caller of Run, and the task is gone", function()
	local scheduler = Scheduler.New(Clock(0))
	scheduler:Spawn(function() error("broken task") end)
	local err = Raises(scheduler.Run, scheduler, 1)
	T.eq(err:find("broken task", 1, true) ~= nil, true, "the task's message")
	T.eq(scheduler:Count(), 0, "removed")
end)

T.test("a run with nothing to do returns at once", function()
	local scheduler = Scheduler.New(Clock(1))
	scheduler:Run(5)
	T.eq(scheduler:Count(), 0, "nothing")
end)

T.finish()
