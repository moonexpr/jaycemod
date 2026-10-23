-- The arena mode (features.arena.round): tf_logic_arena's round as TF2
-- plays it (teamplayroundbased_gamerules.cpp's IsInArenaMode branches,
-- CTFGameRules::SetupOnStalemateStart and CArenaLogic, tf_gamerules.cpp). The
-- pre-round lasts mp_arena_preround_time, then the round is fought in the
-- STALEMATE state: nobody respawns, a team wins by killing the other or by
-- capturing the point once the cap-enable time has passed.
local T = dofile("tests/harness.lua")
local FakeObjective = dofile("tests/fake_objective.lua")
local Rounds = T.require("games.gameplay.rounds")
local Arena = T.require("features.arena.round")
local ControlPoints = T.require("features.rounds.control_points")
local Koth = T.require("features.koth.model")
local State = T.require("games.gameplay.rounds.state")
local Text = T.require("features.rounds.text")
local Scenario = T.require("features.aiwar.scenario")
local Teams = T.require("games.gameplay.teams")
local Spawns = T.require("games.system.spawn_manager")

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local W = Rounds.WINREASON
local T0 = 100
local PREROUND = 10 -- mp_arena_preround_time's default

local function Settings(over)
	local s = {
		respawnWaveTime = 10,
		bonusRoundTime = 15,
		enableRoundWaitTime = 1,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		matchEndAtTimelimit = false,
		chattime = 10,
		mapResetTime = 0,
		scrambleAuto = true,
		scrambleWinDifference = 1,
		arenaPreroundTime = PREROUND,
		arenaRoundTime = 0,
	}
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function Team(players, alive)
	return {
		players = players,
		alive = alive,
	}
end

local function World(over)
	local w = {
		havePlayers = true,
		teams = {
			[RED] = Team(1, 1),
			[BLUE] = Team(1, 1),
		},
		scores = {
			[RED] = 0,
			[BLUE] = 0,
		},
		stalemateTimerLeft = nil,
		timerMayExpire = true,
		mapHasActiveTimer = false,
		objective = FakeObjective.Objective(),
	}
	for k, v in pairs(over or {}) do w[k] = v end
	return w
end

local function Kinds(effects)
	local list = {}
	for i, e in ipairs(effects) do
		list[i] = e.kind == "output" and ("output " .. e.name) or e.kind == "hook" and ("hook " .. e.name)
			or e.kind == "state" and ("state " .. e.to) or e.kind
	end
	return table.concat(list, ", ")
end

local function Has(effects, kind)
	for _, e in ipairs(effects) do
		if e.kind == kind then return e end
	end
	return nil
end

-- An arena round from PREGAME into its pre-round at T0.
local function Preround(settings)
	local round = Rounds.New(Settings(settings))
	T.eq(round:SetMode(Arena.Mode), true, "arena chosen")
	round:Think(T0, World())
	T.eq(round:State(), State.PREROUND, "pre-round")
	return round
end

-- The arena round opens in setup once the one-second pre-round is over.
local SETUP_AT = T0 + Rounds.PREROUND_SECONDS
-- An arena round in its setup, from SETUP_AT.
local function InSetup(settings)
	local round = Preround(settings)
	round:Think(SETUP_AT, World())
	T.eq(round:State(), State.STALEMATE, "the arena round")
	T.eq(round:InSetup(), true, "in setup")
	return round
end

-- An arena round fought from SETUP_AT + PREROUND (mp_arena_preround_time of
-- setup), which is T0 + PREROUND + 1.
local FIGHT_AT = SETUP_AT + PREROUND
local function Fighting(settings)
	local round = InSetup(settings)
	round:Think(FIGHT_AT, World())
	T.eq(round:InSetup(), false, "setup over")
	return round
end

-- The mode ---------------------------------------------------------------------------

T.test("a tf_logic_arena makes the game arena over every other mode", function()
	local round = Rounds.New(Settings())
	round:SetMode(ControlPoints.Mode)
	T.eq(round:SetMode(Arena.Mode), true, "arena over control points")
	T.eq(round:SetMode(Koth.Mode), false, "koth never replaces arena")
	T.eq(round:Mode(), Arena.Mode, "arena")
	T.eq(Arena.Mode.NAME, "arena", "named for the AI war's scenarios")
	T.eq(Arena.Mode.HUD, Rounds.HUD_CONTROL_POINTS, "the point HUD")
end)

