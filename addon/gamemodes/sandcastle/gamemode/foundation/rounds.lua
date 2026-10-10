-- The rounds system: TF2's round-based gamerules as a stateful model. A
-- Round is CTeamplayRoundBasedRules' state machine (teamplayroundbased_
-- gamerules.cpp) with the parts of CTFGameRules (tf_gamerules.cpp) that drive
-- it: wins, sudden death, the win, round and time limits, respawn waves,
-- setup and overtime, TimerMayExpire and the played-round history.
--
-- The game's variations are Mode strategies (Mode:Extend(name) plus
-- overrides), chosen by map entities: control points, koth and payload are
-- parts of their own (foundation.rounds.control_points, .koth, .payload).
--
-- Nothing here touches the engine. Time comes in as `now`, the world as a
-- snapshot, and every method that changes the game returns a list of
-- effects, plain tables { kind = ..., ... }, for the rounds controller to
-- carry out in order.
local ipairs, math, pairs, setmetatable, tostring = ipairs, math, pairs, setmetatable, tostring
local Teams = require("foundation.teams")
local State = require("foundation.rounds.state")
module(...)

-- teamplayroundbased_gamerules.h
WINREASON = {
	NONE = 0,
	ALL_POINTS_CAPTURED = 1,
	OPPONENTS_DEAD = 2,
	FLAG_CAPTURE_LIMIT = 3,
	DEFEND_UNTIL_TIME_LIMIT = 4,
	STALEMATE = 5,
	TIMELIMIT = 6,
	WINLIMIT = 7,
	WINDIFFLIMIT = 8,
}
STALEMATE = {
	JOIN_MID = 0,
	TIMER = 1,
	SERVER_TIMELIMIT = 2,
	MATCH_TIED = 3, -- a limit ended the match on a tied score
	ADMIN = 4, -- the Administrator called it (mp_forcewin)
}

-- mp_forcewin's argument: RED ("red", "2"), BLUE ("blue", "blu", "3") or
-- FORCE_SUDDEN_DEATH ("sudden", "0"), whatever the case; nil for anything
-- else.
FORCE_SUDDEN_DEATH = "sudden_death"
local FORCE_TARGETS = {
	red = Teams.RED, ["2"] = Teams.RED,
	blue = Teams.BLUE, blu = Teams.BLUE, ["3"] = Teams.BLUE,
	sudden = FORCE_SUDDEN_DEATH, ["0"] = FORCE_SUDDEN_DEATH,
}

function ForceWinTarget(text)
	return FORCE_TARGETS[text:lower()]
end

local UNASSIGNED, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local FIRST_GAME_TEAM = Teams.FIRST_GAME_TEAM
local GAME_TEAMS = { RED, BLUE }

-- restrict_team_cap_win's "Neither" (team_control_point_round.cpp): TEAM_SPECTATOR,
-- which no playing team is, so every team may win the round.
RESTRICT_NEITHER = Teams.SPECTATOR

-- What the client draws for the mode (wetsand_round_hud_type).
HUD_NONE = 0
HUD_CONTROL_POINTS = 1
HUD_KOTH = 2
HUD_PAYLOAD = 3

-- The round phases other features listen to, and the listener order, which
-- reproduces TF2's RoundSpawn/RoundActivate order: timers, then the master
-- and points, then logic entities.
PHASE_SPAWN = "spawn"
PHASE_ACTIVATE = "activate"
PHASE_ROUND_END = "round_end"
-- The arena round starts (SetupOnStalemateStart's arena branch).
PHASE_ARENA_START = "arena_start"
LISTEN_TIMERS = 10
LISTEN_CAPTURE = 20
LISTEN_LOGIC = 30

-- The pre-round lasts this many seconds times mp_enableroundwaittime. TF2's
-- State_Enter_PREROUND uses 5; Sandcastle uses 3.
PREROUND_SECONDS = 3
-- GetMinTimeWhenPlayerMaySpawn: 2 s death animation plus the freezecam's
-- spec_freeze_traveltime (0.4) and spec_freeze_time (4).
DEATH_ANIM_LENGTH = 2.0 + 0.4 + 4.0
-- GetRespawnTimeScalar: teams this big wait the whole wave.
OPTIMAL_TEAM_SIZE = 8
local MIN_WAVE_SCALE, MAX_WAVE_SCALE = 0.25, 1.0
-- CTFGameRules::GetRespawnWaveMaxLength: small teams never shorten a wave below this.
MIN_SCALED_WAVE = 5
-- m_TeamRespawnWaveTimes before a map input sets one.
WAVE_TIME_UNSET = -1
-- CTFGameRules::TimerMayExpire's m_flCapInProgressBuffer.
CAP_IN_PROGRESS_BUFFER = 0.1
-- State_Enter_TEAM_WIN: the bonus time is never shorter than this.
MIN_BONUS_ROUND_TIME = 5
-- CTeamplayRoundBasedRules::Think's once-a-second checks.
PERIODIC_INTERVAL = 1
-- A stopped game (Halt) has no waves: the dead come back after this long.
HALT_RESPAWN = 3
-- CheckTimeLimit: with a time limit over this, under this much left ends the map now.
local SWITCH_MINUTES = 5
local SECONDS_PER_MINUTE = 60

-- The objective port the capture controller implements (the map's
-- control point master). Methods are called with ':'.
OBJECTIVE_METHODS = {
	"PlayingMiniRounds",
	"NumPlayable",
	"PlayAllRounds",
	"RoundsRemaining",
	"ScorePerRound",
	"SuddenDeathWin",
}

-- A map without a master: no mini-rounds, scoring per round, and sudden
-- death ending with SetWinningTeam (no SuddenDeathWin).
NO_OBJECTIVE = {}
function NO_OBJECTIVE:PlayingMiniRounds() return false end
function NO_OBJECTIVE:NumPlayable() return 0 end
function NO_OBJECTIVE:PlayAllRounds() return false end
function NO_OBJECTIVE:RoundsRemaining(team) return 0 end
function NO_OBJECTIVE:ScorePerRound() return true end

-- Pure rules ------------------------------------------------------------------------

-- State_Think_STALEMATE: teams[t] = { players, alive, soldiers }. A team
-- with no live player (or no players) and no live soldier (the AI war's; nil
-- for none) is dead. Returns the surviving team when exactly one side is
-- dead, and whether everyone is dead.
function StalemateOutcome(teams)
	local dead, alive
	for _, t in ipairs(GAME_TEAMS) do
		local side = teams[t]
		if (side.players > 0 and side.alive > 0) or (side.soldiers or 0) > 0 then alive = t else dead = t end
	end
	if dead and alive then return alive, false end
	return nil, dead ~= nil and alive == nil
end

-- The respawn wave length a team gets: an admin's override (the Game Rules
-- editor), else the map's (SetRed/BlueTeamRespawnWaveTime), else
-- mp_respawnwavetime. A negative value is unset.
function WaveTime(override, mapTime, default)
	if override >= 0 then return override end
	if mapTime >= 0 then return mapTime end
	return default
