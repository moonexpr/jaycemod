-- The rounds feature's controller. It owns the foundation.rounds Round (the
-- gamerules state machine), a foundation.rounds.timer Timer per
-- team_round_timer, the timer shown in the HUD, the gamerules proxy
-- (tf_gamerules), the mode, the round listeners, the timer holds, the team
-- clocks and the objective port. It feeds the models engine time and a
-- snapshot of the players, and carries out their effects: outputs, the map
-- cleanup, respawns, sounds and the ws_round_* and ws_timer_*
-- keys. It decides nothing itself.
--
-- Loaded by tf_gamerules, team_round_timer, game_round_win and
-- tf_logic_competitive, and by every objective feature (capture, koth,
-- payload). On a map with an objective entity and no tf_gamerules it makes
-- one, as CTFGameRules::CreateStandardEntities does, so the rounds run and
-- outputs aimed at the name tf_gamerules reach it.
local Rounds = WS.require("foundation.rounds")
local Text = WS.require("foundation.rounds.text")
local Timer = WS.require("foundation.rounds.timer")
local ControlPoints = WS.require("foundation.rounds.control_points")
local SpawnHold = WS.require("features.rounds.spawn_doors")
local Limits = WS.require("foundation.rounds.limits")

local S = WS.STATE
local UNASSIGNED, SPECTATOR = WS.TEAM_UNASSIGNED, WS.TEAM_SPECTATOR
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
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
local scrambleAuto = ConVarOrCreate("mp_scrambleteams_auto", "1", FCVAR_NOTIFY,
	"Server will automatically scramble the teams if criteria met.  Only works on dedicated servers.")
local scrambleWinDifference = ConVarOrCreate("mp_scrambleteams_auto_windifference", "2", FCVAR_NOTIFY,
	"Number of round wins a team must lead by in order to trigger an auto scramble.", 0)