T.test("other modes keep their rounds: the pre-round's freeze, then RND_RUNNING", function()
	local round = Rounds.New(Settings({ enableRoundWaitTime = 2 }))
	round:SetMode(ControlPoints.Mode)
	round:Think(T0, World())
	T.eq(round:PreroundEnd(), T0 + Rounds.PREROUND_SECONDS * 2, "mp_enableroundwaittime scales it")
	round:Think(T0 + Rounds.PREROUND_SECONDS * 2 + 1, World())
	T.eq(round:State(), State.RND_RUNNING, "running")
end)

-- The round --------------------------------------------------------------------------

T.test("the pre-round is the one-second freeze every mode has, whatever mp_arena_preround_time says", function()
	local round = Preround({ arenaPreroundTime = 30 })
	T.eq(round:PreroundEnd(), T0 + Rounds.PREROUND_SECONDS, "PREROUND_SECONDS times mp_enableroundwaittime (1)")
	T.eq(Rounds.PREROUND_SECONDS, 1, "a second: the map cleaned up and the teams scrambled, nothing more")
	T.eq(round:PointsMayBeCaptured(T0), false, "no captures in the pre-round")
end)

T.test("the pre-round ends in the arena round, in STALEMATE, opening in setup for mp_arena_preround_time", function()
	local round = Preround()
	local effects = round:Think(SETUP_AT, World())
	T.eq(Kinds(effects), table.concat({
		"output OnStateExitPreRound",
		"doors_unlock",
		"state " .. State.STALEMATE,
		"arena_setup",
		"hook WSRoundActive",
	}, ", "), "no sudden death, no respawn, the map's timers left alone, the round not started yet")
	T.eq(Has(effects, "arena_setup").ends, SETUP_AT + PREROUND, "setup ends mp_arena_preround_time on")
	T.eq(round:State(), State.STALEMATE, "STALEMATE")
	T.eq(round:InSetup(), true, "in setup")
	T.eq(round:PointsMayBeCaptured(SETUP_AT + 1), false, "no captures in setup")
end)

T.test("setup's end starts the arena round (arena_round_start), and only respawns happen before it", function()
	local round = InSetup()
	T.eq(Kinds(round:Think(FIGHT_AT - 1, World())), "respawn_team, respawn_team", "still setup: the dead come back")
	local effects = round:Think(FIGHT_AT, World())
	T.eq(Kinds(effects), "arena_setup_end, arena_round_start", "setup over, the round started")
	T.eq(round:InSetup(), false, "out of setup")
end)

T.test("with no mp_arena_preround_time the arena round starts as the pre-round ends", function()
	local round = Preround({ arenaPreroundTime = 0 })
	local effects = round:Think(SETUP_AT, World())
	T.eq(Has(effects, "arena_setup"), nil, "no setup")
	T.eq(Has(effects, "arena_round_start") ~= nil, true, "started")
	T.eq(round:InSetup(), false)
end)

T.test("mp_arena_round_time, not mp_stalemate_timelimit, times the arena round, from setup's end", function()
	local untimed = InSetup({ stalemateTimelimit = 240 })
	T.eq(Has(untimed:Think(FIGHT_AT, World()), "stalemate_timer"), nil, "0: no timer")
	local timed = InSetup({ arenaRoundTime = 300 })
	local timer = Has(timed:Think(FIGHT_AT, World()), "stalemate_timer")
	T.eq(timer and timer.seconds, 300, "mp_arena_round_time's seconds")
end)

T.test("the arena's setup respawns the dead with quick waves", function()
	local round = InSetup({ respawnWaveTime = 1 })
	local effects = round:Think(SETUP_AT + 1, World())
	T.eq(Has(effects, "respawn_team") ~= nil, true, "a wave in setup")
	T.eq(round:RespawnAt(RED, SETUP_AT + 1, 3, false), SETUP_AT + 1 + Rounds.QUICK_WAVE, "the respawn time shown: the next quick wave")
	local status, at = round:RespawnStatus(RED, SETUP_AT + 1, 3, false)
	T.eq(status, Spawns.WAVE, "said: a wave")
	T.eq(at, SETUP_AT + 1 + Rounds.QUICK_WAVE)
end)

