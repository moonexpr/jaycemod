-- foundation.rounds: mini-round selection, win checks and limits, as the SDK's
-- CTeamControlPointMaster / CTeamControlPointRound / CTeamplayRoundBasedRules
-- compute them.
local T = dofile("tests/harness.lua")
local R = T.require("foundation.rounds")
local Teams = T.require("foundation.teams")

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

local function P(owner, group) return { owner = owner, group = group or 0 } end

-- TeamOwnsAllPoints ---------------------------------------------------------

T.test("one team owning every point of a group wins it", function()
	T.eq(R.TeamOwnsAllPoints({ P(BLU), P(BLU) }), BLU)
end)

T.test("mixed owners in the only group is nobody", function()
	T.eq(R.TeamOwnsAllPoints({ P(BLU), P(RED) }), NOBODY)
end)

T.test("neutral points are nobody", function()
	T.eq(R.TeamOwnsAllPoints({ P(NOBODY), P(NOBODY) }), NOBODY)
end)

-- plr_pipeline: blue_cap_A is alone in group 1, red_cap_A in group 0.
T.test("a group owned outright wins even when another group is contested", function()
	T.eq(R.TeamOwnsAllPoints({ P(NOBODY, 0), P(BLU, 1) }), BLU)
end)

T.test("groups are reported in group order", function()
	T.eq(R.TeamOwnsAllPoints({ P(BLU, 1), P(RED, 0) }), RED)
end)

T.test("an empty point list is nobody", function()
	T.eq(R.TeamOwnsAllPoints({}), NOBODY)
end)

-- RoundWinner / RoundPlayable ------------------------------------------------

T.test("the restricted team cannot win by capping", function()
	T.eq(R.RoundWinner(RED, { P(RED), P(RED) }), nil)
end)

T.test("the other team wins by capping everything", function()
	T.eq(R.RoundWinner(RED, { P(BLU), P(BLU) }), BLU)
end)

T.test("restrict 1 means neither team wins by capping", function()
	T.eq(R.RoundWinner(R.RESTRICT_NEITHER, { P(BLU), P(BLU) }), nil)
end)

T.test("a round someone has already won is not playable", function()
	T.eq(R.RoundPlayable(RED, { P(BLU), P(BLU) }), false)
end)

T.test("a round owned by its restricted team is playable", function()
	T.eq(R.RoundPlayable(RED, { P(RED), P(RED) }), true)
end)

T.test("restrict 1 rounds are always playable", function()
	T.eq(R.RoundPlayable(R.RESTRICT_NEITHER, { P(BLU), P(BLU) }), true)
end)

-- ChooseRound (GetControlPointRoundToPlay) ---------------------------------------

local function first(n) return 1 end
local function last(n) return n end

local function Rounds(list)
	local rounds = {}
	for i, r in ipairs(list) do rounds[i] = { name = r[1], priority = r[2], playable = r[3] } end
	return rounds
end

local NO_HISTORY = { previous = {}, first = nil, firstAfterRestart = true }

T.test("the highest-priority playable round is chosen (pl_goldrush stage 1)", function()
	local rounds = Rounds({ { "round_c", 0, true }, { "round_a", 2, true }, { "round_b", 1, true } })
	T.eq(rounds[R.ChooseRound(rounds, NO_HISTORY, first)].name, "round_a")
end)

T.test("a won round is skipped for the next priority (pl_goldrush stage 2)", function()
	local rounds = Rounds({ { "round_a", 2, false }, { "round_b", 1, true }, { "round_c", 0, true } })
	T.eq(rounds[R.ChooseRound(rounds, NO_HISTORY, first)].name, "round_b")
end)

T.test("no playable round chooses nothing", function()
	local rounds = Rounds({ { "round_a", 2, false } })
	T.eq(R.ChooseRound(rounds, NO_HISTORY, first), nil)
end)

T.test("the last played round is avoided among equals", function()
	local rounds = Rounds({ { "x", 1, true }, { "y", 1, true } })
	local history = { previous = { "x" }, firstAfterRestart = false }
	T.eq(rounds[R.ChooseRound(rounds, history, first)].name, "y")
	T.eq(rounds[R.ChooseRound(rounds, history, last)].name, "y")
end)

T.test("the first round after the last restart is avoided after a new restart", function()
	local rounds = Rounds({ { "x", 1, true }, { "y", 1, true }, { "z", 1, true } })
	local history = { previous = {}, first = "x", firstAfterRestart = true }
	T.eq(rounds[R.ChooseRound(rounds, history, first)].name, "y")
end)

T.test("previously played rounds are skipped while others remain", function()
	local rounds = Rounds({ { "x", 1, true }, { "y", 1, true }, { "z", 1, true } })
	local history = { previous = { "z", "x" }, firstAfterRestart = false }
	-- last played (z) is removed first; x is previously played, so y remains
	T.eq(rounds[R.ChooseRound(rounds, history, first)].name, "y")
end)

