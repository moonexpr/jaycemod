local T = dofile("tests/harness.lua")
local S = gameplay.spawn

local Teams = gameplay.teams
local NO_POINT = gameplay.rounds.NO_POINT

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local KV = tostring -- the map gives keyvalues as text

local function Spawn(t)
	return S.FromKeyValues(t)
end

-- CTFTeamSpawn keyvalues

T.test("a teamspawn record reads TF2's keyvalues", function()
	local s = Spawn({ teamnum = KV(BLU), startdisabled = "1", controlpoint = "cap_a", round_bluespawn = "round_a", round_redspawn = "", spawnmode = KV(S.SPAWN_MODE_TRIGGERED), matchsummary = KV(S.MATCH_SUMMARY_WINNER) })
	T.eq(s.team, BLU, "team")
	T.eq(s.disabled, true, "disabled")
	T.eq(s.controlpoint, "cap_a", "controlpoint")
	T.eq(s.roundBlue, "round_a", "blue round")
	T.eq(s.roundRed, nil, "empty red round")
	T.eq(s.spawnMode, S.SPAWN_MODE_TRIGGERED, "spawn mode")
	T.eq(s.matchSummary, S.MATCH_SUMMARY_WINNER, "match summary")
end)

T.test("a teamspawn with no keys is enabled on no team", function()
	local s = Spawn({})
	T.eq(s.team, NOBODY, "team")
	T.eq(s.disabled, false, "disabled")
	T.eq(s.spawnMode, S.SPAWN_MODE_NORMAL, "mode")
	T.eq(s.matchSummary, S.MATCH_SUMMARY_NONE, "summary")
end)

-- CTFGameRules::IsSpawnPointValid

T.test("a spawn is valid for its team when enabled, normal and not a podium", function()
	T.eq(S.Valid(Spawn({ teamnum = KV(RED) }), RED), true, "plain")
	T.eq(S.Valid(Spawn({ teamnum = KV(RED) }), BLU), false, "other team")
	T.eq(S.Valid(Spawn({ teamnum = KV(RED), startdisabled = "1" }), RED), false, "disabled")
	T.eq(S.Valid(Spawn({ teamnum = KV(RED), spawnmode = KV(S.SPAWN_MODE_TRIGGERED) }), RED), false, "triggered")
	T.eq(S.Valid(Spawn({ teamnum = KV(RED), matchsummary = KV(S.MATCH_SUMMARY_LOSER) }), RED), false, "podium")
end)

-- CTFGameRules::SetupSpawnPointsForRound, as pl_goldrush and plr_hightower use it

local function GoldrushSpawns()
	return {
		Spawn({ teamnum = KV(NOBODY), controlpoint = "cap_a_2", round_bluespawn = "round_b", round_redspawn = "round_a" }),
		Spawn({ teamnum = KV(BLU), round_bluespawn = "round_a" }),
		Spawn({ teamnum = KV(RED), startdisabled = "1", round_redspawn = "round_c" }),
		Spawn({ teamnum = KV(RED), startdisabled = "1" }),
	}
end

local OWNERS = { cap_a_1 = RED, cap_a_2 = RED, cap_b_1 = RED, cap_b_2 = RED }
local function Owner(name) return OWNERS[name] end

T.test("stage one: the point-linked spawn takes its point's owner", function()
	local spawns = GoldrushSpawns()
	S.SetupForRound(spawns, "round_a", { cap_a_1 = true, cap_a_2 = true }, Owner)
	T.eq(spawns[1].disabled, false, "cap spawn on")
	T.eq(spawns[1].team, RED, "cap spawn RED")
	T.eq(spawns[2].disabled, false, "blue round spawn on")
	T.eq(spawns[2].team, BLU, "blue round spawn BLU")
	T.eq(spawns[3].disabled, true, "stage three spawn off")
	T.eq(spawns[4].disabled, true, "unlinked spawn off")
end)

