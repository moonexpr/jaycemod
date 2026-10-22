-- Whether the server is idle: once it has had no players for a delay (a
-- CountdownTimer started as the last one leaves, or as the map starts
-- empty), it goes IDLE; a player joining calls the countdown off, or, on
-- an idle server, makes it ACTIVE again. ws/sv_idle.lua runs it and says
-- each change (WSServerIdle, WSServerActive).
local setmetatable = setmetatable
local Countdown = require("game.timer.countdown")
module(...)

IDLE = "idle"
ACTIVE = "active"

local Watch = {}
Watch.__index = Watch

-- clock: Now(); delay: the seconds an empty server waits before idling.
function New(clock, delay)
	return setmetatable({
		countdown = Countdown.New(clock),
		delay = delay,
		idle = false,
	}, Watch)
end

function Watch:IsIdle() return self.idle end

-- The players on the server now; IDLE or ACTIVE when that changes whether
-- the server is idle, else nil.
function Watch:Update(humans)
	if humans > 0 then
		self.countdown:Invalidate()
		if not self.idle then return nil end
		self.idle = false
		return ACTIVE
	end
	if self.idle then return nil end
	if not self.countdown:HasStarted() then
		self.countdown:Start(self.delay)
		return nil
	end
	if not self.countdown:IsElapsed() then return nil end
	self.countdown:Invalidate()
	self.idle = true
	return IDLE
end