local winlimit = ConVarOrCreate("mp_winlimit", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "Max score one team can reach before server changes maps", 0)
local maxrounds = ConVarOrCreate("mp_maxrounds", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "max number of rounds to play before server changes maps", 0)
local timelimit = ConVarOrCreate("mp_timelimit", "0", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "game time per map in minutes")
local matchEndAtTimelimit = ConVarOrCreate("mp_match_end_at_timelimit", "0", FCVAR_NOTIFY, "Allow the match to end when mp_timelimit hits instead of waiting for the end of the current round.")
local chattime = ConVarOrCreate("mp_chattime", "10", FCVAR_REPLICATED, "amount of time players can chat after the game is over", 1, 120)
-- teamplay_round_timer.cpp
local overtimeNag = ConVarOrCreate("tf_overtime_nag", "0", FCVAR_NOTIFY, "Announcer overtime nag.")
-- The round limits (foundation.rounds.limits): only a map without an
-- objective plays to them. Both on by default, the frag limit the one
-- reached first.
local roundFraglimit = CreateConVar("mp_round_fraglimit", "30", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Frags a team needs in a round to win it, on a map without an objective; 0: no frag limit.", 0)
local roundCashlimit = CreateConVar("mp_round_cashlimit", "10000", { FCVAR_NOTIFY, FCVAR_REPLICATED },
	"Money a team must earn in a round to win it, on a map without an objective (frags decide first); 0: no cash limit.", 0)

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
local THINK_HOOK = "ws_rounds"

-- CTeamRoundTimer::AddTimerSeconds' ROUND_TIMER_TIME_ADDED_* sounds.
local TIME_ADDED_WINNER = {
	"Announcer.TimeAwardedForTeam",
	"Announcer.TimeAwardedCongrats",
	"Announcer.TimeAwardedSuccess",
}

local TIME_ADDED_LOSER = "Announcer.TimeAddedForEnemy"
local TIME_ADDED = "Announcer.TimeAdded"
local OVERTIME_NAG = "Game.Overtime"
local SUDDEN_DEATH = "Game.SuddenDeath"

local ROUND_RESTART = "Game.Stalemate"
local SPECTATOR_WIN_MUSIC = "MatchMaking.RoundEndStalemateMusic"
local STALEMATE_LINE = "Announcer.CompRoundStalemate" -- vo/compmode/cm_admin_stalemate.mp3
-- The notification cards' icons (TF2's, as the admin notices'):
-- no respawn clock for sudden death, a clock for the next map.
local ICON_SUDDEN_DEATH = "hud/ico_time_none"
local ICON_NEXT_MAP = "hud/ico_time_10"
local ICON_SCRAMBLE = "hud/ico_teamswitch"
local SCRAMBLE_LINE = "Announcer.AM_TeamScrambleRandom"

-- The match won (GoToIntermission; a tie goes to sudden death instead):
-- each side its music on CHAN_AUTO (the spectators the winner's colour of
-- it), and the announcer names the winner to everyone on CHAN_VOICE2.
local MATCH_WIN_MUSIC, MATCH_LOSE_MUSIC = "MatchMaking.MatchEndWinMusicCasual", "MatchMaking.MatchEndLoseMusicCasual"
local MATCH_SPECTATOR_MUSIC = {
	[RED] = "MatchMaking.MatchEndRedWinMusic",
	[BLUE] = "MatchMaking.MatchEndBlueWinMusic",
}
local MATCH_WIN_LINE = {
	[RED] = "Announcer.CompMatchWinRed",
	[BLUE] = "Announcer.CompMatchWinBlu",
}

local function PlayMatchEnd(winner)
	WS.BroadcastSound(winner, MATCH_WIN_MUSIC)
	WS.BroadcastSound(WS.EnemyOf(winner), MATCH_LOSE_MUSIC)
	WS.BroadcastSound(SPECTATOR, MATCH_SPECTATOR_MUSIC[winner])
	WS.BroadcastPA(UNASSIGNED, MATCH_WIN_LINE[winner])
end

-- The level after the match (Rounds.NextMap): the engine's nextlevel, else
-- the map cycle's next (mapcyclefile), else this map again.
local nextlevel = GetConVar("nextlevel")

local function MapInstalled(map)
	return file.Exists("maps/" .. map .. ".bsp", "GAME")
end

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
		scrambleAuto = scrambleAuto:GetBool(),
		scrambleWinDifference = scrambleWinDifference:GetInt(),
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
		[Rounds.PHASE_ARENA_START] = {},
	},
	holds = {},
	objective = Rounds.NO_OBJECTIVE,
	tally = Limits.Tally.New(), -- the round's frags and earnings, for its limits
	roundTime = 0, -- an admin's round time on a map without an objective (0: untimed)
	roundTimer = NULL, -- its timer this round
	multipleTrains = false,
	spawnDoors = nil,
	spawnTriggers = nil, -- the open doors' triggers: trigger -> true
	spawnHold = nil, -- which of them come back on (features.rounds.spawn_doors)
	switchingTriggers = false, -- our own Enable/Disable, not the map's
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
		if WS.TeamOf(ply) == t then players[#players + 1] = ply end
	end
	return players
end

-- A player counts once their client has finished loading (client_ready,
-- ws/sh_events.lua), so the pre-round freeze is not spent on a
-- loading screen. Bots have no client to report it.
local function Ready(ply)
	return WS.IsReady(ply) or ply:IsBot()
end

-- BHavePlayers: someone ready and on RED or BLU, or something else fighting
-- for a team (the AI war says so through WSHaveCombatants).
local function HavePlayers()
	for _, ply in ipairs(player.GetAll()) do
		if Ready(ply) and WS.TeamOf(ply) ~= UNASSIGNED then return true end
	end
	return hook.Run("WSHaveCombatants") == true
end

local function Scores()
	return {
		[RED] = team.GetScore(RED),
		[BLUE] = team.GetScore(BLUE),
	}
end

-- Each team's players, its live ones, and its live soldiers (the AI war
-- says how many through WSTeamCombatants): sudden death ends only when
-- a side's last soldier is down too.
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
			soldiers = hook.Run("WSTeamCombatants", t) or 0,
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
		local t = WS.TeamOf(ply)
		if t ~= UNASSIGNED then WS.SetPlayerTeam(ply, WS.EnemyOf(t), true) end
	end)
	local red, blu = team.GetScore(RED), team.GetScore(BLUE)
	team.SetScore(RED, blu)
	team.SetScore(BLUE, red)