T.test("nobody respawns in the arena round", function()
	local round = Fighting({ respawnWaveTime = 1 })
	for t = 1, 30 do
		T.eq(Has(round:Think(T0 + PREROUND + 1 + t, World({
			teams = {
				[RED] = Team(3, 1),
				[BLUE] = Team(3, 2),
			},
		})), "respawn_team"), nil, "no wave at +" .. t)
	end
	T.eq(round:RespawnAt(RED, T0 + PREROUND + 2, 3, false), 0, "no respawn time shown")
	T.eq(round:RespawnStatus(RED, T0 + PREROUND + 2, 3, false), Spawns.ARENA, "said: no respawning in arena mode")
end)

T.test("killing the other team wins the round, and the dead stay dead for the humiliation", function()
	local round = Fighting()
	local effects = round:Think(T0 + PREROUND + 5, World({
		teams = {
			[RED] = Team(2, 0),
			[BLUE] = Team(2, 1),
		},
	}))
	T.eq(Has(effects, "sudden_death_over"), nil, "no sudden-death reward or respawn")
	local win = Has(effects, "stalemate_winner")
	T.eq(win and win.team, BLUE, "the survivors win")
	T.eq(win and win.forceMapReset, true, "a full round")
end)

-- Arena's stalemate (everyone dead at once, or the round's timer out) is
-- the game's default end: without sudden death the match ends drawn; with
-- it, a sudden-death round follows, timed by mp_stalemate_timelimit.
local function BothDead()
	return World({ teams = { [RED] = Team(2, 0), [BLUE] = Team(2, 0) } })
end

T.test("everyone dead, or the arena round's timer out, without sudden death ends the match drawn", function()
	for _, world in ipairs({ BothDead(), World({ stalemateTimerLeft = 0 }) }) do
		local round = Fighting()
		local effects = round:Think(T0 + PREROUND + 5, world)
		T.eq(Has(effects, "intermission").reason, Rounds.STALEMATE_GAME_OVER, "game over")
		T.eq(Has(effects, "intermission").winner, Rounds.NOBODY_WON, "nobody won")
		T.eq(Has(effects, "publish_win"), nil, "no round win, no humiliation")
		T.eq(round:State(), State.GAME_OVER, "the game is over")
	end
end)

T.test("with sudden death, everyone dead or the timer out starts a sudden-death round on mp_stalemate_timelimit", function()
	for _, world in ipairs({ BothDead(), World({ stalemateTimerLeft = 0 }) }) do
		local round = Fighting({ stalemateEnable = true, stalemateTimelimit = 60, arenaRoundTime = 300 })
		local effects = round:Think(T0 + PREROUND + 5, world)
		T.eq(Has(effects, "sudden_death") ~= nil, true, "sudden death: " .. Kinds(effects))
		T.eq(Has(effects, "respawn_all") ~= nil, true, "everyone back for it")
		T.eq(Has(effects, "stalemate_timer").seconds, 60, "mp_stalemate_timelimit, not the arena round's")
		T.eq(round:InSuddenDeath(), true, "in sudden death")
	end
end)

