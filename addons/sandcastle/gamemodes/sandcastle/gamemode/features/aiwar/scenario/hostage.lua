-- The hostage rescue scenario (features.aiwar.scenario): the war fought over
-- the hostages of CS:S's hostage maps. BLU frees them and leads them to its
-- zone (its spawn); RED keeps them, and wins by killing BLU.
--
-- Squads are organised by the hostages' groups (features.hostage.groups):
-- each team forms a squad for every group (war:SetSquadsMin), and every
-- squad owns one group (Groups.Assign), BLU's to free it and lead it out,
-- RED's to guard it.
--
-- BLU's rescuers (job COURIER): whoever has a hostage following leads it to
-- the zone, stopping for nothing (LeadHostage); the squad's others escort it
-- (EscortHostage); a squad whose group holds hostages frees the nearest
-- (FreeHostage), and once its group is settled helps another group, then
-- hunts RED (HuntGuards).
--
-- RED's defenders (job CTF_DEFEND) are more protective and more attentive
-- to the hostages than the bomb's and the cart's:
--   GuardHostages   stand tight round the group's hostages where they stand
--                   now (HOSTAGE_RING, HOSTAGE_LEASH: tighter than the bomb
--                   defenders' GUARD_RING and DEFENDER_LEASH), patrolling
--   RecoverHostage  a hostage of the group is taken: urgently onto it, past
--                   the leash, at once (the stance turns critical)
--   CoverHostages   the group is settled: guard another group's hostages
--   SweepForRescuers every hostage settled: to BLU's zone for the kill
-- A patrol ends when the state of its group's hostages changes
-- (PatrolHolds), and an idle guard watches BLU's zone, where it comes from,
-- or the hostage once it is taken (Threat).
--
-- field.hostages: { id, home, pos, state, rescuer } (features.hostage.model's
-- states; rescuer is the handle of the soldier a following hostage follows),
-- field.zones[BLUE] the zone, field.bases and field.waypoints. Brief puts on
-- the field, per team, its objectives: hostages, groups, groupOf (id ->
-- group), zone.
local ipairs, pairs, select = ipairs, pairs, select
local concat, sort = table.concat, table.sort
local AiWar = require("features.aiwar.model")
local Orders = require("features.aiwar.orders")
local Rescue = require("features.hostage.model")
local Groups = require("features.hostage.groups")
local Teams = gameplay.teams
local Base = require("features.aiwar.scenario")
local Ctf = require("features.aiwar.scenario.ctf")
local Distance = math.geometry.Distance
module(...)

MODE = "hostage"

HELD, FOLLOWING, RESCUED, KILLED = Rescue.HELD, Rescue.FOLLOWING, Rescue.RESCUED, Rescue.KILLED

-- The guards stand HOSTAGE_RING from their hostages, a squad of one leash
-- from there at most; going for a hostage taken they may range to
-- RECOVER_LEASH. Covering another group they keep the guard's ring and leash.
HOSTAGE_RING, HOSTAGE_ARRIVE, HOSTAGE_LEASH = 120, 60, 300
RECOVER_ARRIVE, RECOVER_LEASH = 90, 800
-- The sweep stands SWEEP_RING from BLU's zone and ranges SWEEP_LEASH.
SWEEP_RING, SWEEP_LEASH = 500, 1200
-- A leader whose hostage has fallen further behind than LEAD_LAG goes back
-- to it before leading on.
LEAD_LAG = 350
-- BLU's squad escorts at ESCORT_RING from the hostage. Hunting, BLU's squads
-- close to HUNT_RING of RED's base and RED's soldiers of the soldier they
-- hunt.
ESCORT_RING = Ctf.ESCORT_RING
HUNT_RING = 250
-- RED holds its posts for as long as the hostages change; quiet for
-- HUNT_AFTER seconds, all but the first of each squad hunt BLU's soldiers,
-- and for HUNT_ALL_AFTER the first too, so the round cannot stall with BLU
-- alive.
HUNT_AFTER, HUNT_ALL_AFTER = 45, 120
-- BLU walks onto a hostage to take it; the hostage takes it within USE_RANGE.
USE_ARRIVE = Rescue.USE_RANGE / 2

local RED, BLUE = Teams.RED, Teams.BLUE
local RESCUERS = BLUE
local TEAMS = { RED, BLUE }
local COURIER, CTF_DEFEND = AiWar.COURIER, AiWar.CTF_DEFEND

local function ObjectivesOf(field, member) return field.objectives[member.team] end

-- The situation -----------------------------------------------------------------------

local function With(list, state)
	local found = {}
	for _, h in ipairs(list) do
		if h.state == state then found[#found + 1] = h end
	end
	return found
end

local function Nearest(list, from)
	local best, bestRange
	for _, h in ipairs(list) do
		local range = from and Distance(from, h.pos) or 0
		if not best or range < bestRange then best, bestRange = h, range end
	end
	return best
end

local function Centre(list)
	local x, y, z = 0, 0, 0
	for _, h in ipairs(list) do x, y, z = x + h.pos.x, y + h.pos.y, z + (h.pos.z or 0) end
	local n = #list
	return { x = x / n, y = y / n, z = z / n }
end

-- The hostages of a group.
local function InGroup(o, group)
	local list = {}
	if not group then return list end
	for _, h in ipairs(o.hostages) do
		if o.groupOf[h.id].index == group.index then list[#list + 1] = h end
	end
	return list
end

-- The group the member's squad owns; a soldier in no squad takes the group
-- nearest it.
local function OwnGroup(o, member)
	local fireTeam = member.fireTeam
	if fireTeam and fireTeam.group then return fireTeam.group end
	local best, bestRange
	for _, group in ipairs(o.groups) do
		local range = member.pos and Distance(member.pos, group.center) or 0
		if not best or range < bestRange then best, bestRange = group, range end
	end
	return best
end

-- The hostage the soldier leads.
local function Led(o, member)
	for _, h in ipairs(o.hostages) do
		if h.state == FOLLOWING and h.rescuer == member.handle then return h end
	end
	return nil
end

-- The states of a group's hostages, as one string: a patrol ends when it
-- changes.
local function Signature(o, group)
	local parts = {}
	for _, h in ipairs(InGroup(o, group)) do parts[#parts + 1] = h.id .. "=" .. h.state end
	sort(parts)
	return concat(parts, ",")
end

-- BLU's stage and where it goes: stage, pos.
local function RescuerPlan(field, member)
	local o = ObjectivesOf(field, member)
	local led = Led(o, member)
	if led then
		if member.pos and Distance(member.pos, led.pos) > LEAD_LAG then return "StayWithHostage", led.pos end
		return "LeadHostage", o.zone
	end
	local own = InGroup(o, OwnGroup(o, member))
	local following = Nearest(With(own, FOLLOWING), member.pos)
	if following then return "EscortHostage", Orders.Ring(following.pos, member.slot, ESCORT_RING) end
	local held = Nearest(With(own, HELD), member.pos)
	if held then return "FreeHostage", held.pos end
	following = Nearest(With(o.hostages, FOLLOWING), member.pos)
	if following then return "EscortHostage", Orders.Ring(following.pos, member.slot, ESCORT_RING) end
	held = Nearest(With(o.hostages, HELD), member.pos)
	if held then return "FreeHostage", held.pos end
	return "HuntGuards", Orders.Ring(field.bases[RED], member.slot, HUNT_RING)
end

-- Where the soldier hunts, or nil: the nearest BLU soldier, once the hostages
-- have been quiet HUNT_AFTER seconds (HUNT_ALL_AFTER for the first of its
-- squad, who keeps the post until then).
local function HuntFor(o, member)
	if not (o.quiet and o.rescuers and #o.rescuers > 0) or o.quiet < HUNT_AFTER then return nil end
	if (member.place or 0) == 0 and o.quiet < HUNT_ALL_AFTER then return nil end
	local best, bestRange
	for _, pos in ipairs(o.rescuers) do
		local range = member.pos and Distance(member.pos, pos) or 0
		if not best or range < bestRange then best, bestRange = pos, range end
	end
	return Orders.Ring(best, member.slot, HUNT_RING)
end

-- RED's stage and where it goes: stage, pos.
local function DefenderPlan(field, member)
	local o = ObjectivesOf(field, member)
	local own = InGroup(o, OwnGroup(o, member))
	local taken = Nearest(With(own, FOLLOWING), member.pos)
	if taken then return "RecoverHostage", taken.pos end
	local hunt = HuntFor(o, member)
	if hunt then return "HuntRescuers", hunt end
	local held = With(own, HELD)
	if #held > 0 then return "GuardHostages", Orders.Ring(Centre(held), member.slot, HOSTAGE_RING) end
	taken = Nearest(With(o.hostages, FOLLOWING), member.pos)
	if taken then return "RecoverHostage", taken.pos end
	local other = Nearest(With(o.hostages, HELD), member.pos)
	if other then return "CoverHostages", Orders.Ring(other.pos, member.slot, HOSTAGE_RING) end
	return "SweepForRescuers", Orders.Ring(o.zone, member.slot, SWEEP_RING)
end

local function PlanOf(field, member)
	if member.team == RESCUERS then return RescuerPlan(field, member) end
	return DefenderPlan(field, member)
end

-- The doctrine ------------------------------------------------------------------------

local RESCUER = {
	name = "HostageRescuer",
	tactic = "attack",
	arrive = USE_ARRIVE,
	leash = Ctf.COURIER_LEASH,
	rushes = false,
	Goal = function(field, member) return (select(2, RescuerPlan(field, member))) end,
	Stage = function(field, member) return (RescuerPlan(field, member)) end,
	-- freeing a hostage and leading it out are urgent: hurried, never retreating
	Urgent = function(field, member)
		local stage = RescuerPlan(field, member)
		return stage == "FreeHostage" or stage == "LeadHostage" or stage == "StayWithHostage"
	end,
	STAGES = {
		LeadHostage = {
			arrive = Ctf.TOUCH,
			leash = Ctf.COURIER_LEASH,
			tactic = "attack",
			chases = false,
			patrols = false,
			heals = false,
			squads = false,
			Zone = false,
		},
		StayWithHostage = {
			arrive = Ctf.ESCORT_FOLLOW,
			chases = false,
		},
		EscortHostage = {
			arrive = Ctf.ESCORT_FOLLOW,
		},
		HuntGuards = {
			chases = "opportunist",
			arrive = Orders.DEFEND_ARRIVE,
			leash = Ctf.DEFENDER_LEASH,
		},
	},
}

local DEFENDER = {
	name = "HostageDefender",
	chases = "opportunist",
	patrols = true,
	tactic = "defend",
	arrive = HOSTAGE_ARRIVE,
	leash = HOSTAGE_LEASH,
	rushes = false,
	Goal = function(field, member) return (select(2, DefenderPlan(field, member))) end,
	Stage = function(field, member) return (DefenderPlan(field, member)) end,
	Urgent = function(field, member) return DefenderPlan(field, member) == "RecoverHostage" end,
	STAGES = {
		RecoverHostage = {
			patrols = false,
			arrive = RECOVER_ARRIVE,
			leash = RECOVER_LEASH,
		},
		HuntRescuers = {
			chases = "opportunist",
			patrols = false,
			arrive = Orders.DEFEND_ARRIVE,
			leash = SWEEP_LEASH,
		},
		SweepForRescuers = {
			chases = "opportunist",
			patrols = false,
			arrive = Orders.DEFEND_ARRIVE,
			leash = SWEEP_LEASH,
		},
	},
}

local ROLES = { [COURIER] = RESCUER, [CTF_DEFEND] = DEFENDER }
do
	local explore = {}
	for k, v in pairs(Orders.EXPLORE_ROLE) do explore[k] = v end
	ROLES[AiWar.EXPLORE] = explore
end

DOCTRINE = {
	NAME = "hostage",
	ROLES = ROLES,
	-- there are no setup gates: nobody waits behind one
	WaitsForSetup = function(field, member) return false end,
	ChaseAnchor = function(field, member) return (select(2, PlanOf(field, member))) end,
	SIDES = { rescuer = "HostageRescuerSide", defender = "HostageDefenderSide" },
	SHORT_SIDES = { rescuer = "Rescuer", defender = "Defender" },
	Side = function(field, member)
		return member.team == RESCUERS and "rescuer" or "defender"
	end,
	-- BLU meets RED coming from its side; RED meets BLU coming from BLU's
	-- zone, and watches a hostage once it is taken
	Threat = function(field, member)
		if member.team == RESCUERS then return field.bases[RED] end
		local o = ObjectivesOf(field, member)
		local taken = Nearest(With(InGroup(o, OwnGroup(o, member)), FOLLOWING), member.pos)
		if taken then return taken.pos end
		return o.zone
	end,
	PatrolMark = function(field, member)
		local o = ObjectivesOf(field, member)
		return { signature = Signature(o, OwnGroup(o, member)) }
	end,
	PatrolHolds = function(mark, field, member)
		local o = ObjectivesOf(field, member)
		if Signature(o, OwnGroup(o, member)) ~= mark.signature then return false, "a hostage of the group changed" end
		return true
	end,
}

-- The scenario ------------------------------------------------------------------------

Scenario = Base.Scenario:Extend(MODE)
Scenario.NEEDS = { Base.BASES, Base.HOSTAGES, Base.WAYPOINTS }

function Scenario:Reset()
	Base.Scenario.Reset(self)
	self.memory = {}
end

function Scenario:Command(war, field, now)
	self:Explore(field).explore:Survey(war:Members(), now)
	self:Brief(field, now)
	self:Locate(war, field, now)
	self:Allocate(war, field, now)
end

-- Where BLU's soldiers are (objectives' rescuers, positions) and for how
-- long no hostage has changed state (quiet, seconds), which RED hunts by.
function Scenario:Locate(war, field, now)
	local rescuers = {}
	for _, member in ipairs(war:Members()) do
		if member.team == RESCUERS and member.pos then rescuers[#rescuers + 1] = member.pos end
	end
	local states = {}
	for i, h in ipairs(field.hostages) do states[i] = h.id .. "=" .. h.state end
	sort(states)
	local signature = concat(states, ",")
	if signature ~= self.memory.signature then self.memory.signature, self.memory.changedAt = signature, now end
	local quiet = now - self.memory.changedAt
	for _, team in ipairs(TEAMS) do
		field.objectives[team].rescuers = rescuers
		field.objectives[team].quiet = quiet
	end
end

-- The groups are those of the hostages' homes, so they stay the same as the
-- hostages move.
function Scenario:Brief(field, now)
	self:Explore(field)
	local homes = {}
	for i, h in ipairs(field.hostages) do homes[i] = { id = h.id, pos = h.home or h.pos } end
	local groups = Groups.Cluster(homes)
	local groupOf = {}
	for _, h in ipairs(field.hostages) do groupOf[h.id] = Groups.Of(groups, h.id) end
	local objectives = {}
	for _, team in ipairs(TEAMS) do
		objectives[team] = {
			hostages = field.hostages,
			groups = groups,
			groupOf = groupOf,
			zone = field.zones[BLUE],
		}
	end
	field.doctrine = DOCTRINE
	field.objectives = objectives
end

local function Stance(shares)
	local stance = {}
	for _, share in ipairs(shares) do stance[#stance + 1] = { role = share[1], weight = share[2] } end
	return stance
end

local STANCES = {
	rescue = Stance({ { COURIER, 10 } }),
	guard = Stance({ { CTF_DEFEND, 10 } }),
}

-- RED's stance turns critical, skipping the wait, once a hostage is taken.
function Scenario:Stances(field, now)
	local taken = #With(field.objectives[RED].hostages, FOLLOWING) > 0
	return {
		[RESCUERS] = { stance = STANCES.rescue, key = "rescue" },
		[RED] = { stance = STANCES.guard, key = taken and "recover" or "guard", critical = taken },
	}, {}
end

local JOBS = { [COURIER] = true, [CTF_DEFEND] = true }

-- A squad for every group on each team (at least: the operator's own minimum
-- stands when larger), each squad given a group.
function Scenario:Allocate(war, field, now)
	local groups = field.objectives[RED].groups
	if war.squadsMin < #groups then war:SetSquadsMin(#groups) end
	Base.Scenario.Allocate(self, war, field, now)
	Groups.Assign(war.fireTeams, groups, JOBS)
end

-- The lanes lead to the group BLU reaches first, its nearest to the zone
-- (the lowest on a tie).
function Scenario:Front(field, team)
	local o = field.objectives[team]
	local best, bestRange
	for _, group in ipairs(o.groups) do
		local range = Distance(group.center, o.zone)
		if not best or range < bestRange then best, bestRange = group, range end
	end
	return best.center
end

-- There are no setup gates.
function Scenario:SetupAttacks(field)
	return {}
end
