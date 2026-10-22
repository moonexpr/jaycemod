-- NextBot's IntervalTimer (util_shared.h), on a clock port: `clock:Now()`
-- gives the time (an NPC's actor port is a clock, as is any port with Now).
--   New(clock): Start, Reset, Invalidate, HasStarted, GetElapsedTime
--     (INTERVAL_UNSTARTED when unstarted), IsLessThen, IsGreaterThen.
local setmetatable = setmetatable
module(...)

-- IntervalTimer::GetElapsedTime when unstarted.
INTERVAL_UNSTARTED = 99999.9

-- The timestamp an unstarted timer holds.
local UNSTARTED = -1

local Interval = {}
Interval.__index = Interval

function New(clock)
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