end

-- CTeamplayRoundBasedRules::GetTimeLeft
function TimeLeft(mapResetTime, timelimitMinutes, now)
	return math.max(0, math.floor(mapResetTime + timelimitMinutes * SECONDS_PER_MINUTE - now))
end

-- The match's winner as it ends: the team with the higher score, or
-- NOBODY_WON on a tie (or no scores).
NOBODY_WON = UNASSIGNED

function MatchWinner(scores)
	local red, blue = scores[RED] or 0, scores[BLUE] or 0
	if red > blue then return RED end
	if blue > red then return BLUE end
	return NOBODY_WON
end

-- The level the match ends into: TF2's nextlevel when set, else the map
-- cycle's next (GMod's game.GetMapNext), else the current map again; a map
-- not installed (exists(map) false) is skipped.
function NextMap(nextlevel, cycleNext, current, exists)
	if nextlevel ~= "" and exists(nextlevel) then return nextlevel end
	if cycleNext ~= "" and exists(cycleNext) then return cycleNext end
	return current
end

-- CheckWinLimit
function WinLimitReached(winlimit, scores)
	if winlimit <= 0 then return false end
	return scores[RED] >= winlimit or scores[BLUE] >= winlimit
end

-- CheckMaxRounds
function MaxRoundsReached(maxrounds, roundsPlayed)
	return maxrounds > 0 and roundsPlayed >= maxrounds
end

-- CTFGameRules::CanChangelevelBecauseOfTimeLimit: maps like Dustbowl play all
-- their mini-rounds before the time limit may change the level.
function CanChangeLevelForTimeLimit(forceMapReset, playingMiniRounds, playAllRounds, playable)
	return not (not forceMapReset and playingMiniRounds and playAllRounds and playable > 0)
end

-- CheckTimeLimit: c = { timelimit (minutes), timeLeft, canChange, afterStalemate }.
-- Under five minutes left the level changes now, so sudden death never starts
-- just after a new round.
function TimeLimitReached(c)
	if not ((c.timelimit > 0 and c.canChange) or c.afterStalemate) then return false end
	local switchDueToTime = c.timelimit > SWITCH_MINUTES and c.timeLeft < SWITCH_MINUTES * SECONDS_PER_MINUTE
	return c.timeLeft <= 0 or c.afterStalemate == true or switchDueToTime
end

-- State_Think_RND_RUNNING at the time limit: the higher score, nobody when drawn.
function TimelimitWinner(scores)
	if scores[RED] == scores[BLUE] then return UNASSIGNED end
	return scores[BLUE] > scores[RED] and BLUE or RED
end

-- SetWinningTeam: a round win scores for a full round, or at the time limit.
function ShouldRewardTeam(forceMapReset, timelimit, timeLeft, dontAddScore)
	if dontAddScore then return false end
	return forceMapReset or (timelimit > 0 and timeLeft <= 0)
end

-- CTeamplayRoundBasedRules::AddPlayedRound: remember the last two.
function AddPlayedRound(previous, name)
	local list = { name, previous[1] }
	return list
end

-- A stopped game's dead come back HALT_RESPAWN seconds after dying.
function HaltedRespawnDue(since, now)
	return now - since >= HALT_RESPAWN
end

-- GetRespawnTimeScalar: a quarter of the wave for one player, all of it
-- for OPTIMAL_TEAM_SIZE.
local function RespawnTimeScalar(teamSize)
	local n = math.min(math.max(teamSize, 1), OPTIMAL_TEAM_SIZE)
	return MIN_WAVE_SCALE + (n - 1) / (OPTIMAL_TEAM_SIZE - 1) * (MAX_WAVE_SCALE - MIN_WAVE_SCALE)
