-- The AI war in arena (features.aiwar.scenario.arena, features.aiwar.model.
-- explore): the arena round is no sudden death for the soldiers (no hunt,
-- no sight of every enemy); squads keep together and explore the map,
-- each going for what its own soldiers saw, until the point opens; then a
-- King-of-the-Hill-like split, with a share still exploring.
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local FP = dofile("tests/fake_points.lua")
local AiWar = T.require("features.aiwar.model")
local Explore = T.require("games.ns.explore")
local Scenario = T.require("features.aiwar.scenario")
local CP = T.require("features.aiwar.scenario.control_points")
local Arena = T.require("features.aiwar.scenario.arena")
local Squad = T.require("games.ns.squad")
local Tactics = T.require("games.ns.tactics")
local State = T.require("games.gameplay.rounds.state")
local Teams = T.require("games.gameplay.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point
local S = Explore.SPACING

-- Explore: the waypoints ----------------------------------------------------------

T.test("the nav mesh's area centres thin to one waypoint per SPACING cell, in their order", function()
	local list = Explore.Sample({ P(10, 10), P(20, 30), P(S + 10, 0), P(0, 0, S * 2), P(S * 3, S * 3) }, S)
	T.eq(#list, 4, "the second point shares the first's cell")
	T.eq(list[1].x, 10, "the first of a cell is kept")
	T.eq(list[2].x, S + 10, "the next cell")
	T.eq(list[3].z, S * 2, "a floor above is a cell of its own")
	T.eq(Explore.Sample({}, S)[1], nil, "no areas, no waypoints")
end)

-- Explore: the board --------------------------------------------------------------

local WAYPOINTS = { P(1000, 0), P(2000, 0), P(3000, 0) }

T.test("a squad goes for the nearest waypoint it has not visited, and keeps it", function()
	local board = Explore.Board.New(WAYPOINTS)
	local goal = board:Next("a", RED, P(0, 0), 0)
	T.eq(goal.x, 1000, "the nearest")
	T.eq(board:Next("a", RED, P(2900, 0), 1).x, 1000, "kept until reached, wherever the squad stands")
	board:Visit("a", P(1000 + Explore.VISIT_RADIUS - 1, 0))
	T.eq(board:Next("a", RED, P(1000, 0), 2).x, 2000, "visited: on to the next")
end)

T.test("each squad knows only where its own soldiers have been", function()
	local board = Explore.Board.New(WAYPOINTS)
	board:Visit("a", P(1000, 0))
	T.eq(board:Next("b", BLUE, P(0, 0), 0).x, 1000, "another squad has not seen it")
end)

T.test("two squads of a team never make for the same waypoint; the enemy's claims are its own", function()
	local board = Explore.Board.New(WAYPOINTS)
	T.eq(board:Next("a", RED, P(0, 0), 0).x, 1000, "the first squad takes the nearest")
	T.eq(board:Next("b", RED, P(0, 0), 0).x, 2000, "its teammates take the next")
	T.eq(board:Next("c", BLUE, P(0, 0), 0).x, 1000, "the enemy may go there too")
end)

T.test("a waypoint not reached within GIVE_UP is given up as visited", function()
	local board = Explore.Board.New(WAYPOINTS)
	board:Next("a", RED, P(0, 0), 0)
	T.eq(board:Next("a", RED, P(0, 0), Explore.GIVE_UP - 1).x, 1000, "still going")
	T.eq(board:Next("a", RED, P(0, 0), Explore.GIVE_UP + 1).x, 2000, "given up: the next")
end)

T.test("a squad that has been everywhere starts over", function()
	local board = Explore.Board.New(WAYPOINTS)
	for _, p in ipairs(WAYPOINTS) do board:Visit("a", p) end
	local goal = board:Next("a", RED, P(2900, 0), 0)
	T.eq(goal ~= nil, true, "a waypoint again")
	T.eq(goal.x, 3000, "the nearest")
	T.eq(Explore.Board.New({}):Next("a", RED, P(0, 0), 0), nil, "no waypoints: no goal")
end)

-- The phase -----------------------------------------------------------------------

T.test("an arena round is its own phase: orders, no waves, no hunt, no sight of every enemy", function()
	local arena = AiWar.PhaseOf(true, State.STALEMATE, nil, true)
	T.eq(arena, AiWar.PHASES.arena, "arena")
	T.eq(arena.orders, true, "orders run")
	T.eq(arena.reinforce, false, "no respawns")
	T.eq(arena.hunt, false, "no hunt")
	T.eq(arena.sightAll, false, "no global vision")
	T.eq(AiWar.PhaseOf(true, State.STALEMATE, nil, false), AiWar.PHASES.suddenDeath, "sudden death elsewhere")
	T.eq(AiWar.PhaseOf(true, State.PREROUND, nil, true), AiWar.PHASES.frozen, "the pre-round still freezes and reinforces")
end)

-- The scenario --------------------------------------------------------------------

local POINT_AT = P(0, 0)
local NEAR = { P(-1000, 0), P(1000, 0), P(0, 1000), P(0, -1000) }

local function Point(t)
	t.rank = 0
	t.at = POINT_AT
	return FP.Point(t)
end

-- A field at now 100 whose point opens at `open` (nil: no time yet).
local function Field(point, open, t)
	t = t or {}
	t.points = { point }
	local field = FP.Field(t)
	field.now = t.now or 100
	field.capEnableAt = open
	field.waypoints = t.waypoints or NEAR
	return field
end

local function Brief(field, scenario)
	scenario = scenario or Arena.Scenario:New()
	scenario:Brief(field, field.now)
	return field, scenario
end

local function Shares(stance)
	local shares = {}
	for i, share in ipairs(stance) do shares[i] = share.role .. ":" .. share.weight end
	return table.concat(shares, " ")
end

T.test("the arena variant is the rounds mode's and a control point scenario that needs waypoints", function()
	T.eq(Scenario.For("arena"), Arena.Scenario, "chosen by the mode's NAME")
	T.eq(getmetatable(Arena.Scenario), CP.Scenario, "a control point scenario")
	local field = Field(Point({}), nil, { waypoints = {} })
	T.eq(Arena.Scenario:MapLacks(field), Scenario.WAYPOINTS, "no nav mesh, no war")
	T.eq(Arena.Scenario:MapLacks(Field(Point({}), nil)), nil, "with waypoints it may start")
	T.eq(Brief(Field(Point({}), nil)).doctrine, Arena.DOCTRINE, "the arena doctrine")
end)

T.test("until the cap-enable time nobody attacks or guards the point", function()
	for _, open in ipairs({ false, 150 }) do
		local field = Brief(Field(Point({ mayCapture = { [RED] = true, [BLUE] = true } }), open or nil))
		for _, team in ipairs({ RED, BLUE }) do
			local o = field.objectives[team]
			T.eq(#o.attack, 0, "no attack")
			T.eq(o.guard, nil, "no guard")
			T.eq(o.focus, nil, "no focus")
		end
	end
end)

T.test("once open, the point is a target to the team without it and guarded by its owner", function()
	local field = Brief(Field(Point({ owner = RED }), 90))
	T.eq(#field.objectives[BLUE].attack, 1, "BLU attacks it")
	T.eq(field.objectives[BLUE].target ~= nil, true, "its target")
	T.eq(field.objectives[RED].guard ~= nil, true, "RED guards it")
	T.eq(#field.objectives[RED].attack, 0, "its owner does not attack it")
	local neutral = Brief(Field(Point({}), 90))
	T.eq(neutral.objectives[RED].target ~= nil and neutral.objectives[BLUE].target ~= nil, true, "neutral: both go for it")
end)

T.test("stances: everyone explores until the point opens, then a split with explorers still out", function()
	local function Entries(point, open)
		local field, scenario = Brief(Field(point, open))
		return scenario:Stances(field, field.now)
	end
	local e = Entries(Point({}), 150)
	T.eq(e[RED].key, Arena.SHUT, "shut")
	T.eq(Shares(e[RED].stance), "explore:1", "all explore")
	e = Entries(Point({}), 90)
	T.eq(e[RED].key, Arena.OPEN, "open")
	T.eq(Shares(e[RED].stance), "capture:4 assault:3 explore:3", "open weights")
	e = Entries(Point({ owner = RED }), 90)
	T.eq(e[RED].key, Arena.HELD, "held")
	T.eq(Shares(e[RED].stance), "hold:3 defend:4 explore:3", "held weights")
	T.eq(e[BLUE].key, Arena.LOST, "lost")
	T.eq(Shares(e[BLUE].stance), "capture:5 assault:3 explore:2", "lost weights")
	e = Entries(Point({ owner = RED, capping = BLUE, progress = CP.CRITICAL_PROGRESS }), 90)
	T.eq(e[RED].key, Arena.CAPPED, "capped")
	T.eq(e[RED].critical, true, "critical past half")
	T.eq(Shares(e[RED].stance), "hold:6 defend:3 explore:1", "capped weights")
end)

T.test("the holder is all defense, the rest all offense", function()
	local field, scenario = Brief(Field(Point({ owner = RED }), 90))
	local _, defense = scenario:Stances(field, field.now)
	T.eq(defense[RED], 1, "RED defends")
	T.eq(defense[BLUE], 0, "BLU attacks")
end)

-- A battle --------------------------------------------------------------------------

local SQUAD = AiWar.FIRE_TEAM_SIZE

local function BattleField(battle, open)
	local field = Field(Point({}), open, { phase = AiWar.PHASES.arena, now = battle.now })
	return field
end

local function Tick(battle, open, n)
	for _ = 1, n do
		local field = BattleField(battle, open)
		field.now = battle.now + FP.TICK
		battle:Tick(field)
	end
end

local function LeaderAndMembers(battle, team)
	local leader, members = nil, {}
	for _, s in ipairs(battle:Of(team, AiWar.EXPLORE)) do
		local fireTeam = s.member.fireTeam
		if fireTeam and Squad.Leader(fireTeam) == s.member then leader = s else members[#members + 1] = s end
	end
	return leader, members
end

T.test("a squad explores together: its leader makes for a waypoint and its members follow", function()
	local battle = FP.Battle(Arena.Scenario)
	battle:Enlist(RED, SQUAD)
	battle:Start(BattleField(battle, 1000))
	T.eq(battle:Count(RED, AiWar.EXPLORE), SQUAD, "all explore")
	local first = battle.soldiers[1].member.fireTeam
	for _, s in ipairs(battle.soldiers) do T.eq(s.member.fireTeam, first, s.member.handle .. " in one squad") end
	Tick(battle, 1000, 12)
	local leader, members = LeaderAndMembers(battle, RED)
	T.eq(leader ~= nil, true, "a leader")
	local start = FP.BASES[RED]
	T.eq(FS.Distance(leader.me.pos, start) > 500, true, "the leader set off")
	for _, m in ipairs(members) do
		T.eq(FS.Distance(m.me.pos, leader.me.pos) < 500, true, m.member.handle .. " kept up")
	end
end)

T.test("an explorer squad goes for what its own soldiers saw, not what another squad did", function()
	local battle = FP.Battle(Arena.Scenario)
	battle:Enlist(RED, SQUAD * 2)
	battle:Start(BattleField(battle, 1000))
	local squads = {}
	for _, s in ipairs(battle.soldiers) do squads[s.member.fireTeam] = true end
	local list = {}
	for fireTeam in pairs(squads) do list[#list + 1] = fireTeam end
	T.eq(#list, 2, "two squads")
	local seen = P(-2000, 1500)
	Tactics.Report(list[1], seen, battle.now)
	local field = BattleField(battle, 1000)
	battle.scenario:Brief(field, field.now)
	local spotter = Squad.Leader(list[1])
	local other = Squad.Leader(list[2])
	T.eq(Arena.DOCTRINE.ROLES[AiWar.EXPLORE].Goal(field, spotter).x, seen.x, "the spotter's squad goes there")
	T.eq(Arena.DOCTRINE.ROLES[AiWar.EXPLORE].Goal(field, other).x ~= seen.x, true, "the other keeps exploring")
end)

-- Lanes ----------------------------------------------------------------------------

local Lanes = T.require("games.ns.lanes")
local EXPLORE_ROLE = Arena.DOCTRINE.ROLES[AiWar.EXPLORE]

T.test("lanes lead from each spawn to the point, shut or open; without one, to the enemy's base", function()
	local scenario = Arena.Scenario:New()
	for _, open in ipairs({ 150, 90 }) do
		local field = Brief(Field(Point({}), open), scenario)
		for _, team in ipairs({ RED, BLUE }) do
			local front = scenario:Front(field, team)
			T.eq(front.x == POINT_AT.x and front.y == POINT_AT.y, true, "the point")
		end
	end
	local field = FP.Field({ points = {} })
	field.now, field.waypoints = 100, NEAR
	scenario:Brief(field, field.now)
	T.eq(scenario:Front(field, RED).x, field.bases[BLUE].x, "no point: RED's lanes lead to BLU's base")
	T.eq(scenario:Front(field, BLUE).x, field.bases[RED].x, "and BLU's to RED's")
end)

T.test("explorer squads take the lanes to the objective: the direct way and the flanks", function()
	T.eq(Lanes.JOBS[AiWar.EXPLORE], true, "explorers take lanes")
	T.eq(Lanes.JOB_KINDS[AiWar.EXPLORE][Lanes.DIRECT], true, "direct")
	T.eq(Lanes.JOB_KINDS[AiWar.EXPLORE][Lanes.FLANK], true, "flanks")
	T.eq(Lanes.JOB_KINDS[AiWar.EXPLORE][Lanes.TOUR], nil, "no tours through the enemy")
end)

-- A battle of one RED squad on a lane from its base to the point.
local LANE = { kind = Lanes.DIRECT, ids = { 1, 2, 3 }, points = { P(-2000, 600), P(-1000, 600), P(-200, 0) }, length = 2600 }

local function LaneField(battle, open)
	local field = Field(Point({}), open, { phase = AiWar.PHASES.arena, now = battle.now,
		lanes = { [RED] = { key = "plan", LANE } } })
	return field
end

local function LaneBattle()
	local battle = FP.Battle(Arena.Scenario)
	battle:Enlist(RED, SQUAD)
	battle:Start(LaneField(battle, 1000))
	return battle, battle.soldiers[1].member.fireTeam
end

T.test("an explorer squad walks its lane to the point, then explores the waypoints", function()
	local battle, fireTeam = LaneBattle()
	T.eq(fireTeam.lane, LANE, "the squad holds the lane")
	local field = LaneField(battle, 1000)
	battle.scenario:Brief(field, field.now)
	local leader = Squad.Leader(fireTeam)
	local goal = EXPLORE_ROLE.Goal(field, leader)
	T.eq(goal.x == LANE.points[3].x and goal.y == LANE.points[3].y, true, "the lane's end")
	battle:Tick(LaneField(battle, 1000), 2)
	local onLane = 0
	for _, s in ipairs(battle.soldiers) do
		if s.npc:State().onLane then onLane = onLane + 1 end
	end
	T.eq(onLane, 1, "its leader walks the lane")
	-- the leader reaches the lane's end
	for _, s in ipairs(battle.soldiers) do s.me.pos, s.member.pos = P(-200, 0), P(-200, 0) end
	field = LaneField(battle, 1000)
	battle.scenario:Command(battle.war, field, field.now)
	battle.scenario:Brief(field, field.now)
	goal = EXPLORE_ROLE.Goal(field, leader)
	T.eq(goal.x == LANE.points[3].x and goal.y == LANE.points[3].y, false, "walked: on to a waypoint")
end)

T.test("a new round walks the lanes again, and forgets the fights", function()
	local battle, fireTeam = LaneBattle()
	local leader = Squad.Leader(fireTeam)
	for _, s in ipairs(battle.soldiers) do s.me.pos, s.member.pos = P(-200, 0), P(-200, 0) end
	Tactics.Report(fireTeam, P(-1500, -1500), battle.now)
	local field = LaneField(battle, 1000)
	battle.scenario:Command(battle.war, field, field.now)
	battle.scenario:Reset()
	fireTeam.contact = nil
	for _, s in ipairs(battle.soldiers) do s.member.pos = FP.BASES[RED] end
	field = LaneField(battle, 1000)
	battle.scenario:Command(battle.war, field, field.now)
	battle.war:SetField(field)
	T.eq(EXPLORE_ROLE.LeavesLane(field, leader), false, "not engaged")
	T.eq(EXPLORE_ROLE.Goal(field, leader).x, LANE.points[3].x, "the lane's end again")
end)

T.test("a squad in a fight is engaged: off its lane, it hunts where the enemy was, then goes back to it", function()
	local battle, fireTeam = LaneBattle()
	local leader = Squad.Leader(fireTeam)
	local seen = P(-1500, -1500)
	Tactics.Report(fireTeam, seen, battle.now)
	local field = LaneField(battle, 1000)
	battle.scenario:Command(battle.war, field, field.now)
	battle.scenario:Brief(field, field.now)
	T.eq(EXPLORE_ROLE.Goal(field, leader).x, seen.x, "in contact: the contact")
	T.eq(EXPLORE_ROLE.LeavesLane(field, leader), true, "off the lane")
	-- the contact is forgotten, the engagement is not
	field = LaneField(battle, 1000)
	field.now = battle.now + Tactics.CONTACT_MEMORY + 1
	battle.scenario:Command(battle.war, field, field.now)
	battle.scenario:Brief(field, field.now)
	T.eq(Tactics.Contact(fireTeam, field.now), nil, "no contact")
	T.eq(EXPLORE_ROLE.Goal(field, leader).x, seen.x, "engaged: hunting where it was")
	T.eq(EXPLORE_ROLE.LeavesLane(field, leader), true, "still off the lane")
	battle.now = field.now
	battle:Tick(field, 4)
	for _, s in ipairs(battle.soldiers) do T.eq(s.npc:State().onLane, nil, s.member.handle .. " not walking the lane") end
	-- the engagement is over
	field = LaneField(battle, 1000)
	field.now = battle.now + Explore.ENGAGED_FOR + 1
	battle.scenario:Command(battle.war, field, field.now)
	battle.scenario:Brief(field, field.now)
	T.eq(EXPLORE_ROLE.LeavesLane(field, leader), false, "back on the lane")
	T.eq(EXPLORE_ROLE.Goal(field, leader).x, LANE.points[3].x, "for its end")
end)

T.finish()
