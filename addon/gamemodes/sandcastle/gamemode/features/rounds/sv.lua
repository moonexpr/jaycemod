-- The rounds feature's controller. It owns the foundation.rounds Round (the
-- gamerules state machine), a foundation.rounds.timer Timer per
-- team_round_timer, the timer shown in the HUD, the gamerules proxy
-- (tf_gamerules), the mode, the round listeners, the timer holds, the team
-- clocks and the objective port. It feeds the models engine time and a
-- snapshot of the players, and carries out their effects: outputs, the map
-- cleanup, respawns, sounds and the wetsand_round_* and wetsand_timer_*
-- keys. It decides nothing itself.
--
-- Loaded by tf_gamerules, team_round_timer, game_round_win and
-- tf_logic_competitive, and by every objective feature (capture, koth,
-- payload). On a map with an objective entity and no tf_gamerules it makes
-- one, as CTFGameRules::CreateStandardEntities does, so the rounds run and
-- outputs aimed at the name tf_gamerules reach it.
local Rounds = WETSAND.require("foundation.rounds")
local Timer = WETSAND.require("foundation.rounds.timer")
local ControlPoints = WETSAND.require("foundation.rounds.control_points")

local S = WETSAND.STATE
local UNASSIGNED, SPECTATOR = WETSAND.TEAM_UNASSIGNED, WETSAND.TEAM_SPECTATOR
local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }

-- TF2's own convars, as teamplayroundbased_gamerules.cpp and
-- multiplay_gamerules.cpp define them. GMod's engine may already define some
-- of the multiplay ones; those are used as they are.
local function ConVarOrCreate(name, ...)
	return GetConVar(name) or CreateConVar(name, ...)
end

local respawnwavetime = ConVarOrCreate("mp_respawnwavetime", "10.0", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "Time between respawn waves.")
local bonusroundtime = ConVarOrCreate("mp_bonusroundtime", "15", FCVAR_REPLICATED, "Time after round win until round restarts", 5, 15)
local enableroundwaittime = ConVarOrCreate("mp_enableroundwaittime", "1", FCVAR_REPLICATED, "Enable timers to wait between rounds.")
local stalemateEnable = ConVarOrCreate("mp_stalemate_enable", "0", FCVAR_NOTIFY, "Enable/Disable stalemate mode.")
local stalemateTimelimit = ConVarOrCreate("mp_stalemate_timelimit", "240", FCVAR_REPLICATED, "Timelimit (in seconds) of the stalemate round.")
local winlimit = ConVarOrCreate("mp_winlimit", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "Max score one team can reach before server changes maps", 0)
local maxrounds = ConVarOrCreate("mp_maxrounds", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "max number of rounds to play before server changes maps", 0)
local timelimit = ConVarOrCreate("mp_timelimit", "0", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "game time per map in minutes")
local matchEndAtTimelimit = ConVarOrCreate("mp_match_end_at_timelimit", "0", FCVAR_NOTIFY, "Allow the match to end when mp_timelimit hits instead of waiting for the end of the current round.")
local chattime = ConVarOrCreate("mp_chattime", "10", FCVAR_REPLICATED, "amount of time players can chat after the game is over", 1, 120)
-- teamplay_round_timer.cpp
local overtimeNag = ConVarOrCreate("tf_overtime_nag", "0", FCVAR_NOTIFY, "Announcer overtime nag.")

local PROXY_CLASS = "tf_gamerules"
local TIMER_CLASS = "team_round_timer"
local LOGIC_AUTO_CLASS = "logic_auto"
local COMPETITIVE_CLASS = "tf_logic_competitive"
local MASTER_CLASS = "team_control_point_master"
local TIMELIMIT_TIMER_NAME = "zz_teamplay_timelimit_timer"
-- A full reset keeps the gamerules, as TF2 does, and the admin editors.
local CLEANUP_KEEPS = { PROXY_CLASS, "edit_gamerules", "edit_roundtimer" }
-- The entities that make a map a round-based one, proxy or not.
local OBJECTIVE_CLASSES = {
	MASTER_CLASS,
	"team_control_point",
	"trigger_capture_area",
	"team_train_watcher",
	"tf_logic_koth",
}

local ROUND_THINK_INTERVAL = 0.1
local TIMER_THINK_INTERVAL = 0.05 -- CTeamRoundTimer's context thinks
local HALT_DOORS_INTERVAL = 2
local ROLE_NONE = 0 -- TEAM_ROLE_NONE
local THINK_HOOK = "wetsand_rounds"

