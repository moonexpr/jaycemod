-- The rounds feature's controller. It owns the foundation.rounds Round (the
-- gamerules state machine), a foundation.rounds.timer Timer per
-- team_round_timer, the timer shown in the HUD, the gamerules proxy
-- (tf_gamerules), the mode, the round listeners, the timer holds, the team
-- clocks and the objective port. It feeds the models engine time and a
-- snapshot of the players, and carries out their effects: outputs, the map
-- cleanup, respawns, sounds and the ws_round_* and ws_timer_*
-- keys. It decides nothing itself.
--
-- This root declares the controller's state, the proxy, the mode, the round
-- state, thinking and the map's setup, and runs its parts: sv_players (the
-- players and their teams), sv_timers (timers, team clocks and the round
-- limits), sv_effects (sounds, logic_auto and the model's effects) and
-- sv_gamerules (the surface tf_gamerules forwards, and its inputs).
--
-- Loaded by tf_gamerules, team_round_timer, game_round_win and
-- tf_logic_competitive, and by every objective feature (capture, koth,
-- payload). On a map with an objective entity and no tf_gamerules it makes
-- one, as CTFGameRules::CreateStandardEntities does, so the rounds run and
-- outputs aimed at the name tf_gamerules reach it.
local Rounds = WS.require("foundation.rounds")
local ControlPoints = WS.require("foundation.rounds.control_points")
local Limits = WS.require("foundation.rounds.limits")

local S = WS.STATE
local UNASSIGNED = WS.TEAM_UNASSIGNED
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
-- Sandcastle's tie-breaker for a match (foundation.rounds' Deathmatch), as
-- sudden death is for a stalemated round: a round of frags alone.
local deathmatchEnable = ConVarOrCreate("mp_deathmatch_enable", "1", FCVAR_NOTIFY,
	"1: a tied match goes to a deathmatch round, won by the first team to mp_round_fraglimit frags")
local stalemateTimelimit = ConVarOrCreate("mp_stalemate_timelimit", "240", FCVAR_REPLICATED, "Timelimit (in seconds) of the stalemate round.")
local scrambleAuto = ConVarOrCreate("mp_scrambleteams_auto", "1", FCVAR_NOTIFY,
	"Server will automatically scramble the teams if criteria met.  Only works on dedicated servers.")
local scrambleWinDifference = ConVarOrCreate("mp_scrambleteams_auto_windifference", "2", FCVAR_NOTIFY,
	"Number of round wins a team must lead by in order to trigger an auto scramble.", 0)
local winlimit = ConVarOrCreate("mp_winlimit", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "Max score one team can reach before server changes maps", 0)
local maxrounds = ConVarOrCreate("mp_maxrounds", "0", { FCVAR_REPLICATED, FCVAR_NOTIFY }, "max number of rounds to play before server changes maps", 0)
local timelimit = ConVarOrCreate("mp_timelimit", "30", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "game time per map in minutes")
-- GMod defines mp_timelimit itself, at 0 (no limit); Sandcastle's default
-- is DEFAULT_TIMELIMIT minutes, taken while the server leaves it at GMod's.
local DEFAULT_TIMELIMIT = 30
if timelimit:GetString() == timelimit:GetDefault() and timelimit:GetDefault() ~= tostring(DEFAULT_TIMELIMIT) then
	RunConsoleCommand("mp_timelimit", tostring(DEFAULT_TIMELIMIT))
end
-- Sandcastle ends every map at mp_timelimit (TF2 waits for the round on its
-- own maps, which call SetStalemateOnTimelimit when they want otherwise):
-- the leader wins, a tie is sudden death or, with mp_stalemate_enable 0,
-- the stalemate's bonus time, then the next map.
local matchEndAtTimelimit = ConVarOrCreate("mp_match_end_at_timelimit", "1", FCVAR_NOTIFY, "Allow the match to end when mp_timelimit hits instead of waiting for the end of the current round.")
local chattime = ConVarOrCreate("mp_chattime", "10", FCVAR_REPLICATED, "amount of time players can chat after the game is over", 1, 120)
-- teamplay_round_timer.cpp
local overtimeNag = ConVarOrCreate("tf_overtime_nag", "0", FCVAR_NOTIFY, "Announcer overtime nag.")

local PROXY_CLASS = "tf_gamerules"
local MASTER_CLASS = "team_control_point_master"
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
local THINK_HOOK = "ws_rounds"

local function Settings()
	return {
		respawnWaveTime = respawnwavetime:GetFloat(),
		bonusRoundTime = bonusroundtime:GetInt(),
		enableRoundWaitTime = enableroundwaittime:GetFloat(),
		stalemateEnable = stalemateEnable:GetBool(),
		deathmatchEnable = deathmatchEnable:GetBool(),
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
	timeLimitTimer = NULL, -- mp_timelimit's own, on a map without a timer (CreateTimeLimitTimer)
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

-- TF2 reads the match's limits live: a change mid-match moves its end, and
-- the time limit timer with it (HandleTimeLimitChange).
for _, name in ipairs({ "mp_winlimit", "mp_maxrounds", "mp_timelimit" }) do
	cvars.AddChangeCallback(name, function()
		Controller.round:SetLimits({
			winlimit = winlimit:GetInt(),
			maxrounds = maxrounds:GetInt(),
			timelimit = timelimit:GetInt(),
		})
		PublishLimits()
		if name == "mp_timelimit" and Active() then
			local now = CurTime()
			Controller:Apply(Controller.round:TimeLimitTimer(now, Controller:World(now)))
		end
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

-- Parts ------------------------------------------------------------------------------

local Part = WS.FeatureParts(getfenv(1), "rounds")
local Players = Part("sv_players", GAME_TEAMS)
local HavePlayers, TeamLife, Scores = Players.HavePlayers, Players.TeamLife, Players.Scores
local RoundWon, PublishOvertime, TIMELIMIT_TIMER_NAME = Part("sv_timers", Controller, Active, GAME_TEAMS)
Part("sv_effects", Controller, Players, PublishLimits, PublishOvertime, TIMELIMIT_TIMER_NAME, PROXY_CLASS)
Part("sv_gamerules", Controller, Players)

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

-- Thinking ----------------------------------------------------------------------------

-- This round's flag captures, as the flag feature publishes its tally
-- (none on a map without flags).
local function Captures()
	return {
		[RED] = GetGlobal2Int("ws_flag_caps_" .. RED, 0),
		[BLUE] = GetGlobal2Int("ws_flag_caps_" .. BLUE, 0),
	}
end

function Controller:World(now)
	local stalemateTimer = self.stalemateTimer
	return {
		havePlayers = HavePlayers(),
		teams = TeamLife(),
		scores = Scores(),
		captures = Captures(),
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
	if not WS.Can(ply, WS.require("foundation.permissions").MATCH) then return Reply("mp_forcewin: you may not force a win") end
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
