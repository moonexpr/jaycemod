-- NextBot's timers (util_shared.h), on a clock port: `clock:Now()` gives
-- the time (an NPC's actor port is a clock, as is any port with Now).
--   CountdownTimer(clock): Start(duration), Reset (again for the same
--     duration), Invalidate, HasStarted, IsElapsed (an unstarted one has),
--     GetElapsedTime, GetRemainingTime, GetCountdownDuration;
--   IntervalTimer(clock): Start, Reset, Invalidate, HasStarted,
--     GetElapsedTime (INTERVAL_UNSTARTED when unstarted), IsLessThen,
--     IsGreaterThen.
local setmetatable = setmetatable
module(...)

-- IntervalTimer::GetElapsedTime when unstarted.
INTERVAL_UNSTARTED = 99999.9

-- The timestamp an unstarted timer holds.
local UNSTARTED = -1

local Countdown = {}
Countdown.__index = Countdown

function CountdownTimer(clock)
	return setmetatable({
		clock = clock,
		timestamp = UNSTARTED,
		duration = 0,
	}, Countdown)
end

function Countdown:Reset() self.timestamp = self.clock:Now() + self.duration end

function Countdown:Start(duration)
	self.timestamp = self.clock:Now() + duration
	self.duration = duration
end

function Countdown:Invalidate() self.timestamp = UNSTARTED end
function Countdown:HasStarted() return self.timestamp > 0 end
function Countdown:IsElapsed() return self.clock:Now() > self.timestamp end
function Countdown:GetElapsedTime() return self.clock:Now() - self.timestamp + self.duration end
function Countdown:GetRemainingTime() return self.timestamp - self.clock:Now() end

function Countdown:GetCountdownDuration()
	if self.timestamp > 0 then return self.duration end
	return 0
end

local Interval = {}
Interval.__index = Interval

function IntervalTimer(clock)
	return setmetatable({
		clock = clock,
		timestamp = UNSTARTED,
	}, Interval)
end

function Interval:Reset() self.timestamp = self.clock:Now() end
function Interval:Start() self.timestamp = self.clock:Now() end
function Interval:Invalidate() self.timestamp = UNSTARTED end
function Interval:HasStarted() return self.timestamp > 0 end

function Interval:GetElapsedTime()
	if self:HasStarted() then return self.clock:Now() - self.timestamp end
	return INTERVAL_UNSTARTED
end

-- The names keep util_shared.h's "Then".
function Interval:IsLessThen(duration) return self.clock:Now() - self.timestamp < duration end
function Interval:IsGreaterThen(duration) return self.clock:Now() - self.timestamp > duration end
