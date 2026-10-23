-- The Mann vs. Machine scenario (features.aiwar.scenario): the war fought
-- over BLU's bomb. BLU fights it as TF2's invading robots do
-- (CTFBotScenarioMonitor's MvM branch): every robot fetches the bomb
-- (CTFBotFetchFlag), its carrier delivers it to the hatch
-- (CTFBotDeliverFlag), and while a teammate carries it the robots near it
-- escort it (CTFBotEscortFlagCarrier) and the rest attack the defenders
-- round it (CTFBotAttackFlagDefenders). RED, whose players defend in TF2,
-- guards the hatch, holds an outpost out on the bomb's way, and runs the
-- bomb down once it moves.
--
-- It reads BLU's bomb (field.flags[BLUE], as features.aiwar.scenario.ctf
-- reads a flag) and its hatch (field.zones[BLUE]), with field.bases and
-- field.waypoints. Brief puts on the field, per team, its objectives: bomb,
-- hatch, carrying (a BLU soldier has the bomb), moving (the bomb is away from
-- home), escorts (BLU's) and outpost (RED's).
local floor, ipairs, min, pairs, sort = math.floor, ipairs, math.min, pairs, table.sort
local AiWar = require("features.aiwar.model")
local Orders = require("features.aiwar.orders")
local Teams = require("games.gameplay.teams")
local Base = require("features.aiwar.scenario")
local Ctf = require("features.aiwar.scenario.ctf")
local Geometry = require("foundation.math.geometry")
local Distance = Geometry.Distance
module(...)

MODE = "mvm"

HOME, CARRIED, DROPPED = Ctf.HOME, Ctf.CARRIED, Ctf.DROPPED
TOUCH = Ctf.TOUCH
GUARD_RING = Ctf.GUARD_RING
ESCORT_RING = Ctf.ESCORT_RING
ESCORT_RANGE, ESCORT_GIVE_UP, MAX_ESCORTS = Ctf.ESCORT_RANGE, Ctf.ESCORT_GIVE_UP, Ctf.MAX_ESCORTS
ESCORT_FOLLOW = Ctf.ESCORT_FOLLOW
-- CTFBotAttackFlagDefenders: the robots not escorting fight round the
-- carrier, out to ATTACK_RING.
ATTACK_RING = 400
OUTPOST_RADIUS = Ctf.OUTPOST_RADIUS
COURIER_LEASH, DEFENDER_LEASH, OPERATIVE_LEASH = Ctf.COURIER_LEASH, Ctf.DEFENDER_LEASH, Ctf.OPERATIVE_LEASH

local RED, BLUE = Teams.RED, Teams.BLUE
local INVADERS = BLUE
local TEAMS = { RED, BLUE }

local function ObjectivesOf(field, member) return field.objectives[member.team] end