T.test("a single candidate is played even if it was played before", function()
	local rounds = Rounds({ { "x", 1, true } })
	local history = { previous = { "x" }, firstAfterRestart = false }
	T.eq(rounds[R.ChooseRound(rounds, history, first)].name, "x")
end)

T.test("played-round history keeps the two most recent", function()
	local previous = {}
	previous = R.AddPlayedRound(previous, "a")
	previous = R.AddPlayedRound(previous, "b")
	previous = R.AddPlayedRound(previous, "c")
	T.eq(#previous, 2)
	T.eq(previous[1], "c")
	T.eq(previous[2], "b")
end)

T.test("the playable count counts playable rounds", function()
	T.eq(R.PlayableCount(Rounds({ { "a", 1, true }, { "b", 1, false }, { "c", 0, true } })), 2)
end)

T.test("stage numbers follow priority order", function()
	local rounds = Rounds({ { "round_c", 0, true }, { "round_a", 2, true }, { "round_b", 1, true } })
	T.eq(R.StageOf(rounds, 3), 2)
	T.eq(R.StageOf(rounds, 1), 3)
	T.eq(R.StageOf(rounds, 2), 1)
end)

-- RoundsRemaining (CalcNumRoundsRemaining) ----------------------------------------

T.test("rounds remaining for BLU on pl_goldrush before any stage", function()
	local points = { P(RED), P(RED), P(RED), P(RED), P(RED), P(RED), P(RED) }
	local rounds = {
		{ restrict = RED, points = { 1, 2 } },
		{ restrict = RED, points = { 3, 4 } },
		{ restrict = RED, points = { 5, 6, 7 } },
	}
	T.eq(R.RoundsRemaining(BLU, rounds, points), 3)
	points[1].owner, points[2].owner = BLU, BLU
	T.eq(R.RoundsRemaining(BLU, rounds, points), 2)
end)

T.test("rounds remaining stops when no round can make progress", function()
	local points = { P(RED), P(RED) }
	local rounds = { { restrict = RED, points = { 1 } } }
	T.eq(R.RoundsRemaining(BLU, rounds, points), 1)
end)

-- StalemateOutcome (State_Think_STALEMATE) ------------------------------------------

T.test("a team with nobody alive loses sudden death", function()
	local winner, draw = R.StalemateOutcome({ [RED] = { players = 3, alive = 0 }, [BLU] = { players = 2, alive = 1 } })
	T.eq(winner, BLU)
	T.eq(draw, false)
end)

T.test("an empty team counts as dead", function()
	local winner = R.StalemateOutcome({ [RED] = { players = 1, alive = 1 }, [BLU] = { players = 0, alive = 0 } })
	T.eq(winner, RED)
end)

T.test("both teams dead is a draw", function()
	local winner, draw = R.StalemateOutcome({ [RED] = { players = 1, alive = 0 }, [BLU] = { players = 1, alive = 0 } })
	T.eq(winner, nil)
	T.eq(draw, true)
end)

T.test("both teams alive goes on", function()
	local winner, draw = R.StalemateOutcome({ [RED] = { players = 1, alive = 1 }, [BLU] = { players = 1, alive = 1 } })
	T.eq(winner, nil)
	T.eq(draw, false)
end)

-- Limits -----------------------------------------------------------------------

T.test("time left counts down from the map reset", function()
	T.eq(R.TimeLeft(100, 1, 130), 30)
	T.eq(R.TimeLeft(100, 1, 200), 0)
end)

T.test("win limit is reached by the score", function()
	T.eq(R.WinLimitReached(3, { [RED] = 1, [BLU] = 3 }), true)
	T.eq(R.WinLimitReached(3, { [RED] = 1, [BLU] = 2 }), false)
	T.eq(R.WinLimitReached(0, { [RED] = 9, [BLU] = 9 }), false)
end)

T.test("max rounds counts full rounds played", function()
	T.eq(R.MaxRoundsReached(2, 2), true)
	T.eq(R.MaxRoundsReached(2, 1), false)
	T.eq(R.MaxRoundsReached(0, 50), false)
end)

T.test("time limit ends the map at zero", function()
	T.eq(R.TimeLimitReached({ timelimit = 30, timeLeft = 0, canChange = true }), true)
	T.eq(R.TimeLimitReached({ timelimit = 30, timeLeft = 900, canChange = true }), false)
	T.eq(R.TimeLimitReached({ timelimit = 0, timeLeft = 0, canChange = true }), false)
end)

T.test("under five minutes left the map ends at the round's end", function()
	T.eq(R.TimeLimitReached({ timelimit = 30, timeLeft = 299, canChange = true }), true)
	T.eq(R.TimeLimitReached({ timelimit = 5, timeLeft = 299, canChange = true }), false)
end)

T.test("mini-rounds that must all be played hold the time limit", function()
	T.eq(R.TimeLimitReached({ timelimit = 30, timeLeft = 0, canChange = false }), false)
	T.eq(R.TimeLimitReached({ timelimit = 0, timeLeft = 0, canChange = false, afterStalemate = true }), true)
end)

T.test("the time limit may change level unless unplayed mini-rounds must be played", function()
	T.eq(R.CanChangeLevelForTimeLimit(false, true, true, 1), false)
	T.eq(R.CanChangeLevelForTimeLimit(true, true, true, 1), true)
	T.eq(R.CanChangeLevelForTimeLimit(false, true, false, 1), true)
	T.eq(R.CanChangeLevelForTimeLimit(false, true, true, 0), true)
end)

T.test("the timelimit winner is the team with more points, or nobody when tied", function()
	T.eq(R.TimelimitWinner({ [RED] = 2, [BLU] = 2 }), NOBODY)
	T.eq(R.TimelimitWinner({ [RED] = 3, [BLU] = 2 }), RED)
	T.eq(R.TimelimitWinner({ [RED] = 1, [BLU] = 2 }), BLU)
end)

T.test("a full round or an expired time limit rewards the winner", function()
	T.eq(R.ShouldRewardTeam(true, 0, 0, false), true)
	T.eq(R.ShouldRewardTeam(false, 0, 0, false), false)
	T.eq(R.ShouldRewardTeam(false, 30, 0, false), true)
	T.eq(R.ShouldRewardTeam(true, 0, 0, true), false)
end)

-- Capture rules (TeamMayCapturePoint) ------------------------------------------------

T.test("point ranks are 0-based in index order", function()
	local ranks = R.Ranks({ 4, 1, 3, 2 })
	T.eq(ranks[1], 3)
	T.eq(ranks[2], 0)
	T.eq(ranks[3], 2)
	T.eq(ranks[4], 1)
end)

T.test("the base point is the team's end of the chain", function()
	local points = { { index = 0, defaultOwner = BLU }, { index = 1, defaultOwner = NOBODY }, { index = 2, defaultOwner = RED } }
	T.eq(R.BaseControlPoint(BLU, points), 0)
	T.eq(R.BaseControlPoint(RED, points), 2)
	T.eq(R.BaseControlPoint(NOBODY, { { index = 0, defaultOwner = RED } }), R.NO_POINT)
end)

T.test("the farthest owned point walks from the base", function()
	local owners = { [0] = BLU, [1] = BLU, [2] = NOBODY, [3] = RED }
	T.eq(R.FarthestOwnedControlPoint(BLU, owners, 4, 0), 1)
	T.eq(R.FarthestOwnedControlPoint(RED, owners, 4, 3), 3)
	T.eq(R.FarthestOwnedControlPoint(RED, owners, 4, R.NO_POINT), R.NO_POINT)
end)

local function Q(over)
	local q = { caplinear = true, index = 1, team = BLU, locked = false, previous = { R.NO_POINT, R.NO_POINT, R.NO_POINT },
		playingMiniRounds = false, owners = { [0] = BLU, [1] = NOBODY, [2] = RED }, count = 3, base = 0 }
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

T.test("a point next to the team's farthest point may be capped", function()
	T.eq(R.TeamMayCapturePoint(Q()), true)
	T.eq(R.TeamMayCapturePoint(Q({ index = 2 })), false)
end)

T.test("a locked point may not be capped", function()
	T.eq(R.TeamMayCapturePoint(Q({ locked = true })), false)
end)

T.test("a point that requires itself is always cappable, locked or not", function()
	T.eq(R.TeamMayCapturePoint(Q({ locked = true, previous = { 1, R.NO_POINT, R.NO_POINT } })), true)
end)

T.test("named previous points must all be owned", function()
	T.eq(R.TeamMayCapturePoint(Q({ index = 2, previous = { 0, R.NO_POINT, R.NO_POINT } })), true)
	T.eq(R.TeamMayCapturePoint(Q({ index = 2, previous = { 0, 1, R.NO_POINT } })), false)
end)

T.test("with mini-rounds and no previous points any point is cappable", function()
	T.eq(R.TeamMayCapturePoint(Q({ index = 2, playingMiniRounds = true })), true)
end)

T.test("tf_caplinear 0 allows everything", function()
	T.eq(R.TeamMayCapturePoint(Q({ caplinear = false, locked = true })), true)
end)

T.test("a team's respawn wave is an admin's override, else the map's, else mp_respawnwavetime", function()
	T.eq(R.WaveTime(-1, -1, 10), 10, "the convar")
	T.eq(R.WaveTime(-1, 6, 10), 6, "the map's")
	T.eq(R.WaveTime(2, 6, 10), 2, "the admin's")
	T.eq(R.WaveTime(0, 6, 10), 0, "instant")
end)

T.finish()
