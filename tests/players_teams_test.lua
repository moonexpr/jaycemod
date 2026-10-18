local T = dofile("tests/harness.lua")
local L = T.require("foundation.teams")

local STATE = T.require("foundation.rounds.state")

local UNASSIGNED, SPEC, RED, BLU = L.UNASSIGNED, L.SPECTATOR, L.RED, L.BLUE

-- jointeam (CTFPlayer::HandleCommand_JoinTeam)

-- Humiliation: the losers hold their fire while the winners celebrate.

T.test("the losers of a round or of the match cannot attack; nobody else is held", function()
	T.eq(L.Humiliated(STATE.TEAM_WIN, RED, BLU), true, "a round's losers")
	T.eq(L.Humiliated(STATE.TEAM_WIN, RED, RED), false, "its winners")
	T.eq(L.Humiliated(STATE.GAME_OVER, BLU, RED), true, "the match's losers")
	T.eq(L.Humiliated(STATE.GAME_OVER, BLU, BLU), false, "its winners")
	T.eq(L.Humiliated(STATE.TEAM_WIN, UNASSIGNED, RED), false, "a stalemate humiliates nobody")
	T.eq(L.Humiliated(STATE.TEAM_WIN, RED, UNASSIGNED), false, "nor anyone of no team")
	T.eq(L.Humiliated(STATE.RND_RUNNING, RED, BLU), false, "a round running")
end)

-- TF_COND_CRITBOOSTED_BONUS_TIME: the winners crit the humiliated losers.
T.test("the winners of a round or of the match are crit boosted; nobody else is", function()
	T.eq(L.BonusCrits(STATE.TEAM_WIN, RED, RED), true, "a round's winners")
	T.eq(L.BonusCrits(STATE.TEAM_WIN, RED, BLU), false, "its losers")
	T.eq(L.BonusCrits(STATE.GAME_OVER, BLU, BLU), true, "the match's winners")
	T.eq(L.BonusCrits(STATE.TEAM_WIN, UNASSIGNED, RED), false, "a stalemate crits nobody")
	T.eq(L.BonusCrits(STATE.TEAM_WIN, RED, UNASSIGNED), false, "nor anyone of no team")
	T.eq(L.BonusCrits(STATE.RND_RUNNING, RED, RED), false, "a round running")
end)

-- mp_friendlyfire (CTFGameRules::FPlayerCanTakeDamage): off, a teammate's
-- hit hurts nobody but its attacker; those of no team are anyone's.
T.test("without friendly fire teammates cannot hurt each other; anyone else can", function()
	T.eq(L.FriendlySpared(false, RED, RED, false), true, "a teammate")
	T.eq(L.FriendlySpared(false, RED, BLU, false), false, "an enemy")
	T.eq(L.FriendlySpared(false, RED, RED, true), false, "oneself")
	T.eq(L.FriendlySpared(false, UNASSIGNED, UNASSIGNED, false), false, "the world and the teamless")
	T.eq(L.FriendlySpared(true, RED, RED, false), false, "friendly fire on")
end)

-- mp_forceautoteam, mp_allowspectators (HandleCommand_JoinTeam)

T.test("a join under mp_forceautoteam is auto-assigned; spectating needs mp_allowspectators", function()
	T.eq(L.ResolveJoin(RED, false, true), RED, "a free choice")
	T.eq(L.ResolveJoin(RED, true, true), L.AUTO, "forced to auto-assign")
	T.eq(L.ResolveJoin(BLU, true, true), L.AUTO, "BLU too")
	T.eq(L.ResolveJoin(L.AUTO, true, true), L.AUTO, "auto stays auto")
	T.eq(L.ResolveJoin(SPEC, true, true), SPEC, "spectating is no team pick")
	local refused, why = L.ResolveJoin(SPEC, false, false)
	T.eq(refused, nil, "no spectating with mp_allowspectators 0")
	T.eq(why, "Spectating is off on this server.", "and why")
end)

-- mp_scrambleteams_auto (CTFGameRules::ShouldScrambleTeams, HandleScrambleTeams)