-- CTeamRoundTimer::AddTimerSeconds' ROUND_TIMER_TIME_ADDED_* sounds.
local TIME_ADDED_WINNER = "Announcer.TimeAwardedForTeam"
local TIME_ADDED_LOSER = "Announcer.TimeAddedForEnemy"
local TIME_ADDED = "Announcer.TimeAdded"
local OVERTIME_NAG = "Game.Overtime"
local SUDDEN_DEATH = "Game.SuddenDeath"

local function Settings()
	return {
		respawnWaveTime = respawnwavetime:GetFloat(),
		bonusRoundTime = bonusroundtime:GetInt(),
		enableRoundWaitTime = enableroundwaittime:GetFloat(),
		stalemateEnable = stalemateEnable:GetBool(),
		stalemateTimelimit = stalemateTimelimit:GetInt(),
		winlimit = winlimit:GetInt(),
		maxrounds = maxrounds:GetInt(),
		timelimit = timelimit:GetInt(),
		matchEndAtTimelimit = matchEndAtTimelimit:GetBool(),
		chattime = chattime:GetInt(),
	}
end

local function NewRound()
	local settings = Settings()
	settings.mapResetTime = CurTime()
	return Rounds.New(settings)
end

local Controller = {
	round = NewRound(),
	proxy = NULL,
	timers = {}, -- team_round_timer entity -> its Timer
	timerList = {}, -- the bound timers, in the order they spawned
	notHudChoice = {}, -- timers never chosen as the HUD timer (team clocks)
	hudTimer = NULL,
	previousActiveTimer = NULL,
	stalemateTimer = NULL,
	teamClocks = {},
	listeners = {
		[Rounds.PHASE_SPAWN] = {},
		[Rounds.PHASE_ACTIVATE] = {},
		[Rounds.PHASE_ROUND_END] = {},
	},
	holds = {},
	objective = Rounds.NO_OBJECTIVE,
	multipleTrains = false,
	spawnDoors = nil,
	nextDoorsOpen = 0,
	suppressNewMap = false,
	nextRoundThink = 0,
	nextTimerThink = 0,
	mapSetUp = false,
}

local function Active()
	return IsValid(Controller.proxy)
end

-- Players -----------------------------------------------------------------------

