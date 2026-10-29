-- The rounds system: TF2's round-based gamerules as a stateful model. A
-- Round is CTeamplayRoundBasedRules' state machine (teamplayroundbased_
-- gamerules.cpp) with the parts of CTFGameRules (tf_gamerules.cpp) that drive
-- it: wins, sudden death, the win, round and time limits, respawn waves,
-- setup and overtime, TimerMayExpire and the played-round history.
--
-- The game's variations are Mode strategies (Mode:Extend(name) plus
-- overrides), chosen by map entities: control points, koth and payload are
-- parts of their own (features.rounds.control_points, .koth, .payload).
--
-- Nothing here touches the engine. Time comes in as `now`, the world as a
-- snapshot, and every method that changes the game returns a list of
-- effects, plain tables { kind = ..., ... }, for the rounds controller to
-- carry out in order.
local error, ipairs, math, pairs, setmetatable, tostring = error, ipairs, math, pairs, setmetatable, tostring
local find, gmatch, sort, table_remove = string.find, string.gmatch, table.sort, table.remove
local Teams = gameplay.teams
local State = require("games.gameplay.rounds.state")
local Cfsm = generator.state_machine
local Snapshot = world.snapshot
local Class = core.class
local Spawns = system.spawn_manager
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
	-- games.gameplay.rounds.limits': mp_round_fraglimit and mp_round_cashlimit
	FRAGLIMIT = 9,
	CASHLIMIT = 10,
	-- CTF's time limit: the team with more captures wins (features/flag)
	MOST_CAPTURES = 11,
	-- the match ended early, won by the team nearer to completing the
	-- objective (Round:EndEarly)
	ENDED_EARLY = 12,
}
STALEMATE = {
	JOIN_MID = 0,
	TIMER = 1,
	SERVER_TIMELIMIT = 2,
	MATCH_TIED = 3, -- a limit ended the match on a tied score
	ADMIN = 4, -- the Administrator called it (mp_forcewin)
	BOTH_DEAD = 5, -- both teams fell at once: no tie-breaker, sudden death again
	LIMIT_TIED = 6, -- both teams reached a round limit together (games.gameplay.rounds.limits)
	ENDED_EARLY = 7, -- the match closed early on a tie (Round:EndEarly)
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

-- What the client draws for the mode (ws_round_hud_type).
HUD_NONE = 0
HUD_CONTROL_POINTS = 1
HUD_KOTH = 2
HUD_PAYLOAD = 3
HUD_DEATHMATCH = 4 -- frags alone: no objective panel (the frag limit's own)

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
-- State_Enter_PREROUND uses 5; Sandcastle holds everyone one second, long
-- enough for the map's cleanup and a team scramble, and shows no countdown.
PREROUND_SECONDS = 1
-- The bonus rounds, deathmatch and sudden death, open frozen this long in
-- place of setup, so everyone reads the rules (bonus_freeze).
BONUS_FREEZE_SECONDS = 3
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

-- The level the match ends into: TF2's nextlevel when set, else the
-- rotation's next (the map cycle's, GMod's game.GetMapNext, or with
-- mp_maplist_enabled the maplist's, MaplistNext), else the current map
-- again; a map not installed (exists(map) false) is skipped.
function NextMap(nextlevel, rotationNext, current, exists)
	if nextlevel ~= "" and exists(nextlevel) then return nextlevel end
	if rotationNext ~= "" and exists(rotationNext) then return rotationNext end
	return current
end

-- The maplist: of the installed maps, those the gamemode's map filter
-- matches (its .txt's "maps": Lua patterns joined by |, as GMod's map
-- picker reads them), in name order.
function MapsMatching(installed, filter)
	local patterns = {}
	for pattern in gmatch(filter, "[^|]+") do patterns[#patterns + 1] = pattern end
	local maps = {}
	for _, map in ipairs(installed) do
		for _, pattern in ipairs(patterns) do
			if find(map, pattern) then
				maps[#maps + 1] = map
				break
			end
		end
	end
	sort(maps)
	return maps
end

-- The maplist's map after current: the next in name order, round to the
-- first ("" for an empty list). A map off the list goes on from where it
-- would sit.
function MaplistNext(maps, current)
	for _, map in ipairs(maps) do
		if map > current then return map end
	end
	return maps[1] or ""
end

-- The next-map vote --------------------------------------------------------------

-- CTFGameRules::ManageServerSideVoteCreation's time limit: the vote is
-- called this many seconds before mp_timelimit runs out.
MAP_VOTE_TIME_LEFT = 120
-- Its choices: this many of the current map's mode, and of another mode.
MAP_VOTE_SAME, MAP_VOTE_OTHER = 2, 1

-- Whether the next-map vote is due: the match is one round from its end or
-- over, whichever comes first. facts = { winlimit, maxrounds, timelimit
-- (minutes), roundsPlayed, timeLeft (seconds), scores (each team's), over }.
function MapVoteDue(facts)
	if facts.over then return true end
	if facts.winlimit > 0 then
		for _, score in ipairs(facts.scores) do
			if score >= facts.winlimit - 1 then return true end
		end
	end
	if facts.maxrounds > 0 and facts.roundsPlayed >= facts.maxrounds - 1 then return true end
	return facts.timelimit > 0 and facts.timeLeft <= MAP_VOTE_TIME_LEFT
end

-- The index of the filter's pattern a map matches (its mode), or nil.
local function ModeOf(map, patterns)
	for i, pattern in ipairs(patterns) do
		if find(map, pattern) then return i end
	end
	return nil
end

-- Takes one of list at random (random(n): 1..n) out of it.
local function Draw(list, random)
	return table_remove(list, random(#list))
end

-- The vote's maps, from the maplist (MapsMatching's): MAP_VOTE_SAME of the
-- current map's mode and MAP_VOTE_OTHER of one other mode, at random, never
-- the current map; when a mode is short, the rest come from whatever maps
-- are left.
function MapVoteChoices(maps, current, filter, random)
	local patterns = {}
	for pattern in gmatch(filter, "[^|]+") do patterns[#patterns + 1] = pattern end
	local mode = ModeOf(current, patterns)
	local same, others, otherModes = {}, {}, {}
	for _, map in ipairs(maps) do
		if map ~= current then
			local m = ModeOf(map, patterns)
			if m ~= nil and m == mode then
				same[#same + 1] = map
			elseif m ~= nil then
				if not others[m] then
					others[m] = {}
					otherModes[#otherModes + 1] = m
				end
				local list = others[m]
				list[#list + 1] = map
			end
		end
	end
	local choices = {}
	for _ = 1, MAP_VOTE_SAME do
		if #same > 0 then choices[#choices + 1] = Draw(same, random) end
	end
	for _ = 1, MAP_VOTE_OTHER do
		if #otherModes > 0 then
			local list = others[Draw(otherModes, random)]
			choices[#choices + 1] = Draw(list, random)
		end
	end
	-- a short mode: fill from the maps left, of any mode
	local left = {}
	for _, map in ipairs(same) do left[#left + 1] = map end
	for _, list in pairs(others) do
		for _, map in ipairs(list) do left[#left + 1] = map end
	end
	sort(left)
	while #choices < MAP_VOTE_SAME + MAP_VOTE_OTHER and #left > 0 do
		choices[#choices + 1] = Draw(left, random)
	end
	return choices
end

-- An empty server's next map: one of the maplist's without a nav mesh
-- (hasNav(map) false), at random (random(n): 1..n), never the current map,
-- so the idle server builds it one (ws/sv_nav.lua); nil when there is none.
function IdleNextMap(maps, current, hasNav, random)
	local unmeshed = {}
	for _, map in ipairs(maps) do
		if map ~= current and not hasNav(map) then unmeshed[#unmeshed + 1] = map end
	end
	if #unmeshed == 0 then return nil end
	return unmeshed[random(#unmeshed)]
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
	local n = math.scalar.Clamp(teamSize, 1, OPTIMAL_TEAM_SIZE)
	return MIN_WAVE_SCALE + (n - 1) / (OPTIMAL_TEAM_SIZE - 1) * (MAX_WAVE_SCALE - MIN_WAVE_SCALE)
end

-- Mode: the strategy a game type fills in ---------------------------------------------

Mode = {
	NAME = "none",
	PRIORITY = 0,
	HUD = HUD_NONE,
	CREATES_TIME_LIMIT_TIMER = true,
	ANNOUNCES_TIME_ADDED = true,
	-- The state the pre-round ends in: the round is fought there.
	ROUND_STATE = State.RND_RUNNING,
	-- Whether STALEMATE is the round itself (arena) rather than sudden death:
	-- entering it respawns nobody and hides no timer, and its end rewards no
	-- survivors.
	STALEMATE_IS_ROUND = false,
	-- mp_scrambleteams_auto applies.
	AUTO_SCRAMBLE = true,
	-- The map has an objective that decides its rounds, so the round limits
	-- (games.gameplay.rounds.limits) are off: none here, the base mode's.
	OBJECTIVE = false,
	-- A flag captured scores for its team toward tf_flag_caplimit (CTF).
	FLAG_CAPS_SCORE = false,
	-- A flag is carried by its own team, not its enemies (MvM's bomb).
	FLAG_OWNERS_CARRY = false,
	-- Who must be there before a game begins (games.system.gamemode's wait,
	-- mp_waitingforplayers): count players and NPCs, on team, or on RED and
	-- BLU together without one. The base mode needs nobody.
	PLAYERS_NEEDED = { count = 0 },
}
Mode.__index = Mode

-- needed: a mode's PLAYERS_NEEDED; counts: each team's players and NPCs
-- ({ [RED], [BLUE] }), and free, the players on neither, who count toward
-- any requirement (they choose a team once the game begins). Returns how
-- many count toward it, and how many it needs: it is met once the first
-- reaches the second.
function PlayersNeeded(needed, counts)
	local onTeams = needed.team and counts[needed.team] or counts[RED] + counts[BLUE]
	return onTeams + counts.free, needed.count
end

-- A variant named `name`, inheriting every member it does not override.
function Mode:Extend(name)
	return Class.Extend(self, { NAME = name })
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

-- Who wins at the time limit, and why: the team with the higher score
-- (UNASSIGNED for a tie). world: the round's (scores; captures, in CTF).
function Mode:TimelimitWin(world)
	return TimelimitWinner(world.scores), WINREASON.TIMELIMIT
end

-- How long a round fought in STALEMATE (arena) is in setup first; none.
function Mode:SetupSeconds(settings) return 0 end

-- State_Enter_STALEMATE: its timer's length, none for 0 or less.
function Mode:StalemateSeconds(settings)
	return settings.stalemateTimelimit
end

-- Deathmatch (mp_deathmatch_enable): the bonus round that breaks a tied
-- match. Frags alone decide it (mp_round_fraglimit, games.gameplay.rounds.limits),
-- so its mode has no objective: no point wins it, no flag scores.
DEATHMATCH = "deathmatch"
DeathmatchMode = Mode:Extend(DEATHMATCH)
DeathmatchMode.OBJECTIVE = false
DeathmatchMode.HUD = HUD_DEATHMATCH
function DeathmatchMode:MayWinByPoints() return false end

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
-- The round states' machine, defined below its handlers.
local ROUND_STATES

function New(settings)
	local round = setmetatable({
		settings = {},
		mode = Mode,
		states = ROUND_STATES:New(State.PREGAME),
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
		preroundEnd = nil, -- a new game's first pre-round's end (BeginGame)
		nextPeriodic = 0,
		teamCounts = PerTeam(0),
		inSetup = false,
		overtime = false,
		capBuffer = 0,
		waveTime = PerTeam(WAVE_TIME_UNSET),
		originalWaveTime = PerTeam(WAVE_TIME_UNSET),
		adminWaveTime = PerTeam(WAVE_TIME_UNSET),
		nextWave = PerTeam(0),
		waveScale = PerTeam(1), -- a helped team's share of its wave (games.gameplay.handicap)
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

-- The round's mode: deathmatch's while it is fought (Round:InDeathmatch).
function Round:Mode() return self.deathmatch and DeathmatchMode or self.mode end
function Round:InDeathmatch() return self.deathmatch == true end
function Round:State() return self.states:State() end
function Round:Halted() return self.halted end
function Round:InSetup() return self.inSetup end
function Round:InOvertime() return self.overtime end
function Round:PreroundEnd() return self.transitionAt end
function Round:Winner() return self.winningTeam end
function Round:ForceMapReset() return self.forceMapReset end

function Round:TimeLeft(now)
	return TimeLeft(self.settings.mapResetTime, self.settings.timelimit, now)
end

-- The round as plain data (games.world.snapshot), every time in it kept
-- as seconds from now; Restore puts it back in place from the new now. The
-- mode is the map's choice, so a snapshot only restores into the same one.
local SNAPSHOT = Snapshot.Spec({
	name = "round",
	skip = { "mode" },
	machines = { "states" },
	times = {
		"capBuffer",
		"capEnableAt",
		"intermissionEnd",
		"intermissionFreeze",
		"nextPeriodic",
		"nextWave.*",
		"preroundEnd",
		"setupEnd",
		"transitionAt",
		"settings.mapResetTime",
	},
})

function Round:Snapshot(now)
	local snapshot = Snapshot.Take(self, SNAPSHOT, now)
	snapshot.mode = self.mode.NAME
	return snapshot
end

function Round:Restore(snapshot, now)
	if snapshot.mode ~= self.mode.NAME then
		error("round: the snapshot's mode is " .. tostring(snapshot.mode) .. ", this round's " .. self.mode.NAME, 2)
	end
	local fields = {}
	for k, v in pairs(snapshot) do
		if k ~= "mode" then fields[k] = v end
	end
	Snapshot.Apply(self, fields, SNAPSHOT, now)
end

-- New mp_winlimit, mp_maxrounds and mp_timelimit values, which TF2 reads
-- live: limits = { winlimit, maxrounds, timelimit (minutes) }.
function Round:SetLimits(limits)
	self.settings.winlimit = limits.winlimit
	self.settings.maxrounds = limits.maxrounds
	self.settings.timelimit = limits.timelimit
end

-- How the match ends, for the scoreboard (ws.scoreboard's WinConditions).
function Round:Limits(now)
	return {
		winlimit = self.settings.winlimit,
		maxrounds = self.settings.maxrounds,
		timelimit = self.settings.timelimit,
		roundsPlayed = self.roundsPlayed,
		timeLeft = self:TimeLeft(now),
	}
end

-- State machine (State_Transition, State_Enter, State_Leave, State_Think) ---------

local ENTER, LEAVE, THINK = {}, {}, {}

-- The effect a move to state adds; an enter handler may annotate it.
local function Change(self, state)
	return {
		kind = "state",
		from = self:State(),
		to = state,
	}
end

-- Every move's transition action: the pending transition is dropped and
-- the change is told, before the new state's enter handler runs.
local function Changing(_, _, self, effects, _, _, change)
	self.transitionAt = nil
	Add(effects, change)
end

-- State_Enter: world is the snapshot of the Think that brought it, if any.
-- Handlers are called (self, effects, now, world, change).
local function Enter(self, effects, state, now, world)
	self.states:Enter(state, self, effects, now, world, Change(self, state))
	return effects
end

local function Transition(self, effects, state, now, world)
	self.states:Transition(state, self, effects, now, world, Change(self, state))
	return effects
end

local function TransitionDue(self, now)
	return self.transitionAt ~= nil and now >= self.transitionAt
end

-- GoToIntermission: the match's winner (MatchWinner) is celebrated for
-- MATCH_WIN_EXTRA, its side hunting the humiliated losers to its music,
-- then everyone is frozen for mp_chattime, then the level changes.
MATCH_WIN_EXTRA = 30

-- The match is over, won by winner.
local function Intermission(self, effects, reason, now, winner)
	self.intermissionFreeze = now + MATCH_WIN_EXTRA
	self.intermissionFreezes = true
	self.intermissionEnd = self.intermissionFreeze + self.settings.chattime
	self.decideMatch = false
	Add(effects, {
		kind = "intermission",
		reason = reason,
		winner = winner,
		["until"] = self.intermissionEnd,
	})
	return Enter(self, effects, State.GAME_OVER, now)
end

local function GoToIntermission(self, effects, reason, now, world)
	return Intermission(self, effects, reason, now, MatchWinner(world.scores))
end

-- Why an admin's match win ended the match (Round:ForceMatchWin, or a
-- sudden death called to decide it).
ADMIN_MATCH_WIN = "Decided by the Administrator"
-- Why a deathmatch's winner won the match.
DEATHMATCH_MATCH_WIN = "Won the deathmatch"
-- Why a match ended early was won (Round:EndEarly); all a player is told.
ENDED_EARLY_WIN = "The match ended early."


-- A stalemate is the game's default end. With no sudden death to break it,
-- the match ends drawn (STALEMATE_GAME_OVER): nobody won, so nobody is
-- humiliated; everyone plays on in bonus time, never frozen, until the
-- level changes after MATCH_WIN_EXTRA and mp_chattime, the next map named
-- (next_map) when the extra is over.
STALEMATE_GAME_OVER = "Stalemate"
-- The draw at the time limit says so (mp_match_end_at_timelimit's tie).
TIMELIMIT_GAME_OVER = "Game ran out of time."

local function StalemateGameOver(self, effects, now, stalemate)
	self.intermissionFreeze = now + MATCH_WIN_EXTRA
	self.intermissionFreezes = false
	self.intermissionEnd = self.intermissionFreeze + self.settings.chattime
	Add(effects, {
		kind = "intermission",
		reason = stalemate == STALEMATE.SERVER_TIMELIMIT and TIMELIMIT_GAME_OVER or STALEMATE_GAME_OVER,
		winner = NOBODY_WON,
		["until"] = self.intermissionEnd,
	})
	return Transition(self, effects, State.GAME_OVER, now)
end

-- Sudden death's bonus round, for reason: STALEMATE entered as sudden death
-- (ENTER[State.STALEMATE] reads enteringSuddenDeath).
local function SuddenDeathRound(self, effects, now, reason)
	self.winningTeam = UNASSIGNED
	self.enteringSuddenDeath = true
	Add(effects, {
		kind = "sudden_death",
		reason = reason,
	})
	return Transition(self, effects, State.STALEMATE, now)
end

-- Sudden death whatever mp_stalemate_enable says (a tied match, an admin).
local function ForcedSuddenDeath(self, effects, now, reason)
	self.forceMapReset = true
	return SuddenDeathRound(self, effects, now, reason)
end

-- A stalemate in the round's STALEMATE: the arena round's end with nobody
-- left or its time out, or sudden death's with both teams dead at once.
-- Sudden death breaks it when there is one to play (this sudden death goes
-- on to another, forced or not), else the match ends drawn.
local function Stalemate(self, effects, now, reason)
	if self.suddenDeath or self.settings.stalemateEnable then return SuddenDeathRound(self, effects, now, reason) end
	return StalemateGameOver(self, effects, now, reason)
end

-- A bonus round's opening freeze: nobody moves or attacks until it ends,
-- which it returns.
function BonusFreeze(effects, now)
	local ends = now + BONUS_FREEZE_SECONDS
	Add(effects, {
		kind = "bonus_freeze",
		ends = ends,
	})
	return ends
end

-- A bonus round's timer (sudden death's, a deathmatch's), of seconds; none
-- for 0 or less.
local function StalemateTimer(effects, seconds)
	if seconds > 0 then
		Add(effects, {
			kind = "stalemate_timer",
			seconds = seconds,
		})
	end
end

-- A tied match's bonus round: deathmatch, when on (mp_deathmatch_enable), a
-- fresh round of frags alone whose winner wins the match; else sudden death.
-- Fought, it is timed as sudden death is (RND_RUNNING's enter and think).
local function Deathmatch(self, effects, now)
	self.deathmatch = true
	self.decideMatch, self.decideReason = true, DEATHMATCH_MATCH_WIN
	self.forceMapReset = true
	Add(effects, Kind("deathmatch"))
	return Transition(self, effects, State.PREROUND, now)
end

local function MatchSuddenDeath(self, effects, now)
	self.suddenDeathMatch = false
	if self.settings.deathmatchEnable then return Deathmatch(self, effects, now) end
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
	if self:State() == State.RND_RUNNING then
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

-- CTFGameRules::CreateTimeLimitTimer: a timer for the time left, only when
-- the time limit ends the round and the map shows no timer of its own.
local function TimeLimitTimerDue(self, now, world)
	local settings = self.settings
	return settings.timelimit > 0 and self:TimeLeft(now) > 0 and not world.mapHasActiveTimer
		and self.mode.CREATES_TIME_LIMIT_TIMER
		and (self.allowStalemateAtTimelimit or settings.matchEndAtTimelimit)
end

local function TimeLimitTimerEffect(self, now)
	return {
		kind = "time_limit_timer",
		seconds = self:TimeLeft(now),
	}
end

-- CTFGameRules::HandleTimeLimitChange, after SetLimits: the time limit
-- timer set to the time left, or removed when none is due.
function Round:TimeLimitTimer(now, world)
	if TimeLimitTimerDue(self, now, world) then return { TimeLimitTimerEffect(self, now) } end
	return { Kind("remove_time_limit_timer") }
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
		if TimeLimitTimerDue(self, now, world) then Add(effects, TimeLimitTimerEffect(self, now)) end
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
	-- a deathmatch is the tie at the time limit broken: it plays out
	if self.deathmatch or self.settings.timelimit <= 0 or self:TimeLeft(now) > 0 then return end
	if not (self.allowStalemateAtTimelimit or self.settings.matchEndAtTimelimit) then return end
	local winner, reason = self.mode:TimelimitWin(world)
	if winner == UNASSIGNED and self.settings.deathmatchEnable then
		Deathmatch(self, effects, now)
	elseif winner == UNASSIGNED then
		self.changelevelAfterStalemate = true
		for _, e in ipairs(self:SetStalemate(now, STALEMATE.SERVER_TIMELIMIT, self.forceMapReset)) do Add(effects, e) end
	else
		for _, e in ipairs(self:SetWinningTeam(now, winner, reason, true, false, true, world.objective)) do
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
	if self.deathmatch then
		-- the deathmatch's map has no setup: its timers' ends at once
		Add(effects, Kind("skip_setup"))
		self.transitionAt = BonusFreeze(effects, now)
	else
		self.transitionAt = self.preroundEnd or now + self.mode:PreroundSeconds(self.settings)
		self.preroundEnd = nil
	end
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

-- A deathmatch's map timers hide behind its stalemate timer, as sudden
-- death's do.
ENTER[State.RND_RUNNING] = function(self, effects)
	self.nextWave = PerTeam(0)
	Add(effects, Output("OnStateEnterRoundRunning"))
	Add(effects, Hook("WSRoundActive", {}))
	if self.deathmatch then
		Add(effects, Kind("hide_timers"))
		StalemateTimer(effects, self.settings.stalemateTimelimit)
	end
end

LEAVE[State.RND_RUNNING] = function(self, effects)
	if self.deathmatch then Add(effects, Kind("restore_timers")) end
end

-- A deathmatch whose stalemate timer ran out with no team at the frag
-- limit (which Round:LimitReached ends it at): the match ends a stalemate.
local function DeathmatchTimedOut(self, world)
	local left = world.stalemateTimerLeft
	return self.deathmatch and left ~= nil and world.timerMayExpire and left <= 0
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
	if DeathmatchTimedOut(self, world) then return StalemateGameOver(self, effects, now, STALEMATE.TIMER) end
	CheckRespawnWaves(self, effects, now, world)
	CheckTimelimitStalemate(self, effects, now, world)
end

-- TEAM_WIN (the humiliation)

ENTER[State.TEAM_WIN] = function(self, effects, now)
	if self.forceMapReset then self.roundsPlayed = self.roundsPlayed + 1 end
	self.transitionAt = now + math.max(MIN_BONUS_ROUND_TIME, self.settings.bonusRoundTime)
	Add(effects, Hook("WSRoundWin", { self.winningTeam, self.winReason }))
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
-- and the pre-round led to it, nobody respawns and the map's timers stay:
-- the round starts (arena_round_start: OnArenaRoundStart and the
-- cap-enable time) and runs, timed by the mode (StalemateSeconds).

-- The arena round starts: arena_round_start (OnArenaRoundStart and the
-- cap-enable time), timed by the mode.
local function StartArenaRound(self, effects)
	Add(effects, Kind("arena_round_start"))
	StalemateTimer(effects, self.mode:StalemateSeconds(self.settings))
end

-- An arena round opens in setup for the mode's SetupSeconds
-- (mp_arena_preround_time): everyone moves, no point may be captured, and
-- the round starts as it ends (THINK's arena_setup_end).
ENTER[State.STALEMATE] = function(self, effects, now)
	self.suddenDeath = self.enteringSuddenDeath == true
	self.enteringSuddenDeath = nil
	if self.suddenDeath then
		Add(effects, Kind("respawn_all"))
		BonusFreeze(effects, now)
		Add(effects, Kind("hide_timers"))
		StalemateTimer(effects, self.settings.stalemateTimelimit)
		return
	end
	local setup = self.mode:SetupSeconds(self.settings)
	if setup > 0 then
		self.inSetup = true
		self.setupEnd = now + setup
		Add(effects, {
			kind = "arena_setup",
			ends = self.setupEnd,
		})
		Add(effects, Hook("WSRoundActive", {}))
		return
	end
	StartArenaRound(self, effects)
	Add(effects, Hook("WSRoundActive", {}))
end

LEAVE[State.STALEMATE] = function(self, effects)
	if self.suddenDeath then Add(effects, Kind("restore_timers")) end
	self.suddenDeath = false
	if self.setupEnd then
		self.inSetup, self.setupEnd = false, nil
		Add(effects, Kind("arena_setup_end"))
	end
end

THINK[State.STALEMATE] = function(self, effects, now, world)
	if not world.havePlayers then
		self.forceMapReset = true
		Transition(self, effects, State.PREGAME, now, world)
		return
	end
	if self.setupEnd then
		if now < self.setupEnd then
			CheckRespawnWaves(self, effects, now, world)
			return
		end
		self.inSetup, self.setupEnd = false, nil
		Add(effects, Kind("arena_setup_end"))
		StartArenaRound(self, effects)
		return
	end
	local winner, allDead = StalemateOutcome(world.teams)
	local suddenDeath = self.suddenDeath
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
	-- both teams fell at once: no tie-breaker
	if allDead then return Stalemate(self, effects, now, STALEMATE.BOTH_DEAD) end
	local left = world.stalemateTimerLeft
	if not (left ~= nil and world.timerMayExpire and left <= 0) then return end
	if not suddenDeath then return Stalemate(self, effects, now, STALEMATE.TIMER) end
	-- sudden death timed out: a tie, a point to each team
	Add(effects, Kind("sudden_death_over"))
	for _, e in ipairs(self:Tie(now, not world.objective:PlayingMiniRounds())) do Add(effects, e) end
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
		Add(effects, Kind(self.intermissionFreezes and "freeze" or "next_map"))
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
	if self:State() ~= State.TEAM_WIN and self:State() ~= State.STALEMATE then
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
	self.states:Think(self, effects, now, world)
	if self:State() ~= State.GAME_OVER and now > self.nextPeriodic then
		PeriodicThink(self, effects, now, world)
		self.nextPeriodic = now + PERIODIC_INTERVAL
	end
	return effects
end

-- Round control --------------------------------------------------------------------

-- The round ends, won by winner (UNASSIGNED: nobody), each of scorers
-- taking a point.
local function EndRound(self, now, winner, reason, forceMapReset, switchTeams, scorers)
	local effects = {}
	self.forceMapReset = forceMapReset
	self.switchTeams = switchTeams == true
	self.winningTeam = winner
	self.winReason = reason
	local scores = { [RED] = self.scores[RED] or 0, [BLUE] = self.scores[BLUE] or 0 }
	for _, team in ipairs(scorers) do
		Add(effects, {
			kind = "score",
			team = team,
			points = 1,
		})
		scores[team] = scores[team] + 1
	end
	-- a win that ends the match is the match win at once, in the round win's
	-- place: no round win music or bonus round first
	local roundsPlayed = self.roundsPlayed + (forceMapReset and 1 or 0)
	-- a sudden death an admin called, or a deathmatch, to decide the match:
	-- its winner wins it
	if self.decideMatch and winner ~= UNASSIGNED then
		self.roundsPlayed = roundsPlayed
		if winner == RED then Add(effects, Output("OnWonByTeam1")) end
		if winner == BLUE then Add(effects, Output("OnWonByTeam2")) end
		Intermission(self, effects, self.decideReason, now, winner)
		return effects
	end
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

local function Over(self)
	return self.halted or self:State() == State.TEAM_WIN or self:State() == State.GAME_OVER
end

-- CTeamplayRoundBasedRules::SetWinningTeam.
function Round:SetWinningTeam(now, winner, reason, forceMapReset, switchTeams, dontAddScore, objective)
	if Over(self) then return {} end
	forceMapReset = forceMapReset ~= false
	local reward = ShouldRewardTeam(forceMapReset, self.settings.timelimit, self:TimeLeft(now), dontAddScore == true)
	-- the survivors of sudden death, a team the Administrator hands the round
	-- (mp_forcewin's WINREASON.NONE) and one at a round limit take a point
	-- whatever the map scores by
	local always = self:State() == State.STALEMATE or reason == WINREASON.NONE
		or reason == WINREASON.FRAGLIMIT or reason == WINREASON.CASHLIMIT
	local scored = reward and winner ~= UNASSIGNED and (always or objective:ScorePerRound())
	return EndRound(self, now, winner, reason, forceMapReset, switchTeams, scored and { winner } or {})
end

-- Sudden death timed out: a tie, nobody's win, a point to each team.
function Round:Tie(now, forceMapReset)
	if Over(self) then return {} end
	return EndRound(self, now, UNASSIGNED, WINREASON.STALEMATE, forceMapReset, false, { RED, BLUE })
end

-- Whether the round is being fought, so kills and earnings count toward its
-- limits: running, or arena's round, out of setup and not halted.
function Round:LimitsCount()
	local fought = self:State() == State.RND_RUNNING or (self:State() == State.STALEMATE and not self.suddenDeath)
	return fought and not self.inSetup and not self.halted
end

-- A round limit reached (games.gameplay.rounds.limits' Outcome: { team, reason }
-- or { tie, reason }), in a round being fought (running, or arena's, out of
-- setup): the team wins the round, or a tie is a stalemate.
function Round:LimitReached(now, outcome, objective)
	if not self:LimitsCount() then return {} end
	if outcome.tie then return self:SetStalemate(now, STALEMATE.LIMIT_TIED, true, false) end
	return self:SetWinningTeam(now, outcome.team, outcome.reason, true, false, false, objective)
end

-- Whether the round is sudden death's bonus round now.
function Round:InSuddenDeath()
	return self:State() == State.STALEMATE and self.suddenDeath == true
end

-- mp_forcewin's sudden death: the running round goes to sudden death for
-- reason, whatever mp_stalemate_enable says; nothing outside a running round.
-- Whether a round is under way, one an admin may send to sudden death: a
-- running round, or arena's fought in STALEMATE (its setup too), not yet in
-- sudden death, and not halted.
function Round:Underway()
	if self.halted then return false end
	return self:State() == State.RND_RUNNING or (self:State() == State.STALEMATE and not self.suddenDeath)
end

function Round:SuddenDeath(now, reason)
	local effects = {}
	if not self:Underway() then return effects end
	ForcedSuddenDeath(self, effects, now, reason)
	return effects
end

-- CTeamplayRoundBasedRules::SetStalemate: sudden death when
-- mp_stalemate_enable is on, otherwise the match ends drawn (the game's
-- default end: StalemateGameOver). Nothing while sudden death is on.
function Round:SetStalemate(now, reason, forceMapReset, switchTeams)
	local effects = {}
	if Over(self) or self:InSuddenDeath() then return effects end
	if not self.settings.stalemateEnable then return StalemateGameOver(self, effects, now, reason) end
	self.forceMapReset = forceMapReset ~= false
	return SuddenDeathRound(self, effects, now, reason)
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

-- A restart (mp_round_restart, the reset vote, the editors, a new game).
-- A round in play with players on its teams (withPlayers) ends as a
-- stalemate, an actual round end: its win panel and stalemate song, nobody
-- scoring, then a fresh round on a reset map. Otherwise, with nobody
-- playing (NPCs alone) or no round in
-- play, back to PREGAME silently, with a full reset to come: the next
-- pre-round cleans the map up and respawns everyone. Out of the
-- intermission, everyone is let go.
function Round:RestartRound(now, withPlayers)
	local effects = {}
	if self.halted then return effects end
	self.switchTeams, self.scrambleTeams = false, false
	self.decideMatch, self.deathmatch = false, false
	local inPlay = self:State() == State.PREROUND or self:State() == State.RND_RUNNING or self:State() == State.STALEMATE
	if withPlayers and inPlay then
		return EndRound(self, now, UNASSIGNED, WINREASON.STALEMATE, true, false, {})
	end
	if self:State() == State.GAME_OVER then
		self.intermissionEnd, self.intermissionFreeze = nil, nil
		Add(effects, Kind("unfreeze"))
	end
	self.forceMapReset = true
	return Transition(self, effects, State.PREGAME, now)
end

-- An admin ends the match now, won by team (Utilities > Match Control).
function Round:ForceMatchWin(now, team)
	local effects = {}
	if self.halted or self:State() == State.GAME_OVER then return effects end
	self.winningTeam = team
	if team == RED then Add(effects, Output("OnWonByTeam1")) end
	if team == BLUE then Add(effects, Output("OnWonByTeam2")) end
	Intermission(self, effects, ADMIN_MATCH_WIN, now, team)
	return effects
end

-- An admin's sudden death whose winner wins the match, not only the round.
function Round:SuddenDeathForMatch(now)
	local effects = self:SuddenDeath(now, STALEMATE.ADMIN)
	if #effects > 0 then self.decideMatch, self.decideReason = true, ADMIN_MATCH_WIN end
	return effects
end

-- The match ended early, by the gamerules' own judgement, with their
-- evaluation of the game's progress, leader: the team nearer to completing
-- the objective (gameplay.standing), or nil on a genuine tie. It ends as a
-- round completed: the leader wins the round (SetWinningTeam,
-- WINREASON.ENDED_EARLY) and that win decides the match; a tie goes to a
-- sudden death whose winner decides it, and with no round under way to
-- hold one, the match ends drawn. The model says only that it ended early.
function Round:EndEarly(now, leader, objective)
	if Over(self) then return {} end
	if leader then
		self.decideMatch, self.decideReason = true, ENDED_EARLY_WIN
		return self:SetWinningTeam(now, leader, WINREASON.ENDED_EARLY, true, false, false, objective)
	end
	local effects = self:SuddenDeath(now, STALEMATE.ENDED_EARLY)
	if #effects > 0 then
		self.decideMatch, self.decideReason = true, ENDED_EARLY_WIN
		return effects
	end
	return StalemateGameOver(self, {}, now, STALEMATE.ENDED_EARLY)
end

-- A passed scramble vote (TF_vote_passed_scramble_teams): the next round's
-- teams are scrambled, as mp_scrambleteams_auto would, and told now.
function Round:ScheduleScramble()
	self.scrambleTeams = true
	local effects = {}
	Add(effects, Kind("scramble_due"))
	return effects
end

-- Whether the next round's teams are already to be scrambled.
function Round:ScramblePending()
	return self.scrambleTeams == true
end

-- Stopping the game (Sandbox mode) is TF2's tournament ready-up: the rounds
-- wait in BETWEEN_RNDS and make no transition at all (no pre-round, win,
-- sudden death or game over, whatever the map or players do) until Unhalt,
-- then RestartRound. A halted map is no longer fresh: halting ends its setup
-- and fires its outputs (a race map's OnSetupFinished disables its own
-- timer), so the next full reset cleans it up even before the first game.
function Round:Halt(now)
	local effects = {}
	if self:State() == State.GAME_OVER then
		self.intermissionEnd, self.intermissionFreeze = nil, nil
		Add(effects, Kind("unfreeze"))
	end
	self.halted = true
	self.mapFresh = false
	if self:State() ~= State.BETWEEN_RNDS then Transition(self, effects, State.BETWEEN_RNDS, now) end
	return effects
end

function Round:Unhalt()
	self.halted = false
end

-- A new game readies in two steps the gamemode's countdown times
-- (games.system.gamemode's CUE_CLEANUP and CUE_PREROUND). CleanUp: the halted
-- map cleaned up, so the first pre-round's full reset need not again.
function Round:CleanUp()
	local effects = {}
	self.mapFresh = true
	Add(effects, Kind("cleanup"))
	return effects
end

-- BeginGame: the halted rounds go to the first pre-round, its full reset
-- respawning everyone, held until preroundEnd (the countdown's end), when
-- the round runs; world is the snapshot of now.
function Round:BeginGame(now, preroundEnd, world)
	self.halted = false
	self.switchTeams, self.scrambleTeams = false, false
	self.decideMatch, self.deathmatch = false, false
	self.forceMapReset = true
	self.preroundEnd = preroundEnd
	return Transition(self, {}, State.PREROUND, now, world)
end

function Round:SetStalemateOnTimelimit(on)
	self.allowStalemateAtTimelimit = on
end

-- CTeamplayRoundBasedRules::PointsMayBeCaptured (never in a deathmatch),
-- and in arena
-- CTFGameRules::TeamMayCapturePoint's wait for the cap-enable time.
function Round:PointsMayBeCaptured(now)
	if self.deathmatch then return false end
	if self.capEnableAt and now < self.capEnableAt then return false end
	return (self:State() == State.RND_RUNNING or self:State() == State.STALEMATE) and not self.inSetup
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

-- On a map without an objective the dead come back at once, unless an admin
-- or the map sets a wave.
function Round:TeamWaveTime(team)
	local default = self.mode.OBJECTIVE and self.settings.respawnWaveTime or 0
	return WaveTime(self.adminWaveTime[team], self.waveTime[team], default)
end

-- Sandcastle's pre-round and setup (the arena's too) bring the dead back
-- with quick waves, QUICK_WAVE apart: no death animation, no team wave.
QUICK_WAVE = 1

function Round:RespawnsAtOnce()
	return self:State() == State.PREROUND or self.inSetup
end

-- CTFGameRules::GetRespawnWaveMaxLength
function Round:WaveMaxLength(team, teamSize, scale)
	if self:RespawnsAtOnce() then return QUICK_WAVE end
	if self:State() ~= State.RND_RUNNING then return 0 end
	local t = self:TeamWaveTime(team)
	if scale and t > MIN_SCALED_WAVE then
		t = math.max(MIN_SCALED_WAVE, t * RespawnTimeScalar(teamSize))
	end
	return t * self.waveScale[team]
end

-- A helped team's share of the wave TF2 would give it (Help Other Team,
-- games.gameplay.handicap); 1 for every other team.
function Round:SetWaveScale(team, scale)
	self.waveScale[team] = scale
end

-- CTFGameRules::GetMinTimeWhenPlayerMaySpawn: the earliest a player dead
-- since deathTime may spawn: with the next quick wave in the pre-round and
-- setup (RespawnsAtOnce), else after the death animation and a whole wave;
-- switched (a player who died changing teams) waits only the animation, so
-- the new team's next wave brings them back.
local function MinSpawnTime(self, team, deathTime, switched)
	if self:RespawnsAtOnce() then return deathTime end -- the next quick wave
	local delay = DEATH_ANIM_LENGTH
	if not switched then delay = delay + self:WaveMaxLength(team, 0, false) end
	return deathTime + delay
end

function Round:MayRespawn(team, deathTime, now, switched)
	return now >= MinSpawnTime(self, team, deathTime, switched)
end

-- GetNextRespawnWave
function Round:NextRespawn(team, deathTime, teamSize, switched)
	local minTime = MinSpawnTime(self, team, deathTime, switched)
	if self:RespawnsAtOnce() then return math.max(self.nextWave[team], minTime) end
	local nextWave = self.nextWave[team]
	local waveLength = self:WaveMaxLength(team, teamSize, true)
	if waveLength <= 0 then return math.max(nextWave, minTime) end
	while nextWave < minTime do
		nextWave = nextWave + waveLength
	end
	return nextWave
end

-- The respawn time a dead player is shown: 0 in sudden death (the arena
-- round, out of its setup) and while an admin has stopped respawns.
function Round:RespawnAt(team, deathTime, teamSize, switched)
	if (self:State() == State.STALEMATE and not self.inSetup) or self.respawnsDisabled then return 0 end
	return self:NextRespawn(team, deathTime, teamSize, switched)
end

-- Why a dead player is not spawning (games.system.spawn_manager's
-- statuses) and, waiting for a wave, when it comes: none in an arena round
-- (STALEMATE is the mode's round) or sudden death, out of setup; none
-- until the next round while an admin has stopped respawns.
function Round:RespawnStatus(team, deathTime, teamSize, switched)
	if self:State() == State.STALEMATE and not self.inSetup then
		return self:Mode().STALEMATE_IS_ROUND and Spawns.ARENA or Spawns.SUDDEN_DEATH, 0
	end
	if self.respawnsDisabled then return Spawns.NEXT_ROUND, 0 end
	return Spawns.WAVE, self:NextRespawn(team, deathTime, teamSize, switched)
end

-- Whether the team's wave comes now; if so the next is set a wave after the
-- one due (CheckRespawnWaves sets it a wave after now: our think, every
-- ROUND_THINK_INTERVAL, would make each wave that much longer than the one
-- NextRespawn shows). Waves missed (none due, or a pause) start again from
-- now.
function Round:WaveDue(team, now, teamSize)
	local nextWave = self.nextWave[team]
	if nextWave ~= 0 and nextWave > now then return false end
	local length = self:WaveMaxLength(team, teamSize, true)
	if length <= 0 then
		self.nextWave[team] = 0
		return true
	end
	local after = nextWave + length
	self.nextWave[team] = after > now and after or now + length
	return true
end

-- Stopping respawns leaves the dead dead until the next full round; allowing
-- them again returns true when the dead need new respawn times.
function Round:SetRespawnsDisabled(disabled)
	if self.respawnsDisabled == disabled then return false end
	self.respawnsDisabled = disabled
	return not disabled and self:State() ~= State.STALEMATE
end

function Round:RespawnsDisabled()
	return self.respawnsDisabled
end

-- TF2's gamerules move between their states from wherever a round is
-- decided (a win, a stalemate, a limit, an admin), so every declared state
-- may follow any other; what the machine holds is the states themselves and
-- one handler of each kind per state.
ROUND_STATES = Cfsm.Define({
	name = "round",
	states = {
		State.INIT,
		State.PREGAME,
		State.STARTGAME,
		State.PREROUND,
		State.RND_RUNNING,
		State.TEAM_WIN,
		State.RESTART,
		State.STALEMATE,
		State.GAME_OVER,
		State.BONUS,
		State.BETWEEN_RNDS,
	},
	changing = Changing,
	enter = ENTER,
	leave = LEAVE,
	think = THINK,
})
