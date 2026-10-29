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

T.finish()
