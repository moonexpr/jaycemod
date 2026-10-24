-- features.gamemode.ready: the ready-up while a game waits for players.
-- TF2's two kinds: a tournament's teams ready as a whole (CTFGameRules'
-- IsTeamReady, "F4 = change team name/status"), MvM's defenders each
-- (IsPlayerReady, "F4 = Toggle Ready") once there are enough of them
-- (PlayerReadyStatus_HaveMinPlayersToEnable).
local T = dofile("tests/harness.lua")
local Ready = T.require("features.gamemode.ready")
local Teams = gameplay.teams

local RED, BLUE, UNASSIGNED, SPECTATOR = Teams.RED, Teams.BLUE, Teams.UNASSIGNED, Teams.SPECTATOR

local function Q(over)
	local q = {
		kind = Ready.TEAM,
		have = 1,
		need = 6,
		humans = { [RED] = 0, [BLUE] = 1 },
		teamReady = { [RED] = false, [BLUE] = false },
		defenders = RED,
		readyDefenders = 0,
	}
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

T.test("MvM readies each defender, every other mode its teams", function()
	T.eq(Ready.Kind(true), Ready.PLAYER, "MvM")
	T.eq(Ready.Kind(false), Ready.TEAM, "the rest")
end)

T.test("a team ready-up ends the wait once every team with players is ready", function()
	T.eq(Ready.Met(Q()), false, "BLU not ready")
	T.eq(Ready.Met(Q({ teamReady = { [RED] = false, [BLUE] = true } })), true, "BLU ready, RED has nobody")
	local both = { [RED] = 2, [BLUE] = 1 }
	T.eq(Ready.Met(Q({ humans = both, teamReady = { [RED] = false, [BLUE] = true } })), false, "RED has players, not ready")
	T.eq(Ready.Met(Q({ humans = both, teamReady = { [RED] = true, [BLUE] = true } })), true, "both ready")
end)

T.test("a team ready-up needs somebody on a team, and the players being there is enough on its own", function()
	T.eq(Ready.Met(Q({ humans = { [RED] = 0, [BLUE] = 0 }, teamReady = { [RED] = true, [BLUE] = true } })), false,
		"nobody to be ready")
	T.eq(Ready.Met(Q({ have = 6 })), true, "the players are there")
end)

T.test("an MvM ready-up waits for the players, then for every defender to ready", function()
	local mvm = { kind = Ready.PLAYER, humans = { [RED] = 2, [BLUE] = 0 } }
	local function M(over)
		local q = Q(mvm)
		for k, v in pairs(over) do q[k] = v end
		return Ready.Met(q)
	end
	T.eq(M({ have = 3, need = 6, readyDefenders = 2 }), false, "too few, all ready")
	T.eq(M({ have = 6, need = 6, readyDefenders = 1 }), false, "enough, one not ready")
	T.eq(M({ have = 6, need = 6, readyDefenders = 2 }), true, "enough, all ready")
	T.eq(M({ have = 6, need = 6, readyDefenders = 0, humans = { [RED] = 0, [BLUE] = 0 } }), true,
		"no defender to ready: the count alone, as before")
end)

T.test("MvM's ready toggle is enabled only once its players are there", function()
	T.eq(Ready.Enabled(Q({ kind = Ready.PLAYER, have = 5, need = 6 })), false, "waiting for players")
	T.eq(Ready.Enabled(Q({ kind = Ready.PLAYER, have = 6, need = 6 })), true, "enough")
	T.eq(Ready.Enabled(Q({ kind = Ready.TEAM, have = 1, need = 6 })), true, "a team readies at any count")
end)

T.test("who may toggle: a team's player its team, an MvM defender themself", function()
	T.eq(Ready.MayToggle(Ready.TEAM, BLUE, RED), true, "BLU")
	T.eq(Ready.MayToggle(Ready.TEAM, RED, RED), true, "RED")
	T.eq(Ready.MayToggle(Ready.TEAM, UNASSIGNED, RED), false, "no team")
	T.eq(Ready.MayToggle(Ready.TEAM, SPECTATOR, RED), false, "a spectator")
	T.eq(Ready.MayToggle(Ready.PLAYER, RED, RED), true, "a defender")
	T.eq(Ready.MayToggle(Ready.PLAYER, BLUE, RED), false, "an invader")
end)

T.finish()