end

-- Mode: the strategy a game type fills in ---------------------------------------------

Mode = {
	NAME = "none",
	PRIORITY = 0,
	HUD = HUD_NONE,
	CREATES_TIME_LIMIT_TIMER = true,
	ANNOUNCES_TIME_ADDED = true,
	-- Hud.EndRoundScored to everyone, else to the capping team.
	SCORE_CHIME_TO_ALL = false,
	-- The state the pre-round ends in: the round is fought there.
	ROUND_STATE = State.RND_RUNNING,
	-- Whether STALEMATE is the round itself (arena) rather than sudden death:
	-- entering it respawns nobody and hides no timer, and its end rewards no
	-- survivors.
	STALEMATE_IS_ROUND = false,
	-- mp_scrambleteams_auto applies.
	AUTO_SCRAMBLE = true,
}
Mode.__index = Mode

-- A variant named `name`, inheriting every member it does not override.
function Mode:Extend(name)
	local mode = setmetatable({}, self)
	mode.__index = mode
	mode.NAME = name
	return mode
end

-- Whether a team owning every point wins now. q = { clockRemaining = the
-- team's clock or nil, timerMayExpire }.
function Mode:MayWinByPoints(team, q) return true end

-- CTFGameRules::PlaySpecialCapSounds: { { team, sound }... }.
-- q = { wouldWinGame, scorePerRound }.
function Mode:CapSounds(capTeam, q) return {} end

-- Lines each team hears as the round ends, { [team] = sound }.
function Mode:RoundWinLines(winner, fullRound, race) return {} end

-- State_Enter_PREROUND: the pre-round's length.
function Mode:PreroundSeconds(settings)
	return PREROUND_SECONDS * settings.enableRoundWaitTime
end

-- State_Enter_STALEMATE: its timer's length, none for 0 or less.
function Mode:StalemateSeconds(settings)
	return settings.stalemateTimelimit
end

-- Round ------------------------------------------------------------------------------

local Round = {}
Round.__index = Round

local function Add(effects, e)
	effects[#effects + 1] = e
	return effects
end

local function Output(name, value)
	return {
		kind = "output",
		name = name,
		value = value,
	}
end

local function Hook(name, args)
	return {
		kind = "hook",
		name = name,
		args = args,
	}
end

local function Kind(kind)
	return { kind = kind }
end

local function PerTeam(value)
	return {
		[RED] = value,
		[BLUE] = value,
	}
end

-- settings = { respawnWaveTime, bonusRoundTime, enableRoundWaitTime,
-- stalemateEnable, stalemateTimelimit, winlimit, maxrounds, timelimit,
-- matchEndAtTimelimit, chattime, scrambleAuto, scrambleWinDifference,
-- mapResetTime }, in TF2's units.
function New(settings)
	local round = setmetatable({
		settings = {},
		mode = Mode,
		state = State.PREGAME,
		transitionAt = nil,
		halted = false,
		forceMapReset = true,
		mapFresh = true,
		switchTeams = false,
		scrambleTeams = false,
		winningTeam = UNASSIGNED,
		winReason = WINREASON.NONE,
		roundsPlayed = 0,
		scores = PerTeam(0), -- the latest the world gave (Think), for a win's outcome
		previousRounds = {},
		firstRound = nil,
		allowStalemateAtTimelimit = false,
		changelevelAfterStalemate = false,
		intermissionEnd = nil,
		intermissionFreeze = nil,
		nextPeriodic = 0,
		teamCounts = PerTeam(0),
		inSetup = false,
		overtime = false,
		capBuffer = 0,
		waveTime = PerTeam(WAVE_TIME_UNSET),
		originalWaveTime = PerTeam(WAVE_TIME_UNSET),
		adminWaveTime = PerTeam(WAVE_TIME_UNSET),
		nextWave = PerTeam(0),
		respawnsDisabled = false,
		capEnableAt = nil, -- CTFGameRules's m_flCapturePointEnableTime (arena), or nil
	}, Round)
	round:Configure(settings)
	return round
end

-- The controller refreshes the convars each think; given fields replace the old.
function Round:Configure(settings)
	for k, v in pairs(settings) do self.settings[k] = v end
end

-- Keeps the higher PRIORITY, as CTFGameRules::Activate settles the game type.
function Round:SetMode(mode)
	if mode.PRIORITY <= self.mode.PRIORITY then return false end
	self.mode = mode
	return true
end

function Round:Mode() return self.mode end
function Round:State() return self.state end
function Round:Halted() return self.halted end
function Round:InSetup() return self.inSetup end
function Round:InOvertime() return self.overtime end
function Round:PreroundEnd() return self.transitionAt end
function Round:Winner() return self.winningTeam end
function Round:ForceMapReset() return self.forceMapReset end

function Round:TimeLeft(now)
	return TimeLeft(self.settings.mapResetTime, self.settings.timelimit, now)
end

-- State machine (State_Transition, State_Enter, State_Leave, State_Think) ---------

local ENTER, LEAVE, THINK = {}, {}, {}

-- State_Enter: world is the snapshot of the Think that brought it, if any.
local function Enter(self, effects, state, now, world)
	local from = self.state
	self.state = state
	self.transitionAt = nil
	local change = {
		kind = "state",
		from = from,
		to = state,
	}
	Add(effects, change)
	if ENTER[state] then ENTER[state](self, effects, now, world, change) end
	return effects
end

local function Transition(self, effects, state, now, world)
	if LEAVE[self.state] then LEAVE[self.state](self, effects, now) end
	return Enter(self, effects, state, now, world)
end

local function TransitionDue(self, now)
	return self.transitionAt ~= nil and now >= self.transitionAt
end

-- GoToIntermission: the match's winner (MatchWinner) is celebrated for
-- MATCH_WIN_EXTRA, its side hunting the humiliated losers to its music,
-- then everyone is frozen for mp_chattime, then the level changes.
MATCH_WIN_EXTRA = 60

local function GoToIntermission(self, effects, reason, now, world)
	self.intermissionFreeze = now + MATCH_WIN_EXTRA
	self.intermissionEnd = self.intermissionFreeze + self.settings.chattime
	Add(effects, {
		kind = "intermission",
		reason = reason,
		winner = MatchWinner(world.scores),
		["until"] = self.intermissionEnd,
	})
	return Enter(self, effects, State.GAME_OVER, now)
end

-- Sudden death whatever mp_stalemate_enable says (a tied match, an admin).
local function ForcedSuddenDeath(self, effects, now, reason)
	self.forceMapReset = true
	self.winningTeam = UNASSIGNED
	Add(effects, {
		kind = "sudden_death",
		reason = reason,
	})
	return Transition(self, effects, State.STALEMATE, now)
end

local function MatchSuddenDeath(self, effects, now)
	self.suddenDeathMatch = false
	return ForcedSuddenDeath(self, effects, now, STALEMATE.MATCH_TIED)
end

-- A limit ended the match: its intermission, or on a tied score sudden death
-- (MATCH_TIED), now while a round runs, else in the next round
-- (suddenDeathMatch, which RND_RUNNING's think takes up). True when the
-- match ended or went to sudden death now; false lets the round go on.
local function EndMatch(self, effects, reason, now, world)
	if MatchWinner(world.scores) ~= NOBODY_WON then
		GoToIntermission(self, effects, reason, now, world)
		return true
	end
	if self.state == State.RND_RUNNING then
		MatchSuddenDeath(self, effects, now)
		return true
	end
	self.suddenDeathMatch = true
	return false
end

local function CheckWinLimit(self, effects, now, world)
	if not WinLimitReached(self.settings.winlimit, world.scores) then return false end
	return EndMatch(self, effects, "Reached Win Limit", now, world)
end

local function CheckMaxRounds(self, effects, now, world)
	if not MaxRoundsReached(self.settings.maxrounds, self.roundsPlayed) then return false end
	return EndMatch(self, effects, "Reached Round Limit", now, world)
end

local function CheckTimeLimit(self, effects, now, world)
	local objective = world.objective
	local mini = objective:PlayingMiniRounds()
	local canChange = CanChangeLevelForTimeLimit(self.forceMapReset, mini,
		mini and objective:PlayAllRounds(), mini and objective:NumPlayable() or 0)
	local reached = TimeLimitReached({
		timelimit = self.settings.timelimit,
		timeLeft = self:TimeLeft(now),
		canChange = canChange,
		afterStalemate = self.changelevelAfterStalemate,
	})
	if not reached then return false end
	return EndMatch(self, effects, "Reached Time Limit", now, world)
end

-- CTFGameRules::SetupOnRoundStart: overtime ends and every entity hears
-- RoundSpawn, then RoundActivate.
local function SetupOnRoundStart(self, effects)
	if self:SetOvertime(false) then
		Add(effects, {
			kind = "overtime",
			value = false,
		})
	end
	Add(effects, Kind("round_spawn"))
	Add(effects, Kind("round_activate"))
end

-- CTeamplayRoundBasedRules::RoundRespawn (with CTFGameRules's). A full reset
-- cleans the map up (not the first round's fresh map), forgets the played
-- rounds and fires every logic_auto's OnMultiNewRound, as TF2's logic_autos
-- do when recreated in a round restart (CLogicAuto::Think, InRoundRestart);
-- a mini-round keeps the map as it is, less the last stage's gore.
local function RoundRespawn(self, effects, now, world)
	self.winningTeam = UNASSIGNED
	self.capEnableAt = nil
	local full = self.forceMapReset
	if full then
		if not self.mapFresh then Add(effects, Kind("cleanup")) end
		self.mapFresh = false
		self.previousRounds = {}
		Add(effects, Kind("activate_timers"))
		-- CTFGameRules::CreateTimeLimitTimer: only when the time limit ends the round.
		local settings = self.settings
		if settings.timelimit > 0 and self:TimeLeft(now) > 0 and not world.mapHasActiveTimer
			and self.mode.CREATES_TIME_LIMIT_TIMER
			and (self.allowStalemateAtTimelimit or settings.matchEndAtTimelimit) then
			Add(effects, {
				kind = "time_limit_timer",
				seconds = self:TimeLeft(now),
			})
		end
	else
		-- the kept map loses the last stage's bodies and blood, as a cleanup would
		Add(effects, Kind("clear_gore"))
	end
	for _, t in ipairs(GAME_TEAMS) do
		if self.originalWaveTime[t] >= 0 then self.waveTime[t] = self.originalWaveTime[t] end
	end
	SetupOnRoundStart(self, effects)
	if full then Add(effects, Kind("new_round_outputs")) end
	-- a scramble due (mp_scrambleteams_auto) takes the switch's place
	if self.scrambleTeams then
		Add(effects, Kind("scramble_teams"))
	elseif self.switchTeams then
		Add(effects, Kind("switch_teams"))
	end
	self.scrambleTeams, self.switchTeams = false, false
	Add(effects, Kind("respawn_all"))
end

-- CheckRespawnWaves: each team's wave, when due, brings back its dead.
local function CheckRespawnWaves(self, effects, now, world)
	for _, t in ipairs(GAME_TEAMS) do
		if self:WaveDue(t, now, world.teams[t].players) and not self.respawnsDisabled then
			Add(effects, {
				kind = "respawn_team",
				team = t,
			})
		end
	end
end

-- With SetStalemateOnTimelimit (or mp_match_end_at_timelimit) the time limit
-- ends the round: the higher score wins, a tie goes to sudden death.
local function CheckTimelimitStalemate(self, effects, now, world)
	if self.settings.timelimit <= 0 or self:TimeLeft(now) > 0 then return end
	if not (self.allowStalemateAtTimelimit or self.settings.matchEndAtTimelimit) then return end
	local winner = TimelimitWinner(world.scores)
	if winner == UNASSIGNED then
		self.changelevelAfterStalemate = true
		for _, e in ipairs(self:SetStalemate(now, STALEMATE.SERVER_TIMELIMIT, self.forceMapReset)) do Add(effects, e) end
	else
		for _, e in ipairs(self:SetWinningTeam(now, winner, WINREASON.TIMELIMIT, true, false, true, world.objective)) do
			Add(effects, e)
		end
	end
end

-- PREGAME

THINK[State.PREGAME] = function(self, effects, now, world)
	if world.havePlayers then Transition(self, effects, State.PREROUND, now, world) end
end

-- PREROUND: CTFGameRules::PreRound_Start fires the proxy's output, then every
-- tf_logic_competitive's OnSpawnRoomDoorsShouldLock.

ENTER[State.PREROUND] = function(self, effects, now, world, change)
	Add(effects, Kind("balance_teams"))
	RoundRespawn(self, effects, now, world)
	self.transitionAt = now + self.mode:PreroundSeconds(self.settings)
	change.preroundEnd = self.transitionAt
	Add(effects, Output("OnStateEnterPreRound"))
	Add(effects, Kind("doors_lock"))
end

THINK[State.PREROUND] = function(self, effects, now, world)
	if TransitionDue(self, now) then
		Transition(self, effects, self.mode.ROUND_STATE, now, world)
		return
	end
	CheckRespawnWaves(self, effects, now, world)
end

-- PreRound_End: the proxy's output, then the doors unlock.
LEAVE[State.PREROUND] = function(self, effects)
	Add(effects, Output("OnStateExitPreRound"))
	Add(effects, Kind("doors_unlock"))
end

-- RND_RUNNING: State_Enter_RND_RUNNING and CTFGameRules::SetupOnRoundRunning.

ENTER[State.RND_RUNNING] = function(self, effects)
	self.nextWave = PerTeam(0)
	Add(effects, Output("OnStateEnterRoundRunning"))
	Add(effects, Hook("WetsandRoundActive", {}))
end

THINK[State.RND_RUNNING] = function(self, effects, now, world)
	if not world.havePlayers then
		self.forceMapReset = true
		Transition(self, effects, State.PREGAME, now, world)
		return
	end
	-- the round after a tied match's end is played as sudden death
	if self.suddenDeathMatch then
		MatchSuddenDeath(self, effects, now)
		return
	end
	CheckRespawnWaves(self, effects, now, world)
	CheckTimelimitStalemate(self, effects, now, world)
end

-- TEAM_WIN (the humiliation)

ENTER[State.TEAM_WIN] = function(self, effects, now)
	if self.forceMapReset then self.roundsPlayed = self.roundsPlayed + 1 end
	self.transitionAt = now + math.max(MIN_BONUS_ROUND_TIME, self.settings.bonusRoundTime)
	Add(effects, Hook("WetsandRoundWin", { self.winningTeam, self.winReason }))
end

THINK[State.TEAM_WIN] = function(self, effects, now, world)
	if not TransitionDue(self, now) then return end
	if CheckTimeLimit(self, effects, now, world) or CheckWinLimit(self, effects, now, world)
		or CheckMaxRounds(self, effects, now, world) then
		return
	end
	-- CTFGameRules::PreviousRoundEnd: the mini-round's OnEnd.
	Add(effects, Kind("previous_round_end"))
	Transition(self, effects, State.PREROUND, now, world)
end

-- Sudden death over (sudden_death_over), whoever won it: its survivors are
-- rewarded and the dead come back, to enjoy the victory or the humiliation.
-- The reward: TF2's full overheal, half again a survivor's most health.
SURVIVOR_OVERHEAL = 1.5

function SurvivorHealth(maxHealth, health)
	return math.max(health, math.floor(maxHealth * SURVIVOR_OVERHEAL))
end
--
-- STALEMATE (sudden death): State_Enter_STALEMATE and
-- CTFGameRules::SetupOnStalemateStart: everyone respawns once, the map's
-- timer hides, and a stalemate timer of mp_stalemate_timelimit seconds shows
-- instead. Nobody respawns after that. Where STALEMATE is the round (arena)
-- nobody respawns and the map's timers stay: the round starts
-- (arena_round_start: OnArenaRoundStart and the cap-enable time) and runs.

ENTER[State.STALEMATE] = function(self, effects)
	if self.mode.STALEMATE_IS_ROUND then
		Add(effects, Kind("arena_round_start"))
		Add(effects, Hook("WetsandRoundActive", {}))
	else
		Add(effects, Kind("respawn_all"))
		Add(effects, Kind("hide_timers"))
	end
	local seconds = self.mode:StalemateSeconds(self.settings)
	if seconds > 0 then
		Add(effects, {
			kind = "stalemate_timer",
			seconds = seconds,
		})
	end
end

LEAVE[State.STALEMATE] = function(self, effects)
	if not self.mode.STALEMATE_IS_ROUND then Add(effects, Kind("restore_timers")) end
end

THINK[State.STALEMATE] = function(self, effects, now, world)
	if not world.havePlayers then
		self.forceMapReset = true
		Transition(self, effects, State.PREGAME, now, world)
		return
	end
	local winner, allDead = StalemateOutcome(world.teams)
	local suddenDeath = not self.mode.STALEMATE_IS_ROUND
	if winner then
		-- Without a full reset the survivors take the round's points.
		if suddenDeath then Add(effects, Kind("sudden_death_over")) end
		Add(effects, {
			kind = "stalemate_winner",
			team = winner,
			forceMapReset = self.forceMapReset,
		})
		return
	end
	local left = world.stalemateTimerLeft
	local timerOut = left ~= nil and world.timerMayExpire and left <= 0
	if allDead or timerOut then
		if suddenDeath then Add(effects, Kind("sudden_death_over")) end
		local objective = world.objective
		for _, e in ipairs(self:SetWinningTeam(now, UNASSIGNED, WINREASON.STALEMATE,
			not objective:PlayingMiniRounds(), false, false, objective)) do
			Add(effects, e)
		end
	end
end

-- BETWEEN_RNDS: CTFGameRules::BetweenRounds_Start.

ENTER[State.BETWEEN_RNDS] = function(self, effects)
	Add(effects, Output("OnStateEnterBetweenRounds"))
	Add(effects, Kind("doors_unlock"))
end

-- GAME_OVER

THINK[State.GAME_OVER] = function(self, effects, now)
	if self.intermissionFreeze and now >= self.intermissionFreeze then
		self.intermissionFreeze = nil
		Add(effects, Kind("freeze"))
	end
	if self.intermissionEnd and now >= self.intermissionEnd then
		self.intermissionEnd = nil
		Add(effects, Kind("changelevel"))
	end
end

-- Team1PlayersChanged / Team2PlayersChanged (CTFGameRulesProxy::TeamPlayerCountChanged).
local COUNT_OUTPUT = {
	[RED] = "Team1PlayersChanged",
	[BLUE] = "Team2PlayersChanged",
}

-- CTeamplayRoundBasedRules::Think's once-a-second checks.
local function PeriodicThink(self, effects, now, world)
	if self.state ~= State.TEAM_WIN and self.state ~= State.STALEMATE then
		if CheckWinLimit(self, effects, now, world) or CheckMaxRounds(self, effects, now, world) then return end
	end
	for _, t in ipairs(GAME_TEAMS) do
		local n = world.teams[t].players
		if self.teamCounts[t] ~= n then
			self.teamCounts[t] = n
			Add(effects, Output(COUNT_OUTPUT[t], tostring(n)))
		end
	end
end

-- world = { havePlayers, teams = { [team] = { players, alive } }, scores,
-- stalemateTimerLeft = n or nil, timerMayExpire, mapHasActiveTimer, objective }.
function Round:Think(now, world)
	local effects = {}
	self.scores = world.scores
	if self.halted then return effects end
	if THINK[self.state] then THINK[self.state](self, effects, now, world) end
	if self.state ~= State.GAME_OVER and now > self.nextPeriodic then
		PeriodicThink(self, effects, now, world)
		self.nextPeriodic = now + PERIODIC_INTERVAL
	end
	return effects
end

-- Round control --------------------------------------------------------------------

-- CTeamplayRoundBasedRules::SetWinningTeam.
function Round:SetWinningTeam(now, winner, reason, forceMapReset, switchTeams, dontAddScore, objective)
	local effects = {}
	if self.halted or self.state == State.TEAM_WIN or self.state == State.GAME_OVER then return effects end
	forceMapReset = forceMapReset ~= false
	self.forceMapReset = forceMapReset
	self.switchTeams = switchTeams == true
	self.winningTeam = winner
	self.winReason = reason
	local reward = ShouldRewardTeam(forceMapReset, self.settings.timelimit, self:TimeLeft(now), dontAddScore == true)
	-- the survivors of sudden death, and a team the Administrator hands the
	-- round (mp_forcewin's WINREASON.NONE), take a point whatever the map
	-- scores by
	local always = self.state == State.STALEMATE or reason == WINREASON.NONE
	local scored = reward and winner ~= UNASSIGNED and (always or objective:ScorePerRound())
	if scored then
		Add(effects, {
			kind = "score",
			team = winner,
			points = 1,
		})
	end
	-- a win that ends the match is the match win at once, in the round win's
	-- place: no round win music or bonus round first
	local scores = { [RED] = self.scores[RED] or 0, [BLUE] = self.scores[BLUE] or 0 }
	if scored then scores[winner] = scores[winner] + 1 end
	local roundsPlayed = self.roundsPlayed + (forceMapReset and 1 or 0)
	local limit = (WinLimitReached(self.settings.winlimit, scores) and "Reached Win Limit")
		or (MaxRoundsReached(self.settings.maxrounds, roundsPlayed) and "Reached Round Limit")
	if limit and MatchWinner(scores) ~= NOBODY_WON then
		self.roundsPlayed = roundsPlayed
		if winner == RED then Add(effects, Output("OnWonByTeam1")) end
		if winner == BLUE then Add(effects, Output("OnWonByTeam2")) end
		GoToIntermission(self, effects, limit, now, { scores = scores })
		return effects
	end
	-- mp_scrambleteams_auto: a full round won to a lead of the win
	-- difference scrambles the next round's teams (scramble_due tells it now)
	if forceMapReset and self.mode.AUTO_SCRAMBLE and self.settings.scrambleAuto and Teams.ScrambleDue(scores, self.settings.scrambleWinDifference) then
		self.scrambleTeams = true
		Add(effects, Kind("scramble_due"))
	end
	Add(effects, {
		kind = "publish_win",
		winner = winner,
		reason = reason,
		fullRound = forceMapReset,
	})
	Transition(self, effects, State.TEAM_WIN, now)
	Add(effects, {
		kind = "win_song",
		winner = winner,
		fullRound = forceMapReset,
	})
	if winner == RED then Add(effects, Output("OnWonByTeam1")) end
	if winner == BLUE then Add(effects, Output("OnWonByTeam2")) end
	return effects
end

-- mp_forcewin's sudden death: the running round goes to sudden death for
-- reason, whatever mp_stalemate_enable says; nothing outside a running round.
function Round:SuddenDeath(now, reason)
	local effects = {}
	if self.halted or self.state ~= State.RND_RUNNING then return effects end
	ForcedSuddenDeath(self, effects, now, reason)
	return effects
end

-- CTeamplayRoundBasedRules::SetStalemate: sudden death when
-- mp_stalemate_enable is on, otherwise a drawn round.
function Round:SetStalemate(now, reason, forceMapReset, switchTeams)
	if self.halted then return {} end
	if not self.settings.stalemateEnable then
		return self:SetWinningTeam(now, UNASSIGNED, WINREASON.STALEMATE, forceMapReset, switchTeams, false, NO_OBJECTIVE)
	end
	local effects = {}
	if self.state == State.STALEMATE then return effects end
	self.forceMapReset = forceMapReset ~= false
	self.winningTeam = UNASSIGNED
	Add(effects, {
		kind = "sudden_death",
		reason = reason,
	})
	return Transition(self, effects, State.STALEMATE, now)
end

-- CTeamplayRoundWin::RoundWin (game_round_win): win = { team, reason,
-- forceMapReset, switchTeams }. Team 0 is a stalemate; only a full-reset win
-- switches teams.
function Round:GameRoundWin(now, win, objective)
	if win.team >= FIRST_GAME_TEAM then
		return self:SetWinningTeam(now, win.team, win.reason, win.forceMapReset,
			win.forceMapReset and win.switchTeams, false, objective)
	end
	return self:SetStalemate(now, STALEMATE.TIMER, win.forceMapReset, win.switchTeams)
end

-- Back to PREGAME with a full reset to come: the next pre-round cleans the
-- map up and respawns everyone. Out of the intermission, everyone is let go.
function Round:RestartRound(now)
	local effects = {}
	if self.halted then return effects end
	if self.state == State.GAME_OVER then
		self.intermissionEnd, self.intermissionFreeze = nil, nil
		Add(effects, Kind("unfreeze"))
	end
	self.forceMapReset = true
	self.switchTeams, self.scrambleTeams = false, false
	return Transition(self, effects, State.PREGAME, now)
end

-- Stopping the game (Sandbox mode) is TF2's tournament ready-up: the rounds
-- wait in BETWEEN_RNDS and make no transition at all (no pre-round, win,
-- sudden death or game over, whatever the map or players do) until Unhalt,
-- then RestartRound. A halted map is no longer fresh: halting ends its setup
-- and fires its outputs (a race map's OnSetupFinished disables its own
-- timer), so the next full reset cleans it up even before the first game.
function Round:Halt(now)
	local effects = {}
	if self.state == State.GAME_OVER then
		self.intermissionEnd, self.intermissionFreeze = nil, nil
		Add(effects, Kind("unfreeze"))
	end
	self.halted = true
	self.mapFresh = false
	if self.state ~= State.BETWEEN_RNDS then Transition(self, effects, State.BETWEEN_RNDS, now) end
	return effects
end

function Round:Unhalt()
	self.halted = false
end

function Round:SetStalemateOnTimelimit(on)
	self.allowStalemateAtTimelimit = on
end

-- CTeamplayRoundBasedRules::PointsMayBeCaptured, and in arena
-- CTFGameRules::TeamMayCapturePoint's wait for the cap-enable time.
function Round:PointsMayBeCaptured(now)
	if self.capEnableAt and now < self.capEnableAt then return false end
	return (self.state == State.RND_RUNNING or self.state == State.STALEMATE) and not self.inSetup
end

-- CTFGameRules::SetupOnStalemateStart's m_flCapturePointEnableTime: until
-- `at` no point may be captured. A new round forgets it.
function Round:SetCapEnableTime(at)
	self.capEnableAt = at
end

function Round:CapEnableTime()
	return self.capEnableAt
end

-- SetSetup / SetOvertime: each returns whether it changed.
function Round:SetSetup(on)
	if self.inSetup == on then return false end
	self.inSetup = on
	return true
end

function Round:SetOvertime(on)
	if self.overtime == on then return false end
	self.overtime = on
	return true
end

-- CTFGameRules::TimerMayExpire. holds = { capturing, other }: a capture in
-- progress holds the clock and for CAP_IN_PROGRESS_BUFFER after ("an
-- order-of-operations issue with caps that fire an AddTime output"); a cp
-- timer or a train watcher holds it only while it does.
function Round:TimerMayExpire(now, holds)
	if holds.capturing then
		self.capBuffer = now + CAP_IN_PROGRESS_BUFFER
		return false
	end
	if self.capBuffer >= now then return false end
	return not holds.other
end

function Round:MayWinByPoints(team, q)
	return self.mode:MayWinByPoints(team, q)
end

-- Played rounds (the master's GetControlPointRoundToPlay reads them).

function Round:AddPlayedRound(name)
	self.previousRounds = AddPlayedRound(self.previousRounds, name)
end

function Round:History()
	return {
		previous = self.previousRounds,
		first = self.firstRound,
	}
end

function Round:SetFirstRoundPlayed(name)
	self.firstRound = name
end

-- Respawn waves (CheckRespawnWaves / GetNextRespawnWave) -------------------------

-- SetTeamRespawnWaveTime / AddTeamRespawnWaveTime: the first value a team
-- receives is what each full round starts from again.
function Round:SetTeamWaveTime(team, seconds)
	seconds = math.max(0, seconds)
	if self.originalWaveTime[team] < 0 then self.originalWaveTime[team] = seconds end
	self.waveTime[team] = seconds
end

function Round:AddTeamWaveTime(team, seconds)
	local current = self.waveTime[team]
	if current < 0 then current = self.settings.respawnWaveTime end
	if self.originalWaveTime[team] < 0 then self.originalWaveTime[team] = current end
	self.waveTime[team] = math.max(0, current + seconds)
end

-- seconds >= 0 overrides the team's wave for the rest of the map; nil gives
-- the map's back.
function Round:SetAdminWaveTime(team, seconds)
	self.adminWaveTime[team] = seconds or WAVE_TIME_UNSET
end

function Round:TeamWaveTime(team)
	return WaveTime(self.adminWaveTime[team], self.waveTime[team], self.settings.respawnWaveTime)
end

-- CTFGameRules::GetRespawnWaveMaxLength
function Round:WaveMaxLength(team, teamSize, scale)
	if self.state ~= State.RND_RUNNING then return 0 end
	local t = self:TeamWaveTime(team)
	if scale and t > MIN_SCALED_WAVE then
		t = math.max(MIN_SCALED_WAVE, t * RespawnTimeScalar(teamSize))
	end
	return t
end

-- CTFGameRules::GetMinTimeWhenPlayerMaySpawn: setup respawns quickly
-- (ShouldRespawnQuickly), anything else waits a wave too.
-- The earliest a player dead since deathTime may spawn: after the death
-- animation and, out of setup, a whole wave; switched (a player who died
-- changing teams) waits only the animation, so the new team's next wave
-- brings them back.
local function MinSpawnTime(self, team, deathTime, switched)
	local delay = DEATH_ANIM_LENGTH
	if not self.inSetup and not switched then delay = delay + self:WaveMaxLength(team, 0, false) end
	return deathTime + delay
end

function Round:MayRespawn(team, deathTime, now, switched)
	return now >= MinSpawnTime(self, team, deathTime, switched)
end

-- GetNextRespawnWave
function Round:NextRespawn(team, deathTime, teamSize, switched)
	local minTime = MinSpawnTime(self, team, deathTime, switched)
	if self.inSetup then return minTime end
	local nextWave = self.nextWave[team]
	local waveLength = self:WaveMaxLength(team, teamSize, true)
	if waveLength <= 0 then return math.max(nextWave, minTime) end
	while nextWave < minTime do
		nextWave = nextWave + waveLength
	end
	return nextWave
end

-- The respawn time a dead player is shown: 0 in sudden death and while an
-- admin has stopped respawns.
function Round:RespawnAt(team, deathTime, teamSize, switched)
	if self.state == State.STALEMATE or self.respawnsDisabled then return 0 end
	return self:NextRespawn(team, deathTime, teamSize, switched)
end

-- Whether the team's wave comes now; if so the next is set a wave later.
function Round:WaveDue(team, now, teamSize)
	local nextWave = self.nextWave[team]
	if nextWave ~= 0 and nextWave > now then return false end
	local length = self:WaveMaxLength(team, teamSize, true)
	self.nextWave[team] = length > 0 and now + length or 0
	return true
end

-- Stopping respawns leaves the dead dead until the next full round; allowing
-- them again returns true when the dead need new respawn times.
function Round:SetRespawnsDisabled(disabled)
	if self.respawnsDisabled == disabled then return false end
	self.respawnsDisabled = disabled
	return not disabled and self.state ~= State.STALEMATE
end

function Round:RespawnsDisabled()
	return self.respawnsDisabled
end