T.test("stage two: the same spawn becomes BLU's forward spawn", function()
	local spawns = GoldrushSpawns()
	S.SetupForRound(spawns, "round_b", { cap_b_1 = true, cap_b_2 = true }, Owner)
	T.eq(spawns[1].disabled, false, "on")
	T.eq(spawns[1].team, BLU, "BLU")
	T.eq(spawns[2].disabled, true, "stage one BLU spawn off")
end)

T.test("a red round spawn is moved to RED whatever its keyvalue team", function()
	-- plr_hightower's RED spawns are TeamNum 3 with round_redspawn set.
	local spawns = { Spawn({ teamnum = KV(BLU), round_redspawn = "plr_round_C" }) }
	S.SetupForRound(spawns, "plr_round_C", {}, Owner)
	T.eq(spawns[1].team, RED, "RED")
	T.eq(spawns[1].disabled, false, "on")
end)

-- Control-point spawns without mini-rounds (SetupOnRoundStart,
-- RecalculateControlPointState, GetFarthestOwnedControlPoint)

local function Points(owners)
	local points = {}
	for i, o in ipairs(owners) do
		points[i] = { name = "cp" .. (i - 1), index = i - 1, owner = o.owner, defaultOwner = o.default }
	end
	return points
end

local function IndexOf(points)
	return function(name)
		for _, p in ipairs(points) do
			if p.name == name then return p.index end
		end
	end
end

T.test("the base point is the end of the line a team owns by default", function()
	local points = Points({ { default = RED }, { default = RED }, { default = BLU } })
	T.eq(S.BaseControlPoint(points, RED), 0, "RED holds the low end")
	T.eq(S.BaseControlPoint(points, BLU), 2, "BLU holds the high end")
	T.eq(S.BaseControlPoint(Points({ { default = NOBODY }, { default = NOBODY } }), RED), NO_POINT, "nobody")
end)

T.test("the farthest owned point with spawns is where a team spawns", function()
	local points = Points({
		{ default = RED, owner = RED },
		{ default = NOBODY, owner = RED },
		{ default = NOBODY, owner = RED },
		{ default = BLU, owner = BLU },
	})
	local spawns = {
		Spawn({ teamnum = KV(RED), controlpoint = "cp0" }),
		Spawn({ teamnum = KV(RED), controlpoint = "cp1" }),
		Spawn({ teamnum = KV(BLU), controlpoint = "cp3" }),
		Spawn({ teamnum = KV(RED) }),
	}
	local controlSpawns = S.StartControlPointSpawns(spawns, IndexOf(points))
	T.eq(spawns[1].disabled, true, "linked spawns start off")
	T.eq(spawns[4].disabled, false, "unlinked spawn untouched")
	-- RED owns 0..2 but has spawns only at 0 and 1.
	T.eq(S.FarthestOwnedPoint(RED, points, controlSpawns), 1, "farthest RED")
	S.RecalculateControlPointState(spawns, points, controlSpawns, IndexOf(points))
	T.eq(spawns[1].disabled, true, "rear RED spawn off")
	T.eq(spawns[2].disabled, false, "forward RED spawn on")
	T.eq(spawns[3].disabled, false, "BLU base spawn on")
end)

T.test("losing a point moves a team's spawn back", function()
	local points = Points({ { default = RED, owner = RED }, { default = NOBODY, owner = BLU }, { default = BLU, owner = BLU } })
	local spawns = { Spawn({ teamnum = KV(RED), controlpoint = "cp0" }), Spawn({ teamnum = KV(RED), controlpoint = "cp1" }) }
	local controlSpawns = S.StartControlPointSpawns(spawns, IndexOf(points))
	S.RecalculateControlPointState(spawns, points, controlSpawns, IndexOf(points))
	T.eq(spawns[1].disabled, false, "base spawn")
	T.eq(spawns[2].disabled, true, "lost forward spawn")
end)

