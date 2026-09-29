-- team_round_timer: the round clock, with an optional setup phase first
-- (CTeamRoundTimer, teamplay_round_timer.cpp). A map may have several; the
-- one shown in the HUD (WETSAND.HudTimer) publishes the tf2.timer.* keys, speaks
-- the countdown on clients, and puts the round into overtime.
ENT.Type = "point"
ENT.Base = "base_point"

local STATE_SETUP, STATE_NORMAL = "setup", "normal"

local INT_KEYS = {
	timer_length = "timerLength",
	max_length = "maxLength",
	setup_length = "setupLength",
	start_paused = "startPaused",
	show_in_hud = "showInHud",
	auto_countdown = "autoCountdown",
	show_time_remaining = "showTimeRemaining",
	reset_time = "resetTime",
	startdisabled = "startDisabled",
}

function ENT:KeyValue(key, value)
	local field = INT_KEYS[string.lower(key)]
	if field then
		self[field] = tonumber(value) or 0
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

-- CTeamRoundTimer::Spawn: paused, holding the setup time (or the round time
-- when there is no setup). A disabled timer still takes its time first.
function ENT:Initialize()
	self.timerLength = self.timerLength or 600
	self.maxLength = self.maxLength or 0
	self.setupLength = self.setupLength or 0
	self.startPaused = self.startPaused or 1
	self.showInHud = self.showInHud or 1
	self.autoCountdown = self.autoCountdown or 1
	self.resetTime = self.resetTime or 0
	self.serial = 0
	self.disabled = false
	self.paused = true
	self.remaining = 0
	self.endTime = CurTime()
	local length = self.timerLength
	if self.setupLength > 0 then
		length = self.setupLength
		self:SetState(STATE_SETUP, true)
	else
		self:SetState(STATE_NORMAL, true)
	end
	self.timeAfterSetup = self.timerLength
	self:SetTimeRemaining(length)
	self.disabled = self.startDisabled == 1
end

function ENT:OnRemove()
	if WETSAND.IsHudTimer(self) then WETSAND.SetActiveTimer(nil) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- Time -------------------------------------------------------------------------------

function ENT:TimeRemaining()
	local left = self.paused and self.remaining or self.endTime - CurTime()
	return math.max(0, left)
end

function ENT:Publish()
	if not WETSAND.IsHudTimer(self) then return end
	SetGlobal2Bool("tf2.timer.show", true)
	SetGlobal2Bool("tf2.timer.paused", self.paused)
	SetGlobal2Float("tf2.timer.left", self:TimeRemaining())
	SetGlobal2Float("tf2.timer.end", CurTime() + self:TimeRemaining())
	SetGlobal2Bool("tf2.timer.setup", self.state == STATE_SETUP)
	SetGlobal2Bool("tf2.timer.autocountdown", self.autoCountdown ~= 0)
	SetGlobal2Int("tf2.timer.serial", self.serial)
end

-- Every change to the timer's length bumps the serial, which is how clients
-- re-arm their countdown (the client's CalculateOutputMessages on a length change).
function ENT:LengthChanged()
	self.armed = WETSAND.RoundsLib.ArmTimerOutputs(self:TimeRemaining())
	self.serial = self.serial + 1
	self:Publish()
end

-- CTeamRoundTimer::SetTimeRemaining
function ENT:SetTimeRemaining(seconds)
	if self.disabled then return end
	if self.maxLength > 0 then seconds = math.min(seconds, self.maxLength) end
	self.remaining = seconds
	self.endTime = CurTime() + seconds
	self:LengthChanged()
end

function ENT:Pause()
	if self.disabled then return end
	if not self.paused then
		self.paused = true
		self.remaining = self.endTime - CurTime()
	end
	self:Publish()
end

function ENT:Resume()
	if self.disabled then return end
	if self.paused then
		self.paused = false
		self.endTime = CurTime() + self.remaining
	end
	self:Publish()
end

-- CTeamRoundTimer::SetState: every timer tells the gamerules whether it is in setup.
function ENT:SetState(state, fireOutput)
	self.state = state
	WETSAND.SetSetup(state == STATE_SETUP)
	if fireOutput then
		self:TriggerOutput(state == STATE_SETUP and "OnSetupStart" or "OnRoundStart", self)
	end
	self:Publish()
end

-- CTeamRoundTimer::InputRoundSpawn, sent at every round start (full or mini).
function ENT:RoundSpawn()
	self.timeAfterSetup = WETSAND.RoundsLib.TimeAfterSetup(self.resetTime == 1, self.state == STATE_NORMAL,
		self:TimeRemaining(), self.timerLength)
	if self.setupLength > 0 then
		self:SetState(STATE_SETUP, true)
		self:SetTimeRemaining(self.setupLength)
	else
		self:SetState(STATE_NORMAL, true)
		self:SetTimeRemaining(self.timeAfterSetup)
	end
	if self.startPaused == 0 then self:Resume() end
end

-- Thinking -----------------------------------------------------------------------------

local function RoundWon()
	return WETSAND.Active() and WETSAND.State() == WETSAND.STATE.TEAM_WIN
end

function ENT:FireMark(mark)
	self.armed[mark] = false
	self:TriggerOutput(WETSAND.RoundsLib.TimerOutputName(mark), self)
end

-- Setup's end, as the clock reaching zero brings it: OnSetupFinished (maps
-- wire their setup gates to it), then the round's clock with OnRoundStart.
-- Stopping the game for free play ends setup so, early.
function ENT:InSetup()
	return self.state == STATE_SETUP
end

