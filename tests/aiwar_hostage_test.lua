-- features.aiwar.scenario.hostage: the war fought over hostages, as CS:S's
-- hostage maps are. BLU frees them and leads them to its spawn, a squad to
-- each group of hostages; RED guards them, a squad to each group, closer and
-- more attentively than the bomb's and the cart's defenders do: it stands
-- tight round the hostages where they stand, goes at once for whoever takes
-- one, and covers a group already settled.
local T = dofile("tests/harness.lua")
local AiWar = T.require("features.aiwar.model")
local Scenario = T.require("features.aiwar.scenario")
local Hostage = T.require("features.aiwar.scenario.hostage")
local Rescue = T.require("features.hostage.model")
local Groups = T.require("features.hostage.groups")
local Ctf = T.require("features.aiwar.scenario.ctf")
local Teams = gameplay.teams
local Distance = math.geometry.Distance

local RED, BLUE = Teams.RED, Teams.BLUE
local HELD, FOLLOWING, RESCUED, KILLED = Rescue.HELD, Rescue.FOLLOWING, Rescue.RESCUED, Rescue.KILLED

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

-- Two groups of two hostages near RED's end of the map, as cs_office has;
-- BLU's spawn (its zone) is far away at x -4000.
local ZONE, RED_BASE, BLUE_BASE = P(-4000, 0), P(3000, 0), P(-4000, 0)
local HOMES = { h1 = P(1000, 500), h2 = P(1040, 540), h3 = P(1000, -500), h4 = P(1040, -540) }