-- An admin's sudden death (mp_round_suddendeath, mp_match_forcewin sudden):
-- the arena round, fought in STALEMATE, is a round under way as RND_RUNNING is.
T.test("an admin may send the arena round to sudden death, in setup or fought, for the round or the match", function()
	for _, start in ipairs({ InSetup, Fighting }) do
		local round = start({ stalemateTimelimit = 60 })
		T.eq(round:Underway(), true, "a round under way")
		local effects = round:SuddenDeath(FIGHT_AT + 1, Rounds.STALEMATE.ADMIN)
		T.eq(Has(effects, "sudden_death") ~= nil, true, "sudden death: " .. Kinds(effects))
		T.eq(round:InSuddenDeath(), true, "in sudden death")
		T.eq(round:InSetup(), false, "setup over")
		T.eq(round:Underway(), false, "not again while in it")
		T.eq(#round:SuddenDeath(FIGHT_AT + 2, Rounds.STALEMATE.ADMIN), 0, "a second ask does nothing")
	end
	local forMatch = Fighting({ stalemateTimelimit = 60 })
	T.eq(Has(forMatch:SuddenDeathForMatch(FIGHT_AT + 1), "sudden_death") ~= nil, true, "for the match")
end)

T.test("before the arena round, in the pre-round, there is no round to send to sudden death", function()
	local round = Preround()
	T.eq(round:Underway(), false)
	T.eq(#round:SuddenDeath(T0, Rounds.STALEMATE.ADMIN), 0, "nothing")
end)

T.test("arena's sudden death is won by the survivors, rewarded, or tied at its timeout with a point each", function()
	local round = Fighting({ stalemateEnable = true })
	round:Think(T0 + PREROUND + 5, BothDead())
	local effects = round:Think(T0 + PREROUND + 6, World({ teams = { [RED] = Team(2, 1), [BLUE] = Team(2, 0) } }))
	T.eq(Has(effects, "sudden_death_over") ~= nil, true, "the survivors rewarded")
	T.eq(Has(effects, "stalemate_winner").team, RED, "RED wins")
	local tie = Fighting({ stalemateEnable = true })
	tie:Think(T0 + PREROUND + 5, BothDead())
	local scores = {}
	for _, e in ipairs(tie:Think(T0 + PREROUND + 6, World({ stalemateTimerLeft = 0 }))) do
		if e.kind == "score" then scores[e.team] = e.points end
	end
	T.eq(scores[RED] == 1 and scores[BLUE] == 1, true, "a point each")
end)

T.test("leaving the arena round restores no timers it never hid", function()
	local round = Fighting()
	local effects = round:SetWinningTeam(T0 + PREROUND + 5, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(Has(effects, "restore_timers"), nil, "nothing to restore")
	T.eq(round:State(), State.TEAM_WIN, "won by the point")
end)

T.test("arena never scrambles teams on its own (SetWinningTeam skips mp_scrambleteams_auto)", function()
	local round = Fighting({ scrambleAuto = true, scrambleWinDifference = 1 })
	local effects = round:SetWinningTeam(T0 + PREROUND + 5, RED, W.OPPONENTS_DEAD, true, false, false, FakeObjective.Objective())
	T.eq(Has(effects, "scramble_due"), nil, "no scramble")
end)

T.test("arena makes no time limit timer (CreateTimeLimitTimer returns in arena)", function()
	local round = Rounds.New(Settings({
		timelimit = 30,
		matchEndAtTimelimit = true,
	}))
	round:SetMode(Arena.Mode)
	T.eq(Has(round:Think(T0, World()), "time_limit_timer"), nil, "none")
end)

T.test("a second arena round plays the same way", function()
	local round = Fighting()
	round:SetWinningTeam(T0 + 20, RED, W.OPPONENTS_DEAD, true, false, false, FakeObjective.Objective())
	local now = T0 + 20 + 15
	round:Think(now, World())
	T.eq(round:State(), State.PREROUND, "the next pre-round")
	T.eq(round:PreroundEnd(), now + Rounds.PREROUND_SECONDS, "as long as the first")
	local setupAt = now + Rounds.PREROUND_SECONDS
	round:Think(setupAt, World())
	T.eq(round:State(), State.STALEMATE, "the next arena round")
	T.eq(round:InSetup(), true, "in its setup")
	round:Think(setupAt + PREROUND, World())
	T.eq(round:InSetup(), false, "then fought")
end)

-- The point: shut until the cap-enable time ---------------------------------------

T.test("the point may be captured only from the cap-enable time on (TeamMayCapturePoint)", function()
	local round = Fighting()
	local start = T0 + PREROUND + 1
	round:SetCapEnableTime(start + 60)
	T.eq(round:CapEnableTime(), start + 60, "kept")
	T.eq(round:PointsMayBeCaptured(start + 59), false, "shut before")
	T.eq(round:PointsMayBeCaptured(start + 60), true, "open at the time")
	T.eq(round:PointsMayBeCaptured(start + 61), true, "and after")
end)

T.test("a new round forgets the last round's cap-enable time", function()
	local round = Fighting()
	round:SetCapEnableTime(T0 + 1000)
	round:SetWinningTeam(T0 + 20, RED, W.OPPONENTS_DEAD, true, false, false, FakeObjective.Objective())
	round:Think(T0 + 35, World())
	T.eq(round:CapEnableTime(), nil, "forgotten at the round's respawn")
end)

T.test("without a cap-enable time the point is as the round allows", function()
	local round = Fighting()
	T.eq(round:CapEnableTime(), nil, "none set")
	T.eq(round:PointsMayBeCaptured(T0 + PREROUND + 2), true, "open")
end)

-- tf_logic_arena ---------------------------------------------------------------------

T.test("the delay is mp_arena_override_cap_enable_time when above 0, else the map's CapEnableDelay", function()
	T.eq(Arena.CapEnableDelay(-1, 60), 60, "-1: the map's")
	T.eq(Arena.CapEnableDelay(0, 60), 60, "0 is not above 0: the map's")
	T.eq(Arena.CapEnableDelay(15, 60), 15, "15 overrides")
	T.eq(Arena.CapEnableDelay(-1, 0), 0, "a map with no delay opens at once")
end)

T.test("a tf_logic_arena without CapEnableDelay takes the FGD's 0", function()
	T.eq(Arena.New({}):CapEnableDelay(-1), 0, "default")
	T.eq(Arena.New({ capEnableDelay = 60 }):CapEnableDelay(-1), 60, "the map's")
	T.eq(Arena.New({ capEnableDelay = 60 }):CapEnableDelay(15), 15, "overridden")
end)

T.test("OnCapEnabled fires once, in the arena round, when the cap-enable time passes (ArenaLogicThink)", function()
	local logic = Arena.New({ capEnableDelay = 60 })
	local at = T0 + 60
	T.eq(logic:Think(T0 + 70, State.PREROUND, at), false, "only in STALEMATE")
	T.eq(logic:Think(T0 + 59, State.STALEMATE, at), false, "not yet")
	T.eq(logic:Think(T0 + 60, State.STALEMATE, at), true, "at the time")
	T.eq(logic:Think(T0 + 61, State.STALEMATE, at), false, "once")
	T.eq(logic:Think(T0 + 62, State.STALEMATE, T0 + 200), false, "a later time re-arms it")
	T.eq(logic:Think(T0 + 200, State.STALEMATE, T0 + 200), true, "and it fires again")
end)

T.test("no cap-enable time yet: nothing fires", function()
	T.eq(Arena.New({}):Think(T0, State.STALEMATE, nil), false, "nothing")
end)

-- The win panel and the AI war ---------------------------------------------------------

T.test("an arena win by elimination reads Winreason_Arena, without sudden death", function()
	local panel = Text.WinPanel({
		winner = BLUE,
		reason = W.OPPONENTS_DEAD,
		fullRound = true,
		remaining = 0,
		arena = true,
	})
	T.eq(panel.reason, "BLU killed all opponents", "Winreason_Arena")
	T.eq(Text.WinPanel({
		winner = BLUE,
		reason = W.OPPONENTS_DEAD,
		fullRound = true,
		remaining = 0,
		arena = false,
	}).reason, "BLU killed all opponents during sudden death", "sudden death keeps its line")
end)

T.test("the AI war fights arena with its own scenario", function()
	T.eq(Scenario.For(Arena.Mode.NAME), T.require("features.aiwar.scenario.arena").Scenario, "the arena scenario")
end)

T.test("an arena game waits for its players, on either team", function()
	T.defined(Arena.MIN_PLAYERS, "Arena.MIN_PLAYERS")
	local n = Arena.MIN_PLAYERS
	local needed = Arena.Mode.PLAYERS_NEEDED
	local function Met(r, b)
		local have, need = Rounds.PlayersNeeded(needed, { [RED] = r, [BLUE] = b, free = 0 })
		return have >= need
	end
	T.eq(Met(n - 1, 0), false, "one short")
	T.eq(Met(n - 1, 1), true, "met across the teams")
	T.eq(Met(0, n), true, "met on one team")
end)

T.finish()