T.test("teams are due a scramble once one leads by mp_scrambleteams_auto_windifference", function()
	T.eq(L.ScrambleDue({ [RED] = 3, [BLU] = 1 }, 2), true, "RED leads by 2")
	T.eq(L.ScrambleDue({ [RED] = 1, [BLU] = 4 }, 2), true, "BLU leads by 3")
	T.eq(L.ScrambleDue({ [RED] = 2, [BLU] = 1 }, 2), false, "a lead of 1")
	T.eq(L.ScrambleDue({ [RED] = 5, [BLU] = 0 }, 0), false, "0 never scrambles")
end)

T.test("a scramble deals the players out by score, best first, alternating sides", function()
	local teams = L.Scramble({
		{ id = 1, score = 5 },
		{ id = 2, score = 20 },
		{ id = 3, score = 10 },
		{ id = 4, score = 10 },
	}, BLU)
	T.eq(teams[2], BLU, "the best to the first side")
	T.eq(teams[3], RED, "the next to the other")
	T.eq(teams[4], BLU, "a tie goes by id")
	T.eq(teams[1], RED, "the last")
end)

T.test("jointeam names resolve case-insensitively", function()
	T.eq(L.ParseJoinTeam("red"), RED, "red")
	T.eq(L.ParseJoinTeam("BLUE"), BLU, "BLUE")
	T.eq(L.ParseJoinTeam("Spectator"), SPEC, "Spectator")
	T.eq(L.ParseJoinTeam("spectate"), SPEC, "spectate")
	T.eq(L.ParseJoinTeam("spectatearena"), SPEC, "spectatearena")
	T.eq(L.ParseJoinTeam("auto"), L.AUTO, "auto")
	T.eq(L.ParseJoinTeam("unassigned"), UNASSIGNED, "unassigned")
end)

T.test("jointeam accepts blu as Blue", function()
	T.eq(L.ParseJoinTeam("blu"), BLU)
end)

T.test("jointeam with an unknown name falls to RED as TF2's does", function()
	T.eq(L.ParseJoinTeam("purple"), RED)
end)

-- GetAutoTeam

T.test("auto team joins the smaller team", function()
	T.eq(L.AutoTeam(3, 1), BLU, "red heavier")
	T.eq(L.AutoTeam(1, 3), RED, "blue heavier")
end)

T.test("auto team on a tie joins BLU so a lone player can push", function()
	T.eq(L.AutoTeam(0, 0), BLU, "empty")
	T.eq(L.AutoTeam(4, 4), BLU, "even")
end)

-- WouldChangeUnbalanceTeams

T.test("joining your own team never unbalances", function()
	T.eq(L.WouldUnbalance({ [RED] = 5, [BLU] = 0 }, RED, RED, 1), false)
end)

T.test("joining the bigger team past the limit is refused", function()
	T.eq(L.WouldUnbalance({ [RED] = 1, [BLU] = 0 }, RED, UNASSIGNED, 1), true, "2 vs 0")
	T.eq(L.WouldUnbalance({ [RED] = 0, [BLU] = 0 }, RED, UNASSIGNED, 1), false, "1 vs 0")
end)

T.test("leaving a team counts against it", function()
	-- a BLU player going RED with 1 RED, 2 BLU: 2 vs 1, within limit 1
	T.eq(L.WouldUnbalance({ [RED] = 1, [BLU] = 2 }, RED, BLU, 1), false, "within")
	-- a BLU player going RED with 2 RED, 2 BLU: 3 vs 1
	T.eq(L.WouldUnbalance({ [RED] = 2, [BLU] = 2 }, RED, BLU, 1), true, "over")
end)

T.test("spectator is always allowed, and limit 0 disables the check", function()
	T.eq(L.WouldUnbalance({ [RED] = 5, [BLU] = 0 }, SPEC, RED, 1), false, "spec")
	T.eq(L.WouldUnbalance({ [RED] = 5, [BLU] = 0 }, RED, UNASSIGNED, 0), false, "limit 0")
end)

-- AreTeamsUnbalanced

T.test("teams within the limit are balanced", function()
	T.eq(L.Unbalanced({ [RED] = 3, [BLU] = 2 }, 1), nil)
end)