function ENT:FinishSetup()
	self.armed.finished = false
	self:TriggerOutput("OnSetupFinished", self)
	self:SetState(STATE_NORMAL, true)
	self:SetTimeRemaining(self.timeAfterSetup)
end

-- RoundTimerSetupThink
function ENT:SetupThink()
	WETSAND.SetOvertime(false)
	local left = self:TimeRemaining()
	local next = WETSAND.RoundsLib.NextTimerOutput(self.armed, left, true)
	if next == "finished" then
		self:FinishSetup()
	elseif next then
		self:FireMark(next)
	end
end

-- RoundTimerThink: at zero the clock holds while a cart is being pushed
-- (overtime, announced by the HUD timer), then fires OnFinished.
function ENT:NormalThink()
	if RoundWon() then
		self:Pause()
		return
	end
	local left = self:TimeRemaining()
	local hud = WETSAND.IsHudTimer(self)
	if left > 0 and hud then WETSAND.SetOvertime(false) end
	local next = WETSAND.RoundsLib.NextTimerOutput(self.armed, left, false)
	if next == "finished" then
		if not WETSAND.TimerMayExpire() then
			self.endTime = CurTime()
			if hud then
				if WETSAND.InOvertime() then WETSAND.OvertimeNag() else WETSAND.SetOvertime(true) end
			end
			return
		end
		self.armed.finished = false
		self:TriggerOutput("OnFinished", self)
	elseif next then
		self:FireMark(next)
	end
end

function ENT:Think()
	self:NextThink(CurTime() + 0.05)
	if self.disabled or self.paused then return true end
	if self.state == STATE_SETUP then self:SetupThink() else self:NormalThink() end
	return true
end

-- Adding time ----------------------------------------------------------------------------

-- The announcer credits the team the time was added for (AddTeamTime).
local function AnnounceTimeAdded(team)
	if team == WETSAND.TEAM_RED or team == WETSAND.TEAM_BLUE then
		WETSAND.BroadcastSound(team, "Announcer.TimeAwardedForTeam")
		WETSAND.BroadcastSound(WETSAND.EnemyOf(team), "Announcer.TimeAddedForEnemy")
	else
		WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, "Announcer.TimeAdded")
	end
end

-- CTeamRoundTimer::AddTimerSeconds: only while the round runs (or has just
-- been won); only the HUD timer speaks, and not once the round is decided.
function ENT:AddTimerSeconds(seconds, team)
	if self.disabled then return end
	if WETSAND.Active() then
		local state = WETSAND.State()
		if state ~= WETSAND.STATE.RND_RUNNING and state ~= WETSAND.STATE.TEAM_WIN then return end
	end
	seconds = WETSAND.RoundsLib.ClampAdd(self:TimeRemaining(), seconds, self.maxLength)
	if self.paused then
		self.remaining = self.remaining + seconds
	else
		self.endTime = self.endTime + seconds
	end
	self:LengthChanged()
	if WETSAND.IsHudTimer(self) and not RoundWon() then
		AnnounceTimeAdded(team)
		if seconds > 0 then
			WETSAND.Announce(string.format("+%d:%02d", math.floor(seconds / 60), seconds % 60), 0)
		end
	end
end

-- Inputs -------------------------------------------------------------------------------------

function ENT:Enable()
	self.disabled = false
	self:Resume()
	if self.showInHud == 1 then WETSAND.SetActiveTimer(self) end
end

function ENT:Disable()
	self:Pause()
	self.disabled = true
	if self.showInHud == 1 then WETSAND.SetActiveTimer(nil) end
end

-- CTeamRoundTimer::InputShowInHUD; the flag is cleared before a replacement is
-- chosen, so a hidden timer never chooses itself.
function ENT:ShowInHUD(show)
	if self.showInHud == 1 and show == 0 then
		self.showInHud = 0
		WETSAND.SetActiveTimer(nil)
	elseif show == 1 then
		self.showInHud = 1
		WETSAND.SetActiveTimer(self)
		self:SetState(self.state, false)
	else
		self.showInHud = show
	end
end

local INPUTS = {
	pause = function(self) self:Pause() end,
	resume = function(self) self:Resume() end,
	settime = function(self, value) self:SetTimeRemaining(tonumber(value) or 0) end,
	setmaxtime = function(self, value)
		self.maxLength = tonumber(value) or 0
		if self.maxLength > 0 and self:TimeRemaining() > self.maxLength then self:SetTimeRemaining(self.maxLength) end
	end,
	addtime = function(self, value) self:AddTimerSeconds(tonumber(value) or 0) end,
	addteamtime = function(self, value)
		local team, seconds = string.match(tostring(value), "^%s*(%-?%d+)%s+(%-?%d+)")
		seconds = tonumber(seconds) or 0
		if seconds ~= 0 then self:AddTimerSeconds(seconds, tonumber(team)) end
	end,
	restart = function(self) self:SetTimeRemaining(self.timerLength) end,
	enable = function(self) self:Enable() end,
	disable = function(self) self:Disable() end,
	showinhud = function(self, value) self:ShowInHUD(tonumber(value) or 0) end,
	autocountdown = function(self, value) self.autoCountdown = tonumber(value) == 1 and 1 or 0 self:Publish() end,
	setsetuptime = function(self, value)
		local seconds = tonumber(value) or 0
		if seconds >= 0 then self.setupLength = seconds end
		if not self.disabled and self.state == STATE_SETUP then self:SetTimeRemaining(self.setupLength) end
	end,
	roundspawn = function(self) self:RoundSpawn() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end

-- The same inputs for Lua callers (the gamerules' stalemate and time limit timers).
function ENT:DoInput(name, value)
	INPUTS[string.lower(name)](self, value)
end
