-- The bomb defusal scenario (features.aiwar.scenario): the war fought over
-- RED's bomb on CS:S's de_ maps (features.defuse). RED fights it as MvM's
-- invaders fight theirs (features.aiwar.scenario.mvm): its carrier takes the
-- bomb to the round's target site and stands in it to plant (the site's
-- capture), those near the carrier escort it, the rest fetch the bomb while
-- it lies; once it is planted every one of RED guards the planted site. BLU
-- guards the sites, split between them, and runs the bomb's carrier down
-- once it is seen near a site; once the bomb is planted every one of BLU
-- goes to stand on the planted site, which defuses it (BLU's capture).
--
-- It reads RED's bomb (field.flags[RED]: gone once planted) and the sites
-- (field.points: a site RED owns is the planted one), with field.bases.
-- Brief puts on the field, per team, its objectives: bomb, sites, target
-- (the site RED makes for this round), planted (the planted site, or nil),
-- carrying (a RED soldier has the bomb).
local ipairs = ipairs
local AiWar = require("features.aiwar.model")
local Orders = require("features.aiwar.orders")
local Teams = gameplay.teams
local Base = require("features.aiwar.scenario")
local Ctf = require("features.aiwar.scenario.ctf")
local Geometry = math.geometry
local Distance = Geometry.Distance
module(...)

MODE = "defuse"

CARRIED, DROPPED, HOME = Ctf.CARRIED, Ctf.DROPPED, Ctf.HOME
TOUCH = Ctf.TOUCH
ESCORT_RING, ESCORT_FOLLOW = Ctf.ESCORT_RING, Ctf.ESCORT_FOLLOW
-- RED round the planted bomb, BLU round a site it guards.
GUARD_RING = 250
-- BLU runs the carrier down once it comes this near a site.
ALARM_RANGE = 900
COURIER_LEASH, DEFENDER_LEASH = Ctf.COURIER_LEASH, Ctf.DEFENDER_LEASH

local RED, BLUE = Teams.RED, Teams.BLUE
local TEAMS = { RED, BLUE }

local function ObjectivesOf(field, member) return field.objectives[member.team] end
local function Carries(o, member) return o.carrying and o.bomb.carrier == member.handle end

-------------------------------------------------------------------------------
-- The doctrine (features.aiwar.orders' doctrine interface)

-- RED's stages.
local function BomberStage(field, member)
	local o = ObjectivesOf(field, member)
	if o.planted then return "GuardPlantedBomb" end
	if Carries(o, member) then return "PlantBomb" end
	if o.carrying then return "EscortBomber" end
	return "FetchBomb"
end

local function BomberGoal(field, member)
	local o = ObjectivesOf(field, member)
	if o.planted then return Orders.Ring(o.planted.pos, member.slot, GUARD_RING) end
	if Carries(o, member) then return o.target.pos end
	if o.carrying then return Orders.Ring(o.bomb.pos, member.slot, ESCORT_RING) end
	return o.bomb.pos
end

local PLANT = {
	arrive = TOUCH,
	leash = COURIER_LEASH,
	tactic = "attack",
	chases = false,
	patrols = false,
	heals = false,
	squads = false,
	Zone = false,
	Goal = function(field, member) return ObjectivesOf(field, member).target.pos end,
	Urgent = function() return true end,
}
local ESCORT = {
	arrive = ESCORT_FOLLOW,
	Goal = function(field, member) return ObjectivesOf(field, member).bomb.pos end,
}
local GUARD_PLANTED = {
	tactic = "defend",
	chases = "opportunist",
	patrols = true,
	arrive = Orders.DEFEND_ARRIVE,
	leash = DEFENDER_LEASH,
}

-- BLU's stages.
local function Alarm(o)
	if not o.carrying then return nil end
	for _, site in ipairs(o.sites) do
		if Distance(o.bomb.pos, site.pos) <= ALARM_RANGE then return site end
	end
	return nil
end

local function GuardedSite(o, member) return o.sites[member.slot % #o.sites + 1] end

local function DefenderStage(field, member)
	local o = ObjectivesOf(field, member)
	if o.planted then return "DefuseBomb" end
	if Alarm(o) then return "StopBomber" end
	if o.bomb and o.bomb.state == DROPPED then return "GuardDroppedBomb" end
	return "GuardSite"
end

local function DefenderGoal(field, member)
	local o = ObjectivesOf(field, member)
	if o.planted then return o.planted.pos end
	if Alarm(o) then return o.bomb.pos end
	if o.bomb and o.bomb.state == DROPPED then return Orders.Ring(o.bomb.pos, member.slot, GUARD_RING) end
	return Orders.Ring(GuardedSite(o, member).pos, member.slot, GUARD_RING)
end

local DEFUSE = {
	arrive = TOUCH,
	leash = COURIER_LEASH,
	tactic = "attack",
	chases = false,
	patrols = false,
	Urgent = function() return true end,
	Goal = function(field, member) return ObjectivesOf(field, member).planted.pos end,
}

local ROLES = {
	[AiWar.COURIER] = {
		name = "Bomber",
		tactic = "attack",
		arrive = TOUCH,
		leash = COURIER_LEASH,
		rushes = false,
		Urgent = function(field, member)
			local o = ObjectivesOf(field, member)
			return not o.planted and not o.carrying
		end,
		Goal = BomberGoal,
		Stage = BomberStage,
		STAGES = { PlantBomb = PLANT, EscortBomber = ESCORT, GuardPlantedBomb = GUARD_PLANTED },
	},
	[AiWar.CTF_DEFEND] = {
		name = "SiteDefender",
		chases = "opportunist",
		patrols = true,
		tactic = "defend",
		arrive = Orders.DEFEND_ARRIVE,
		leash = DEFENDER_LEASH,
		rushes = false,
		Goal = DefenderGoal,
		Stage = DefenderStage,
		Urgent = function(field, member)
			local o = ObjectivesOf(field, member)
			return o.planted ~= nil or Alarm(o) ~= nil
		end,
		STAGES = { DefuseBomb = DEFUSE },
	},
}

DOCTRINE = {
	NAME = "defuse",
	ROLES = ROLES,
	WaitsForSetup = function() return false end,
	ChaseAnchor = function(field, member)
		local o = ObjectivesOf(field, member)
		if o.planted then return o.planted.pos end
		if member.team == RED then return o.bomb.pos end
		return GuardedSite(o, member).pos
	end,
	SIDES = { bomber = "BomberSide", defender = "SiteDefenderSide" },
	SHORT_SIDES = { bomber = "Bomber", defender = "Defender" },
	Side = function(field, member) return member.team == RED and "bomber" or "defender" end,
	-- RED meets BLU at the site it makes for; BLU meets RED coming with the bomb
	Threat = function(field, member)
		local o = ObjectivesOf(field, member)
		if member.team == RED then return (o.planted or o.target).pos end
		return o.bomb.pos
	end,
	PatrolMark = function(field, member)
		local o = ObjectivesOf(field, member)
		return { planted = o.planted ~= nil, state = o.bomb.state }
	end,
	PatrolHolds = function(mark, field, member)
		local o = ObjectivesOf(field, member)
		if (o.planted ~= nil) ~= mark.planted then return false, "the bomb was planted" end
		if o.bomb.state ~= mark.state then return false, "the bomb moved" end
		return true
	end,
}

-------------------------------------------------------------------------------
-- The scenario

Scenario = Base.Scenario:Extend(MODE)
Scenario.NEEDS = { Base.BASES, Base.POINTS }

function Scenario:New()
	local scenario = Base.Scenario.New(self)
	scenario.memory = { rounds = 0 }
	return scenario
end

-- A new round: RED makes for the next site in turn.
function Scenario:Reset()
	Base.Scenario.Reset(self)
	self.memory = { rounds = (self.memory and self.memory.rounds or 0) + 1 }
end

-- The bomb as the field has it; before it is made (or once planted, when it
-- is gone) it lies at RED's base.
local function BombOf(field)
	local bomb = field.flags and field.flags[RED]
	if bomb then return bomb end
	return { state = HOME, pos = field.bases[RED], home = field.bases[RED] }
end

function Scenario:Brief(field, now)
	self:Explore(field)
	local sites, planted = {}, nil
	for _, point in ipairs(field.points) do
		local site = { id = point.id, pos = point.pos }
		sites[#sites + 1] = site
		if point.owner == RED then planted = site end
	end
	local bomb = BombOf(field)
	local target = sites[self.memory.rounds % #sites + 1]
	local carrying = bomb.state == CARRIED and bomb.carrierTeam == RED
	local objectives = {}
	for _, team in ipairs(TEAMS) do
		objectives[team] = { bomb = bomb, sites = sites, target = target, planted = planted, carrying = carrying }
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
	bomb = Stance({ { AiWar.COURIER, 10 } }),
	sites = Stance({ { AiWar.CTF_DEFEND, 10 } }),
}

function Scenario:Stances(field, now)
	return {
		[RED] = { stance = STANCES.bomb, key = "bomb" },
		[BLUE] = { stance = STANCES.sites, key = "sites", critical = field.objectives[BLUE].planted ~= nil },
	}, {}
end

function Scenario:Front(field, team)
	local o = field.objectives[team]
	if o.planted then return o.planted.pos end
	if team == RED then return o.target.pos end
	return o.bomb.pos
end

function Scenario:SetupAttacks(field) return {} end