T.test("unbalanced teams name the heavy and light team", function()
	local heavy, light = L.Unbalanced({ [RED] = 1, [BLU] = 4 }, 1)
	T.eq(heavy, BLU, "heavy")
	T.eq(light, RED, "light")
end)

T.test("limit 0 turns balancing off", function()
	T.eq(L.Unbalanced({ [RED] = 0, [BLU] = 6 }, 0), nil)
end)

-- Both rules loop over every game team, so they hold for any number of teams.
local THIRD, NOT_PLAYING = 4, 7 -- a game team TF2 lacks, and a team that is not in counts

T.test("joining is checked against every other team", function()
	local counts = { [RED] = 1, [BLU] = 1, [THIRD] = 0 }
	T.eq(L.WouldUnbalance(counts, RED, UNASSIGNED, 1), true, "2 vs 0 against the third team")
	T.eq(L.WouldUnbalance(counts, THIRD, UNASSIGNED, 1), false, "1 vs 1")
	T.eq(L.WouldUnbalance(counts, NOT_PLAYING, UNASSIGNED, 1), false, "not a game team")
end)

T.test("the heaviest and lightest of several teams are compared", function()
	local heavy, light = L.Unbalanced({ [RED] = 2, [BLU] = 4, [THIRD] = 1 }, 1)
	T.eq(heavy, BLU, "heavy")
	T.eq(light, THIRD, "light")
end)

-- BalanceTeams

T.test("switches required is half the difference, rounded down", function()
	T.eq(L.SwitchesRequired(5, 1), 2, "5-1")
	T.eq(L.SwitchesRequired(4, 1), 1, "4-1")
end)

T.test("balance score prefers recent joiners and spares recently switched players", function()
	T.eq(L.BalanceScore(100, 40, nil), -60, "connected 60s ago")
	T.eq(L.BalanceScore(100, 40, 50), -10060, "switched 50s ago")
	T.eq(L.BalanceScore(1000, 40, 50), -960, "switched long ago")
end)

