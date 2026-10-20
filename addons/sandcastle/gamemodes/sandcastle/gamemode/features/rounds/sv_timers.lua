-- Part of the rounds controller (sv.lua): the timers, the team clocks and the round limits.
local Controller, Active, GAME_TEAMS = ...
local Rounds = WS.require("foundation.rounds")
local Timer = WS.require("foundation.rounds.timer")
local Limits = WS.require("foundation.rounds.limits")

local S = WS.STATE
local UNASSIGNED, SPECTATOR = WS.TEAM_UNASSIGNED, WS.TEAM_SPECTATOR
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

-- The round limits (foundation.rounds.limits): only a map without an
-- objective plays to them. Both on by default, the frag limit the one
-- reached first.
local roundFraglimit = CreateConVar("mp_round_fraglimit", "30", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Frags a team needs in a round to win it, on a map without an objective; 0: no frag limit.", 0)
local roundCashlimit = CreateConVar("mp_round_cashlimit", "10000", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Money a team must earn in a round to win it, on a map without an objective (frags decide first); 0: no cash limit.", 0)

local TIMER_CLASS = "team_round_timer"
local TIMELIMIT_TIMER_NAME = "zz_teamplay_timelimit_timer"

-- CTeamRoundTimer::AddTimerSeconds' ROUND_TIMER_TIME_ADDED_* sounds.
local TIME_ADDED_WINNER = {
	"Announcer.TimeAwardedForTeam",
	"Announcer.TimeAwardedCongrats",
	"Announcer.TimeAwardedSuccess",
}

local TIME_ADDED_LOSER = "Announcer.TimeAddedForEnemy"
local TIME_ADDED = "Announcer.TimeAdded"
local OVERTIME_NAG = "Game.Overtime"

-- The announcer credits the team the time was added for (AddTeamTime).
local function AnnounceTimeAdded(t)
	if t == RED or t == BLUE then
		WS.BroadcastPA(t, table.Random(TIME_ADDED_WINNER))
		WS.BroadcastPA(WS.EnemyOf(t), TIME_ADDED_LOSER)
		WS.BroadcastPA(SPECTATOR, TIME_ADDED)
	else
		WS.BroadcastPA(UNASSIGNED, TIME_ADDED)
	end
end

-- Timers ------------------------------------------------------------------------------

local TIMER_KEYS_BOOL = { "ws_timer_shown", "ws_timer_paused", "ws_timer_in_setup" }

local function ClearTimerKeys()
	for _, key in ipairs(TIMER_KEYS_BOOL) do SetGlobal2Bool(key, false) end
end

-- What the client's HUD timer and countdown read (the objective resource's
-- m_iTimerToShowInHUD and the timer's networked state).
function Controller:PublishHudTimer(now)
	local ent = self.hudTimer
	if not IsValid(ent) then return end
	local timer = self.timers[ent]
	local left = timer:TimeRemaining(now)
	SetGlobal2Bool("ws_timer_shown", true)
	SetGlobal2Bool("ws_timer_paused", timer:Paused())
	if timer:Paused() then
		SetGlobal2Float("ws_timer_time_left", left)
	else
		SetGlobal2Float("ws_timer_end_time", now + left)
	end
	SetGlobal2Bool("ws_timer_in_setup", timer:InSetup())
	SetGlobal2Bool("ws_timer_auto_countdown", timer:AutoCountdown())
	SetGlobal2Int("ws_timer_serial", timer:Serial())
end

local function PublishOvertime(on)
	SetGlobal2Bool("ws_round_overtime", on)
	-- Train watchers hear it (the SDK sends them OnStartOvertime).
	hook.Run("WSOvertime", on)
end

-- CTeamplayRoundBasedRules::SetSetup, from every timer's SetState. Its
-- change is heard as WSSetup(on): MvM's wave starts as setup ends.
function Controller:SetSetup(on)
	if not self.round:SetSetup(on) then return end
	SetGlobal2Bool("ws_round_in_setup", on)
	hook.Run("WSSetup", on)
end

function Controller:SetOvertime(on)
	if self.round:SetOvertime(on) then PublishOvertime(on) end
end

-- In whole seconds, as TF2's event carries them; a clamp to the timer's
-- maximum length can leave a fraction.
local function Notify(t, seconds)
	WS.Events.Fire("game_teamplay_timer_time_added", {
		team = t,
		seconds_added = math.Round(seconds),
	})
end

-- A timer model's events, carried out on its entity.
local TIMER_EVENTS = {
	output = function(self, ent, e)
		ent:TriggerOutput(e.name, ent)
		-- an admin's round time ran out: no win condition decides it, a stalemate
		if ent == self.roundTimer and e.name == "OnFinished" then
			self:Apply(self.round:SetStalemate(CurTime(), Rounds.STALEMATE.TIMER, true, false))
		end
	end,
	setup = function(self, ent, e) self:SetSetup(e.value) end,
	overtime = function(self, ent, e) self:SetOvertime(e.value) end,
	nag = function() WS.BroadcastPA(UNASSIGNED, OVERTIME_NAG) end,
	length_changed = function() end,
	time_added = function(self, ent, e)
		AnnounceTimeAdded(e.team)
		Notify(e.team, e.seconds)
	end,
}

function Controller:ApplyTimerEvents(ent, events)
	for _, e in ipairs(events) do TIMER_EVENTS[e.kind](self, ent, e) end
end

-- team_round_timer: kv = { length, maxLength, setupLength, startPaused,
-- showInHud, autoCountdown, resetTime, startDisabled }.
function Controller:BindTimer(ent, kv)
	kv.now = CurTime()
	local timer = Timer.New(kv)
	self.timers[ent] = timer
	self.timerList[#self.timerList + 1] = ent
	self:ApplyTimerEvents(ent, timer:SpawnEvents())
	return timer
end

-- The timers the gamerules make, each made again when next due.
local OWN_TIMERS = { "timeLimitTimer", "stalemateTimer", "roundTimer" }

-- A timer removed (a map cleanup removes the gamerules' own too): it stays
-- valid until the frame ends, so the controller lets go of it now.
function Controller:UnbindTimer(ent)
	self.timers[ent] = nil
	self.notHudChoice[ent] = nil
	for _, field in ipairs(OWN_TIMERS) do
		if self[field] == ent then self[field] = NULL end
	end
	for i, other in ipairs(self.timerList) do
		if other == ent then
			table.remove(self.timerList, i)
			break
		end
	end
	if self.hudTimer == ent then self:SetActiveTimer(nil) end
end

function Controller:TimerOf(ent)
	return self.timers[ent]
end

function Controller:HudTimer()
	return IsValid(self.hudTimer) and self.hudTimer or nil
end

-- CTeamRoundTimer::SetActiveTimer: newly (or nil) becomes the timer shown in
-- the HUD; other enabled, shown timers stop showing. Team clocks show
-- without ever being chosen.
function Controller:SetActiveTimer(newly)
	local candidates, infos, newlyIndex = {}, {}, nil
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) and not self.notHudChoice[ent] then
			local timer = self.timers[ent]
			candidates[#candidates + 1] = ent
			infos[#infos + 1] = {
				enabled = not timer:Disabled(),
				show = timer:ShowInHud(),
			}
			if ent == newly then newlyIndex = #candidates end
		end
	end
	local chosen, hide = Timer.ChooseActiveTimer(infos, newlyIndex)
	for _, i in ipairs(hide) do self.timers[candidates[i]]:SetShowInHud(false) end
	self.hudTimer = chosen and candidates[chosen] or NULL
	if not IsValid(self.hudTimer) then ClearTimerKeys() end
	self:PublishHudTimer(CurTime())
end

-- CTeamRoundTimer::Activate for every timer, after the map (or a full reset) spawns.
function Controller:ActivateTimers()
	self.hudTimer = NULL
	ClearTimerKeys()
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) and not self.notHudChoice[ent] and self.timers[ent]:ShowInHud() then self:SetActiveTimer(ent) end
	end
end

local function RoundWon()
	return Active() and Controller.round:State() == S.TEAM_WIN
end

-- CTeamRoundTimer::AddTimerSeconds. Without a proxy nothing restricts it.
function Controller:AddTimerSeconds(ent, seconds, t)
	local state = self.round:State()
	local events = self.timers[ent]:AddSeconds(CurTime(), seconds, t, {
		roundRunningOrWon = not Active() or state == S.RND_RUNNING or state == S.TEAM_WIN,
		isHud = ent == self.hudTimer,
		roundWon = RoundWon(),
		inStalemate = Active() and state == S.STALEMATE,
		announces = self.round:Mode().ANNOUNCES_TIME_ADDED,
	})
	AnnounceTimeAdded(t)
	self:ApplyTimerEvents(ent, events)
end

-- InputAddTeamTime's "team seconds"; a team that is not RED or BLU credits everyone.
local function ParseTeamTime(value)
	local t, seconds = string.match(tostring(value), "^%s*(%-?%d+)%s+(%-?%d+)")
	t = tonumber(t)
	if t ~= RED and t ~= BLUE then t = UNASSIGNED end
	return t, tonumber(seconds) or 0
end

-- InputShowInHUD: the flag is cleared before a replacement is chosen, so a
-- hidden timer never chooses itself.
local function ShowInHUD(self, ent, timer, show)
	if timer:ShowInHud() and not show then
		timer:SetShowInHud(false)
		self:SetActiveTimer(nil)
	elseif show then
		timer:SetShowInHud(true)
		self:SetActiveTimer(ent)
		self:ApplyTimerEvents(ent, timer:StateEvents())
	end
end

local TIMER_INPUTS = {
	pause = function(self, ent, timer, value, now) timer:Pause(now) end,
	resume = function(self, ent, timer, value, now) timer:Resume(now) end,
	settime = function(self, ent, timer, value, now)
		self:ApplyTimerEvents(ent, timer:SetTimeRemaining(now, tonumber(value) or 0))
	end,
	setmaxtime = function(self, ent, timer, value, now)
		self:ApplyTimerEvents(ent, timer:SetMaxLength(now, tonumber(value) or 0))
	end,
	addtime = function(self, ent, timer, value) self:AddTimerSeconds(ent, tonumber(value) or 0, UNASSIGNED) end,
	addteamtime = function(self, ent, timer, value)
		local t, seconds = ParseTeamTime(value)
		if seconds ~= 0 then self:AddTimerSeconds(ent, seconds, t) end
	end,
	restart = function(self, ent, timer, value, now) self:ApplyTimerEvents(ent, timer:Restart(now)) end,
	enable = function(self, ent, timer, value, now)
		timer:Enable(now)
		if timer:ShowInHud() then self:SetActiveTimer(ent) end
	end,
	disable = function(self, ent, timer, value, now)
		timer:Disable(now)
		if timer:ShowInHud() then self:SetActiveTimer(nil) end
	end,
	showinhud = function(self, ent, timer, value) ShowInHUD(self, ent, timer, tonumber(value) == 1) end,
	autocountdown = function(self, ent, timer, value) timer:SetAutoCountdown(tonumber(value) == 1) end,
	setsetuptime = function(self, ent, timer, value, now)
		self:ApplyTimerEvents(ent, timer:SetSetupLength(now, tonumber(value) or 0))
	end,
	roundspawn = function(self, ent, timer, value, now) self:ApplyTimerEvents(ent, timer:RoundSpawn(now)) end,
}

-- A team_round_timer input, lower-cased; returns whether it is one.
function Controller:TimerInput(ent, name, value)
	local handler = TIMER_INPUTS[name]
	if not handler then return false end
	handler(self, ent, self.timers[ent], value, CurTime())
	self:PublishHudTimer(CurTime())
	return true
end

-- Timers the gamerules make (stalemate, time limit) and the koth clocks.
-- opts = { showInHud (default true), hudChoice (default true) }.
function Controller:CreateTimer(name, seconds, opts)
	local ent = ents.Create(TIMER_CLASS)
	if name then ent:SetName(name) end
	local show = not (opts and opts.showInHud == false)
	ent:SetKeyValue("show_in_hud", show and "1" or "0")
	ent:Spawn()
	if opts and opts.hudChoice == false then self.notHudChoice[ent] = true end
	self:TimerInput(ent, "settime", seconds)
	self:TimerInput(ent, "resume")
	self:TimerInput(ent, "enable")
	return ent
end

-- MapHasActiveTimer: a map timer (not the time limit one) shown in the HUD.
function Controller:MapHasActiveTimer()
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) and self.timers[ent]:ShowInHud() and ent:GetName() ~= TIMELIMIT_TIMER_NAME then return true end
	end
	return false
end

-- HideActiveTimer / RestoreActiveTimer (with CTFGameRules's re-showing of
-- the koth clocks).
function Controller:HideActiveTimer()
	self.previousActiveTimer = NULL
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) and self.timers[ent]:ShowInHud() then
			if not self.notHudChoice[ent] then self.previousActiveTimer = ent end
			self:TimerInput(ent, "showinhud", 0)
		end
	end
end

function Controller:RestoreActiveTimer()
	if IsValid(self.stalemateTimer) then self.stalemateTimer:Remove() end
	self.stalemateTimer = NULL
	if IsValid(self.previousActiveTimer) then self:TimerInput(self.previousActiveTimer, "showinhud", 1) end
	self.previousActiveTimer = NULL
	for _, t in ipairs(GAME_TEAMS) do
		local clock = self:TeamClock(t)
		if clock then self.timers[clock]:SetShowInHud(true) end
	end
end

-- Team clocks (koth) ----------------------------------------------------------------

function Controller:SetTeamClock(t, ent)
	self.teamClocks[t] = ent
end

function Controller:TeamClock(t)
	local ent = self.teamClocks[t]
	return IsValid(ent) and self.timers[ent] and ent or nil
end

-- CTFGameRulesProxy::InputSetRed/BlueKothClockActive: the enemy's clock
-- pauses and the team's resumes. Without clocks nothing happens.
function Controller:ActivateTeamClock(t)
	local enemy = self:TeamClock(WS.EnemyOf(t))
	if enemy then self:TimerInput(enemy, "pause") end
	local own = self:TeamClock(t)
	if own then self:TimerInput(own, "resume") end
end

-- Round limits (foundation.rounds.limits) ---------------------------------------------

-- The announcer's cues: the arena's first blood, and Player Destruction's
-- close to winning, to the team and to its enemy.
local FIRST_BLOOD = "Announcer.AM_FirstBloodRandom"
local CLOSE_OURS, CLOSE_THEIRS = "Announcer.OurTeamCloseToWinning", "Announcer.EnemyTeamCloseToWinning"

function Controller:RoundLimits()
	return Limits.Of(self.round:Mode(), roundFraglimit:GetInt(), roundCashlimit:GetInt())
end

-- For the HUD's Player Destruction panels: each limit (0: no panel) and each
-- team's count toward it.
function Controller:PublishRoundLimits()
	local limits = self:RoundLimits()
	SetGlobal2Int("ws_round_fraglimit", limits.frags)
	SetGlobal2Int("ws_round_cashlimit", limits.cash)
	for _, t in ipairs(GAME_TEAMS) do
		SetGlobal2Int("ws_round_frags_" .. t, self.tally:Frags(t))
		SetGlobal2Int("ws_round_earned_" .. t, self.tally:Earned(t))
	end
end

-- A frag or an earning counted: the HUD's counts, the announcer's cues, and
-- a limit reached decides the round.
function Controller:Counted()
	local limits = self:RoundLimits()
	self:PublishRoundLimits()
	for _, call in ipairs(self.tally:Calls(limits)) do
		if call.kind == "first_blood" then
			WS.BroadcastPA(UNASSIGNED, FIRST_BLOOD)
		else
			WS.BroadcastPA(call.team, CLOSE_OURS)
			WS.BroadcastPA(WS.EnemyOf(call.team), CLOSE_THEIRS)
		end
	end
	local outcome = Limits.Outcome(limits, self.tally)
	if outcome then self:Apply(self.round:LimitReached(CurTime(), outcome, self.objective)) end
end

local function Counts()
	return Active() and Controller.round:LimitsCount()
end

-- A frag toward the frag limit is Player Destruction's deposit: its score
-- chime (CTFRobotDestructionLogic's points scored), bright to the team, dull
-- to its enemy.
local SCORE_OURS, SCORE_THEIRS = "RD.TeamScoreCore", "RD.EnemyScoreCore"

hook.Add("WSTeamFrag", "ws_rounds_limits", function(team)
	if not Counts() then return end
	Controller.tally:Frag(team)
	if Controller:RoundLimits().frags > 0 then
		WS.BroadcastSound(team, SCORE_OURS)
		WS.BroadcastSound(WS.EnemyOf(team), SCORE_THEIRS)
	end
	Controller:Counted()
end)

hook.Add("WSMoneyEarned", "ws_rounds_limits", function(ent, amount)
	local team = WS.LastTeamNumber(ent)
	if not (Counts() and (team == RED or team == BLUE)) then return end
	Controller.tally:Earn(team, amount)
	Controller:Counted()
end)

return RoundWon, PublishOvertime, TIMELIMIT_TIMER_NAME