local function TeamPlayers(t)
	local players = {}
	for _, ply in ipairs(player.GetAll()) do
		if WETSAND.TeamOf(ply) == t then players[#players + 1] = ply end
	end
	return players
end

-- A player counts once their client has finished loading (client_ready,
-- wetsand/sh_events.lua), so the pre-round freeze is not spent on a
-- loading screen. Bots have no client to report it.
local function Ready(ply)
	return WETSAND.IsReady(ply) or ply:IsBot()
end

-- BHavePlayers: someone ready and on RED or BLU, or something else fighting
-- for a team (the AI war says so through WetsandHaveCombatants).
local function HavePlayers()
	for _, ply in ipairs(player.GetAll()) do
		if Ready(ply) and WETSAND.TeamOf(ply) ~= UNASSIGNED then return true end
	end
	return hook.Run("WetsandHaveCombatants") == true
end

local function Scores()
	return {
		[RED] = team.GetScore(RED),
		[BLUE] = team.GetScore(BLUE),
	}
end

local function TeamLife()
	local teams = {}
	for _, t in ipairs(GAME_TEAMS) do
		local players, alive = TeamPlayers(t), 0
		for _, ply in ipairs(players) do
			if ply:Alive() then alive = alive + 1 end
		end
		teams[t] = {
			players = #players,
			alive = alive,
		}
	end
	return teams
end

local function EachPlayer(fn)
	for _, ply in ipairs(player.GetAll()) do fn(ply) end
end

-- Every RED player to BLU and every BLU player to RED, and their scores
-- (CTFGameRules::HandleSwitchTeams).
local function SwitchTeams()
	EachPlayer(function(ply)
		local t = WETSAND.TeamOf(ply)
		if t ~= UNASSIGNED then WETSAND.SetPlayerTeam(ply, WETSAND.EnemyOf(t), true) end
	end)
	local red, blu = team.GetScore(RED), team.GetScore(BLUE)
	team.SetScore(RED, blu)
	team.SetScore(BLUE, red)
end

-- CTeamplayRoundBasedRules::PlayWinSong: each side hears its own result.
-- (The teamless would hear Game.TeamWin2/3, which no soundscript defines.)
local function PlayWinSong(winner)
	if winner == UNASSIGNED then
		WETSAND.BroadcastSound(UNASSIGNED, "Game.Stalemate")
		return
	end
	WETSAND.BroadcastSound(winner, "Game.YourTeamWon")
	WETSAND.BroadcastSound(WETSAND.EnemyOf(winner), "Game.YourTeamLost")
end

-- The announcer credits the team the time was added for (AddTeamTime).
local function AnnounceTimeAdded(t)
	if t == RED or t == BLUE then
		WETSAND.BroadcastSound(t, TIME_ADDED_WINNER)
		WETSAND.BroadcastSound(WETSAND.EnemyOf(t), TIME_ADDED_LOSER)
	else
		WETSAND.BroadcastSound(UNASSIGNED, TIME_ADDED)
	end
end

-- The spawn doors of a stopped game ---------------------------------------------------

local function Overlap(aMins, aMaxs, bMins, bMaxs)
	return aMins.x <= bMaxs.x and bMins.x <= aMaxs.x and aMins.y <= bMaxs.y and bMins.y <= aMaxs.y
		and aMins.z <= bMaxs.z and bMins.z <= aMaxs.z
end

-- func_doors overlapped by a trigger_multiple whose filter is a
-- filter_activator_tfteam, and those triggers.
local function SpawnDoors()
	local triggers = {}
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		local filter = trigger:GetInternalVariable("m_hFilter")
		if IsValid(filter) and filter:GetClass() == "filter_activator_tfteam" then
			local mins, maxs = trigger:WorldSpaceAABB()
			triggers[#triggers + 1] = {
				ent = trigger,
				mins = mins,
				maxs = maxs,
			}
		end
	end
	local doors, doorTriggers = {}, {}
	for _, door in ipairs(ents.FindByClass("func_door*")) do
		local mins, maxs = door:WorldSpaceAABB()
		local found = false
		for _, trigger in ipairs(triggers) do
			if Overlap(mins, maxs, trigger.mins, trigger.maxs) then
				found = true
				doorTriggers[trigger.ent] = true
			end
		end
		if found then doors[#doors + 1] = door end
	end
	return doors, doorTriggers
end

-- The proxy -------------------------------------------------------------------------

local function PublishState()
	local round = Controller.round
	SetGlobal2Int("wetsand_round_state", round:State())
	SetGlobal2Int("wetsand_round_hud_type", round:Mode().HUD)
end

function Controller:BindProxy(ent)
	if IsValid(self.proxy) then return end
	self.proxy = ent
	WETSAND.Rules = ent
	SetGlobal2Bool("wetsand_rounds_active", true)
	PublishState()
end

function Controller:UnbindProxy(ent)
	if ent ~= self.proxy then return end
	self.proxy = NULL
	WETSAND.Rules = nil
	SetGlobal2Bool("wetsand_rounds_active", false)
end

function Controller:Proxy()
	return self.proxy
end

-- Timers ------------------------------------------------------------------------------

local TIMER_KEYS_BOOL = { "wetsand_timer_shown", "wetsand_timer_paused", "wetsand_timer_in_setup" }

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
	SetGlobal2Bool("wetsand_timer_shown", true)
	SetGlobal2Bool("wetsand_timer_paused", timer:Paused())
	if timer:Paused() then
		SetGlobal2Float("wetsand_timer_time_left", left)
	else
		SetGlobal2Float("wetsand_timer_end_time", now + left)
	end
	SetGlobal2Bool("wetsand_timer_in_setup", timer:InSetup())
	SetGlobal2Bool("wetsand_timer_auto_countdown", timer:AutoCountdown())
	SetGlobal2Int("wetsand_timer_serial", timer:Serial())
end

local function PublishOvertime(on)
	SetGlobal2Bool("wetsand_round_overtime", on)
	-- Train watchers hear it (the SDK sends them OnStartOvertime).
	hook.Run("WetsandOvertime", on)
end

-- CTeamplayRoundBasedRules::SetSetup, from every timer's SetState.
function Controller:SetSetup(on)
	if self.round:SetSetup(on) then SetGlobal2Bool("wetsand_round_in_setup", on) end
end

function Controller:SetOvertime(on)
	if self.round:SetOvertime(on) then PublishOvertime(on) end
end

-- In whole seconds, as TF2's event carries them; a clamp to the timer's
-- maximum length can leave a fraction.
local function Notify(t, seconds)
	WETSAND.Events.Fire("teamplay_timer_time_added", {
		team = t,
		seconds_added = math.Round(seconds),
	})
end

-- A timer model's events, carried out on its entity.
local TIMER_EVENTS = {
	output = function(self, ent, e) ent:TriggerOutput(e.name, ent) end,
	setup = function(self, ent, e) self:SetSetup(e.value) end,
	overtime = function(self, ent, e) self:SetOvertime(e.value) end,
	nag = function() WETSAND.BroadcastSound(UNASSIGNED, OVERTIME_NAG) end,
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

function Controller:UnbindTimer(ent)
	self.timers[ent] = nil
	self.notHudChoice[ent] = nil
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
	local enemy = self:TeamClock(WETSAND.EnemyOf(t))
	if enemy then self:TimerInput(enemy, "pause") end
	local own = self:TeamClock(t)
	if own then self:TimerInput(own, "resume") end
end

-- Mode, listeners and holds ----------------------------------------------------------

function Controller:SetMode(mode)
	if self.round:SetMode(mode) then PublishState() end
end

function Controller:Mode()
	return self.round:Mode()
end

-- fn runs at the phase (Rounds.PHASE_*), in `order` (Rounds.LISTEN_*), each
-- function once however often it is added.
function Controller:AddRoundListener(phase, order, fn)
	local list = self.listeners[phase]
	for _, l in ipairs(list) do
		if l.fn == fn then return end
	end
	local at = #list + 1
	for i, l in ipairs(list) do
		if l.order > order then
			at = i
			break
		end
	end
	table.insert(list, at, {
		order = order,
		fn = fn,
	})
end

function Controller:RunListeners(phase)
	for _, l in ipairs(self.listeners[phase]) do l.fn() end
end

-- fn() returns true while it holds the clock at zero. A capture hold
-- (isCapture) also holds it for the 0.1 s after (TimerMayExpire).
function Controller:AddTimerHold(name, fn, isCapture)
	self.holds[name] = {
		fn = fn,
		isCapture = isCapture == true,
	}
end

function Controller:TimerMayExpire()
	local holds = {
		capturing = false,
		other = false,
	}
	for _, h in pairs(self.holds) do
		if h.fn() then
			if h.isCapture then holds.capturing = true else holds.other = true end
		end
	end
	return self.round:TimerMayExpire(CurTime(), holds)
end

-- q for the mode: the team's clock (koth) and whether the timer may expire.
function Controller:MayWinByPoints(t)
	local clock = self:TeamClock(t)
	return self.round:MayWinByPoints(t, {
		clockRemaining = clock and self.timers[clock]:TimeRemaining(CurTime()) or nil,
		timerMayExpire = self:TimerMayExpire(),
	})
end

-- The capture controller's port on the master (Rounds.OBJECTIVE_METHODS).
function Controller:SetObjective(port)
	self.objective = port
end

-- CTFGameRules::SetMultipleTrains: a payload race (tf_logic_multiple_escort,
-- through the payload feature), which the mode's win lines ask about.
function Controller:SetMultipleTrains(on)
	self.multipleTrains = on
end

function Controller:HasMultipleTrains()
	return self.multipleTrains
end

-- Round state ----------------------------------------------------------------------

function Controller:State() return self.round:State() end
function Controller:PointsMayBeCaptured() return self.round:PointsMayBeCaptured() end
function Controller:InSetup() return self.round:InSetup() end
function Controller:InOvertime() return self.round:InOvertime() end
function Controller:AddPlayedRound(name) self.round:AddPlayedRound(name) end
function Controller:History() return self.round:History() end
function Controller:SetFirstRoundPlayed(name) self.round:SetFirstRoundPlayed(name) end

-- A map without a proxy has no rounds to win: game_round_win and the master
-- are ignored there, as they were without tf_gamerules.
function Controller:SetWinningTeam(winner, reason, forceMapReset, switchTeams, dontAddScore)
	if not Active() then return end
	self:Apply(self.round:SetWinningTeam(CurTime(), winner, reason, forceMapReset, switchTeams, dontAddScore, self.objective))
end

function Controller:SetStalemate(reason, forceMapReset, switchTeams)
	if not Active() then return end
	self:Apply(self.round:SetStalemate(CurTime(), reason, forceMapReset, switchTeams))
end

-- game_round_win: win = { team, reason, forceMapReset, switchTeams }.
function Controller:GameRoundWin(ent, win)
	if Active() then self:Apply(self.round:GameRoundWin(CurTime(), win, self.objective)) end
	ent:TriggerOutput("OnRoundWin", ent)
end

-- Sounds and notices -------------------------------------------------------------

-- CTFGameRules::PlaySpecialCapSounds, as the mode says.
function Controller:CapSounds(capTeam, wouldWinGame, scorePerRound)
	local lines = self.round:Mode():CapSounds(capTeam, {
		wouldWinGame = wouldWinGame,
		scorePerRound = scorePerRound,
	})
	for _, line in ipairs(lines) do WETSAND.BroadcastSound(line.team, line.sound) end
end

-- logic_auto (CLogicAuto::Think) ----------------------------------------------------

-- A cleanup recreates every logic_auto, which would fire OnMultiNewMap as at
-- map load: GMod's gamerules never report InRoundRestart. Its keyvalue is
-- emptied while the cleanup runs, and OnMultiNewRound fires instead.
hook.Add("EntityKeyValue", "wetsand_rounds_new_map", function(ent, key)
	if Controller.suppressNewMap and ent:GetClass() == LOGIC_AUTO_CLASS and string.lower(key) == "onmultinewmap" then
		return ""
	end
end)

local function FireNewRoundOutputs()
	for _, auto in ipairs(ents.FindByClass(LOGIC_AUTO_CLASS)) do
		WETSAND.FireOutput(auto, "OnMultiNewRound", auto)
	end
end

function Controller:CleanUpMap()
	self.suppressNewMap = true
	game.CleanUpMap(false, CLEANUP_KEEPS)
	self.suppressNewMap = false
end

-- Effects ---------------------------------------------------------------------------

-- The model's round hooks, for other features: the round is running
-- (spawns, the AI war), and a round was won (winner).
local ROUND_ACTIVE = "WetsandRoundActive"
local ROUND_WIN = "WetsandRoundWin"
local ROUND_HOOKS = {
	[ROUND_ACTIVE] = function() hook.Run(ROUND_ACTIVE) end,
	[ROUND_WIN] = function(args) hook.Run(ROUND_WIN, args[1]) end,
}

local function FireCompetitive(output)
	for _, logic in ipairs(ents.FindByClass(COMPETITIVE_CLASS)) do logic:TriggerOutput(output, logic) end
end

local function RespawnTeam(self, t, now)
	for _, ply in ipairs(TeamPlayers(t)) do
		if not ply:Alive() and self.round:MayRespawn(t, ply.wetsandDeathTime or 0, now, ply.wetsandSwitchedTeam == true) then
			ply:Spawn()
		end
	end
end

local EFFECTS = {
	state = function(self, e)
		SetGlobal2Int("wetsand_round_state", e.to)
		if e.to == S.PREROUND then
			SetGlobal2Float("wetsand_preround_end_time", e.preroundEnd)
			SetGlobal2Int("wetsand_round_winner", UNASSIGNED)
		end
	end,
	output = function(self, e)
		if IsValid(self.proxy) then self.proxy:TriggerOutput(e.name, self.proxy, e.value) end
	end,
	balance_teams = function() WETSAND.BalanceTeams(false) end,
	cleanup = function(self) self:CleanUpMap() end,
	new_round_outputs = function() timer.Simple(0, FireNewRoundOutputs) end,
	round_spawn = function(self)
		-- CTFGameRules::SetupOnRoundStart forgets the koth clocks.
		self.teamClocks = {}
		self:RunListeners(Rounds.PHASE_SPAWN)
		hook.Run("WetsandRoundSpawn")
	end,
	round_activate = function(self)
		self:RunListeners(Rounds.PHASE_ACTIVATE)
		hook.Run("WetsandRoundActivate")
	end,
	previous_round_end = function(self) self:RunListeners(Rounds.PHASE_ROUND_END) end,
	activate_timers = function(self) self:ActivateTimers() end,
	time_limit_timer = function(self, e) self:CreateTimer(TIMELIMIT_TIMER_NAME, e.seconds) end,
	switch_teams = function() SwitchTeams() end,
	respawn_all = function()
		EachPlayer(function(ply)
			if ply:Team() ~= SPECTATOR then ply:Spawn() end
		end)
	end,
	respawn_team = function(self, e, now) RespawnTeam(self, e.team, now) end,
	doors_lock = function() FireCompetitive("OnSpawnRoomDoorsShouldLock") end,
	doors_unlock = function() FireCompetitive("OnSpawnRoomDoorsShouldUnlock") end,
	hook = function(self, e) ROUND_HOOKS[e.name](e.args) end,
	score = function(self, e) team.AddScore(e.team, e.points) end,
	-- What the win panel shows (SendWinPanelInfo).
	publish_win = function(self, e)
		local remaining = 0
		if e.winner ~= UNASSIGNED then remaining = self.objective:RoundsRemaining(e.winner) end
		SetGlobal2Int("wetsand_round_winner", e.winner)
		SetGlobal2Int("wetsand_round_win_reason", e.reason)
		SetGlobal2Bool("wetsand_round_full_round", e.fullRound)
		SetGlobal2Int("wetsand_rounds_remaining", remaining)
	end,
	win_song = function(self, e)
		PlayWinSong(e.winner)
		for t, line in pairs(self.round:Mode():RoundWinLines(e.winner, e.fullRound, self.multipleTrains)) do
			WETSAND.BroadcastSound(t, line)
		end
	end,
	sudden_death = function(self, e)
		SetGlobal2Int("wetsand_stalemate_reason", e.reason)
		WETSAND.BroadcastSound(UNASSIGNED, SUDDEN_DEATH)
	end,
	hide_timers = function(self) self:HideActiveTimer() end,
	restore_timers = function(self) self:RestoreActiveTimer() end,
	stalemate_timer = function(self, e) self.stalemateTimer = self:CreateTimer(nil, e.seconds) end,
	-- Without a full reset the survivors take the round's points (the
	-- master's SetWinnerAndForceCaps).
	stalemate_winner = function(self, e)
		if not e.forceMapReset and self.objective.SuddenDeathWin then
			self.objective:SuddenDeathWin(e.team)
		else
			self:SetWinningTeam(e.team, Rounds.WINREASON.OPPONENTS_DEAD, e.forceMapReset)
		end
	end,
	intermission = function(self, e)
		SetGlobal2String("wetsand_game_over_reason", e.reason)
		EachPlayer(function(ply) ply:Freeze(true) end)
	end,
	changelevel = function() RunConsoleCommand("changelevel", game.GetMap()) end,
	unfreeze = function()
		EachPlayer(function(ply) ply:Freeze(false) end)
	end,
	overtime = function(self, e) PublishOvertime(e.value) end,
}

function Controller:Apply(effects)
	local now = CurTime()
	for _, e in ipairs(effects) do EFFECTS[e.kind](self, e, now) end
end

-- The gamerules surface tf_gamerules forwards ------------------------------------------

function Controller:OnPlayerDeath(ply)
	local now = CurTime()
	ply.wetsandDeathTime = now
	-- a death that changed the player's team (WETSAND.SetPlayerTeam) waits only
	-- for the new team's next wave
	ply.wetsandSwitchedTeam = ply.wetsandChangingTeam == true
	local t = WETSAND.TeamOf(ply)
	local at = 0
	-- Sandbox mode: no waves, the player clicks to respawn (GM:PlayerDeathThink)
	if t ~= UNASSIGNED and not WETSAND.GameplayStopped() then
		at = self.round:RespawnAt(t, now, #TeamPlayers(t), ply.wetsandSwitchedTeam)
	end
	ply:SetNW2Float("wetsand_respawn_time", at)
end

function Controller:RestartRound()
	self:Apply(self.round:RestartRound(CurTime()))
end

function Controller:Halted()
	return self.round:Halted()
end

-- Stopping the game (non-gameplay mode): the round waits between rounds and
-- every timer pauses. Setup, if it is on, ends as its clock running out
-- would, so the map opens its own setup gates. The spawn doors stand open:
-- their triggers, which would shut them as players leave, are off until the
-- next game's map reset restores them.
function Controller:Halt()
	local now = CurTime()
	self:Apply(self.round:Halt(now))
	SetGlobal2Bool("wetsand_gameplay_halted", true)
	for _, ent in ipairs(self.timerList) do
		local timer = self.timers[ent]
		if IsValid(ent) then
			if timer:InSetup() then self:ApplyTimerEvents(ent, timer:FinishSetup(now)) end
			timer:Pause(now)
		end
	end
	self:SetSetup(false)
	local triggers
	self.spawnDoors, triggers = SpawnDoors()
	for trigger in pairs(triggers) do trigger:Fire("Disable") end
	for _, door in ipairs(self.spawnDoors) do
		door:Fire("Unlock")
		door:Fire("Open")
	end
	self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
	self:PublishHudTimer(now)
end

function Controller:Unhalt()
	self.round:Unhalt()
	self.spawnDoors = nil
	SetGlobal2Bool("wetsand_gameplay_halted", false)
end

-- A stopped game: the doors stay open, and a dead player on a team is back
-- after a pause, as no respawn wave comes.
function Controller:HaltedThink(now)
	if now >= self.nextDoorsOpen then
		self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
		for _, door in ipairs(self.spawnDoors or {}) do
			if IsValid(door) then door:Fire("Open") end
		end
	end
	EachPlayer(function(ply)
		if not ply:Alive() and WETSAND.TeamOf(ply) ~= UNASSIGNED and ply:Team() ~= SPECTATOR then
			ply.wetsandHaltedDeath = ply.wetsandHaltedDeath or now
			if Rounds.HaltedRespawnDue(ply.wetsandHaltedDeath, now) then
				ply.wetsandHaltedDeath = nil
				ply:Spawn()
			end
		else
			ply.wetsandHaltedDeath = nil
		end
	end)
end

function Controller:RespawnsDisabled()
	return self.round:RespawnsDisabled()
end

-- Allowing respawns again puts the dead back in the waves.
function Controller:SetRespawnsDisabled(disabled)
	if not self.round:SetRespawnsDisabled(disabled) then return end
	EachPlayer(function(ply)
		if not ply:Alive() and WETSAND.TeamOf(ply) ~= UNASSIGNED then self:OnPlayerDeathTime(ply) end
	end)
end

-- A dead player's respawn time again, from their death.
function Controller:OnPlayerDeathTime(ply)
	local t = WETSAND.TeamOf(ply)
	ply:SetNW2Float("wetsand_respawn_time", self.round:RespawnAt(t, ply.wetsandDeathTime or CurTime(), #TeamPlayers(t),
		ply.wetsandSwitchedTeam == true))
end

-- The Game Rules editor's override: seconds >= 0, or nil for the map's.
function Controller:SetAdminRespawnWaveTime(t, seconds)
	self.round:SetAdminWaveTime(t, seconds)
end

function Controller:TeamRespawnWaveTime(t)
	return self.round:TeamWaveTime(t)
end

function Controller:GetRespawnWaveMaxLength(t, scaleWithNumPlayers)
	return self.round:WaveMaxLength(t, #TeamPlayers(t), scaleWithNumPlayers)
end

-- tf_gamerules' inputs (CTFGameRulesProxy) -------------------------------------------

local function WaveSetter(t)
	return function(self, v) self.round:SetTeamWaveTime(t, tonumber(v) or 0) end
end

local function WaveAdder(t)
	return function(self, v) self.round:AddTeamWaveTime(t, tonumber(v) or 0) end
end

-- Goal strings and roles, published for the HUD.
local function GoalSetter(t)
	return function(self, v) SetGlobal2String("wetsand_round_goal_" .. t, tostring(v or "")) end
end

local function RoleSetter(t)
	return function(self, v) SetGlobal2Int("wetsand_round_role_" .. t, tonumber(v) or ROLE_NONE) end
end

local function ScoreAdder(t)
	return function(self, v) team.AddScore(t, tonumber(v) or 0) end
end

local function VoiceTo(t)
	return function(self, v) WETSAND.BroadcastSound(t, tostring(v)) end
end

local function ClockActivator(t)
	return function(self) self:ActivateTeamClock(t) end
end

local function Ignore() end

local PROXY_INPUTS = {
	setredteamrespawnwavetime = WaveSetter(RED),
	setblueteamrespawnwavetime = WaveSetter(BLUE),
	addredteamrespawnwavetime = WaveAdder(RED),
	addblueteamrespawnwavetime = WaveAdder(BLUE),
	setredteamgoalstring = GoalSetter(RED),
	setblueteamgoalstring = GoalSetter(BLUE),
	setredteamrole = RoleSetter(RED),
	setblueteamrole = RoleSetter(BLUE),
	addredteamscore = ScoreAdder(RED),
	addblueteamscore = ScoreAdder(BLUE),
	setrequiredobservertarget = function(self, v) WETSAND.SetRequiredObserverTarget(tostring(v or "")) end,
	setstalemateontimelimit = function(self, v)
		self.round:SetStalemateOnTimelimit(tonumber(v) == 1 or tostring(v) == "true")
	end,
	-- PlayVO is heard by everyone (BroadcastSound to 255), the others by one team.
	playvo = VoiceTo(UNASSIGNED),
	playvored = VoiceTo(RED),
	playvoblue = VoiceTo(BLUE),
	setroundrespawnfreezeenabled = function(self, v)
		WETSAND.RestartFreeze:SetBool(tonumber(v) ~= 0 and tostring(v) ~= "false")
	end,
	setredkothclockactive = ClockActivator(RED),
	setbluekothclockactive = ClockActivator(BLUE),
	-- Accepted so the map's I/O is honoured, with no effect in GMod: no
	-- holiday map events, CTF bonus, upgrades file or truce.
	handlemapevent = Ignore,
	setmapforcedtruceduringbossfight = Ignore,
	setctfcapturebonustime = Ignore,
	setcustomupgradesfile = Ignore,
}

-- A tf_gamerules input, in any case; returns whether it is one.
function Controller:ProxyInput(name, value)
	local handler = PROXY_INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end

-- Thinking ----------------------------------------------------------------------------

function Controller:World(now)
	local stalemateTimer = self.stalemateTimer
	return {
		havePlayers = HavePlayers(),
		teams = TeamLife(),
		scores = Scores(),
		stalemateTimerLeft = IsValid(stalemateTimer) and self.timers[stalemateTimer]:TimeRemaining(now) or nil,
		timerMayExpire = self:TimerMayExpire(),
		mapHasActiveTimer = self:MapHasActiveTimer(),
		objective = self.objective,
	}
end

-- Sandbox mode pauses every timer and lets none of them fire.
function Controller:ThinkTimers(now)
	if Active() and self.round:Halted() then
		self:PublishHudTimer(now)
		return
	end
	local q = {
		mayExpire = self:TimerMayExpire(),
		roundWon = RoundWon(),
		overtime = self.round:InOvertime(),
		nagEnabled = overtimeNag:GetBool(),
		random = math.random,
	}
	-- A copy: an output may remove a timer as it fires.
	local list = {}
	for i, ent in ipairs(self.timerList) do list[i] = ent end
	for _, ent in ipairs(list) do
		local timer = self.timers[ent]
		if IsValid(ent) and timer then
			self:ApplyTimerEvents(ent, timer:Think(now, q))
			q.overtime = self.round:InOvertime()
		end
	end
	self:PublishHudTimer(now)
end

function Controller:ThinkRound(now)
	if not Active() then return end
	self.round:Configure(Settings())
	if self.round:Halted() then
		self:HaltedThink(now)
		return
	end
	self:Apply(self.round:Think(now, self:World(now)))
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	if now >= Controller.nextTimerThink then
		Controller.nextTimerThink = now + TIMER_THINK_INTERVAL
		Controller:ThinkTimers(now)
	end
	if now >= Controller.nextRoundThink then
		Controller.nextRoundThink = now + ROUND_THINK_INTERVAL
		Controller:ThinkRound(now)
	end
end)

-- The map, once its entities exist ------------------------------------------------------

local function HasObjective()
	for _, class in ipairs(OBJECTIVE_CLASSES) do
		if ents.FindByClass(class)[1] then return true end
	end
	return false
end

-- A master makes the map a control points one (the mode other objective
-- features may raise). A map with an objective and no tf_gamerules gets
-- one, named as TF2 names it, and the gamemode then starts in its mode.
-- Without a proxy nothing sends RoundSpawn, so the timers run from map spawn.
function Controller:SetUpMap()
	if self.mapSetUp then return end
	self.mapSetUp = true
	if ents.FindByClass(MASTER_CLASS)[1] then self:SetMode(ControlPoints.Mode) end
	if not Active() and HasObjective() then
		local proxy = ents.Create(PROXY_CLASS)
		proxy:SetName(PROXY_CLASS)
		proxy:Spawn()
	end
	self:ActivateTimers()
	-- The rules exist now: the gamemode puts the map in its Sandbox or
	-- Gameplay mode (StartAtLoad is idempotent).
	if Active() then
		WETSAND.Feature("gamemode"):StartAtLoad()
		return
	end
	local now = CurTime()
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) then self:ApplyTimerEvents(ent, self.timers[ent]:RoundSpawn(now)) end
	end
end

-- Loaded during the map's spawn this waits for InitPostEntity; loaded later,
-- the next tick has every entity.
hook.Add("InitPostEntity", THINK_HOOK, function() Controller:SetUpMap() end)
timer.Simple(0, function() Controller:SetUpMap() end)

-- The timers take their RoundSpawn from the rounds, first of all.
Controller:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_TIMERS, function()
	local now = CurTime()
	for _, ent in ipairs(Controller.timerList) do
		if IsValid(ent) then Controller:ApplyTimerEvents(ent, Controller.timers[ent]:RoundSpawn(now)) end
	end
end)

return Controller
