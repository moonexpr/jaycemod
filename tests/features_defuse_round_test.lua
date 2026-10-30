-- The bomb defusal mode (features.defuse.round): a round fought in STALEMATE
-- as arena's and the hostage mode's are, nobody respawning, under CS:S's
-- gamerules; RED's bomb is carried by its own team (MvM's, RED the
-- invaders). The bomb's state (features.defuse.model), which the defuse
-- controller tells the rounds, keeps the round on once it is planted.
local T = dofile("tests/harness.lua")
local Round = T.require("features.defuse.round")
local Defuse = T.require("features.defuse.model")
local State = T.require("games.gameplay.rounds.state")
local Rounds = gameplay.rounds
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON

T.test("it is a rounds mode named defuse, fought like an arena round under CS:S's rules", function()
	T.eq(Round.Mode.NAME, "defuse", "name")
	T.eq(Round.Mode.ROUND_STATE, State.STALEMATE, "fought in STALEMATE")
	T.eq(Round.Mode.STALEMATE_IS_ROUND, true, "the stalemate is the round")
	T.eq(Round.Mode.RULES_CLASS, "cs_gamerules", "CS:S's gamerules")
	T.eq(Round.Mode.OBJECTIVE, true, "the bomb is the objective")
	T.eq(Round.Mode:MayWinByPoints(RED, {}), false, "owning the sites wins nothing")
end)

T.test("the bomb is RED's own to carry, as MvM's is its invaders'", function()
	T.eq(Round.Mode.FLAG_OWNERS_CARRY, true, "owners carry")
	T.eq(Round.Mode.FLAG_INVADERS, RED, "RED carries")
end)

T.test("the AI war fights it with its own scenario", function()
	T.eq(T.require("features.aiwar.scenario").For(Round.Mode.NAME), T.require("features.aiwar.scenario.defuse").Scenario, "defuse")
end)

local function World(bomb) return { objectiveState = bomb and { bomb = bomb } or nil } end

T.test("time running out before the plant saves the targets: BLU wins", function()
	local winner, reason = Round.Mode:StalemateTimerWin(World(Defuse.New()))
	T.eq(winner == BLUE and reason == W.TARGET_SAVED, true, "BLU, the targets saved")
	T.eq(Round.Mode:HoldsStalemateTimer(World(Defuse.New())), false, "the timer ends it")
end)

T.test("planted, the bomb decides: neither time nor RED's death ends the round", function()
	local planted = World(Defuse.New():Plant("A", 0, 45))
	T.eq(Round.Mode:HoldsStalemateTimer(planted), true, "time out holds")
	T.eq(Round.Mode:EliminationWins(BLUE, planted), false, "BLU alone must defuse")
	T.eq(Round.Mode:EliminationWins(RED, planted), true, "RED alone wins")
	T.eq(Round.Mode:EliminationWins(nil, planted), false, "nobody left: the bomb decides")
	T.eq(Round.Mode:EliminationWins(BLUE, World(Defuse.New())), true, "unplanted: as arena")
	T.eq(Round.Mode:EliminationWins(BLUE, World(nil)), true, "no bomb told yet: as arena")
end)

-- Through the rounds' own think ------------------------------------------------------

local T0 = 100
local function Settings()
	return {
		respawnWaveTime = 10, bonusRoundTime = 15, enableRoundWaitTime = 1, stalemateEnable = false,
		stalemateTimelimit = 240, winlimit = 0, maxrounds = 0, timelimit = 0, matchEndAtTimelimit = false,
		chattime = 10, mapResetTime = 0, scrambleAuto = true, scrambleWinDifference = 1,
		arenaPreroundTime = 10, arenaRoundTime = 0, defuseRoundTime = 135,
	}
end

local function Full(over)
	local w = {
		havePlayers = true,
		teams = { [RED] = { players = 2, alive = 2 }, [BLUE] = { players = 2, alive = 2 } },
		scores = { [RED] = 0, [BLUE] = 0 },
		stalemateTimerLeft = nil, timerMayExpire = true, mapHasActiveTimer = false,
		objective = dofile("tests/fake_objective.lua").Objective(),
	}
	for k, v in pairs(over or {}) do w[k] = v end
	return w
end

local function Has(effects, kind)
	for _, e in ipairs(effects) do
		if e.kind == kind then return e end
	end
	return nil
end

local FIGHT_AT = T0 + Rounds.PREROUND_SECONDS + Round.FREEZE_SECONDS
local function Fighting()
	local round = Rounds.New(Settings())
	T.eq(round:SetMode(Round.Mode), true, "defuse chosen")
	round:Think(T0, Full())
	round:Think(T0 + Rounds.PREROUND_SECONDS, Full())
	round:Think(FIGHT_AT, Full())
	T.eq(round:State(), State.STALEMATE, "fought in STALEMATE")
	return round
end

local PLANTED = { bomb = Defuse.New():Plant("A", 0, 45) }
local RED_DEAD = { [RED] = { players = 2, alive = 0 }, [BLUE] = { players = 2, alive = 2 } }
local BLUE_DEAD = { [RED] = { players = 2, alive = 2 }, [BLUE] = { players = 2, alive = 0 } }

T.test("with the bomb planted, killing RED does not end the round; killing BLU does", function()
	local effects = Fighting():Think(FIGHT_AT + 20, Full({ teams = RED_DEAD, objectiveState = PLANTED }))
	T.eq(Has(effects, "stalemate_winner"), nil, "BLU must defuse")
	effects = Fighting():Think(FIGHT_AT + 20, Full({ teams = BLUE_DEAD, objectiveState = PLANTED }))
	T.eq(Has(effects, "stalemate_winner").team, RED, "RED wins")
	effects = Fighting():Think(FIGHT_AT + 20, Full({ teams = RED_DEAD }))
	T.eq(Has(effects, "stalemate_winner").team, BLUE, "unplanted: BLU wins")
end)

T.test("with the bomb planted, the round's timer running out ends nothing", function()
	local effects = Fighting():Think(FIGHT_AT + 135, Full({ stalemateTimerLeft = 0, objectiveState = PLANTED }))
	T.eq(Has(effects, "publish_win"), nil, "on")
	effects = Fighting():Think(FIGHT_AT + 135, Full({ stalemateTimerLeft = 0 }))
	local win = Has(effects, "publish_win")
	T.eq(win.winner == BLUE and win.reason == W.TARGET_SAVED, true, "unplanted: the targets saved")
end)

T.test("the round's length is the map's setting, after the freeze", function()
	T.eq(Round.Mode:StalemateSeconds({ defuseRoundTime = 135 }), 135, "timed")
	T.eq(Round.Mode:SetupSeconds({}), Round.FREEZE_SECONDS, "the freeze")
end)

T.finish()