local function Hostages(states)
	local list = {}
	for _, id in ipairs({ "h1", "h2", "h3", "h4" }) do
		local s = states and states[id] or {}
		list[#list + 1] = { id = id, home = HOMES[id], pos = s.pos or HOMES[id], state = s.state or HELD, rescuer = s.rescuer }
	end
	return list
end

local function Field(states)
	local waypoints = {}
	for x = -4000, 3000, 200 do waypoints[#waypoints + 1] = P(x, 0) end
	return {
		bases = { [RED] = RED_BASE, [BLUE] = BLUE_BASE },
		zones = { [BLUE] = ZONE },
		hostages = Hostages(states),
		waypoints = waypoints,
	}
end

local function Briefed(states, scenario)
	local field = Field(states)
	scenario = scenario or Hostage.Scenario:New()
	scenario:Brief(field, 0)
	return field, scenario
end

-- A soldier in a squad that owns group `g` (1 or 2).
local function Member(field, team, role, g, pos, handle, slot)
	local groups = field.objectives[team].groups
	return { team = team, role = role, slot = slot or 0, pos = pos or P(0, 0), handle = handle or {}, fireTeam = { group = groups[g] } }
end

local function Role(field, member) return field.doctrine.ROLES[member.role] end
local function Goal(field, member) return Role(field, member).Goal(field, member) end
local function Stage(field, member) return Role(field, member).Stage(field, member) end
local function Urgent(field, member) return Role(field, member).Urgent(field, member) end

local function Near(a, b, within) return Distance(a, b) <= within end

T.test("the hostage mode has its own scenario, and needs hostages with a BLU zone", function()
	T.eq(Scenario.For("hostage"), Hostage.Scenario, "the hostage mode's")
	local bare = { bases = { [RED] = RED_BASE, [BLUE] = BLUE_BASE }, waypoints = Field().waypoints }
	T.eq(Hostage.Scenario:MapLacks(bare), Scenario.HOSTAGES, "no hostages")
	bare.hostages = Hostages()
	T.eq(Hostage.Scenario:MapLacks(bare), Scenario.HOSTAGES, "no zone to lead them to")
	bare.zones = { [BLUE] = ZONE }
	T.eq(Hostage.Scenario:MapLacks(bare), nil, "whole")
end)

-- BLU -------------------------------------------------------------------------------

T.test("BLU's squad goes for the nearest held hostage of its own group, and hurries", function()
	local field = Briefed()
	local rescuer = Member(field, BLUE, AiWar.COURIER, 2, P(0, -400))
	T.eq(Stage(field, rescuer), "FreeHostage", "stage")
	T.eq(Near(Goal(field, rescuer), HOMES.h3, 1) or Near(Goal(field, rescuer), HOMES.h4, 1), true, "a hostage of group 2")
	T.eq(Urgent(field, rescuer), true, "urgent")
	T.eq(Role(field, rescuer).arrive <= Rescue.USE_RANGE, true, "close enough to use it")
end)

T.test("the soldier who has a hostage following leads it to the zone, stopping for nothing", function()
	local me = {}
	local field = Briefed({ h1 = { state = FOLLOWING, rescuer = me, pos = P(900, 400) } })
	local lead = Member(field, BLUE, AiWar.COURIER, 1, P(900, 400), me)
	T.eq(Stage(field, lead), "LeadHostage", "stage")
	T.eq(Near(Goal(field, lead), ZONE, 1), true, "to the zone")
	T.eq(Urgent(field, lead), true, "urgent")
	T.eq(Role(field, lead).STAGES.LeadHostage.chases, false, "chases nobody")
end)

T.test("the leader goes back to a hostage that has fallen behind, and leads on once it is close", function()
	local me = {}
	local lagging = Briefed({ h1 = { state = FOLLOWING, rescuer = me, pos = P(900, 400) } })
	local far = Member(lagging, BLUE, AiWar.COURIER, 1, P(900 - Hostage.LEAD_LAG - 100, 400), me)
	T.eq(Stage(lagging, far), "StayWithHostage", "stage")
	T.eq(Near(Goal(lagging, far), P(900, 400), 1), true, "back to the hostage")
	T.eq(Urgent(lagging, far), true, "urgent: it keeps the hostage in hand")
	local close = Member(lagging, BLUE, AiWar.COURIER, 1, P(900 - Hostage.LEAD_LAG + 100, 400), me)
	T.eq(Stage(lagging, close), "LeadHostage", "close enough to lead on")
end)

T.test("any BLU soldier that has a hostage leads it, whatever its squad", function()
	local me = {}
	local field = Briefed({ h3 = { state = FOLLOWING, rescuer = me, pos = P(950, -450) } })
	local stray = Member(field, BLUE, AiWar.COURIER, 1, P(940, -440), me)
	T.eq(Stage(field, stray), "LeadHostage", "leads")
end)

T.test("the rest of the squad escort the hostage its teammate leads", function()
	local field = Briefed({ h1 = { state = FOLLOWING, rescuer = {}, pos = P(900, 400) } })
	local escort = Member(field, BLUE, AiWar.COURIER, 1, P(800, 380), nil, 2)
	T.eq(Stage(field, escort), "EscortHostage", "stage")
	T.eq(Near(Goal(field, escort), P(900, 400), 400), true, "round the hostage")
	T.eq(Urgent(field, escort), false, "not urgent")
end)

T.test("a squad whose group is settled helps the other group, then hunts RED", function()
	local settled = { h1 = { state = RESCUED }, h2 = { state = KILLED } }
	local field = Briefed(settled)
	local helper = Member(field, BLUE, AiWar.COURIER, 1, P(0, 0))
	T.eq(Stage(field, helper), "FreeHostage", "frees the other group's")
	T.eq(Near(Goal(field, helper), HOMES.h3, 1) or Near(Goal(field, helper), HOMES.h4, 1), true, "group 2's hostage")
	local all = { h1 = { state = RESCUED }, h2 = { state = KILLED }, h3 = { state = RESCUED }, h4 = { state = KILLED } }
	local done = Briefed(all)
	local hunter = Member(done, BLUE, AiWar.COURIER, 1, P(0, 0))
	T.eq(Stage(done, hunter), "HuntGuards", "stage")
	T.eq(Near(Goal(done, hunter), RED_BASE, 600), true, "at RED")
	T.eq(Role(done, hunter).STAGES.HuntGuards.chases, "opportunist", "fights what it meets")
end)

-- RED -------------------------------------------------------------------------------

T.test("RED's squad stands tight round the held hostages of its group", function()
	local field = Briefed()
	local guard = Member(field, RED, AiWar.CTF_DEFEND, 1, P(1100, 600))
	T.eq(Stage(field, guard), "GuardHostages", "stage")
	local centre = Groups.Cluster({ { id = "h1", pos = HOMES.h1 }, { id = "h2", pos = HOMES.h2 } })[1].center
	T.eq(Near(Goal(field, guard), centre, Hostage.HOSTAGE_RING + 1), true, "within the ring")
	T.eq(Role(field, guard).patrols, true, "patrols")
end)

T.test("RED guards closer and leashed tighter than the bomb's and the cart's defenders", function()
	T.eq(Hostage.HOSTAGE_RING < Ctf.GUARD_RING, true, "ring")
	T.eq(Hostage.HOSTAGE_LEASH < Ctf.DEFENDER_LEASH, true, "leash")
	local field = Briefed()
	local guard = Member(field, RED, AiWar.CTF_DEFEND, 1)
	T.eq(Role(field, guard).leash, Hostage.HOSTAGE_LEASH, "its leash")
end)

T.test("RED guards the hostages where they stand now, not where they began", function()
	local moved = P(1500, 900)
	local field = Briefed({ h1 = { pos = moved }, h2 = { pos = moved } })
	local guard = Member(field, RED, AiWar.CTF_DEFEND, 1)
	T.eq(Near(Goal(field, guard), moved, Hostage.HOSTAGE_RING + 1), true, "at the new place")
end)

T.test("RED goes at once for whoever takes a hostage of its group, urgently and further than its leash", function()
	local field = Briefed({ h2 = { state = FOLLOWING, rescuer = {}, pos = P(980, 520) } })
	local guard = Member(field, RED, AiWar.CTF_DEFEND, 1, P(1100, 600))
	T.eq(Stage(field, guard), "RecoverHostage", "stage")
	T.eq(Near(Goal(field, guard), P(980, 520), 1), true, "onto the hostage")
	T.eq(Urgent(field, guard), true, "urgent")
	T.eq(Role(field, guard).STAGES.RecoverHostage.leash > Hostage.HOSTAGE_LEASH, true, "may leave its post")
	T.eq(Role(field, guard).STAGES.RecoverHostage.patrols, false, "no longer patrolling")
end)

T.test("the squad of a group nobody has touched keeps to its own", function()
	local field = Briefed({ h2 = { state = FOLLOWING, rescuer = {}, pos = P(980, 520) } })
	local other = Member(field, RED, AiWar.CTF_DEFEND, 2, P(1100, -600))
	T.eq(Stage(field, other), "GuardHostages", "still guarding")
	T.eq(Urgent(field, other), false, "not urgent")
end)

T.test("a RED squad whose group is settled covers the other group, chasing a hostage taken from it", function()
	local settled = { h1 = { state = RESCUED }, h2 = { state = KILLED } }
	local covering = Briefed(settled)
	local guard = Member(covering, RED, AiWar.CTF_DEFEND, 1)
	T.eq(Stage(covering, guard), "CoverHostages", "stage")
	T.eq(Near(Goal(covering, guard), HOMES.h3, 200) or Near(Goal(covering, guard), HOMES.h4, 200), true, "at group 2")
	settled.h3 = { state = FOLLOWING, rescuer = {}, pos = P(700, -300) }
	local chasing = Briefed(settled)
	local again = Member(chasing, RED, AiWar.CTF_DEFEND, 1)
	T.eq(Stage(chasing, again), "RecoverHostage", "chases the one taken")
end)

T.test("with every hostage settled, RED sweeps for the rescuers at BLU's zone", function()
	local all = { h1 = { state = RESCUED }, h2 = { state = KILLED }, h3 = { state = RESCUED }, h4 = { state = KILLED } }
	local field = Briefed(all)
	local guard = Member(field, RED, AiWar.CTF_DEFEND, 1)
	T.eq(Stage(field, guard), "SweepForRescuers", "stage")
	T.eq(Near(Goal(field, guard), ZONE, Hostage.SWEEP_RING + 1), true, "at the zone")
	T.eq(Role(field, guard).STAGES.SweepForRescuers.chases, "opportunist", "fights what it meets")
end)

-- Once the hostages have been quiet a while and BLU is out there, RED stops
-- waiting for it: all but each squad's first soldier hunt the nearest BLU
-- soldier, and later even the first, so the round ends by BLU's death.
local function Hunted(quiet, rescuers)
	local field = Briefed()
	for _, team in ipairs({ RED, BLUE }) do
		field.objectives[team].quiet = quiet
		field.objectives[team].rescuers = rescuers
	end
	return field
end

T.test("RED holds its post while the hostages are not yet quiet, or no BLU soldier is known", function()
	local blu = { P(0, 0) }
	local calm = Hunted(Hostage.HUNT_AFTER - 1, blu)
	local second = Member(calm, RED, AiWar.CTF_DEFEND, 1)
	second.place = 1
	T.eq(Stage(calm, second), "GuardHostages", "not quiet")
	local none = Hunted(Hostage.HUNT_ALL_AFTER + 1, {})
	T.eq(Stage(none, second), "GuardHostages", "no one to hunt")
end)

T.test("after a quiet spell RED's squad mates hunt the nearest BLU soldier, the first of each squad staying", function()
	local field = Hunted(Hostage.HUNT_AFTER + 1, { P(-300, 0), P(-3000, 0) })
	local first = Member(field, RED, AiWar.CTF_DEFEND, 1, P(1000, 500))
	first.place = 0
	local mate = Member(field, RED, AiWar.CTF_DEFEND, 1, P(1000, 500))
	mate.place = 1
	T.eq(Stage(field, first), "GuardHostages", "the first stays")
	T.eq(Stage(field, mate), "HuntRescuers", "the mate hunts")
	T.eq(Near(Goal(field, mate), P(-300, 0), Hostage.HUNT_RING + 1), true, "the nearest BLU soldier")
	T.eq(Role(field, mate).STAGES.HuntRescuers.chases, "opportunist", "fights what it meets")
	T.eq(Role(field, mate).STAGES.HuntRescuers.patrols, false, "no patrol")
end)

T.test("after a long quiet even the first of a squad hunts", function()
	local field = Hunted(Hostage.HUNT_ALL_AFTER + 1, { P(-300, 0) })
	local first = Member(field, RED, AiWar.CTF_DEFEND, 1, P(1000, 500))
	first.place = 0
	T.eq(Stage(field, first), "HuntRescuers", "everyone hunts")
end)

T.test("a hostage taken ends the hunt: RED recovers it", function()
	local field = Briefed({ h1 = { state = FOLLOWING, rescuer = {}, pos = P(900, 400) } })
	for _, team in ipairs({ RED, BLUE }) do
		field.objectives[team].quiet = Hostage.HUNT_ALL_AFTER + 1
		field.objectives[team].rescuers = { P(0, 0) }
	end
	local mate = Member(field, RED, AiWar.CTF_DEFEND, 1, P(1000, 500))
	mate.place = 1
	T.eq(Stage(field, mate), "RecoverHostage", "recovers")
end)

T.test("the scenario tracks BLU's soldiers and how long the hostages have been quiet", function()
	local war = AiWar.War.New()
	local blu = war:Enlist("blu", BLUE, true)
	blu.pos = P(-500, 20)
	local dead = war:Enlist("red", RED, true)
	dead.pos = P(1000, 500)
	local field, scenario = Briefed()
	scenario:Locate(war, field, 100)
	T.eq(#field.objectives[RED].rescuers, 1, "only BLU's")
	T.eq(Near(field.objectives[RED].rescuers[1], P(-500, 20), 1), true, "where it is")
	T.eq(field.objectives[RED].quiet, 0, "just started")
	scenario:Locate(war, field, 130)
	T.eq(field.objectives[RED].quiet, 30, "30 seconds quiet")
	local taken = Briefed({ h1 = { state = FOLLOWING, rescuer = {} } }, scenario)
	scenario:Locate(war, taken, 140)
	T.eq(taken.objectives[RED].quiet, 0, "a hostage was taken: not quiet")
end)

T.test("RED's patrol ends when the state of its group's hostages changes", function()
	local before = Briefed()
	local guard = Member(before, RED, AiWar.CTF_DEFEND, 1)
	local mark = before.doctrine.PatrolMark(before, guard)
	T.eq(before.doctrine.PatrolHolds(mark, before, guard), true, "nothing changed")
	local taken = Briefed({ h1 = { state = FOLLOWING, rescuer = {} } })
	local ok = taken.doctrine.PatrolHolds(mark, taken, Member(taken, RED, AiWar.CTF_DEFEND, 1))
	T.eq(ok, false, "a hostage was taken")
	local other = Briefed({ h3 = { state = FOLLOWING, rescuer = {} } })
	T.eq(other.doctrine.PatrolHolds(mark, other, Member(other, RED, AiWar.CTF_DEFEND, 1)), true, "another group's does not")
end)

T.test("a guard watches for BLU from its zone, and for the hostage once it is taken", function()
	local field = Briefed()
	local guard = Member(field, RED, AiWar.CTF_DEFEND, 1)
	T.eq(Near(field.doctrine.Threat(field, guard), ZONE, 1), true, "BLU comes from its zone")
	local taken = Briefed({ h1 = { state = FOLLOWING, rescuer = {}, pos = P(900, 400) } })
	T.eq(Near(taken.doctrine.Threat(taken, Member(taken, RED, AiWar.CTF_DEFEND, 1)), P(900, 400), 1), true, "the hostage")
	T.eq(Near(field.doctrine.Threat(field, Member(field, BLUE, AiWar.COURIER, 1)), RED_BASE, 1), true, "BLU watches RED's side")
end)

T.test("each side has its own side action, and no one waits for a setup", function()
	local field = Briefed()
	T.eq(field.doctrine.Side(field, Member(field, BLUE, AiWar.COURIER, 1)), "rescuer", "BLU")
	T.eq(field.doctrine.Side(field, Member(field, RED, AiWar.CTF_DEFEND, 1)), "defender", "RED")
	T.eq(field.doctrine.WaitsForSetup(field, Member(field, BLUE, AiWar.COURIER, 1)), false, "BLU does not wait")
	for side in pairs({ rescuer = true, defender = true }) do
		T.eq(type(field.doctrine.SIDES[side]), "string", side .. " is named")
	end
end)

-- Allocation ------------------------------------------------------------------------

T.test("BLU's soldiers are all rescuers and RED's all guards, RED urgently once a hostage is taken", function()
	local field, scenario = Briefed()
	local stances = scenario:Stances(field, 0)
	T.eq(stances[BLUE].stance[1].role, AiWar.COURIER, "BLU")
	T.eq(stances[RED].stance[1].role, AiWar.CTF_DEFEND, "RED")
	T.eq(stances[RED].critical, false, "calm")
	local taken, other = Briefed({ h1 = { state = FOLLOWING, rescuer = {} } })
	T.eq(other:Stances(taken, 0)[RED].critical, true, "critical once taken")
end)

T.test("each team forms a squad for every hostage group, and every squad owns one", function()
	local war = AiWar.War.New()
	local field, scenario = Briefed()
	for i = 1, 4 do
		war:Enlist("red" .. i, RED, true)
		war:Enlist("blue" .. i, BLUE, true)
	end
	scenario:Allocate(war, field, 0)
	for _, team in ipairs({ RED, BLUE }) do
		local owned = {}
		for _, fireTeam in ipairs(war.fireTeams) do
			if fireTeam.team == team then
				T.eq(fireTeam.group ~= nil, true, "a squad of team " .. team .. " has a group")
				owned[fireTeam.group.index] = true
			end
		end
		T.eq(owned[1] and owned[2], true, "team " .. team .. " covers both groups")
	end
end)

T.test("BLU, who must free and lead the hostages out through the guards, has more soldiers than RED, the total unchanged", function()
	local _, scenario = Briefed()
	for _, size in ipairs({ 4, 8, 15 }) do
		local sizes = scenario:TeamSizes(size)
		T.eq(sizes[RED] + sizes[BLUE], size * 2, "the total at size " .. size)
		T.eq(sizes[BLUE] > sizes[RED], true, "BLU outnumbers RED at size " .. size)
		T.eq(sizes[RED] >= 1, true, "RED keeps a guard at size " .. size)
	end
end)

T.test("the war's squads minimum is raised to the number of groups, never lowered", function()
	local field, scenario = Briefed()
	local war = AiWar.War.New()
	war:SetSquadsMin(1)
	scenario:Allocate(war, field, 0)
	T.eq(war.squadsMin, 2, "raised to the two groups")
	war:SetSquadsMin(3)
	scenario:Allocate(war, field, 1)
	T.eq(war.squadsMin, 3, "the operator's larger minimum stands")
end)

T.test("the lanes lead to the group BLU reaches first", function()
	local field, scenario = Briefed()
	-- group 1 and 2 are both about 5000 from the zone; group 1 (lowest id) wins the tie
	local front = scenario:Front(field, BLUE)
	T.eq(Near(front, field.objectives[BLUE].groups[1].center, 1), true, "BLU")
	T.eq(Near(scenario:Front(field, RED), front, 1), true, "RED defends the same")
	T.eq(next(scenario:SetupAttacks(field)), nil, "no setup gates")
end)

-- On CS:S's hostage maps the war's soldiers carry CS:S's arms: RED's are the
-- terrorists' and BLU's the counter-terrorists' (the maps' own sides), every
-- role's kit one the soldiers can carry, of weapons its side may use; a
-- medic keeps its faction's kit, and other scenarios keep theirs.
T.test("hostage rescue's soldiers carry CS:S's arms, each side its own", function()
	local Arms = T.require("features.aiwar.arms")
	local scenario = Hostage.Scenario:New()
	local sides = { [RED] = "TERRORIST", [BLUE] = "CT" }
	local definitions = {}
	local function Definition(class)
		if definitions[class] then return definitions[class] end
		local path = "addons/cstrike_weapons/lua/cstrike_weapons/weapons/" .. class .. ".lua"
		local env = { SWEP = {}, AddCSLuaFile = function() end, Model = function(path) return path end }
		setmetatable(env, { __index = _G })
		setfenv(assert(loadfile(path)), env)()
		definitions[class] = env.SWEP
		return env.SWEP
	end
	for team, faction in pairs(sides) do
		for _, role in ipairs({ AiWar.BLOCK, AiWar.HOLD, AiWar.RAID, AiWar.SUPPORT, AiWar.PUSH, false }) do
			local kit = scenario:Kit(team, role)
			T.eq(kit ~= nil, true, tostring(role) .. " has a kit")
			for _, primary in ipairs(kit.primary) do
				local loadout = Arms.Loadout({ primary = { primary }, secondary = kit.secondary, melee = kit.melee }, function() return 1 end)
				for _, class in ipairs(Arms.Classes(loadout)) do
					local weapon = Definition(class)
					T.eq(weapon.CStrikeTeam == faction or weapon.CStrikeTeam == "ANY", true, team .. " may use " .. class)
				end
			end
		end
		T.eq(scenario:Kit(team, AiWar.MEDIC), nil, "a medic's is its faction's")
	end
	T.eq(scenario:Kit(RED, false).primary[1] ~= scenario:Kit(BLUE, false).primary[1], true, "the sides differ")
	T.eq(Scenario.Scenario:New():Kit(RED, false), nil, "another scenario's soldiers keep their faction's")
end)

T.finish()
