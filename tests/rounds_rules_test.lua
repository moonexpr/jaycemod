-- foundation.rounds: sudden death, the game's limits, played-round history
-- and respawn wave times, as CTeamplayRoundBasedRules computes them. The
-- control point rules (TeamOwnsAllPoints, ChooseRound, TeamMayCapturePoint...)
-- are foundation.capture's, tested there.
local T = dofile("tests/harness.lua")
local R = T.require("foundation.rounds")
local Teams = T.require("foundation.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

-- State_Think_STALEMATE's teams: players on each side and how many live.
local function Sides(redPlayers, redAlive, bluPlayers, bluAlive)
	return {
		[RED] = {
			players = redPlayers,
			alive = redAlive,
		},
		[BLU] = {
			players = bluPlayers,
			alive = bluAlive,
		},
	}
end

-- CheckTimeLimit's question: minutes of mp_timelimit, seconds left.
local function Reached(timelimit, timeLeft, canChange, afterStalemate)
	return R.TimeLimitReached({
		timelimit = timelimit,
		timeLeft = timeLeft,
		canChange = canChange,
		afterStalemate = afterStalemate,
	})
end

local function Scores(red, blu)
	return {
		[RED] = red,
		[BLU] = blu,
	}
end

T.test("played-round history keeps the two most recent", function()
	local previous = {}
	previous = R.AddPlayedRound(previous, "a")
	previous = R.AddPlayedRound(previous, "b")
	previous = R.AddPlayedRound(previous, "c")
	T.eq(#previous, 2)
	T.eq(previous[1], "c")
	T.eq(previous[2], "b")
end)

-- StalemateOutcome (State_Think_STALEMATE) ------------------------------------------

T.test("a team with nobody alive loses sudden death", function()
	local winner, draw = R.StalemateOutcome(Sides(3, 0, 2, 1))
	T.eq(winner, BLU)
	T.eq(draw, false)
end)

T.test("an empty team counts as dead", function()
	local winner = R.StalemateOutcome(Sides(1, 1, 0, 0))
	T.eq(winner, RED)
end)

T.test("both teams dead is a draw", function()
	local winner, draw = R.StalemateOutcome(Sides(1, 0, 1, 0))
	T.eq(winner, nil)
	T.eq(draw, true)
end)

T.test("both teams alive goes on", function()
	local winner, draw = R.StalemateOutcome(Sides(1, 1, 1, 1))
	T.eq(winner, nil)
	T.eq(draw, false)
end)

-- Limits -----------------------------------------------------------------------

T.test("time left counts down from the map reset", function()
	T.eq(R.TimeLeft(100, 1, 130), 30)
	T.eq(R.TimeLeft(100, 1, 200), 0)
end)

T.test("win limit is reached by the score", function()
	T.eq(R.WinLimitReached(3, Scores(1, 3)), true)
	T.eq(R.WinLimitReached(3, Scores(1, 2)), false)
	T.eq(R.WinLimitReached(0, Scores(9, 9)), false)
end)

T.test("max rounds counts full rounds played", function()
	T.eq(R.MaxRoundsReached(2, 2), true)
	T.eq(R.MaxRoundsReached(2, 1), false)
	T.eq(R.MaxRoundsReached(0, 50), false)
end)

T.test("time limit ends the map at zero", function()
	T.eq(Reached(30, 0, true, false), true)
	T.eq(Reached(30, 900, true, false), false)
	T.eq(Reached(0, 0, true, false), false)
end)

T.test("under five minutes left the map ends at the round's end", function()
	T.eq(Reached(30, 299, true, false), true)
	T.eq(Reached(5, 299, true, false), false)
end)

T.test("mini-rounds that must all be played hold the time limit", function()
	T.eq(Reached(30, 0, false, false), false)
	T.eq(Reached(0, 0, false, true), true)
end)

T.test("the time limit may change level unless unplayed mini-rounds must be played", function()
	T.eq(R.CanChangeLevelForTimeLimit(false, true, true, 1), false)
	T.eq(R.CanChangeLevelForTimeLimit(true, true, true, 1), true)
	T.eq(R.CanChangeLevelForTimeLimit(false, true, false, 1), true)
	T.eq(R.CanChangeLevelForTimeLimit(false, true, true, 0), true)
end)

T.test("the timelimit winner is the team with more points, or nobody when tied", function()
	T.eq(R.TimelimitWinner(Scores(2, 2)), NOBODY)
	T.eq(R.TimelimitWinner(Scores(3, 2)), RED)
	T.eq(R.TimelimitWinner(Scores(1, 2)), BLU)
end)

T.test("a full round or an expired time limit rewards the winner", function()
	T.eq(R.ShouldRewardTeam(true, 0, 0, false), true)
	T.eq(R.ShouldRewardTeam(false, 0, 0, false), false)
	T.eq(R.ShouldRewardTeam(false, 30, 0, false), true)
	T.eq(R.ShouldRewardTeam(true, 0, 0, true), false)
end)

T.test("a team's respawn wave is an admin's override, else the map's, else mp_respawnwavetime", function()
	T.eq(R.WaveTime(-1, -1, 10), 10, "the convar")
	T.eq(R.WaveTime(-1, 6, 10), 6, "the map's")
	T.eq(R.WaveTime(2, 6, 10), 2, "the admin's")
	T.eq(R.WaveTime(0, 6, 10), 0, "instant")
end)

T.finish()
