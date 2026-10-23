-- features.aiwar.scenario.mvm: the war fought over BLU's bomb, as TF2's
-- invading robots fight it (CTFBotScenarioMonitor's MvM branch:
-- CTFBotFetchFlag, then CTFBotDeliverFlag for the carrier and
-- CTFBotEscortFlagCarrier or CTFBotAttackFlagDefenders for the rest), and
-- RED defends the hatch and runs the bomb down, as its players would.
local T = dofile("tests/harness.lua")
local AiWar = T.require("features.aiwar.model")
local Scenario = T.require("features.aiwar.scenario")
local Mvm = T.require("features.aiwar.scenario.mvm")
local Teams = T.require("games.gameplay.teams")
local Geometry = T.require("foundation.math.geometry")

local RED, BLUE = Teams.RED, Teams.BLUE
local Distance = Geometry.Distance

local function P(x, y) return { x = x, y = y, z = 0 } end

-- RED holds the hatch at x 200; BLU's spawn and its bomb are at x 3800.
local HATCH, BOMB_HOME = P(200, 0), P(3800, 0)

local function Bomb(state, pos, carrier)
	return { team = BLUE, home = BOMB_HOME, state = state or Mvm.HOME, pos = pos or BOMB_HOME, carrier = carrier, carrierTeam = carrier and BLUE or Teams.UNASSIGNED }
end

