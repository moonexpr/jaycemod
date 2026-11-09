-- The koth feature's controller. It owns the tf_logic_koth model
-- (features.koth.model), puts the round in the koth mode, and at the
-- round's phases does what CKothLogic does: at RoundSpawn it has the rounds
-- controller make the two team clocks (team_round_timer entities named
-- zz_blue_koth_timer and zz_red_koth_timer, so maps' AddOutputs and inputs
-- reach them), shown but never the HUD timer, paused at timer_length; at
-- RoundActivate it locks every point for unlock_point seconds through the
-- capture controller. tf_gamerules' Set<Team>KothClockActive reaches the
-- clocks through the rounds controller. It publishes the clocks for the view
-- (ws_koth_clock_<team>_*).
--
-- Loaded by tf_logic_koth. It loads rounds and capture.
local Koth = WS.require("features.koth.model")
local Rounds = gameplay.rounds

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }
local PUBLISH_INTERVAL = 0.1 -- the HUD's 10 Hz, as the capture controller's
local THINK_HOOK = "ws_koth"

local Controller = {
	rounds = WS.Feature("rounds"),
	capture = WS.Feature("capture"),
	logicEnt = NULL,
	koth = nil,
	clocks = {},
	nextPublish = 0,
}

-- CTFGameRules::Activate: a tf_logic_koth makes the game koth (m_bPlayingKoth).
Controller.rounds:SetMode(Koth.Mode)

-- The first tf_logic_koth is the one in charge (FindEntityByClassname).
-- kv = { timerLength, unlockPoint }, numbers or nil.
function Controller:BindLogic(ent, kv)
	if IsValid(self.logicEnt) and self.logicEnt ~= ent then return end
	self.logicEnt = ent
	self.koth = Koth.New(kv)
end

-- A map reset removes the logic before its replacement binds.
function Controller:UnbindLogic(ent)
	if ent ~= self.logicEnt then return end
	self.logicEnt = NULL
	self.koth = nil
end

-- CKothLogic::InputRoundSpawn. A full reset has removed the last round's
-- clocks; an explicit RoundSpawn input removes them here rather than
-- leaving two clocks with each name.
function Controller:RoundSpawn()
	if not self.koth then return end
	for _, c in ipairs(self.koth:Clocks()) do
		local old = self.clocks[c.team]
		if IsValid(old) then old:Remove() end
		local clock = self.rounds:CreateTimer(c.name, c.length, { hudChoice = false })
		self.rounds:TimerInput(clock, "pause")
		self.rounds:SetTeamClock(c.team, clock)
		self.clocks[c.team] = clock
	end
end

-- CKothLogic::InputRoundActivate: SetLocked, then SetUnlockTime, on every
-- point (the master's, which on a koth map are all of them).
function Controller:RoundActivate()
	if not self.koth then return end
	local lock = self.koth:PointLock()
	for _, point in ipairs(self.capture:Points()) do
		self.capture:SetPointLocked(point, lock.locked)
		if lock.unlockTime then self.capture:SetPointUnlockTime(point, lock.unlockTime) end
	end
end

local PHASE_INPUTS = {
	roundspawn = function(self) self:RoundSpawn() end,
	roundactivate = function(self) self:RoundActivate() end,
}

-- A tf_logic_koth input, lower-cased; returns whether it is one.
-- Set<Team>Timer and Add<Team>Timer reach the team's clock as SetTime and
-- AddTime (SetTimeRemaining and the silent AddTimerSeconds).
function Controller:LogicInput(ent, name, value)
	if ent ~= self.logicEnt then return false end
	local phase = PHASE_INPUTS[name]
	if phase then
		phase(self)
		return true
	end
	local input = Koth.CLOCK_INPUTS[name]
	if not input then return false end
	local clock = self.rounds:TeamClock(input.team)
	if clock then self.rounds:TimerInput(clock, input.timerInput, tonumber(value) or 0) end
	return true
end

-- The view's keys ----------------------------------------------------------------------

local function Key(t, field)
	return "ws_koth_clock_" .. t .. "_" .. field
end

-- What the KOTH HUD (CTFHudKothTimeStatus) and each clock's countdown read.
function Controller:Publish(now)
	for _, t in ipairs(GAME_TEAMS) do
		local clock = self.rounds:TeamClock(t)
		local timer = clock and self.rounds:TimerOf(clock)
		SetGlobal2Bool(Key(t, "shown"), timer ~= nil and timer:ShowInHud())
		if timer then
			local left = timer:TimeRemaining(now)
			SetGlobal2Bool(Key(t, "paused"), timer:Paused())
			if timer:Paused() then
				SetGlobal2Float(Key(t, "time_left"), left)
			else
				SetGlobal2Float(Key(t, "end_time"), now + left)
			end
			SetGlobal2Float(Key(t, "max_length"), timer:MaxLength())
			SetGlobal2Bool(Key(t, "auto_countdown"), timer:AutoCountdown())
			SetGlobal2Int(Key(t, "serial"), timer:Serial())
		end
	end
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now < Controller.nextPublish or not WS.Active() then return end
	Controller.nextPublish = now + PUBLISH_INTERVAL
	Controller:Publish(now)
end)

-- Wiring into the round: after the timers and the points, as TF2's entity
-- order has it.
Controller.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, function() Controller:RoundSpawn() end)
Controller.rounds:AddRoundListener(Rounds.PHASE_ACTIVATE, Rounds.LISTEN_LOGIC, function() Controller:RoundActivate() end)

return Controller
