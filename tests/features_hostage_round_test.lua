-- The hostage rescue mode (features.hostage.round): a round fought in
-- STALEMATE as arena's is, with nobody respawning and no timer: BLU wins by
-- leading the hostages out (the hostage rules, features.hostage.model), RED by
-- killing all of BLU. A map with hostages chooses it.
local T = dofile("tests/harness.lua")
local Round = T.require("features.hostage.round")
local State = T.require("games.gameplay.rounds.state")
local Rounds = gameplay.rounds
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE

T.test("it is a rounds mode named hostage, fought like an arena round", function()
	T.eq(Round.Mode.NAME, "hostage", "name")
	T.eq(Round.Mode.ROUND_STATE, State.STALEMATE, "fought in STALEMATE")
	T.eq(Round.Mode.STALEMATE_IS_ROUND, true, "the stalemate is the round")
	T.eq(Round.Mode.AUTO_SCRAMBLE, false, "no scramble")
	T.eq(Round.Mode.CREATES_TIME_LIMIT_TIMER, false, "no time limit timer")
end)

T.test("its rules are CS:S's, not TF2's", function()
	T.eq(Round.Mode.RULES_CLASS, "cs_gamerules", "the rules class")
	T.eq(Rounds.Mode.RULES_CLASS, nil, "other modes choose by their map")
end)

T.test("no control point wins it: only the hostages and the killing do", function()
	T.eq(Round.Mode:MayWinByPoints(RED, {}), false, "no points")
	T.eq(Round.Mode.OBJECTIVE, true, "the hostages are the objective")
end)

T.test("the round is untimed, after a short freeze", function()
	local settings = { stalemateTimelimit = 240 }
	T.eq(Round.Mode:StalemateSeconds(settings), 0, "untimed")
	T.defined(Round.Mode:SetupSeconds(settings), "freeze")
	T.eq(Round.Mode:SetupSeconds(settings), Round.FREEZE_SECONDS, "the freeze")
end)

T.test("a game waits for players on either team", function()
	T.defined(Round.MIN_PLAYERS, "MIN_PLAYERS")
	local needed = Round.Mode.PLAYERS_NEEDED
	local function Met(r, b)
		local have, need = Rounds.PlayersNeeded(needed, { [RED] = r, [BLUE] = b, free = 0 })
		return have >= need
	end
	T.eq(Met(Round.MIN_PLAYERS - 1, 0), false, "one short")
	T.eq(Met(Round.MIN_PLAYERS - 1, 1), true, "met across the teams")
end)

T.test("the AI war fights it with its own scenario", function()
	T.eq(T.require("features.aiwar.scenario").For(Round.Mode.NAME), T.require("features.aiwar.scenario.hostage").Scenario, "hostage")
end)

-- The round's timer ------------------------------------------------------------------

local State = T.require("games.gameplay.rounds.state")
local T0 = 100
local W = Rounds.WINREASON

local function Settings(over)
	local s = {
		respawnWaveTime = 10, bonusRoundTime = 15, enableRoundWaitTime = 1, stalemateEnable = false,
		stalemateTimelimit = 240, winlimit = 0, maxrounds = 0, timelimit = 0, matchEndAtTimelimit = false,
		chattime = 10, mapResetTime = 0, scrambleAuto = true, scrambleWinDifference = 1,
		arenaPreroundTime = 10, arenaRoundTime = 0, hostageRoundTime = 0,
	}
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function World(over)
	local w = {
		havePlayers = true,
		teams = { [RED] = { players = 2, alive = 2 }, [BLUE] = { players = 2, alive = 2 } },
		scores = { [RED] = 0, [BLUE] = 0 },
		stalemateTimerLeft = nil,
		timerMayExpire = true,
		mapHasActiveTimer = false,
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

-- A hostage round, fought from the end of its freeze.
local FIGHT_AT = T0 + Rounds.PREROUND_SECONDS + Round.FREEZE_SECONDS
local function Fighting(settings)
	local round = Rounds.New(Settings(settings))
	T.eq(round:SetMode(Round.Mode), true, "hostage chosen")
	round:Think(T0, World())
	round:Think(T0 + Rounds.PREROUND_SECONDS, World())
	round:Think(FIGHT_AT, World())
	T.eq(round:State(), State.STALEMATE, "fought in STALEMATE")
	T.eq(round:InSetup(), false, "out of the freeze")
	return round
end

T.test("a timed hostage round has its stalemate timer, an untimed one none", function()
	T.eq(Round.Mode:StalemateSeconds(Settings({ hostageRoundTime = 300 })), 300, "timed")
	T.eq(Round.Mode:StalemateSeconds(Settings()), 0, "untimed")
end)

T.test("when the round's timer runs out the hostages were not rescued: RED wins", function()
	local round = Fighting({ hostageRoundTime = 300 })
	local effects = round:Think(FIGHT_AT + 300, World({ stalemateTimerLeft = 0 }))
	local win = Has(effects, "publish_win")
	T.eq(win ~= nil, true, "a round win, not a drawn match")
	T.eq(win.winner, RED, "RED")
	T.eq(win.reason, W.HOSTAGES_NOT_RESCUED, "the hostages were not rescued")
	T.eq(Has(effects, "intermission"), nil, "the game goes on")
end)

T.test("a mode that names no timer winner still ends a stalemate drawn", function()
	local Arena = T.require("features.arena.round")
	local round = Rounds.New(Settings({ arenaRoundTime = 300 }))
	round:SetMode(Arena.Mode)
	round:Think(T0, World())
	round:Think(T0 + Rounds.PREROUND_SECONDS, World())
	round:Think(T0 + Rounds.PREROUND_SECONDS + 10, World())
	local effects = round:Think(T0 + 400, World({ stalemateTimerLeft = 0 }))
	T.eq(Has(effects, "publish_win"), nil, "no winner")
end)

T.test("killing all of BLU before the timer still wins the round for RED", function()
	local round = Fighting({ hostageRoundTime = 300 })
	local effects = round:Think(FIGHT_AT + 20, World({ teams = { [RED] = { players = 2, alive = 2 }, [BLUE] = { players = 2, alive = 0 } } }))
	T.eq(Has(effects, "stalemate_winner").team, RED, "RED")
end)

T.finish()
