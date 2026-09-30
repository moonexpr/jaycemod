-- The round clock (CTeamRoundTimer, teamplay_round_timer.cpp): an optional
-- setup phase, then normal time, with the map's marks (On5MinRemain...
-- On1SecRemain), overtime while the gamerules hold it at zero, added time,
-- and mini-round carry-over. One Timer per team_round_timer entity; the
-- rounds controller owns them.
--
-- Time comes in as `now`. Changes return events, plain tables:
--   { kind = "output", name }        the entity's output
--   { kind = "setup", value }        SetSetup on the gamerules (SetState)
--   { kind = "overtime", value }     SetOvertime on the gamerules
--   { kind = "nag" }                 the overtime nag (tf_overtime_nag)
--   { kind = "length_changed" }      CalculateOutputMessages: the serial bumped
--   { kind = "time_added", team, seconds }  the announced AddTimerSeconds
local ipairs, math, setmetatable = ipairs, math, setmetatable
module(...)

STATE_SETUP = "setup"   -- RT_STATE_SETUP
STATE_NORMAL = "normal" -- RT_STATE_NORMAL

-- CTeamRoundTimer's timer_length default.
LENGTH_DEFAULT = 600
-- RoundTimerThink: one nag chance a second.
NAG_INTERVAL = 1

local MARKS = { 300, 240, 180, 120, 60, 30, 10, 5, 4, 3, 2, 1 }
local SETUP_MARKS = { 60, 30, 10, 5, 4, 3, 2, 1 }
local OUTPUT = {
	[300] = "On5MinRemain",
	[240] = "On4MinRemain",
	[180] = "On3MinRemain",
	[120] = "On2MinRemain",
	[60] = "On1MinRemain",
	[30] = "On30SecRemain",
	[10] = "On10SecRemain",
	[5] = "On5SecRemain",
	[4] = "On4SecRemain",
	[3] = "On3SecRemain",
	[2] = "On2SecRemain",
	[1] = "On1SecRemain",
}
local FINISHED = "finished"

-- CalculateOutputMessages (server): each mark is armed while there is at
-- least that much time left.
local function ArmTimerOutputs(t)
	local armed = { [FINISHED] = t > 0 }
	for _, m in ipairs(MARKS) do armed[m] = t >= m end
	return armed
end

-- RoundTimerThink / RoundTimerSetupThink: at most one output per think, in
-- this order. Returns FINISHED, a mark, or nil.
local function NextTimerOutput(armed, t, setup)
	if t <= 0 and armed[FINISHED] then return FINISHED end
	for _, m in ipairs(setup and SETUP_MARKS or MARKS) do
		if t <= m and armed[m] then return m end
	end
	return nil
end

-- AddTimerSeconds: the seconds actually added under max_length.
local function ClampAdd(remaining, seconds, maxLength)
	if maxLength > 0 and remaining + seconds > maxLength then return maxLength - remaining end
	return seconds
end

local function Output(name)
	return {
		kind = "output",
		name = name,
	}
end

local function Flag(kind, value)
	return {
		kind = kind,
		value = value,
	}
end

local LENGTH_CHANGED = { kind = "length_changed" }

local Timer = {}
Timer.__index = Timer

-- kv = { length, maxLength, setupLength, startPaused, showInHud,
-- autoCountdown, resetTime, startDisabled, now }. CTeamRoundTimer::Spawn:
-- paused, holding the setup time (or the round time when there is none); a
-- disabled timer still takes its time first.
function New(kv)
	local timer = setmetatable({
		length = kv.length,
		maxLength = kv.maxLength,
		setupLength = kv.setupLength,
		startPaused = kv.startPaused,
		showInHud = kv.showInHud,
		autoCountdown = kv.autoCountdown,
		resetTime = kv.resetTime,
		disabled = false,
		paused = true,
		remaining = 0,
		endTime = kv.now,
		state = kv.setupLength > 0 and STATE_SETUP or STATE_NORMAL,
		timeAfterSetup = kv.length,
		armed = {},
		serial = 0,
		nextNag = 0,
	}, Timer)
	timer:SetTimeRemaining(kv.now, kv.setupLength > 0 and kv.setupLength or kv.length)
	timer.disabled = kv.startDisabled
	return timer
end

function Timer:TimeRemaining(now)
	local left = self.paused and self.remaining or self.endTime - now
	return math.max(0, left)
end