-------------------------------------------------------------------------------
-- The MvM doctrine (features.aiwar.orders' doctrine interface)

local function Carries(o, member) return o.carrying and o.bomb.carrier == member.handle end
local function Escorts(o, member) return o.escorts ~= nil and o.escorts[member.handle] == true end

-- BLU's stages, TF2's action names.
local function InvaderStage(field, member)
	local o = ObjectivesOf(field, member)
	if Carries(o, member) then return "DeliverFlag" end
	if o.carrying then return Escorts(o, member) and "EscortFlagCarrier" or "AttackFlagDefenders" end
	return "FetchFlag"
end

-- Whoever of BLU picks up the bomb delivers it, whatever its job.
local function Delivering(stage)
	return function(field, member)
		if Carries(ObjectivesOf(field, member), member) then return "DeliverFlag" end
		return stage and stage(field, member)
	end
end

local function InvaderGoal(field, member)
	local o = ObjectivesOf(field, member)
	if Carries(o, member) then return o.hatch end
	if o.carrying then return Orders.Ring(o.bomb.pos, member.slot, ESCORT_RING) end
	return o.bomb.pos
end

local DELIVER = {
	arrive = TOUCH,
	leash = COURIER_LEASH,
	tactic = "attack",
	chases = false,
	patrols = false,
	heals = false,
	squads = false,
	Zone = false,
	Goal = function(field, member) return ObjectivesOf(field, member).hatch end,
	Urgent = function() return true end,
}
local ESCORT = {
	arrive = ESCORT_FOLLOW,
	Goal = function(field, member) return ObjectivesOf(field, member).bomb.pos end,
}
local ATTACK_DEFENDERS = {
	chases = "opportunist",
	arrive = Orders.DEFEND_ARRIVE,
	leash = DEFENDER_LEASH,
	Goal = function(field, member) return Orders.Ring(ObjectivesOf(field, member).bomb.pos, member.slot, ATTACK_RING) end,
}

-- RED's stages.
local function DefenderStage(field, member)
	local o = ObjectivesOf(field, member)
	if o.bomb.state == CARRIED then return "ChaseCarrier" end
	if o.bomb.state == DROPPED then return "GuardDroppedBomb" end
	return "GuardHatch"
end

local function DefenderGoal(field, member)
	local o = ObjectivesOf(field, member)
	if o.bomb.state == CARRIED then return o.bomb.pos end
	if o.bomb.state == DROPPED then return Orders.Ring(o.bomb.pos, member.slot, GUARD_RING) end
	return Orders.Ring(o.hatch, member.slot, GUARD_RING)
end

local function OperativeStage(field, member)
	local outpost = ObjectivesOf(field, member).outpost
	if not outpost then return DefenderStage(field, member) end
	if member.pos and Distance(member.pos, outpost) <= OUTPOST_RADIUS then return "HoldOutpost" end
	return "EstablishOutpost"
end

local INVADER_ROLES = {
	-- CTFBotFetchFlag: fights on the way but chases nobody, hurries and
	-- never retreats (urgent) until a teammate has the bomb
	[AiWar.COURIER] = {
		name = "MvMInvader",
		tactic = "attack",
		arrive = TOUCH,
		leash = COURIER_LEASH,
		rushes = false,
		Urgent = function(field, member) return not ObjectivesOf(field, member).carrying end,
		Goal = InvaderGoal,
		Stage = InvaderStage,
		STAGES = { DeliverFlag = DELIVER, EscortFlagCarrier = ESCORT, AttackFlagDefenders = ATTACK_DEFENDERS },
	},
}

local DEFENDER_ROLES = {
	[AiWar.CTF_DEFEND] = {
		name = "MvMDefender",
		chases = "opportunist",
		patrols = true,
		tactic = "defend",
		arrive = Orders.DEFEND_ARRIVE,
		leash = DEFENDER_LEASH,
		rushes = false,
		Goal = DefenderGoal,
		Stage = DefenderStage,
		Urgent = function(field, member) return ObjectivesOf(field, member).bomb.state == CARRIED end,
	},
	[AiWar.OPERATIVE] = {
		name = "MvMOperative",
		chases = "opportunist",
		patrols = true,
		tactic = "defend",
		arrive = Orders.DEFEND_ARRIVE,
		leash = OPERATIVE_LEASH,
		rushes = false,
		Goal = function(field, member)
			local o = ObjectivesOf(field, member)
			if not o.outpost then return DefenderGoal(field, member) end
			return Orders.Ring(o.outpost, member.slot, OUTPOST_RADIUS / 2)
		end,
		Stage = OperativeStage,
		Zone = function(field, member)
			local outpost = ObjectivesOf(field, member).outpost
			if not outpost then return nil end
			return outpost, OUTPOST_RADIUS
		end,
	},
}

-- Both teams' medics: BLU's follow the bomb, RED's the defenders.
local MEDIC = {
	name = "Medic",
	heals = true,
	arrive = Orders.SUPPORT_ARRIVE,
	leash = Orders.SUPPORT_LEASH,
	rushes = false,
	Goal = function(field, member)
		if member.team == INVADERS then return ObjectivesOf(field, member).bomb.pos end
		return DefenderGoal(field, member)
	end,
	Stage = Delivering(nil),
	STAGES = { DeliverFlag = DELIVER },
}

-- The invaders' job is COURIER, the defenders' CTF_DEFEND and OPERATIVE;
-- every scenario's explore job delivers the bomb too, on BLU.
local ROLES = { [AiWar.MEDIC] = MEDIC }
for job, role in pairs(DEFENDER_ROLES) do ROLES[job] = role end
for job, role in pairs(INVADER_ROLES) do ROLES[job] = role end
do
	local explore = {}
	for k, v in pairs(Orders.EXPLORE_ROLE) do explore[k] = v end
	explore.Stage, explore.STAGES = Delivering(nil), { DeliverFlag = DELIVER }
	ROLES[AiWar.EXPLORE] = explore
end

DOCTRINE = {
	NAME = "mvm",
	ROLES = ROLES,
	-- the robots do not leave their spawn before the wave
	WaitsForSetup = function(field, member)
		return field.setup == true and member.team == INVADERS
	end,
	ChaseAnchor = function(field, member)
		local o = ObjectivesOf(field, member)
		if member.team == INVADERS then return o.bomb.pos end
		if member.role == AiWar.OPERATIVE and o.outpost then return o.outpost end
		if o.bomb.state == HOME then return o.hatch end
		return o.bomb.pos
	end,
	SIDES = { invader = "MvMInvaderSide", defender = "MvMDefenderSide", operative = "MvMOperativeSide" },
	SHORT_SIDES = { invader = "Invader", defender = "Defender", operative = "Operative" },
	Side = function(field, member)
		if member.team == INVADERS then return "invader" end
		if member.role == AiWar.OPERATIVE then return "operative" end
		return "defender"
	end,
	-- BLU meets RED coming from its base; RED meets the robots with the bomb
	Threat = function(field, member)
		if member.team == INVADERS then return field.bases[RED] end
		return ObjectivesOf(field, member).bomb.pos
	end,
	PatrolMark = function(field, member)
		return { state = ObjectivesOf(field, member).bomb.state }
	end,
	PatrolHolds = function(mark, field, member)
		if ObjectivesOf(field, member).bomb.state ~= mark.state then return false, "the bomb moved" end
		return true
	end,
}

-------------------------------------------------------------------------------
-- The scenario

Scenario = Base.Scenario:Extend(MODE)
Scenario.NEEDS = { Base.BASES, Base.BOMB }

function Scenario:New()
	local scenario = Base.Scenario.New(self)
	scenario.memory = { escorts = {} }
	return scenario
end

function Scenario:Reset()
	Base.Scenario.Reset(self)
	self.memory = { escorts = {} }
end

function Scenario:Command(war, field, now)
	self:Explore(field).explore:Survey(war:Members(), now)
	self:Brief(field, now)
	self:ChooseEscorts(field, war:Members())
	self:AttachMedic(war, field)
	self:Allocate(war, field, now)
end

-- TF2's medic robots go with the bomb's carrier: while a robot carries it,
-- BLU's medic nearest it joins its squad (the war's Attach), the same one
-- while it lives (memory.medic), and goes back to its own once nobody
-- carries the bomb.
function Scenario:AttachMedic(war, field)
	local o = field.objectives[INVADERS]
	local medic = self.memory.medic and war:Member(self.memory.medic)
	local carrier = o.carrying and war:Member(o.bomb.carrier)
	if not carrier then
		if medic then war:Detach(medic) end
		self.memory.medic = nil
		return
	end
	-- a medic that picked the bomb up itself carries it; another goes with it
	if medic == carrier then
		war:Detach(medic)
		medic = nil
	end
	if not medic then
		local nearest
		for _, member in ipairs(war:Members()) do
			if member ~= carrier and member.team == INVADERS and member.role == AiWar.MEDIC and member.pos and carrier.pos
				and (not nearest or Distance(member.pos, carrier.pos) < Distance(nearest.pos, carrier.pos)) then
				nearest = member
			end
		end
		medic = nearest
	end
	if not medic then
		self.memory.medic = nil
		return
	end
	war:Attach(medic, carrier)
	self.memory.medic = medic.handle