local function Field(bomb, setup)
	local waypoints = {}
	for x = 0, 4000, 200 do waypoints[#waypoints + 1] = P(x, 0) end
	return {
		setup = setup,
		bases = { [RED] = P(0, 0), [BLUE] = P(4000, 0) },
		flags = { [BLUE] = bomb or Bomb() },
		zones = { [BLUE] = HATCH },
		waypoints = waypoints,
	}
end

local function Briefed(field, scenario)
	scenario = scenario or Mvm.Scenario:New()
	scenario:Brief(field, 0)
	return field, scenario
end

local function Member(team, role, slot, pos, handle)
	return { team = team, role = role, slot = slot or 0, pos = pos, handle = handle or {} }
end

local function Role(field, member) return field.doctrine.ROLES[member.role] end
local function Goal(field, member) return Role(field, member).Goal(field, member) end
local function Stage(field, member) return Role(field, member).Stage(field, member) end

T.test("MvM has its own scenario, and needs BLU's bomb and its hatch", function()
	T.eq(Scenario.For(T.require("features.mvm.model").Mode.NAME), Mvm.Scenario, "the mvm mode's")
	local bare = { bases = { [RED] = P(0, 0), [BLUE] = P(1, 0) } }
	T.eq(Mvm.Scenario:MapLacks(bare), Scenario.BOMB, "no bomb")
	T.eq(Mvm.Scenario:MapLacks(Field()), nil, "BLU's bomb alone is enough: RED has none")
end)

-- BLU ---------------------------------------------------------------------------

T.test("BLU's robots fetch the bomb where it lies", function()
	local robot = Member(BLUE, AiWar.COURIER, 0, P(3000, 0))
	T.eq(Distance(Goal(Briefed(Field()), robot), BOMB_HOME), 0, "at home")
	local dropped = Briefed(Field(Bomb(Mvm.DROPPED, P(1500, 300))))
	T.eq(Distance(Goal(dropped, robot), P(1500, 300)), 0, "dropped")
	T.eq(Stage(dropped, robot), "FetchFlag", "FetchFlag")
	T.eq(Role(dropped, robot).arrive <= Mvm.TOUCH, true, "close enough to touch it")
end)

-- CTFBotFetchFlag hurries and never retreats (ShouldHurry yes, ShouldRetreat
-- no): fetching is urgent; escorting a carrier and attacking defenders are not.
T.test("fetching the bomb is urgent; escorting or attacking round a carrier is not", function()
	local robot = Member(BLUE, AiWar.COURIER, 0, P(3000, 0))
	local dropped = Briefed(Field(Bomb(Mvm.DROPPED, P(1500, 300))))
	T.eq(Role(dropped, robot).Urgent(dropped, robot), true, "fetching a dropped bomb")
	T.eq(Role(Briefed(Field()), robot).Urgent(Briefed(Field()), robot), true, "fetching it from home")
	local carrier = Member(BLUE, AiWar.COURIER, 1, P(2000, 0))
	local carried = Briefed(Field(Bomb(Mvm.CARRIED, P(2000, 0), carrier.handle)))
	T.eq(Stage(carried, robot), "AttackFlagDefenders", "a teammate carries it")
	T.eq(Role(carried, robot).Urgent(carried, robot), false, "attacking the defenders is not urgent")
end)

T.test("the bomb's carrier delivers it to the hatch, stopping for nothing", function()
	local carrier = Member(BLUE, AiWar.COURIER, 0, P(3000, 0))
	local field = Briefed(Field(Bomb(Mvm.CARRIED, P(3000, 0), carrier.handle)))
	T.eq(Stage(field, carrier), "DeliverFlag", "DeliverFlag")
	T.eq(Distance(Goal(field, carrier), HATCH), 0, "to the hatch")
	local stage = Role(field, carrier).STAGES.DeliverFlag
	T.eq(stage.chases, false, "chases nobody")
	T.eq(stage.Urgent(field, carrier), true, "urgent")
end)

T.test("any BLU soldier that picks up the bomb delivers it, whatever its job", function()
	local medic = Member(BLUE, AiWar.MEDIC, 0, P(3000, 0))
	local field = Briefed(Field(Bomb(Mvm.CARRIED, P(3000, 0), medic.handle)))
	T.eq(Stage(field, medic), "DeliverFlag", "the medic delivers")
	T.eq(field.doctrine.Side(field, medic), "invader", "on the invaders' side")
end)

T.test("robots near the carrier escort it, at most MAX_ESCORTS; the rest attack the defenders round it", function()
	local carrier = Member(BLUE, AiWar.COURIER, 0, P(2000, 0))
	local field, scenario = Briefed(Field(Bomb(Mvm.CARRIED, P(2000, 0), carrier.handle)))
	local members = { carrier }
	for i = 1, Mvm.MAX_ESCORTS + 1 do members[#members + 1] = Member(BLUE, AiWar.COURIER, i, P(2000 + i * 50, 0)) end
	local far = Member(BLUE, AiWar.COURIER, 9, P(3900, 0))
	members[#members + 1] = far
	scenario:ChooseEscorts(field, members)
	local escorting = 0
	for i = 2, #members do
		if Stage(field, members[i]) == "EscortFlagCarrier" then escorting = escorting + 1 end
	end
	T.eq(escorting, Mvm.MAX_ESCORTS, "MAX_ESCORTS escort")
	T.eq(Stage(field, far), "AttackFlagDefenders", "the far one attacks")
	T.eq(Distance(Goal(field, far), P(2000, 0)) <= Mvm.ATTACK_RING + 1, true, "round the carrier")
end)

-- TF2's medic robots go with the bomb's carrier: while a robot carries it,
-- the medic nearest it joins its squad (the war's Attach), the same one
-- while it lives, and goes back to its own once nobody carries it.
T.test("a medic joins the carrier's squad while it carries the bomb, and leaves it once nobody does", function()
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	local carrier = war:Enlist("carrier", BLUE, true)
	war:ChangeRole(carrier, AiWar.COURIER)
	carrier.pos = P(2000, 0)
	local near = war:Enlist("near", BLUE, true)
	war:ChangeRole(near, AiWar.MEDIC)
	near.pos = P(2300, 0)
	local far = war:Enlist("far", BLUE, true)
	war:ChangeRole(far, AiWar.MEDIC)
	far.pos = P(3900, 0)
	local scenario = Mvm.Scenario:New()
	local field = Briefed(Field(Bomb(Mvm.CARRIED, P(2000, 0), "carrier")), scenario)
	scenario:AttachMedic(war, field)
	T.eq(near.fireTeam ~= nil and near.fireTeam == carrier.fireTeam, true, "the nearest medic is in the carrier's squad")
	T.eq(far.fireTeam == carrier.fireTeam, false, "one medic")
	far.pos = P(2050, 0)
	scenario:AttachMedic(war, field)
	T.eq(near.fireTeam == carrier.fireTeam, true, "the same one while it lives")
	local dropped = Briefed(Field(Bomb(Mvm.DROPPED, P(2000, 0))), scenario)
	scenario:AttachMedic(war, dropped)
	T.eq(near.attached, nil, "nobody carries it: back to its own")
	-- the attached medic picks the bomb up itself: another goes with it
	far.pos = P(3900, 0)
	scenario:AttachMedic(war, field)
	T.eq(near.host, carrier, "near is the carrier's medic again")
	near.pos = P(2000, 0)
	local medicCarries = Briefed(Field(Bomb(Mvm.CARRIED, P(2000, 0), "near")), scenario)
	scenario:AttachMedic(war, medicCarries)
	T.eq(near.attached, nil, "the carrier is attached to nobody")
	T.eq(far.attached == true and far.host == near, true, "the other medic goes with it")
end)

-- TF2's waves outnumber the defenders; the war keeps its total and gives
-- the invaders INVADER_SHARE of it.
T.test("MvM gives BLU INVADER_SHARE of both sides' soldiers; other scenarios split them evenly", function()
	local sizes = Mvm.Scenario:TeamSizes(8)
	T.eq(sizes[BLUE] + sizes[RED], 16, "the war's total kept")
	T.eq(sizes[BLUE], math.floor(16 * Mvm.INVADER_SHARE + 0.5), "BLU's share")
	T.eq(sizes[BLUE] > sizes[RED], true, "more robots than defenders")
	local even = Scenario.Scenario:TeamSizes(8)
	T.eq(even[RED] .. " " .. even[BLUE], "8 8", "elsewhere, even")
	local none = Mvm.Scenario:TeamSizes(0)
	T.eq(none[RED] .. " " .. none[BLUE], "0 0", "no soldiers, none either side")
end)

T.test("in setup the robots wait in their spawn; RED goes out", function()
	local field = Briefed(Field(nil, true))
	T.eq(field.doctrine.WaitsForSetup(field, Member(BLUE, AiWar.COURIER)), true, "BLU waits")
	T.eq(field.doctrine.WaitsForSetup(field, Member(RED, AiWar.CTF_DEFEND)), false, "RED does not")
	local wave = Briefed(Field())
	T.eq(wave.doctrine.WaitsForSetup(wave, Member(BLUE, AiWar.COURIER)), false, "the wave: BLU goes")
end)

-- RED ---------------------------------------------------------------------------

T.test("RED's defenders guard the hatch while the bomb is home", function()
	local field = Briefed(Field())
	local defender = Member(RED, AiWar.CTF_DEFEND, 0, P(500, 0))
	T.eq(Stage(field, defender), "GuardHatch", "GuardHatch")
	T.eq(Distance(Goal(field, defender), HATCH) <= Mvm.GUARD_RING + 1, true, "round the hatch")
end)

T.test("RED's defenders run the carrier down, and guard a dropped bomb", function()
	local defender = Member(RED, AiWar.CTF_DEFEND, 0, P(500, 0))
	local carried = Briefed(Field(Bomb(Mvm.CARRIED, P(2500, 0), {})))
	T.eq(Stage(carried, defender), "ChaseCarrier", "ChaseCarrier")
	T.eq(Distance(Goal(carried, defender), P(2500, 0)), 0, "on the carrier")
	T.eq(Role(carried, defender).Urgent(carried, defender), true, "urgent")
	local dropped = Briefed(Field(Bomb(Mvm.DROPPED, P(1500, 0))))
	T.eq(Stage(dropped, defender), "GuardDroppedBomb", "GuardDroppedBomb")
	T.eq(Distance(Goal(dropped, defender), P(1500, 0)) <= Mvm.GUARD_RING + 1, true, "round the bomb")
end)

T.test("RED's operatives hold an outpost out from the hatch on the bomb's way", function()
	local field = Briefed(Field())
	local outpost = field.objectives[RED].outpost
	T.eq(outpost ~= nil, true, "an outpost")
	local out = Distance(outpost, HATCH)
	T.eq(out >= 600 and out <= 1600, true, "out from the hatch")
	T.eq(outpost.y, 0, "on the way")
	local operative = Member(RED, AiWar.OPERATIVE, 0, outpost)
	T.eq(Stage(field, operative), "HoldOutpost", "held once there")
end)

T.test("RED's sides are its jobs; it never carries the bomb", function()
	local field = Briefed(Field())
	T.eq(field.doctrine.Side(field, Member(RED, AiWar.CTF_DEFEND)), "defender", "defender")
	T.eq(field.doctrine.Side(field, Member(RED, AiWar.OPERATIVE)), "operative", "operative")
	T.eq(field.doctrine.Side(field, Member(RED, AiWar.MEDIC)), "defender", "its medics defend")
	T.eq(field.doctrine.SIDES.invader ~= nil, true, "the invaders' side named")
end)

-- Stances and fronts --------------------------------------------------------------

T.test("BLU sends every robot for the bomb; RED splits, more on defense once the bomb moves", function()
	local function Roles(entry)
		local roles = {}
		for _, s in ipairs(entry.stance) do roles[s.role] = s.weight end
		return roles
	end
	local home = Briefed(Field())
	local entries = Mvm.Scenario:New():Stances(home, 0)
	T.eq(Roles(entries[BLUE])[AiWar.COURIER] ~= nil, true, "BLU fetches")
	T.eq(#entries[BLUE].stance, 1, "and nothing else")
	local redHome = Roles(entries[RED])
	local carried = Briefed(Field(Bomb(Mvm.CARRIED, P(2500, 0), {})))
	local moving = Mvm.Scenario:New():Stances(carried, 0)
	local redMoving = Roles(moving[RED])
	T.eq(redMoving[AiWar.CTF_DEFEND] > redHome[AiWar.CTF_DEFEND], true, "more defenders on a carried bomb")
	T.eq(moving[RED].critical, true, "at once")
end)

T.test("BLU's lanes lead to the hatch, RED's to the bomb", function()
	local field = Briefed(Field(Bomb(Mvm.DROPPED, P(1500, 0))))
	local scenario = Mvm.Scenario:New()
	T.eq(Distance(scenario:Front(field, BLUE), HATCH), 0, "BLU: the hatch")
	T.eq(Distance(scenario:Front(field, RED), P(1500, 0)), 0, "RED: the bomb")
	T.eq(next(scenario:SetupAttacks(field)), nil, "no setup gates")
end)

T.finish()