-- sv_teams_spawn.lua on cp_5gorge's entities: its point_index runs 1..5, and
-- the master renumbers the points from 0 (FindControlPoints) before the
-- spawns walk them.
local function Gorge()
	local POINTS = {
		{ name = "cap_blue_1", index = 1, default = BLU },
		{ name = "cap_blue_2", index = 2, default = BLU },
		{ name = "cap_middle", index = 3, default = NOBODY },
		{ name = "cap_red_2", index = 4, default = RED },
		{ name = "cap_red_1", index = 5, default = RED },
	}
	local SPAWNS = {
		{ RED, "cap_red_1" }, { RED, "cap_middle" }, { RED, "cap_blue_2" },
		{ BLU, "cap_blue_1" }, { BLU, "cap_middle" }, { BLU, "cap_red_2" },
	}
	local byClass = { team_control_point_master = { {} }, team_control_point = {}, info_player_teamspawn = {} }
	local byName, owner = {}, {}
	local function Entity(class, name, kv)
		local ent = { name = name, kv = kv }
		function ent:GetClass() return class end
		function ent:GetName() return name end
		return ent
	end
	for _, p in ipairs(POINTS) do
		local ent = Entity("team_control_point", p.name, { point_default_owner = KV(p.default) })
		ent.index = p.index
		owner[ent] = p.default
		byClass.team_control_point[#byClass.team_control_point + 1] = ent
		byName[p.name] = { ent }
	end
	for _, s in ipairs(SPAWNS) do
		local list = byClass.info_player_teamspawn
		list[#list + 1] = Entity("info_player_teamspawn", s[2], { teamnum = KV(s[1]), controlpoint = s[2] })
	end

	local capture = {}
	function capture:Index(point) return point.index end
	function capture:Rank(point) return point.index - 1 end
	function capture:Owner(point) return owner[point] end
	function capture:CurrentRound() return nil end

	local hooks = {}
	local env = setmetatable({
		NULL = {},
		Vector = function() end,
		WS = {
			TEAM_UNASSIGNED = NOBODY,
			KeyValues = function(ent) return ent.kv end,
			Feature = function() return capture end,
		},
		ents = {
			FindByClass = function(class) return byClass[class] or {} end,
			FindByName = function(name) return byName[name] or {} end,
		},
		hook = {
			Add = function(event, _, fn) hooks[event] = fn end,
			Run = function() end,
		},
		IsValid = function(ent) return ent ~= nil and next(ent) ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile(T.ROOT .. "sv_teams_spawn.lua")), env)()

	local gorge = {}
	function gorge.Capture(name, team)
		owner[byName[name][1]] = team
		hooks.WSPointCaptured()
	end
	function gorge.SpawnsAt(team)
		local names = {}
		for _, ent in ipairs(env.WS.SpawnPoints(team)) do names[#names + 1] = ent:GetName() end
		return table.concat(names, " ")
	end
	return gorge
end

T.test("cp_5gorge: each team starts at its last point", function()
	local gorge = Gorge()
	T.eq(gorge.SpawnsAt(RED), "cap_red_1", "RED")
	T.eq(gorge.SpawnsAt(BLU), "cap_blue_1", "BLU")
end)

T.test("cp_5gorge: BLU's spawn moves forward with its captures, and back", function()
	local gorge = Gorge()
	gorge.SpawnsAt(BLU)
	gorge.Capture("cap_middle", BLU)
	T.eq(gorge.SpawnsAt(BLU), "cap_middle", "holding the mid")
	gorge.Capture("cap_red_2", BLU)
	T.eq(gorge.SpawnsAt(BLU), "cap_red_2", "holding RED's second")
	gorge.Capture("cap_red_2", RED)
	gorge.Capture("cap_middle", RED)
	T.eq(gorge.SpawnsAt(BLU), "cap_blue_1", "pushed back to its last")
end)

T.test("cp_5gorge: RED's spawn moves forward with its captures, and back", function()
	local gorge = Gorge()
	gorge.SpawnsAt(RED)
	gorge.Capture("cap_middle", RED)
	T.eq(gorge.SpawnsAt(RED), "cap_middle", "holding the mid")
	gorge.Capture("cap_blue_2", RED)
	T.eq(gorge.SpawnsAt(RED), "cap_blue_2", "holding BLU's second")
	gorge.Capture("cap_blue_2", BLU)
	gorge.Capture("cap_middle", BLU)
	T.eq(gorge.SpawnsAt(RED), "cap_red_1", "pushed back to its last")
end)

-- CTFPlayer::SelectSpawnSpotByType: round-robin after the last spot used,
-- first a clear spot, then any valid one

T.test("spawns are handed out in turn after the last one used", function()
	local spawns = { Spawn({ teamnum = KV(RED) }), Spawn({ teamnum = KV(BLU) }), Spawn({ teamnum = KV(RED) }), Spawn({ teamnum = KV(RED) }) }
	local clear = function() return true end
	T.eq(S.Pick(spawns, RED, nil, clear), 1, "first")
	T.eq(S.Pick(spawns, RED, 1, clear), 3, "skips BLU")
	T.eq(S.Pick(spawns, RED, 4, clear), 1, "wraps")
end)

T.test("an occupied spot is skipped while a clear one exists", function()
	local spawns = { Spawn({ teamnum = KV(RED) }), Spawn({ teamnum = KV(RED) }) }
	T.eq(S.Pick(spawns, RED, nil, function(i) return i ~= 1 end), 2, "clear one")
	T.eq(S.Pick(spawns, RED, nil, function() return false end), 1, "all occupied")
end)

T.test("no valid spawn gives nil", function()
	T.eq(S.Pick({ Spawn({ teamnum = KV(BLU) }) }, RED, nil, function() return true end), nil)
end)

-- A spawn room's team for routes: the team that spawns in it, or nearest
-- it, whatever the room says (arena_well marks BLU's rooms RED, which shut
-- BLU's soldiers in their own spawn as if it were the enemy's).

T.test("a room is the team of the spawns inside it, whatever its own team", function()
	T.eq(S.RoomTeam(RED, { BLU, BLU }, RED), BLU, "BLU spawns in a room marked RED")
	T.eq(S.RoomTeam(RED, { RED }, RED), RED, "agreeing")
end)

T.test("a room with no spawns inside is the team of the spawn nearest it", function()
	T.eq(S.RoomTeam(RED, {}, BLU), BLU, "BLU's vestibule, marked RED")
	T.eq(S.RoomTeam(BLU, {}, nil), BLU, "no spawns at all: its own")
end)

T.test("a room with both teams' spawns inside keeps its own team", function()
	T.eq(S.RoomTeam(RED, { RED, BLU }, BLU), RED, "both")
end)

-- A CS:S map has no info_player_teamspawn: each side spawns at its own class,
-- the terrorists (RED) at info_player_terrorist and the counter-terrorists
-- (BLU) at info_player_counterterrorist, never the other side's.
T.test("on a CS:S map each team spawns at its own side's class", function()
	T.eq(S.SideClass(RED), "info_player_terrorist", "RED")
	T.eq(S.SideClass(BLU), "info_player_counterterrorist", "BLU")
	T.eq(S.SideClass(NOBODY), nil, "no team, no side")
end)

T.test("a side's spots are taken in turn after the last, clear ones first", function()
	local clear = function() return true end
	T.eq(S.PickNext(3, nil, clear), 1, "the first")
	T.eq(S.PickNext(3, 1, clear), 2, "after the last")
	T.eq(S.PickNext(3, 3, clear), 1, "wraps")
	T.eq(S.PickNext(3, 1, function(i) return i == 1 end), 1, "the only clear one")
	T.eq(S.PickNext(3, 1, function() return false end), 2, "none clear: the next")
	T.eq(S.PickNext(0, nil, clear), nil, "no spots")
end)

T.finish()
