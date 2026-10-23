-- The AI war where the rounds mode is none the war knows (no rounds, or a
-- map without a standard objective): features.aiwar.scenario.freeform.
-- Every squad explores, in bigger squads; a squad follows the nearest
-- living player of its team, and without one explores as arena's do. The
-- soldiers join the fight where the map has no TF2 team spawns at their
-- team's HL2 deathmatch spawns, else at the nav mesh's hiding spots split
-- between the teams (features.aiwar.spawns).
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local FP = dofile("tests/fake_points.lua")
local AiWar = T.require("features.aiwar.model")
local Explore = nextsoldier.explore
local Scenario = T.require("features.aiwar.scenario")
local Freeform = T.require("features.aiwar.scenario.freeform")
local Spawns = T.require("features.aiwar.spawns")
local Squad = nextsoldier.squad
local Tactics = nextsoldier.tactics
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point
local WAYPOINTS = { P(-1000, 0), P(1000, 0), P(0, 1000), P(0, -1000) }
local ROLE = Freeform.DOCTRINE.ROLES[AiWar.EXPLORE]

-- A field at now 100 with no points, the nav mesh's waypoints and these players.
local function Field(t)
	t = t or {}
	t.points = {}
	local field = FP.Field(t)
	field.now = t.now or 100
	field.waypoints = WAYPOINTS
	field.players = t.players or { [RED] = {}, [BLUE] = {} }
	return field
end

local function Brief(field, scenario)
	scenario = scenario or Freeform.Scenario:New()
	scenario:Brief(field, field.now)
	return field, scenario
end

T.test("a rounds mode the war does not know, or none, is fought freeform", function()
	T.eq(Scenario.For(nil), Freeform.Scenario, "no rounds")
	T.eq(Scenario.For("none"), Freeform.Scenario, "a mode without a standard objective")
	T.eq(Scenario.For("arena") ~= Freeform.Scenario, true, "a known mode keeps its own")
end)

T.test("freeform needs both bases and the nav mesh's waypoints, and fights in bigger squads", function()
	T.eq(Freeform.Scenario:MapLacks(Field()), nil, "may start")
	local bare = Field()
	bare.waypoints = {}
	T.eq(Freeform.Scenario:MapLacks(bare), Scenario.WAYPOINTS, "no nav mesh, no war")
	T.eq(Freeform.Scenario.SQUAD_SIZE > AiWar.FIRE_TEAM_SIZE, true, "bigger squads")
end)