end

-- CTFGameRules::HandleScrambleTeams: the players dealt out by score
-- (L.Scramble), the first side at random, and the teams' scores reset.
local function ScrambleTeams()
	local players, byId = {}, {}
	EachPlayer(function(ply)
		if WS.TeamOf(ply) ~= UNASSIGNED then
			players[#players + 1] = { id = ply:UserID(), score = ply:Frags() }
			byId[ply:UserID()] = ply
		end
	end)
	for id, t in pairs(WS.TeamRules.Scramble(players, math.random(0, 1) == 0 and RED or BLUE)) do
		WS.SetPlayerTeam(byId[id], t, true)
	end
	team.SetScore(RED, 0)
	team.SetScore(BLUE, 0)
	PrintMessage(HUD_PRINTTALK, "The teams have been scrambled.")
end

-- CTeamplayRoundBasedRules::PlayWinSong: each side hears its own result.
-- (The teamless would hear Game.TeamWin2/3, which no soundscript defines.)
local function PlayWinSong(winner)
	if winner == UNASSIGNED then
		-- a tie: the stalemate music, the announcer calling it over it
		WS.BroadcastPA(UNASSIGNED, "Game.Stalemate")
		WS.BroadcastPA(UNASSIGNED, STALEMATE_LINE)
		return
	end
	WS.BroadcastPA(winner, "Game.YourTeamWon")
	WS.BroadcastPA(WS.EnemyOf(winner), "Game.YourTeamLost")
	-- spectators, of neither team, hear who won over the stalemate music
	-- (CHAN_AUTO, under the announcer's CHAN_VOICE2)
	WS.BroadcastPA(SPECTATOR, winner == BLUE and "Announcer.CompRoundWinBlu" or "Announcer.CompRoundWinRed")
	WS.BroadcastSound(SPECTATOR, SPECTATOR_WIN_MUSIC)

end

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

-- The match's win conditions, for the scoreboard (ws/cl_scoreboard.lua):
-- the limits, the rounds played, and when the map's time runs out (0 with
-- no time limit), so clients count it down themselves.
local function PublishLimits()
	local now = CurTime()
	local limits = Controller.round:Limits(now)
	SetGlobal2Int("ws_match_winlimit", limits.winlimit)
	SetGlobal2Int("ws_match_maxrounds", limits.maxrounds)
	SetGlobal2Int("ws_match_timelimit", limits.timelimit)
	SetGlobal2Int("ws_match_rounds_played", limits.roundsPlayed)
	SetGlobal2Float("ws_match_time_end", limits.timelimit > 0 and now + limits.timeLeft or 0)
end

-- TF2 reads the match's limits live: a change mid-match moves its end.
for _, name in ipairs({ "mp_winlimit", "mp_maxrounds", "mp_timelimit" }) do
	cvars.AddChangeCallback(name, function()
		Controller.round:SetLimits({
			winlimit = winlimit:GetInt(),
			maxrounds = maxrounds:GetInt(),
			timelimit = timelimit:GetInt(),
		})
		PublishLimits()
	end, "ws_rounds_limits")
end

local function PublishState()
	local round = Controller.round
	SetGlobal2Int("ws_round_state", round:State())
	SetGlobal2Int("ws_round_hud_type", round:Mode().HUD)
	PublishLimits()
end

function Controller:BindProxy(ent)
	if IsValid(self.proxy) then return end
	self.proxy = ent
	WS.Rules = ent
	SetGlobal2Bool("ws_rounds_active", true)
	PublishState()
end

function Controller:UnbindProxy(ent)
	if ent ~= self.proxy then return end
	self.proxy = NULL
	WS.Rules = nil
	SetGlobal2Bool("ws_rounds_active", false)
end

function Controller:Proxy()
	return self.proxy
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

-- CTeamplayRoundBasedRules::SetSetup, from every timer's SetState.
function Controller:SetSetup(on)
	if self.round:SetSetup(on) then SetGlobal2Bool("ws_round_in_setup", on) end
end

function Controller:SetOvertime(on)
	if self.round:SetOvertime(on) then PublishOvertime(on) end
end

-- In whole seconds, as TF2's event carries them; a clamp to the timer's
-- maximum length can leave a fraction.
local function Notify(t, seconds)
	WS.Events.Fire("teamplay_timer_time_added", {
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

-- Mode, listeners and holds ----------------------------------------------------------

function Controller:SetMode(mode)
	if self.round:SetMode(mode) then PublishState() end
end

function Controller:Mode()
	return self.round:Mode()
end

function Controller:InSuddenDeath()
	return self.round:InSuddenDeath()
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
function Controller:PointsMayBeCaptured() return self.round:PointsMayBeCaptured(CurTime()) end
-- The arena's cap-enable time (foundation.rounds' SetCapEnableTime).
function Controller:SetCapEnableTime(at) self.round:SetCapEnableTime(at) end
function Controller:CapEnableTime() return self.round:CapEnableTime() end
-- Settings a mode's feature owns the convars of (the arena's), kept until
-- the feature gives new ones.
function Controller:ConfigureRound(settings) self.round:Configure(settings) end
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
	for _, line in ipairs(lines) do WS.BroadcastPA(line.team, line.sound) end
end

-- logic_auto (CLogicAuto::Think) ----------------------------------------------------

-- A cleanup recreates every logic_auto, which would fire OnMultiNewMap as at
-- map load: GMod's gamerules never report InRoundRestart. Its keyvalue is
-- emptied while the cleanup runs, and OnMultiNewRound fires instead.
hook.Add("EntityKeyValue", "ws_rounds_new_map", function(ent, key)
	if Controller.suppressNewMap and ent:GetClass() == LOGIC_AUTO_CLASS and string.lower(key) == "onmultinewmap" then
		return ""
	end
end)

local function FireNewRoundOutputs()
	for _, auto in ipairs(ents.FindByClass(LOGIC_AUTO_CLASS)) do
		WS.FireOutput(auto, "OnMultiNewRound", auto)
	end
end

function Controller:CleanUpMap()
	self.suppressNewMap = true
	game.CleanUpMap(false, CLEANUP_KEEPS)
	self.suppressNewMap = false
end

-- Effects ---------------------------------------------------------------------------

-- The model's round hooks, for other features: the round is running
-- (spawns, the AI war), and a round was won (winner, its WINREASON).
local ROUND_ACTIVE = "WSRoundActive"
local ROUND_WIN = "WSRoundWin"
local ROUND_HOOKS = {
	[ROUND_ACTIVE] = function() hook.Run(ROUND_ACTIVE) end,
	[ROUND_WIN] = function(args) hook.Run(ROUND_WIN, args[1], args[2]) end,
}

local function FireCompetitive(output)
	for _, logic in ipairs(ents.FindByClass(COMPETITIVE_CLASS)) do logic:TriggerOutput(output, logic) end
end

local function RespawnTeam(self, t, now)
	for _, ply in ipairs(TeamPlayers(t)) do
		if not ply:Alive() and self.round:MayRespawn(t, ply.wsDeathTime or 0, now, ply.wsSwitchedTeam == true) then
			ply:Spawn()
		end
	end
end

-- The level the match's end changes to (Rounds.NextMap).
local function NextMap()
	return Rounds.NextMap(nextlevel:GetString(), game.GetMapNext(), game.GetMap(), MapInstalled)
end

local EFFECTS = {
	state = function(self, e)
		SetGlobal2Int("ws_round_state", e.to)
		PublishLimits()
		if e.to == S.PREROUND then
			self:RestoreSpawnDoors()
			SetGlobal2Float("ws_preround_end_time", e.preroundEnd)
			SetGlobal2Int("ws_round_winner", UNASSIGNED)
		end
	end,
	output = function(self, e)
		if IsValid(self.proxy) then self.proxy:TriggerOutput(e.name, self.proxy, e.value) end
	end,
	balance_teams = function() WS.BalanceTeams(false) end,
	cleanup = function(self) self:CleanUpMap() end,
	clear_gore = function()
		game.RemoveRagdolls()
		WS.Events.Fire("round_gore_cleared", {})
	end,
	new_round_outputs = function() timer.Simple(0, FireNewRoundOutputs) end,
	round_spawn = function(self)
		-- CTFGameRules::SetupOnRoundStart forgets the koth clocks.
		self.teamClocks = {}
		-- the round limits count from zero, and an admin's round time starts again
		self.tally:Reset()
		self:PublishRoundLimits()
		self:StartRoundTimer()
		self:RunListeners(Rounds.PHASE_SPAWN)
		hook.Run("WSRoundSpawn")
	end,
	round_activate = function(self)
		self:RunListeners(Rounds.PHASE_ACTIVATE)
		hook.Run("WSRoundActivate")
	end,
	previous_round_end = function(self) self:RunListeners(Rounds.PHASE_ROUND_END) end,
	arena_round_start = function(self) self:RunListeners(Rounds.PHASE_ARENA_START) end,
	activate_timers = function(self) self:ActivateTimers() end,
	time_limit_timer = function(self, e) self:CreateTimer(TIMELIMIT_TIMER_NAME, e.seconds) end,
	switch_teams = function() SwitchTeams() end,
	-- mp_scrambleteams_auto: told with the win, done as the next round starts
	scramble_due = function()
		WS.BroadcastPA(UNASSIGNED, SCRAMBLE_LINE)
		WS.Announce(Text.SCRAMBLE_NOTE, UNASSIGNED, UNASSIGNED, ICON_SCRAMBLE)
	end,
	scramble_teams = function() ScrambleTeams() end,
	respawn_all = function()
		EachPlayer(function(ply)
			if ply:Team() ~= SPECTATOR then ply:Spawn() end
		end)
	end,
	respawn_team = function(self, e, now) RespawnTeam(self, e.team, now) end,
	-- Sudden death over: its survivors, players and the AI war's soldiers
	-- (WSSuddenDeathOver), overhealed (Rounds.SurvivorHealth), then
	-- every dead player on a team back, to enjoy the victory or the
	-- humiliation.
	sudden_death_over = function()
		EachPlayer(function(ply)
			if ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then
				ply:SetHealth(Rounds.SurvivorHealth(ply:GetMaxHealth(), ply:Health()))
			end
		end)
		hook.Run("WSSuddenDeathOver", Rounds.SurvivorHealth)
		EachPlayer(function(ply)
			if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then ply:Spawn() end
		end)
	end,
	doors_lock = function() FireCompetitive("OnSpawnRoomDoorsShouldLock") end,
	doors_unlock = function() FireCompetitive("OnSpawnRoomDoorsShouldUnlock") end,
	hook = function(self, e) ROUND_HOOKS[e.name](e.args) end,
	score = function(self, e) team.AddScore(e.team, e.points) end,
	-- What the win panel shows (SendWinPanelInfo).
	publish_win = function(self, e, now)
		local remaining = 0
		if e.winner ~= UNASSIGNED then remaining = self.objective:RoundsRemaining(e.winner) end
		SetGlobal2Int("ws_round_winner", e.winner)
		SetGlobal2Int("ws_round_win_reason", e.reason)
		SetGlobal2Bool("ws_round_full_round", e.fullRound)
		SetGlobal2Int("ws_rounds_remaining", remaining)
		-- a team's win opens the setup gates and every spawn door, so its
		-- side can hunt the humiliated losers down
		if e.winner ~= UNASSIGNED then
			self:FinishSetup(now)
			self:OpenSpawnDoors(now)
		end
	end,
	win_song = function(self, e)
		PlayWinSong(e.winner)
		for t, line in pairs(self.round:Mode():RoundWinLines(e.winner, e.fullRound, self.multipleTrains)) do
			WS.BroadcastPA(t, line)
		end
	end,
	-- nobody respawns, so the setup gates (the map's OnSetupFinished relays)
	-- and every spawn door open: the last of each side have nowhere to hide
	sudden_death = function(self, e, now)
		WS.BroadcastPA(UNASSIGNED, SUDDEN_DEATH)
		WS.Announce(Text.SuddenDeathNote(e.reason), UNASSIGNED, UNASSIGNED, ICON_SUDDEN_DEATH)
		self:FinishSetup(now)
		self:OpenSpawnDoors(now)
	end,
	hide_timers = function(self) self:HideActiveTimer() end,
	restore_timers = function(self) self:RestoreActiveTimer() end,
	-- sudden death after the arena round, or after another, replaces its timer
	stalemate_timer = function(self, e)
		if IsValid(self.stalemateTimer) then self.stalemateTimer:Remove() end
		self.stalemateTimer = self:CreateTimer(nil, e.seconds)
	end,
	-- Without a full reset the survivors take the round's points (the
	-- master's SetWinnerAndForceCaps).
	stalemate_winner = function(self, e)
		if not e.forceMapReset and self.objective.SuddenDeathWin then
			self.objective:SuddenDeathWin(e.team)
		else
			self:SetWinningTeam(e.team, Rounds.WINREASON.OPPONENTS_DEAD, e.forceMapReset)
		end
	end,
	intermission = function(self, e, now)
		SetGlobal2String("ws_game_over_reason", e.reason)
		SetGlobal2Int("ws_match_winner", e.winner)
		SetGlobal2Float("ws_game_over_end", e["until"])
		hook.Run("WSMatchWin", e.winner)
		-- its winners hunt the humiliated losers to its music through the
		-- setup gates and every spawn door (MATCH_WIN_EXTRA), then everyone
		-- is frozen for mp_chattime; a match ended drawn (a stalemate) is
		-- bonus time for all to the stalemate music, frozen never
		self:FinishSetup(now)
		self:OpenSpawnDoors(now)
		if e.winner == UNASSIGNED then PlayWinSong(UNASSIGNED) else PlayMatchEnd(e.winner) end
	end,
	changelevel = function()
		RunConsoleCommand("changelevel", NextMap())
	end,
	-- mp_chattime at the match's end: everyone frozen, the AI war's soldiers
	-- too (WSFreeze), until the level changes
	freeze = function()
		EachPlayer(function(ply) ply:Freeze(true) end)
		hook.Run("WSFreeze", true)
		WS.Announce(Text.NextMapNote(NextMap()), UNASSIGNED, UNASSIGNED, ICON_NEXT_MAP)
	end,
	-- a match ended drawn: bonus time goes on, the next map named
	next_map = function()
		WS.Announce(Text.NextMapNote(NextMap()), UNASSIGNED, UNASSIGNED, ICON_NEXT_MAP)
	end,
	unfreeze = function()
		EachPlayer(function(ply) ply:Freeze(false) end)
		hook.Run("WSFreeze", false)
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
	ply.wsDeathTime = now
	-- a death that changed the player's team (WS.SetPlayerTeam) waits only
	-- for the new team's next wave
	ply.wsSwitchedTeam = ply.wsChangingTeam == true
	local t = WS.TeamOf(ply)
	local at = 0
	-- Sandbox mode: no waves, the player clicks to respawn (GM:PlayerDeathThink)
	if t ~= UNASSIGNED and not WS.GameplayStopped() then
		at = self.round:RespawnAt(t, now, #TeamPlayers(t), ply.wsSwitchedTeam)
	end
	ply:SetNW2Float("ws_respawn_time", at)
end

function Controller:RestartRound()
	WS.BroadcastPA(UNASSIGNED, ROUND_RESTART)
	timer.Simple(5, function()
		self:Apply(self.round:RestartRound(CurTime()))
	end)
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
	SetGlobal2Bool("ws_gameplay_halted", true)
	self:FinishSetup(now)
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) then self.timers[ent]:Pause(now) end
	end
	self:OpenSpawnDoors(now)
	self:PublishHudTimer(now)
end

-- Setup, if it is on, ends as its clock running out would (OnSetupFinished),
-- so the map opens its own setup gates.
function Controller:FinishSetup(now)
	for _, ent in ipairs(self.timerList) do
		local timer = self.timers[ent]
		if IsValid(ent) and timer:InSetup() then self:ApplyTimerEvents(ent, timer:FinishSetup(now)) end
	end
	self:SetSetup(false)
end

-- Every spawn door unlocked and open, its triggers off so none shuts it
-- (KeepSpawnDoorsOpen holds them open), until RestoreSpawnDoors or the next
-- map reset. The triggers that were on are remembered, with what the map
-- does to them meanwhile.
function Controller:OpenSpawnDoors(now)
	if not self.spawnDoors then
		local doors, triggers = SpawnDoors()
		local on = {}
		for trigger in pairs(triggers) do
			if not trigger:GetInternalVariable("m_bDisabled") then on[#on + 1] = trigger end
		end
		self.spawnDoors, self.spawnTriggers, self.spawnHold = doors, triggers, SpawnHold.New(on)
		self.switchingTriggers = true
		for _, trigger in ipairs(on) do trigger:Input("Disable") end
		self.switchingTriggers = false
	end
	for _, door in ipairs(self.spawnDoors) do
		if IsValid(door) then
			door:Fire("Unlock")
			door:Fire("Open")
		end
	end
	self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
end

-- The next round (a stage of a multi-stage map has no map reset): the
-- triggers that were on, on again unless the map has since turned them off,
-- with those it turned on, and the doors closed for them to open.
function Controller:RestoreSpawnDoors()
	if self.spawnHold then
		self.switchingTriggers = true
		for _, trigger in ipairs(self.spawnHold:ToEnable()) do
			if IsValid(trigger) then trigger:Input("Enable") end
		end
		self.switchingTriggers = false
	end
	for _, door in ipairs(self.spawnDoors or {}) do
		if IsValid(door) then door:Fire("Close") end
	end
	self.spawnDoors, self.spawnTriggers, self.spawnHold = nil, nil, nil
end

-- The map's own Enable and Disable of a held trigger: a stage's handover in
-- the bonus time (pl_goldrush's cap_a_capture_relay) outlasts the hold.
hook.Add("AcceptInput", "ws_rounds_spawn_doors", function(ent, input)
	local self = Controller
	if self.switchingTriggers or not (self.spawnTriggers and self.spawnTriggers[ent]) then return end
	self.spawnHold:MapInput(ent, string.lower(input))
end)

function Controller:KeepSpawnDoorsOpen(now)
	if now < self.nextDoorsOpen then return end
	self.nextDoorsOpen = now + HALT_DOORS_INTERVAL
	for _, door in ipairs(self.spawnDoors or {}) do
		if IsValid(door) then door:Fire("Open") end
	end
end

function Controller:Unhalt()
	self.round:Unhalt()
	SetGlobal2Bool("ws_gameplay_halted", false)
end

-- A stopped game: the doors stay open, and a dead player on a team is back
-- after a pause, as no respawn wave comes.
function Controller:HaltedThink(now)
	self:KeepSpawnDoorsOpen(now)
	EachPlayer(function(ply)
		if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED and ply:Team() ~= SPECTATOR then
			ply.wsHaltedDeath = ply.wsHaltedDeath or now
			if Rounds.HaltedRespawnDue(ply.wsHaltedDeath, now) then
				ply.wsHaltedDeath = nil
				ply:Spawn()
			end
		else
			ply.wsHaltedDeath = nil
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
		if not ply:Alive() and WS.TeamOf(ply) ~= UNASSIGNED then self:OnPlayerDeathTime(ply) end
	end)
end

-- A dead player's respawn time again, from their death.
function Controller:OnPlayerDeathTime(ply)
	local t = WS.TeamOf(ply)
	ply:SetNW2Float("ws_respawn_time", self.round:RespawnAt(t, ply.wsDeathTime or CurTime(), #TeamPlayers(t),
		ply.wsSwitchedTeam == true))
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
	return function(self, v) SetGlobal2String("ws_round_goal_" .. t, tostring(v or "")) end
end

local function RoleSetter(t)
	return function(self, v) SetGlobal2Int("ws_round_role_" .. t, tonumber(v) or ROLE_NONE) end
end

local function ScoreAdder(t)
	return function(self, v) team.AddScore(t, tonumber(v) or 0) end
end

local function VoiceTo(t)
	return function(self, v) WS.BroadcastPA(t, tostring(v)) end
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
	setrequiredobservertarget = function(self, v) WS.SetRequiredObserverTarget(tostring(v or "")) end,
	setstalemateontimelimit = function(self, v)
		self.round:SetStalemateOnTimelimit(tonumber(v) == 1 or tostring(v) == "true")
	end,
	-- PlayVO is heard by everyone (BroadcastPA to 255), the others by one team.
	playvo = VoiceTo(UNASSIGNED),
	playvored = VoiceTo(RED),
	playvoblue = VoiceTo(BLUE),
	setroundrespawnfreezeenabled = function(self, v)
		WS.RestartFreeze:SetBool(tonumber(v) ~= 0 and tostring(v) ~= "false")
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
	self:PublishRoundLimits()
	if self.round:Halted() then
		self:HaltedThink(now)
		return
	end
	local state = self.round:State()
	if state == S.GAME_OVER or state == S.STALEMATE or (state == S.TEAM_WIN and self.round:Winner() ~= UNASSIGNED) then self:KeepSpawnDoorsOpen(now) end
	self:Apply(self.round:Think(now, self:World(now)))
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
local function MakeProxy()
	local proxy = ents.Create(PROXY_CLASS)
	proxy:SetName(PROXY_CLASS)
	proxy:Spawn()
end

function Controller:SetUpMap()
	if self.mapSetUp then return end
	self.mapSetUp = true
	if ents.FindByClass(MASTER_CLASS)[1] then self:SetMode(ControlPoints.Mode) end
	if not Active() and HasObjective() then MakeProxy() end
	self:ActivateTimers()
	-- The rules exist now: the gamemode puts the map in its Sandbox or
	-- Gameplay mode (StartAtLoad is idempotent).
	if Active() then
		WS.Feature("gamemode"):StartAtLoad()
		return
	end
	local now = CurTime()
	for _, ent in ipairs(self.timerList) do
		if IsValid(ent) then self:ApplyTimerEvents(ent, self.timers[ent]:RoundSpawn(now)) end
	end
end

-- An admin's round time (the Round Timer Editor's Set Round Time) on a map
-- without an objective: each round gets a timer of that many seconds (0:
-- none, untimed), started now and at every round's spawn; its end is a
-- stalemate (TIMER_EVENTS).
function Controller:SetRoundTime(seconds)
	self.roundTime = seconds
	self:StartRoundTimer()
end

function Controller:StartRoundTimer()
	if IsValid(self.roundTimer) then self.roundTimer:Remove() end
	self.roundTimer = NULL
	if self.roundTime > 0 then self.roundTimer = self:CreateTimer(nil, self.roundTime) end
end

-- A game begun on a map without rounds (foundation.gamemode's loadRounds):
-- its tf_gamerules, as a map with an objective gets one, and the base mode,
-- untimed, played to the round limits. The gamemode keeps the rounds halted
-- until the game begins (StartAtLoad, which SetUpMap calls when it runs
-- after this; called now when it already ran).
function Controller:EnsureRules()
	if Active() then return end
	MakeProxy()
	if self.mapSetUp then WS.Feature("gamemode"):StartAtLoad() end
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

-- mp_forcewin red|blue|sudden (TF2's): a team wins the round as if it had
-- (a win that ends the match is the match win), or the running round goes
-- to sudden death, called by the Administrator. Admins only.
local FORCE_WIN_OPTIONS = { "red", "blue", "sudden" }

concommand.Add("mp_forcewin", function(ply, _, args)
	local function Reply(text)
		if IsValid(ply) then ply:ChatPrint(text) else print(text) end
	end
	if IsValid(ply) and not ply:IsAdmin() then return Reply("mp_forcewin: only admins may force a win") end
	local target = Rounds.ForceWinTarget(args[1] or "")
	if not target then return Reply("usage: mp_forcewin " .. table.concat(FORCE_WIN_OPTIONS, "|")) end
	if not Active() then return Reply("mp_forcewin: this map has no rounds") end
	if target == Rounds.FORCE_SUDDEN_DEATH then
		if Controller.round:State() ~= S.RND_RUNNING then return Reply("mp_forcewin: no round is running") end
		Controller:Apply(Controller.round:SuddenDeath(CurTime(), Rounds.STALEMATE.ADMIN))
		return
	end
	Controller:SetWinningTeam(target, Rounds.WINREASON.NONE, true, false, false)
end, function(cmd)
	local options = {}
	for i, option in ipairs(FORCE_WIN_OPTIONS) do options[i] = cmd .. " " .. option end
	return options
end, "Force the round's end: mp_forcewin red, blue or sudden (sudden death); admins only")

return Controller
