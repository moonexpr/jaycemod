-- games.timer.interval: NextBot's IntervalTimer (util_shared.h), on a clock
-- port.
local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Interval = timer.interval

T.test("an unstarted interval is very old; a started one measures from its start", function()
	local clock = Fake.Clock(10)
	local t = Interval.New(clock)
	T.eq(t:HasStarted(), false, "unstarted")
	T.eq(t:GetElapsedTime(), Interval.INTERVAL_UNSTARTED, "unstarted elapsed")
	t:Start()
	clock:Advance(2)
	T.eq(t:HasStarted(), true, "started")
	T.near(t:GetElapsedTime(), 2, 1e-9, "elapsed")
	T.eq(t:IsLessThen(3), true, "less than 3")
	T.eq(t:IsGreaterThen(1), true, "greater than 1")
	T.eq(t:IsGreaterThen(2), false, "not greater than 2")
	t:Reset()
	T.near(t:GetElapsedTime(), 0, 1e-9, "reset")
	t:Invalidate()
	T.eq(t:GetElapsedTime(), Interval.INTERVAL_UNSTARTED, "invalidated")
end)

T.finish()
