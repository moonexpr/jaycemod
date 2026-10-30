-- features.aiwar.scenario.defuse: the war fought over RED's bomb on CS:S's
-- de_ maps. RED fetches it, its carrier plants it at the round's target site
-- with the others escorting, then all of RED guards the planted site; BLU
-- guards the sites, runs the carrier down near one, and once the bomb is
-- planted all of BLU goes to stand on it to defuse it.
local T = dofile("tests/harness.lua")
local AiWar = T.require("features.aiwar.model")
local Defuse = T.require("features.aiwar.scenario.defuse")
local Ctf = T.require("features.aiwar.scenario.ctf")
local Teams = gameplay.teams
local Distance = math.geometry.Distance

local RED, BLUE = Teams.RED, Teams.BLUE

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

local RED_BASE, BLUE_BASE = P(-3000, 0), P(3000, 0)
local SITE_A, SITE_B = P(1000, 1500), P(1000, -1500)

-- bomb: nil (not yet made), or { state, pos, carrier, carrierTeam }; plantedAt: "A", "B" or nil.
local function Field(bomb, plantedAt)
	return {
		bases = { [RED] = RED_BASE, [BLUE] = BLUE_BASE },
		points = {
			{ id = "A", pos = SITE_A, owner = plantedAt == "A" and RED or BLUE },
			{ id = "B", pos = SITE_B, owner = plantedAt == "B" and RED or BLUE },
		},
		flags = bomb and { [RED] = bomb } or {},
		waypoints = { RED_BASE, BLUE_BASE },
	}
end

local function Briefed(bomb, plantedAt, scenario)
	local field = Field(bomb, plantedAt)
	scenario = scenario or Defuse.Scenario:New()
	scenario:Brief(field, 0)
	return field, scenario
end

local function Member(team, role, pos, handle, slot)
	return { team = team, role = role, slot = slot or 0, pos = pos or P(0, 0), handle = handle or {} }
end

local function Role(field, member) return field.doctrine.ROLES[member.role] end
local function Stage(field, member) return Role(field, member).Stage(field, member) end
local function Goal(field, member) return Role(field, member).Goal(field, member) end

local CARRIER = {}
local function Carried(pos) return { state = Ctf.CARRIED, pos = pos, carrier = CARRIER, carrierTeam = RED, home = RED_BASE } end
local function Lying(pos) return { state = Ctf.DROPPED, pos = pos, home = RED_BASE } end

T.test("the AI war fights the defuse mode with this scenario, on a map with bases and sites", function()
	local Scenario = T.require("features.aiwar.scenario")
	T.eq(Scenario.For("defuse"), Defuse.Scenario, "defuse")
	T.eq(Defuse.Scenario:New():MapLacks(Field(nil)), nil, "nothing lacking")
	T.eq(Defuse.Scenario:New():MapLacks({ bases = { [RED] = RED_BASE, [BLUE] = BLUE_BASE }, points = {} }), "points", "no sites")
end)

T.test("before the bomb is made it lies at RED's base, and RED fetches it", function()
	local field = Briefed(nil)
	local bomber = Member(RED, AiWar.COURIER, RED_BASE)
	T.eq(Stage(field, bomber), "FetchBomb", "fetch")
	T.eq(Distance(Goal(field, bomber), RED_BASE), 0, "at the base")
end)

T.test("RED's carrier plants at the target site; the others escort it", function()
	local field = Briefed(Carried(P(0, 0)))
	local carrier = Member(RED, AiWar.COURIER, P(0, 0), CARRIER)
	local other = Member(RED, AiWar.COURIER, P(-200, 0))
	T.eq(Stage(field, carrier), "PlantBomb", "plant")
	local target = field.objectives[RED].target
	T.eq(Distance(Goal(field, carrier), target.pos), 0, "to the target site")
	T.eq(Stage(field, other), "EscortBomber", "escort")
	T.eq(Distance(Goal(field, other), P(0, 0)) <= Ctf.ESCORT_RING + 1, true, "round the carrier")
end)

T.test("RED makes for another site each round, in turn", function()
	local scenario = Defuse.Scenario:New()
	local first = select(1, Briefed(nil, nil, scenario)).objectives[RED].target.id
	scenario:Reset()
	local second = select(1, Briefed(nil, nil, scenario)).objectives[RED].target.id
	T.eq(first ~= second, true, "the other site")
end)

T.test("planted, all of RED guards the planted site and all of BLU goes to defuse it", function()
	local field = Briefed(nil, "B")
	local red = Member(RED, AiWar.COURIER, RED_BASE)
	local blue = Member(BLUE, AiWar.CTF_DEFEND, BLUE_BASE)
	T.eq(Stage(field, red), "GuardPlantedBomb", "RED guards")
	T.eq(Distance(Goal(field, red), SITE_B) <= Defuse.GUARD_RING + 1, true, "round B")
	T.eq(Stage(field, blue), "DefuseBomb", "BLU defuses")
	T.eq(Distance(Goal(field, blue), SITE_B), 0, "on B itself")
	T.eq(Role(field, blue).Urgent(field, blue), true, "at once")
end)

T.test("BLU guards the sites split between them, and runs the carrier down near one", function()
	local field = Briefed(Carried(P(-2000, 0)))
	local onA = Member(BLUE, AiWar.CTF_DEFEND, BLUE_BASE, nil, 0)
	local onB = Member(BLUE, AiWar.CTF_DEFEND, BLUE_BASE, nil, 1)
	T.eq(Stage(field, onA), "GuardSite", "guard")
	local a, b = Goal(field, onA), Goal(field, onB)
	T.eq(math.min(Distance(a, SITE_A), Distance(a, SITE_B)) <= Defuse.GUARD_RING + 1, true, "at a site")
	T.eq((Distance(a, SITE_A) < Distance(a, SITE_B)) ~= (Distance(b, SITE_A) < Distance(b, SITE_B)), true, "different sites")
	local near = Briefed(Carried(P(1000, 1000)))
	T.eq(Stage(near, onA), "StopBomber", "the carrier near A")
	T.eq(Distance(Goal(near, onA), P(1000, 1000)), 0, "at the carrier")
end)

T.test("a bomb lying on the ground: RED fetches it, BLU guards it", function()
	local field = Briefed(Lying(P(500, 0)))
	T.eq(Stage(field, Member(RED, AiWar.COURIER)), "FetchBomb", "RED fetches")
	T.eq(Stage(field, Member(BLUE, AiWar.CTF_DEFEND)), "GuardDroppedBomb", "BLU guards it")
end)

T.test("RED's whole side carries the bomb's war, BLU's the sites'; the plant is critical for BLU", function()
	local field, scenario = Briefed(nil, "A")
	local stances = scenario:Stances(field, 0)
	T.eq(stances[RED].stance[1].role, AiWar.COURIER, "RED bombers")
	T.eq(stances[BLUE].stance[1].role, AiWar.CTF_DEFEND, "BLU defenders")
	T.eq(stances[BLUE].critical, true, "planted: at once")
end)

T.finish()