end

-- While a robot carries the bomb, BLU's escorts (objectives' escorts, handle
-- -> true), as features.aiwar.scenario.ctf's ChooseEscorts.
function Scenario:ChooseEscorts(field, members)
	local o = field.objectives[INVADERS]
	local before = self.memory.escorts
	local chosen = {}
	if o.carrying then
		local carrier, candidates = o.bomb.pos, {}
		for _, member in ipairs(members) do
			if member.team == INVADERS and member.role == AiWar.COURIER and member.pos and member.handle ~= o.bomb.carrier then
				local range = Distance(member.pos, carrier)
				if range <= (before[member.handle] and ESCORT_GIVE_UP or ESCORT_RANGE) then
					candidates[#candidates + 1] = { member = member, range = range, kept = before[member.handle] == true }
				end
			end
		end
		sort(candidates, function(a, b)
			if a.kept ~= b.kept then return a.kept end
			return a.range < b.range
		end)
		for i = 1, min(MAX_ESCORTS, #candidates) do chosen[candidates[i].member.handle] = true end
	end
	self.memory.escorts = chosen
	o.escorts = chosen
end

function Scenario:Brief(field, now)
	self:Explore(field)
	local bomb, hatch = field.flags[INVADERS], field.zones[INVADERS]
	self.memory.outpost = self.memory.outpost or Ctf.Outpost(field.waypoints or {}, hatch, bomb.home)
	local carrying = bomb.state == CARRIED and bomb.carrierTeam == INVADERS
	local objectives = {}
	for _, team in ipairs(TEAMS) do
		objectives[team] = {
			bomb = bomb,
			hatch = hatch,
			carrying = carrying,
			escorts = team == INVADERS and self.memory.escorts or nil,
			outpost = team ~= INVADERS and self.memory.outpost or nil,
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

-- BLU: every robot fetches (TF2 sends all but its medics, engineers, spies
-- and snipers' missions). RED: half on the hatch, half out at the outpost;
-- once the bomb moves, most on the bomb, at once while it is carried.
local STANCES = {
	invade = Stance({ { AiWar.COURIER, 10 } }),
	hold = Stance({ { AiWar.CTF_DEFEND, 5 }, { AiWar.OPERATIVE, 5 } }),
	hunt = Stance({ { AiWar.CTF_DEFEND, 8 }, { AiWar.OPERATIVE, 2 } }),
}

function Scenario:Stances(field, now)
	local bomb = field.objectives[RED].bomb
	local key = bomb.state == HOME and "hold" or "hunt"
	return {
		[INVADERS] = { stance = STANCES.invade, key = "invade" },
		[RED] = { stance = STANCES[key], key = key, critical = bomb.state == CARRIED },
	}, {}
end

-- TF2's waves outnumber its defenders: the war keeps both sides' total and
-- gives the invaders INVADER_SHARE of it.
INVADER_SHARE = 2 / 3

function Scenario:TeamSizes(size)
	local invaders = floor(size * 2 * INVADER_SHARE + 0.5)
	return { [INVADERS] = invaders, [RED] = size * 2 - invaders }
end

function Scenario:Front(field, team)
	local o = field.objectives[team]
	if team == INVADERS then return o.hatch end
	return o.bomb.pos
end

function Scenario:SetupAttacks(field) return {} end