T.test("balance picks the highest scores first", function()
	local cands = {
		{ id = "old", score = -500, alive = false },
		{ id = "new", score = -10, alive = false },
		{ id = "mid", score = -100, alive = false },
	}
	local picked = L.PickBalanceSwitches(cands, 2, false)
	T.eq(#picked, 2, "count")
	T.eq(picked[1], "new", "first")
	T.eq(picked[2], "mid", "second")
end)

T.test("mid-round balance only moves dead players, among the best n+2", function()
	local cands = {
		{ id = "a", score = -1, alive = true },
		{ id = "b", score = -2, alive = true },
		{ id = "c", score = -3, alive = true },
		{ id = "d", score = -4, alive = false },
	}
	T.eq(#L.PickBalanceSwitches(cands, 1, true), 0, "d is outside the best 3")
	cands[3].alive = false
	local picked = L.PickBalanceSwitches(cands, 1, true)
	T.eq(picked[1], "c", "dead candidate within range")
end)

-- CFilterTFTeam::PassesFilterImpl, with CBaseFilter::PassesFilter's negation

T.test("team filter passes its own team", function()
	T.eq(L.FilterPasses(RED, false, RED, STATE.RND_RUNNING, UNASSIGNED), true, "match")
	T.eq(L.FilterPasses(RED, false, BLU, STATE.RND_RUNNING, UNASSIGNED), false, "other")
	T.eq(L.FilterPasses(RED, true, BLU, STATE.RND_RUNNING, UNASSIGNED), true, "negated other")
end)

T.test("winners pass every team filter during team win, negated or not", function()
	T.eq(L.FilterPasses(RED, false, BLU, STATE.TEAM_WIN, BLU), true, "plain")
	T.eq(L.FilterPasses(RED, true, BLU, STATE.TEAM_WIN, BLU), true, "negated")
	T.eq(L.FilterPasses(BLU, true, BLU, STATE.TEAM_WIN, BLU), true, "own negated")
end)

T.test("losers keep the normal filter during team win", function()
	T.eq(L.FilterPasses(BLU, false, RED, STATE.TEAM_WIN, BLU), false)
end)

-- CFuncRespawnRoomVisualizer::ShouldCollide / ShouldTransmit

T.test("a visualizer blocks only the enemies of its team", function()
	T.eq(L.VisualizerBlocks(RED, BLU), true, "blu at red door")
	T.eq(L.VisualizerBlocks(RED, RED), false, "red at red door")
	T.eq(L.VisualizerBlocks(RED, UNASSIGNED), false, "unassigned")
	T.eq(L.VisualizerBlocks(UNASSIGNED, BLU), false, "no team")
end)

T.test("a visualizer on a non-playing team blocks every player", function()
	T.eq(L.VisualizerBlocks(L.HALLOWEEN, RED), true)
end)

T.test("a visualizer shows to enemies while its room is active and nobody has won", function()
	T.eq(L.VisualizerVisible(RED, true, false, BLU), true, "enemy")
	T.eq(L.VisualizerVisible(RED, true, false, RED), false, "friend")
	T.eq(L.VisualizerVisible(RED, false, false, BLU), false, "room inactive")
	T.eq(L.VisualizerVisible(RED, true, true, BLU), false, "team win")
	T.eq(L.VisualizerVisible(RED, true, false, SPEC), false, "spectator")
end)

-- CRegenerateZone::Touch

T.test("a resupply zone serves its own team", function()
	T.eq(L.RegenerateAllowed(RED, RED, STATE.RND_RUNNING, UNASSIGNED), true, "own")
	T.eq(L.RegenerateAllowed(RED, BLU, STATE.RND_RUNNING, UNASSIGNED), false, "enemy")
	T.eq(L.RegenerateAllowed(UNASSIGNED, BLU, STATE.RND_RUNNING, UNASSIGNED), true, "any team")
end)

T.test("during team win every zone serves the winners and none the losers", function()
	T.eq(L.RegenerateAllowed(RED, BLU, STATE.TEAM_WIN, BLU), true, "winner at enemy locker")
	T.eq(L.RegenerateAllowed(RED, RED, STATE.TEAM_WIN, BLU), false, "loser at own locker")
end)

T.test("no resupply in stalemate", function()
	T.eq(L.RegenerateAllowed(RED, RED, STATE.STALEMATE, UNASSIGNED), false)
end)

-- game_teamplay_broadcast_audio: who hears a sound the server broadcast

T.test("a sound for a team is heard by that team only; UNASSIGNED means everyone", function()
	T.eq(L.HearsBroadcast(RED, false, RED), true, "RED hears RED's")
	T.eq(L.HearsBroadcast(RED, false, BLU), false, "BLU does not")
	T.eq(L.HearsBroadcast(RED, false, SPEC), false, "spectators do not")
	T.eq(L.HearsBroadcast(SPEC, false, SPEC), true, "spectators hear the spectators' (which round won)")
	T.eq(L.HearsBroadcast(SPEC, false, RED), false, "RED does not")
	T.eq(L.HearsBroadcast(RED, false, UNASSIGNED), false, "nor the unassigned")
	T.eq(L.HearsBroadcast(UNASSIGNED, false, BLU), true, "everyone: BLU")
	T.eq(L.HearsBroadcast(UNASSIGNED, false, SPEC), true, "everyone: spectators")
end)

T.test("a sound for the others is heard by everyone not on the team, spectators included", function()
	T.eq(L.HearsBroadcast(RED, true, RED), false, "not RED")
	T.eq(L.HearsBroadcast(RED, true, BLU), true, "BLU")
	T.eq(L.HearsBroadcast(RED, true, SPEC), true, "spectators")
	T.eq(L.HearsBroadcast(RED, true, UNASSIGNED), true, "the unassigned")
end)

-- The two teams that play are each other's opponent; no other team has one.

T.test("RED's opponent is BLU and BLU's is RED; a team that does not play has none", function()
	T.eq(L.EnemyOf(RED), BLU, "RED fights BLU")
	T.eq(L.EnemyOf(BLU), RED, "BLU fights RED")
	T.eq(L.EnemyOf(UNASSIGNED), nil, "the unassigned")
	T.eq(L.EnemyOf(SPEC), nil, "spectators")
	T.eq(L.EnemyOf(L.HALLOWEEN), nil, "the Halloween team")
end)

T.finish()