T.test("every soldier explores", function()
	local field, scenario = Brief(Field())
	local entries, defense = scenario:Stances(field, field.now)
	for _, team in ipairs({ RED, BLUE }) do
		T.eq(#entries[team].stance, 1, "one share")
		T.eq(entries[team].stance[1].role, AiWar.EXPLORE, "explore")
		T.eq(defense[team], 0, "no defense")
	end
end)

T.test("lanes lead to the enemy's base, unless both teams start in the same place", function()
	local field, scenario = Brief(Field())
	T.eq(scenario:Front(field, RED).x, field.bases[BLUE].x, "RED's to BLU's")
	local shared = Field({ bases = { [RED] = P(0, 0), [BLUE] = P(10, 0) } })
	T.eq(scenario:Front(Brief(shared), RED), nil, "the same spawns: no lanes")
end)

-- A battle of one RED squad, its leader at `at`.
local function SquadOf(n)
	local battle = FP.Battle(Freeform.Scenario)
	battle:Enlist(RED, n)
	battle:Start(Field({ now = battle.now }))
	return battle
end

T.test("a squad of the war's forming holds SQUAD_SIZE soldiers", function()
	local battle = SquadOf(Freeform.Scenario.SQUAD_SIZE)
	local first = battle.soldiers[1].member.fireTeam
	for _, s in ipairs(battle.soldiers) do T.eq(s.member.fireTeam, first, s.member.handle .. " in one squad") end
end)

T.test("a squad follows the nearest living player of its team, not the enemy's", function()
	local battle = SquadOf(4)
	local leader = Squad.Leader(battle.soldiers[1].member.fireTeam)
	leader.pos = P(0, 0)
	local field = Brief(Field({ players = {
		[RED] = { { handle = "far", pos = P(3000, 0) }, { handle = "near", pos = P(800, 200) } },
		[BLUE] = { { handle = "enemy", pos = P(100, 0) } },
	} }))
	local goal = ROLE.Goal(field, leader)
	T.eq(goal.x == 800 and goal.y == 200, true, "the nearest teammate")
end)

T.test("without a player of its team, a squad explores", function()
	local battle = SquadOf(4)
	local leader = Squad.Leader(battle.soldiers[1].member.fireTeam)
	leader.pos = P(0, 0)
	local field = Brief(Field({ players = { [RED] = {}, [BLUE] = { { handle = "enemy", pos = P(100, 0) } } } }))
	local goal = ROLE.Goal(field, leader)
	local waypoint = false
	for _, w in ipairs(WAYPOINTS) do
		if w.x == goal.x and w.y == goal.y then waypoint = true end
	end
	T.eq(waypoint, true, "a waypoint")
end)

T.test("a squad in a fight fights before it follows its player", function()
	local battle = SquadOf(4)
	local fireTeam = battle.soldiers[1].member.fireTeam
	local leader = Squad.Leader(fireTeam)
	local seen = P(-1500, -1500)
	Tactics.Report(fireTeam, seen, battle.now)
	local field = Field({ now = battle.now, players = { [RED] = { { handle = "near", pos = P(800, 200) } }, [BLUE] = {} } })
	local _, scenario = Brief(field)
	scenario:Command(battle.war, field, field.now)
	T.eq(ROLE.Goal(field, leader).x, seen.x, "the contact")
	field = Field({ now = battle.now + Tactics.CONTACT_MEMORY + 1, players = { [RED] = { { handle = "near", pos = P(800, 200) } }, [BLUE] = {} } })
	scenario:Command(battle.war, field, field.now)
	T.eq(ROLE.Goal(field, leader).x, seen.x, "engaged: where it was")
	field = Field({ now = battle.now + Explore.ENGAGED_FOR + 1, players = { [RED] = { { handle = "near", pos = P(800, 200) } }, [BLUE] = {} } })
	scenario:Command(battle.war, field, field.now)
	T.eq(ROLE.Goal(field, leader).x, 800, "then its player again")
end)

-- Spawns ---------------------------------------------------------------------------

local function Present(classes)
	local set = {}
	for _, c in ipairs(classes) do set[c] = true end
	return function(class) return set[class] == true end
end

T.test("without TF2's team spawns, each faction joins at its HL2 deathmatch spawns, whichever its team", function()
	local present = Present({ "info_player_combine", "info_player_rebel", "info_player_deathmatch" })
	T.eq(table.concat(Spawns.Classes(AiWar.COMBINE, present), ","), "info_player_combine", "the Combine's")
	T.eq(table.concat(Spawns.Classes(AiWar.RESISTANCE, present), ","), "info_player_rebel", "the rebels'")
	T.eq(#Spawns.Classes(nil, present), 0, "no faction, none")
end)

T.test("a team without its own spawns joins at hiding spots; the shared starts are the last resort", function()
	T.eq(#Spawns.Classes(AiWar.RESISTANCE, Present({ "info_player_combine", "info_player_start" })), 0, "no rebels' spawns: none of its own")
	T.eq(table.concat(Spawns.Shared(Present({ "info_player_deathmatch", "info_player_start" })), ","),
		"info_player_deathmatch,info_player_start", "every shared kind")
	T.eq(#Spawns.Shared(Present({})), 0, "none at all")
end)

T.test("the hiding spots are split between the teams along the map's longest side", function()
	-- wide along y: RED takes the low y half, BLU the high
	local spots = { P(0, 3000), P(100, -3000), P(-100, 1000), P(50, -1000) }
	local red, blue = Spawns.Split(spots, RED), Spawns.Split(spots, BLUE)
	T.eq(#red, 2, "half to RED")
	T.eq(#blue, 2, "half to BLU")
	for _, p in ipairs(red) do T.eq(p.y < 0, true, "RED's low") end
	for _, p in ipairs(blue) do T.eq(p.y > 0, true, "BLU's high") end
	local odd = { P(-1000, 0), P(0, 0), P(1000, 0) }
	T.eq(#Spawns.Split(odd, RED) + #Spawns.Split(odd, BLUE), 4, "an odd one out in the middle is both teams'")
	T.eq(#Spawns.Split({}, RED), 0, "no spots, none")
end)

T.finish()