function Timer:Paused() return self.paused end
function Timer:Disabled() return self.disabled end
function Timer:InSetup() return self.state == STATE_SETUP end
function Timer:ShowInHud() return self.showInHud end
function Timer:AutoCountdown() return self.autoCountdown end
function Timer:Serial() return self.serial end

-- Every length change re-arms the marks and bumps the serial, which is how
-- clients re-arm their countdown.
local function LengthChanged(self, now)
	self.armed = ArmTimerOutputs(self:TimeRemaining(now))
	self.serial = self.serial + 1
	return LENGTH_CHANGED
end

-- CTeamRoundTimer::SetTimeRemaining
function Timer:SetTimeRemaining(now, seconds)
	if self.disabled then return {} end
	if self.maxLength > 0 then seconds = math.min(seconds, self.maxLength) end
	self.remaining = seconds
	self.endTime = now + seconds
	return { LengthChanged(self, now) }
end

-- PauseTimer
function Timer:Pause(now)
	if self.disabled or self.paused then return end
	self.paused = true
	self.remaining = self.endTime - now
end

-- ResumeTimer
function Timer:Resume(now)
	if self.disabled or not self.paused then return end
	self.paused = false
	self.endTime = now + self.remaining
end

-- InputEnable / InputDisable (the HUD timer choice is the controller's).
function Timer:Enable(now)
	self.disabled = false
	self:Resume(now)
end

function Timer:Disable(now)
	self:Pause(now)
	self.disabled = true
end

-- InputRestart
function Timer:Restart(now)
	return self:SetTimeRemaining(now, self.length)
end

-- InputSetMaxTime
function Timer:SetMaxLength(now, seconds)
	self.maxLength = seconds
	if seconds > 0 and self:TimeRemaining(now) > seconds then return self:SetTimeRemaining(now, seconds) end
	return {}
end

-- InputSetSetupTime
function Timer:SetSetupLength(now, seconds)
	if seconds >= 0 then self.setupLength = seconds end
	if not self.disabled and self.state == STATE_SETUP then return self:SetTimeRemaining(now, self.setupLength) end
	return {}
end

-- CTeamRoundTimer::SetShowInHud: the flag alone, no HUD-timer choice.
function Timer:SetShowInHud(show)
	self.showInHud = show
end

function Timer:SetAutoCountdown(on)
	self.autoCountdown = on
end

-- CTeamRoundTimer::SetState: every timer tells the gamerules whether it is
-- in setup, and may fire OnSetupStart or OnRoundStart.
local function SetState(self, events, state, fireOutput)
	self.state = state
	events[#events + 1] = Flag("setup", state == STATE_SETUP)
	if fireOutput then
		events[#events + 1] = Output(state == STATE_SETUP and "OnSetupStart" or "OnRoundStart")
	end
	return events
end

local function Append(events, more)
	for _, e in ipairs(more) do events[#events + 1] = e end
	return events
end

-- What Spawn's SetState says as the timer spawns.
function Timer:SpawnEvents()
	return SetState(self, {}, self.state, true)
end

-- The current state again, without its output (InputShowInHUD).
function Timer:StateEvents()
	return SetState(self, {}, self.state, false)
end

-- CTeamRoundTimer::InputRoundSpawn, at every round start (full or mini):
-- without reset_time a timer in normal time carries its time on.
function Timer:RoundSpawn(now)
	if not self.resetTime and self.state == STATE_NORMAL then
		self.timeAfterSetup = self:TimeRemaining(now)
	else
		self.timeAfterSetup = self.length
	end
	local events = {}
	if self.setupLength > 0 then
		SetState(self, events, STATE_SETUP, true)
		Append(events, self:SetTimeRemaining(now, self.setupLength))
	else
		SetState(self, events, STATE_NORMAL, true)
		Append(events, self:SetTimeRemaining(now, self.timeAfterSetup))
	end
	if not self.startPaused then self:Resume(now) end
	return events
end

-- Setup's end, as the clock reaching zero brings it: OnSetupFinished (maps
-- wire their setup gates to it), then the round's clock with OnRoundStart.
function Timer:FinishSetup(now)
	self.armed[FINISHED] = false
	local events = { Output("OnSetupFinished") }
	SetState(self, events, STATE_NORMAL, true)
	return Append(events, self:SetTimeRemaining(now, self.timeAfterSetup))
end

-- CTeamRoundTimer::AddTimerSeconds. q = { roundRunningOrWon, isHud,
-- roundWon, inStalemate, announces }: time is added only while the round
-- runs or has just been won (so points setting their owners at load add
-- none), never in sudden death, and only the HUD timer of an undecided round
-- announces it (not in KOTH). Returns the events and the seconds added.
function Timer:AddSeconds(now, seconds, team, q)
	if self.disabled or q.inStalemate or not q.roundRunningOrWon then return {}, 0 end
	seconds = ClampAdd(self:TimeRemaining(now), seconds, self.maxLength)
	if self.paused then
		self.remaining = self.remaining + seconds
	else
		self.endTime = self.endTime + seconds
	end
	local events = { LengthChanged(self, now) }
	if q.announces and q.isHud and not q.roundWon then
		events[#events + 1] = {
			kind = "time_added",
			team = team,
			seconds = seconds,
		}
	end
	return events, seconds
end

local function FireMark(self, events, mark)
	self.armed[mark] = false
	events[#events + 1] = Output(OUTPUT[mark])
end

-- RoundTimerSetupThink
local function SetupThink(self, events, now, q)
	if q.overtime then events[#events + 1] = Flag("overtime", false) end
	local next = NextTimerOutput(self.armed, self:TimeRemaining(now), true)
	if next == FINISHED then
		Append(events, self:FinishSetup(now))
	elseif next then
		FireMark(self, events, next)
	end
end

-- RoundTimerThink: a won round pauses the clock; at zero it holds while the
-- gamerules say it may not expire (overtime, for a timer shown in the HUD,
-- with a nag at most once a second on a coin flip), then fires OnFinished.
local function NormalThink(self, events, now, q)
	if q.roundWon then
		self:Pause(now)
		return
	end
	local left = self:TimeRemaining(now)
	if left > 0 and self.showInHud and q.overtime then events[#events + 1] = Flag("overtime", false) end
	local next = NextTimerOutput(self.armed, left, false)
	if next == FINISHED then
		if not q.mayExpire then
			self.endTime = now
			if self.showInHud then
				if not q.overtime then
					events[#events + 1] = Flag("overtime", true)
				elseif q.nagEnabled and now > self.nextNag then
					self.nextNag = now + NAG_INTERVAL
					if q.random(0, 1) > 0 then events[#events + 1] = { kind = "nag" } end
				end
			end
			return
		end
		self.armed[FINISHED] = false
		events[#events + 1] = Output("OnFinished")
	elseif next then
		FireMark(self, events, next)
	end
end

-- q = { mayExpire, roundWon, overtime, nagEnabled, random(lo, hi) -> int }.
function Timer:Think(now, q)
	local events = {}
	if self.disabled or self.paused then return events end
	if self.state == STATE_SETUP then
		SetupThink(self, events, now, q)
	else
		NormalThink(self, events, now, q)
	end
	return events
end

-- Client countdown ------------------------------------------------------------------

-- The client's CalculateOutputMessages adds 2 s above ten seconds, covering
-- the time the update took to arrive.
local WARNINGS = { 60, 30, 10, 5, 4, 3, 2, 1 }
local WARN_AT = {
	[60] = 61,
	[30] = 31,
	[10] = 11,
	[5] = 6,
	[4] = 5,
	[3] = 4,
	[2] = 3,
	[1] = 2,
}
local CLIENT_PAD_ABOVE, CLIENT_PAD = 10, 2

function ArmClientWarnings(t)
	local padded = t > CLIENT_PAD_ABOVE and t + CLIENT_PAD or t
	local armed = {}
	for _, s in ipairs(WARNINGS) do armed[s] = padded >= s end
	return armed
end

-- CTeamRoundTimer::ClientThink: the countdown line to speak now, or nil.
function NextClientWarning(armed, t)
	for _, s in ipairs(WARNINGS) do
		if t <= WARN_AT[s] and armed[s] then return s end
	end
	return nil
end

-- CTeamRoundTimer::SetActiveTimer. timers: { enabled, show }; newly: the index
-- becoming active, or nil when the active one goes away. Returns the chosen
-- index (or nil) and the indices whose show_in_hud is turned off.
function ChooseActiveTimer(timers, newly)
	local chosen, hide = newly, {}
	for i, t in ipairs(timers) do
		if i ~= newly and t.enabled and t.show then
			if chosen then hide[#hide + 1] = i else chosen = i end
		end
	end
	return chosen, hide
end
