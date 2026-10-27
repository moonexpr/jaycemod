-- nextsoldier.bot_quota: how many bot players a server keeps, by
-- TF2's tf_bot_quota rules (CTFBotManager::MaintainBotQuota): a quota of
-- bots, of players (fill) or of bots per human (match), one bot added or
-- kicked at a time, never taking the last free slot.
local T = dofile("tests/harness.lua")
local Quota = nextsoldier.bot_quota
local Teams = gameplay.teams

local SLOTS = 32

local function Population(humans, bots, spectators)
	return {
		humans = humans,
		bots = bots,
		spectators = spectators or 0,
		slots = SLOTS,
	}
end

local function Settings(mode, quota, joinAfterPlayer)
	return {
		mode = mode,
		quota = quota,
		joinAfterPlayer = joinAfterPlayer or false,
	}
end

T.test("the modes parse from tf_bot_quota_mode's words, and nothing else", function()
	T.eq(Quota.Mode("normal"), Quota.NORMAL, "normal")
	T.eq(Quota.Mode("fill"), Quota.FILL, "fill")
	T.eq(Quota.Mode("match"), Quota.MATCH, "match")
	T.eq(Quota.Mode("FILL"), Quota.FILL, "any case")
	T.eq(Quota.Mode("crowd"), nil, "an unknown word")
end)

T.test("normal keeps the quota of bots whoever else plays", function()
	T.eq(Quota.Wanted(Settings(Quota.NORMAL, 6), Population(0, 0)), 6, "an empty server")
	T.eq(Quota.Wanted(Settings(Quota.NORMAL, 6), Population(4, 6)), 6, "with four humans")
end)

T.test("fill tops the players on the game teams up to the quota", function()
	T.eq(Quota.Wanted(Settings(Quota.FILL, 6), Population(2, 0)), 4, "two humans leave room for four")
	T.eq(Quota.Wanted(Settings(Quota.FILL, 6), Population(2, 0, 3)), 4, "spectators are not players")
	T.eq(Quota.Wanted(Settings(Quota.FILL, 6), Population(8, 0)), 0, "more humans than the quota: none")
end)

T.test("match keeps the quota of bots for each human on the game teams", function()
	T.eq(Quota.Wanted(Settings(Quota.MATCH, 2), Population(3, 0)), 6, "two each for three")
	T.eq(Quota.Wanted(Settings(Quota.MATCH, 2), Population(0, 0)), 0, "none for nobody")
end)

T.test("join after player: no bots until a human plays on a game team", function()
	T.eq(Quota.Wanted(Settings(Quota.NORMAL, 6, true), Population(0, 0, 2)), 0, "spectators only")
	T.eq(Quota.Wanted(Settings(Quota.NORMAL, 6, true), Population(1, 0)), 6, "one human")
end)

T.test("bots never take the last free slot, so a human can still join", function()
	local population = Population(SLOTS - 4, 0, 1)
	T.eq(Quota.Wanted(Settings(Quota.NORMAL, 10), population), SLOTS - (SLOTS - 4) - 1 - 1, "the slots left but one")
	T.eq(Quota.Wanted(Settings(Quota.NORMAL, 10), Population(SLOTS, 0)), 0, "a full server")
end)

T.test("a step adds or kicks one bot toward the quota, and rests on it", function()
	T.eq(Quota.Step(Settings(Quota.NORMAL, 3), Population(1, 0)), Quota.ADD, "short")
	T.eq(Quota.Step(Settings(Quota.NORMAL, 3), Population(1, 3)), nil, "on the quota")
	T.eq(Quota.Step(Settings(Quota.NORMAL, 3), Population(1, 5)), Quota.KICK, "over")
	T.eq(Quota.Step(Settings(Quota.FILL, 3), Population(2, 2)), Quota.KICK, "a human joined a filled server")
end)

T.test("a kicked bot comes from the team with more players, else the one with more bots", function()
	local function Side(players, bots)
		return {
			players = players,
			bots = bots,
		}
	end
	T.eq(Quota.TeamToKick({ [Teams.RED] = Side(5, 3), [Teams.BLUE] = Side(4, 4) }), Teams.RED, "RED is larger")
	T.eq(Quota.TeamToKick({ [Teams.RED] = Side(4, 1), [Teams.BLUE] = Side(4, 3) }), Teams.BLUE, "even: BLU has more bots")
	T.eq(Quota.TeamToKick({ [Teams.RED] = Side(6, 0), [Teams.BLUE] = Side(2, 2) }), Teams.BLUE, "RED has no bot to kick")
	T.eq(Quota.TeamToKick({ [Teams.RED] = Side(1, 0), [Teams.BLUE] = Side(1, 0) }), nil, "no bots at all")
end)

T.finish()
