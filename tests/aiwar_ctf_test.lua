-- features.aiwar.scenario.ctf: the war fought over the intelligence.
-- Couriers fetch the enemy's flag and carry it home, defenders guard their
-- own and run down whoever takes it, and operatives hold a remote base on
-- the way the enemy's carrier would run, to widen the defenders' reach.
local T = dofile("tests/harness.lua")
local AiWar = T.require("features.aiwar.model")
local Scenario = T.require("features.aiwar.scenario")
local Ctf = T.require("features.aiwar.scenario.ctf")
local Teams = gameplay.teams
local Geometry = math.geometry

local RED, BLUE = Teams.RED, Teams.BLUE
local Distance = Geometry.Distance

local function P(x, y) return { x = x, y = y, z = 0 } end

local RED_HOME, BLUE_HOME = P(200, 0), P(3800, 0)

local function Flag(team, home, state, pos, carrier, carrierTeam)
	return { team = team, home = home, state = state or Ctf.HOME, pos = pos or home, carrier = carrier, carrierTeam = carrierTeam or Teams.UNASSIGNED }
end

-- A long straight map: RED's base at x 0, BLU's at x 4000, the waypoints
-- every 200 along it and one off to the side.
local function Field(flags)
	local waypoints = {}
	for x = 0, 4000, 200 do waypoints[#waypoints + 1] = P(x, 0) end
	waypoints[#waypoints + 1] = P(1000, 1500)
	return {
		bases = { [RED] = P(0, 0), [BLUE] = P(4000, 0) },
		flags = flags or { [RED] = Flag(RED, RED_HOME), [BLUE] = Flag(BLUE, BLUE_HOME) },
		zones = { [RED] = P(250, 100), [BLUE] = P(3750, 100) },
		waypoints = waypoints,
	}
end

local function Briefed(field, scenario)
	scenario = scenario or Ctf.Scenario:New()
	scenario:Brief(field, 0)
	return field, scenario
end

local function Member(team, role, slot, pos, handle)
	return { team = team, role = role, slot = slot or 0, pos = pos, handle = handle or {} }
end

local function Goal(field, member)
	return field.doctrine.ROLES[member.role].Goal(field, member)
end

local function Stage(field, member) return field.doctrine.ROLES[member.role].Stage(field, member) end

T.test("CTF has its own scenario, and needs flags on the map", function()
	T.eq(Scenario.For(T.require("features.flag.model").Mode.NAME), Ctf.Scenario, "the ctf mode's")
	T.eq(Ctf.Scenario:MapLacks({ bases = { [RED] = P(0, 0), [BLUE] = P(1, 0) } }), Scenario.FLAGS, "no flags")
	T.eq(Ctf.Scenario:MapLacks(Field()), nil, "flags and bases")
end)

-- Couriers ---------------------------------------------------------------------

T.test("a courier goes for the enemy's flag where it lies, at home or dropped", function()
	local field = Briefed(Field())
	local courier = Member(RED, AiWar.COURIER, 0, P(1000, 0))
	T.eq(Distance(Goal(field, courier), BLUE_HOME), 0, "on the flag at home")
	local dropped = Briefed(Field({ [RED] = Flag(RED, RED_HOME), [BLUE] = Flag(BLUE, BLUE_HOME, Ctf.DROPPED, P(2500, 300)) }))
	T.eq(Distance(Goal(dropped, courier), P(2500, 300)), 0, "on the dropped flag")
	T.eq(dropped.doctrine.ROLES[AiWar.COURIER].arrive <= Ctf.TOUCH, true, "close enough to touch it")
end)

-- CTFBotFetchFlag: a courier goes for the flag, fighting on the way but
-- chasing nobody; near it, it rushes it as CTFBotCapturePoint rushes a point.
T.test("a courier chases nobody, and rushes the flag once near it", function()
	local field = Briefed(Field())
	local role = field.doctrine.ROLES[AiWar.COURIER]
	T.eq(role.chases, nil, "no chases")
	T.eq(role.Urgent(field, Member(RED, AiWar.COURIER, 0, P(1000, 0))), false, "far off: it fights its way")
	T.eq(role.Urgent(field, Member(RED, AiWar.COURIER, 0, P(3800 - Ctf.FETCH_RUSH, 0))), true, "near: it rushes")
end)

T.test("a courier carrying the flag runs it to its capture zone, stopping for nothing", function()
	local carrier = {}
	local field = Briefed(Field({ [RED] = Flag(RED, RED_HOME), [BLUE] = Flag(BLUE, BLUE_HOME, Ctf.CARRIED, P(3000, 0), carrier, RED) }))
	local courier = Member(RED, AiWar.COURIER, 0, P(3000, 0), carrier)
	local role = field.doctrine.ROLES[AiWar.COURIER]
	T.eq(Distance(Goal(field, courier), P(250, 100)), 0, "home to its zone")
	T.eq(role.Urgent(field, courier), true, "it rushes")
end)

-- CTFBotAttackFlagDefenders / CTFBotEscortFlagCarrier: while a teammate
-- carries the flag, a courier within ESCORT_RANGE of it escorts it, at most
-- MAX_ESCORTS a team, giving up past ESCORT_GIVE_UP; the rest attack the
-- enemy's flag defenders.
local function Carried(carrier)
	return Field({ [RED] = Flag(RED, RED_HOME), [BLUE] = Flag(BLUE, BLUE_HOME, Ctf.CARRIED, P(2000, 0), carrier, RED) })
end

local function Couriers(xs)
	local list = {}
	for i, x in ipairs(xs) do list[i] = Member(RED, AiWar.COURIER, i, P(x, 0)) end
	return list
end

T.test("couriers near a teammate carrying the flag escort it, at most MAX_ESCORTS; the rest attack the defenders", function()
	local carrier = Member(RED, AiWar.CTF_DEFEND, 0, P(2000, 0))
	local field, scenario = Briefed(Carried(carrier.handle))
	local near = Couriers({ 2100, 2150, 2200, 2250, 2300 })
	local far = Member(RED, AiWar.COURIER, 9, P(2000 + Ctf.ESCORT_RANGE + 100, 0))
	local members = { carrier, far }
	for _, m in ipairs(near) do members[#members + 1] = m end
	scenario:ChooseEscorts(field, members)
	for i = 1, Ctf.MAX_ESCORTS do T.eq(Stage(field, near[i]), "EscortFlagCarrier", "escort " .. i) end
	T.eq(Stage(field, near[Ctf.MAX_ESCORTS + 1]), "AttackFlagDefenders", "one too many")
	T.eq(Stage(field, far), "AttackFlagDefenders", "too far to join")
	local defenders = field.doctrine.ROLES[AiWar.COURIER].STAGES.AttackFlagDefenders
	T.eq(Distance(defenders.Goal(field, far), BLUE_HOME) <= Ctf.GUARD_RING + 1e-6, true, "at the enemy's flag stand")
	T.eq(field.doctrine.ROLES[AiWar.COURIER].Urgent(field, near[1]), false, "escorts fight on the way")
end)

T.test("an escort keeps escorting until it falls ESCORT_GIVE_UP behind", function()
	local carrier = {}
	local field, scenario = Briefed(Carried(carrier))
	local escort = Member(RED, AiWar.COURIER, 1, P(2100, 0))
	scenario:ChooseEscorts(field, { escort })
	escort.pos = P(2000 + Ctf.ESCORT_GIVE_UP - 10, 0)
	local again = Briefed(Carried(carrier), scenario)
	scenario:ChooseEscorts(again, { escort })
	T.eq(Stage(again, escort), "EscortFlagCarrier", "still within reach")
	escort.pos = P(2000 + Ctf.ESCORT_GIVE_UP + 10, 0)
	local lost = Briefed(Carried(carrier), scenario)
	scenario:ChooseEscorts(lost, { escort })
	T.eq(Stage(lost, escort), "AttackFlagDefenders", "fallen behind")
end)

-- TF2's scenario monitor: whoever picks up the flag runs it in.
T.test("any soldier that picks up the enemy's flag delivers it as a courier", function()
	for _, job in ipairs({ AiWar.CTF_DEFEND, AiWar.OPERATIVE, AiWar.MEDIC }) do
		local carrier = Member(RED, job, 0, P(3000, 0))
		local field = Briefed(Carried(carrier.handle))
		local d = field.doctrine
		T.eq(d.SIDES[d.Side(field, carrier)], "CaptureFlagCourier", job .. ": a courier now")
		T.eq(Stage(field, carrier), "ReturnHome", job .. ": home")
		local deliver = d.ROLES[job].STAGES.ReturnHome
		T.eq(Distance(deliver.Goal(field, carrier), P(250, 100)), 0, job .. ": to the zone")
		T.eq(deliver.arrive <= Ctf.TOUCH, true, job .. ": into it")
		T.eq(deliver.Urgent(field, carrier), true, job .. ": stopping for nothing")
	end
end)

-- Defenders --------------------------------------------------------------------

T.test("a defender guards its flag at home, round it", function()
	local field = Briefed(Field())
	local defender = Member(RED, AiWar.CTF_DEFEND, 2, P(500, 0))
	T.near(Distance(Goal(field, defender), RED_HOME), Ctf.GUARD_RING, 1e-6, "round the flag")
	T.eq(field.doctrine.ROLES[AiWar.CTF_DEFEND].Urgent(field, defender), false, "no hurry")
end)

T.test("a defender guards its dropped flag, and runs down whoever carries it", function()
	local defender = Member(RED, AiWar.CTF_DEFEND, 0, P(500, 0))
	local dropped = Briefed(Field({ [RED] = Flag(RED, RED_HOME, Ctf.DROPPED, P(1500, 0)), [BLUE] = Flag(BLUE, BLUE_HOME) }))
	T.near(Distance(Goal(dropped, defender), P(1500, 0)), Ctf.GUARD_RING, 1e-6, "by the dropped flag")
	local stolen = Briefed(Field({ [RED] = Flag(RED, RED_HOME, Ctf.CARRIED, P(1800, 200), {}, BLUE), [BLUE] = Flag(BLUE, BLUE_HOME) }))
	T.eq(Distance(Goal(stolen, defender), P(1800, 200)), 0, "on the carrier")
	T.eq(stolen.doctrine.ROLES[AiWar.CTF_DEFEND].Urgent(stolen, defender), true, "in a hurry")
end)

-- Operatives -------------------------------------------------------------------

T.test("an operative holds a remote base on the way the enemy's carrier would run", function()
	local field, scenario = Briefed(Field())
	local outpost = field.objectives[RED].outpost
	T.eq(outpost ~= nil, true, "an outpost")
	local fromHome = Distance(outpost, RED_HOME)
	T.eq(fromHome >= Ctf.OUTPOST_MIN and fromHome <= Ctf.OUTPOST_MAX, true, "out from the flag: " .. fromHome)
	T.eq(outpost.y, 0, "on the carrier's way, not off to the side")
	local operative = Member(RED, AiWar.OPERATIVE, 1, P(500, 0))
	T.eq(Distance(Goal(field, operative), outpost) <= Ctf.OUTPOST_RADIUS, true, "in the outpost")
	local center, radius = field.doctrine.ROLES[AiWar.OPERATIVE].Zone(field, operative)
	T.eq(Distance(center, outpost), 0, "its zone's centre")
	T.eq(radius, Ctf.OUTPOST_RADIUS, "its zone's radius")
	local again = Briefed(Field(), scenario)
	T.eq(Distance(again.objectives[RED].outpost, outpost), 0, "the same base each tick")
end)

T.test("a map with no waypoint in reach has no outpost; operatives guard the flag", function()
	local field = Field()
	field.waypoints = { P(0, 0) }
	Briefed(field)
	T.eq(field.objectives[RED].outpost, nil, "none")
	local operative = Member(RED, AiWar.OPERATIVE, 0, P(500, 0))
	T.near(Distance(Goal(field, operative), RED_HOME), Ctf.GUARD_RING, 1e-6, "with the defenders")
end)

-- Sides, fronts, stances ------------------------------------------------------

-- The tree: ScenarioMonitor > CaptureFlagCourier > RetrieveFlag, and so on.
T.test("each job is its own side action; its medics side with the defenders", function()
	local field = Briefed(Field())
	local d = field.doctrine
	local function SideName(role) return d.SIDES[d.Side(field, Member(RED, role))] end
	T.eq(SideName(AiWar.COURIER), "CaptureFlagCourier", "courier")
	T.eq(SideName(AiWar.CTF_DEFEND), "CaptureFlagDefender", "defender")
	T.eq(SideName(AiWar.OPERATIVE), "CaptureFlagOperative", "operative")
	T.eq(SideName(AiWar.MEDIC), "CaptureFlagDefender", "medic")
end)

T.test("a courier retrieves the flag, escorts a teammate carrying it, or returns home with it", function()
	local carrier = {}
	local courier = Member(RED, AiWar.COURIER, 0, P(1000, 0), carrier)
	T.eq(Stage(Briefed(Field()), courier), "RetrieveFlag", "at home")
	local carried = Briefed(Field({ [RED] = Flag(RED, RED_HOME), [BLUE] = Flag(BLUE, BLUE_HOME, Ctf.CARRIED, P(3000, 0), carrier, RED) }))
	T.eq(Stage(carried, courier), "ReturnHome", "carrying it")
	T.eq(Stage(carried, Member(RED, AiWar.COURIER, 1, P(2000, 0))), "AttackFlagDefenders", "a teammate carrying it, no escorts chosen")
end)

T.test("a defender guards its flag, guards it dropped, or chases its carrier", function()
	local defender = Member(RED, AiWar.CTF_DEFEND, 0, P(500, 0))
	T.eq(Stage(Briefed(Field()), defender), "GuardFlag", "at home")
	T.eq(Stage(Briefed(Field({ [RED] = Flag(RED, RED_HOME, Ctf.DROPPED, P(1500, 0)), [BLUE] = Flag(BLUE, BLUE_HOME) })), defender),
		"GuardDroppedFlag", "dropped")
	T.eq(Stage(Briefed(Field({ [RED] = Flag(RED, RED_HOME, Ctf.CARRIED, P(1800, 0), {}, BLUE), [BLUE] = Flag(BLUE, BLUE_HOME) })), defender),
		"ChaseCarrier", "stolen")
end)

T.test("an operative establishes its outpost, then holds it; with none it guards the flag", function()
	local field = Briefed(Field())
	local outpost = field.objectives[RED].outpost
	T.eq(Stage(field, Member(RED, AiWar.OPERATIVE, 0, P(0, 0))), "EstablishOutpost", "on its way")
	T.eq(Stage(field, Member(RED, AiWar.OPERATIVE, 0, outpost)), "HoldOutpost", "there")
	local bare = Field()
	bare.waypoints = { P(0, 0) }
	Briefed(bare)
	T.eq(Stage(bare, Member(RED, AiWar.OPERATIVE, 0, P(0, 0))), "GuardFlag", "no outpost")
end)

T.test("a team's lanes lead to the enemy's flag", function()
	local field, scenario = Briefed(Field())
	T.eq(Distance(scenario:Front(field, RED), BLUE_HOME), 0, "RED's")
	T.eq(next(scenario:SetupAttacks(field)), nil, "no setup gates to come out of")
end)

local function Weights(stance)
	local w = {}
	for _, share in ipairs(stance) do w[share.role] = share.weight end
	return w
end

-- Couriers lead; defenders join only mid-game: once the round's captures,
-- both teams' together, reach two thirds of the capture limit (2 of 3:
-- one each, or two by either).
T.test("mid-game is the teams' captures together at two thirds of the capture limit, rounded up", function()
	T.eq(Ctf.MidGameAt(3), 2, "2 of 3")
	T.eq(Ctf.MidGameAt(5), 4, "4 of 5")
	T.eq(Ctf.MidGameAt(10), 7, "7 of 10")
	T.eq(Ctf.MidGameAt(0), Ctf.MidGameAt(Ctf.DEFAULT_CAPLIMIT), "no limit: TF2's default")
	T.eq(Ctf.MidGame({ [RED] = 1, [BLUE] = 0 }, 3), false, "one capture of 3")
	T.eq(Ctf.MidGame({ [RED] = 1, [BLUE] = 1 }, 3), true, "one each")
	T.eq(Ctf.MidGame({ [RED] = 0, [BLUE] = 2 }, 3), true, "two by BLU")
	T.eq(Ctf.MidGame({ [RED] = 2, [BLUE] = 1 }, 5), false, "three of 5")
	T.eq(Ctf.MidGame({ [RED] = 2, [BLUE] = 2 }, 5), true, "four of 5")
end)

local function Scored(flags, red, blue)
	local field = Field(flags)
	field.captures, field.caplimit = { [RED] = red, [BLUE] = blue }, 3
	return field
end

local function Stances(field, scenario)
	scenario:Brief(field, 0)
	return scenario:Stances(field, 0)
end

T.test("early on a team sends couriers and operatives, no defenders; a stolen flag sends more operatives", function()
	local scenario = Ctf.Scenario:New()
	local early = Weights(Stances(Scored(nil, 1, 0), scenario)[RED].stance)
	T.eq(early[AiWar.CTF_DEFEND], nil, "no defenders yet")
	T.eq(early[AiWar.COURIER] > early[AiWar.OPERATIVE], true, "couriers first")
	local stolen = Scored({ [RED] = Flag(RED, RED_HOME, Ctf.CARRIED, P(1800, 0), {}, BLUE), [BLUE] = Flag(BLUE, BLUE_HOME) }, 0, 1)
	local hot = Stances(stolen, scenario)[RED]
	T.eq(Weights(hot.stance)[AiWar.CTF_DEFEND], nil, "still none")
	T.eq(Weights(hot.stance)[AiWar.OPERATIVE] > early[AiWar.OPERATIVE], true, "more operatives to intercept")
end)

T.test("mid-game defenders join; a stolen flag puts more on defense at once", function()
	local scenario = Ctf.Scenario:New()
	local entries = Stances(Scored(nil, 0, 2), scenario)
	local calm = Weights(entries[RED].stance)
	T.eq(calm[AiWar.CTF_DEFEND] > 0, true, "defenders now, on both sides")
	T.eq(calm[AiWar.COURIER] > calm[AiWar.CTF_DEFEND], true, "couriers still first")
	T.eq(entries[RED].critical, false, "no hurry")
	local stolen = Scored({ [RED] = Flag(RED, RED_HOME, Ctf.CARRIED, P(1800, 0), {}, BLUE), [BLUE] = Flag(BLUE, BLUE_HOME) }, 0, 2)
	local hot = Stances(stolen, scenario)
	T.eq(Weights(hot[RED].stance)[AiWar.CTF_DEFEND] > calm[AiWar.CTF_DEFEND], true, "more defenders")
	T.eq(hot[RED].critical, true, "at once")
	T.eq(hot[RED].key ~= entries[RED].key, true, "another situation")
	T.eq(hot[BLUE].key, entries[BLUE].key, "BLU's unchanged")
end)

T.finish()
