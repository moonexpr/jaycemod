-- The capture the flag scenario (features.aiwar.scenario): the war fought
-- over each team's intelligence, as TF2's bots fight TF_GAMETYPE_CTF
-- (CTFBotFetchFlag, CTFBotDeliverFlag, CTFBotEscortFlagCarrier,
-- CTFBotDefendFlag), with a third job of Sandcastle's own.
--
-- It reads, per team, its flag (field.flags[team]: { team, home, state
-- (HOME, CARRIED, DROPPED), pos (where it is now: home, dropped, or its
-- carrier's), carrier (the carrier's handle) or nil, carrierTeam }) and
-- where its carriers capture (field.zones[team]: a pos), with field.bases
-- and field.waypoints (the nav mesh's sampled area centres), and each
-- team's captures this round (field.captures) against the limit
-- (field.caplimit, 0 for none).
--
-- Its jobs (DOCTRINE):
--   CTFCourier    fetches the enemy's flag where it lies, fighting on the
--                 way but chasing nobody, and rushes it once near; carrying
--                 it, runs it to its team's zone and stops for nothing;
--                 while a teammate carries it, escorts the carrier if near
--                 and not one too many, else attacks the enemy's defenders.
-- Whoever picks up the enemy's flag, whatever its job, delivers it.
--   CTFDefender   guards its own flag round its home, or where it was
--                 dropped; while the enemy carries it, runs the carrier
--                 down.
--   CTFOperative  holds a remote base (its team's outpost) out on the way
--                 the enemy's carrier would run home, widening the
--                 defenders' reach; with no outpost found, defends.
-- Brief puts on the field, per team, its objectives: own, its flag; enemy,
-- the enemy's; zone, where it captures; stolen, its flag carried by the
-- enemy; carrying, the enemy's flag carried by one of its own; outpost.
local abs, ceil, ipairs, min, pairs, sort = math.abs, math.ceil, ipairs, math.min, pairs, table.sort
local AiWar = require("features.aiwar.model")
local Orders = require("features.aiwar.orders")
local Teams = gameplay.teams
local Base = require("features.aiwar.scenario")
local Geometry = math.geometry
local Distance = Geometry.Distance
module(...)

MODE = "ctf"

-- The flag's states (the flag feature's item_teamflag).
HOME, CARRIED, DROPPED = "home", "carried", "dropped"

-- A courier must touch the flag (item_teamflag's trigger): it arrives
-- within TOUCH. Defenders stand GUARD_RING round their flag, escorts
-- ESCORT_RING round their carrier.
TOUCH = 24
-- tf_bot_near_point_travel_distance: a courier this near the flag rushes it.
FETCH_RUSH = 750
GUARD_RING, ESCORT_RING = 220, 200
-- The outpost: a waypoint OUTPOST_MIN to OUTPOST_MAX out from the team's
-- flag, the nearest the way the enemy's carrier would run (the flag to the
-- enemy's zone), then the nearest OUTPOST_IDEAL out; held within
-- OUTPOST_RADIUS.
OUTPOST_MIN, OUTPOST_MAX, OUTPOST_IDEAL = 600, 1600, 1000
OUTPOST_RADIUS = 300
COURIER_LEASH, DEFENDER_LEASH, OPERATIVE_LEASH = 400, 700, 600
-- tf_bot_flag_escort_range, tf_bot_flag_escort_give_up_range,
-- tf_bot_flag_escort_max_count: while a teammate carries the flag, a courier
-- within ESCORT_RANGE of it escorts it, at most MAX_ESCORTS a team, until it
-- falls ESCORT_GIVE_UP behind; an escort walks on once ESCORT_FOLLOW from
-- the carrier (CTFBotEscortFlagCarrier's half the escort range).
ESCORT_RANGE, ESCORT_GIVE_UP, MAX_ESCORTS = 500, 1000, 4
ESCORT_FOLLOW = ESCORT_RANGE / 2

local RED, BLUE = Teams.RED, Teams.BLUE
local TEAMS = { RED, BLUE }
local EnemyOf = Teams.EnemyOf

local function ObjectivesOf(field, member) return field.objectives[member.team] end

-- The distance from p to the segment a-b.
local function ToSegment(p, a, b)
	return Distance(p, Geometry.ClosestOnSegment(p, a, b))
end

-- The team's outpost from waypoints, or nil with none in reach.
function Outpost(waypoints, home, enemyZone)
	local best, bestOff, bestIdeal
	for _, p in ipairs(waypoints) do
		local out = Distance(p, home)
		if out >= OUTPOST_MIN and out <= OUTPOST_MAX then
			local off, ideal = ToSegment(p, home, enemyZone), abs(out - OUTPOST_IDEAL)
			if not best or off < bestOff or (off == bestOff and ideal < bestIdeal) then
				best, bestOff, bestIdeal = p, off, ideal
			end
		end
	end
	return best
end

-------------------------------------------------------------------------------
-- The CTF doctrine (features.aiwar.orders' doctrine interface)

local function Carries(o, member) return o.carrying and o.enemy.carrier == member.handle end

-- A courier rushes while it carries the flag, or while the flag lies
-- within FETCH_RUSH of it (CTFBotCapturePoint's near-point push).
local function Rushes(o, member)
	if Carries(o, member) then return true end
	return not o.carrying and member.pos ~= nil and Distance(member.pos, o.enemy.pos) <= FETCH_RUSH
end

local function GuardSpot(o, slot)
	return Orders.Ring(o.own.pos, slot, GUARD_RING)
end

local function CourierGoal(field, member)
	local o = ObjectivesOf(field, member)
	if Carries(o, member) then return o.zone end
	if o.carrying then return Orders.Ring(o.enemy.pos, member.slot, ESCORT_RING) end
	return o.enemy.pos
end

local function Escorts(o, member) return o.escorts ~= nil and o.escorts[member.handle] == true end

local function DefenderGoal(field, member)
	local o = ObjectivesOf(field, member)
	if o.stolen then return o.own.pos end
	return GuardSpot(o, member.slot)
end

-- Each job's stages, its actions under its side's (ScenarioMonitor >
-- CaptureFlagCourier > RetrieveFlag): TF2's FetchFlag, DeliverFlag and
-- EscortFlagCarrier (bot/behavior/scenario/capture_the_flag) for the
-- courier; the defender's and operative's are Sandcastle's own.
local function CourierStage(field, member)
	local o = ObjectivesOf(field, member)
	if Carries(o, member) then return "ReturnHome" end
	if o.carrying then return Escorts(o, member) and "EscortFlagCarrier" or "AttackFlagDefenders" end
	return "RetrieveFlag"
end

-- TF2's scenario monitor: whoever picks up the flag runs it in. Every job
-- is ReturnHome while it carries the enemy's flag, else its own stage.
local function Delivering(stage)
	return function(field, member)
		if Carries(ObjectivesOf(field, member), member) then return "ReturnHome" end
		return stage and stage(field, member)
	end
end

-- The stages that override a job's settings: delivering the flag, stepping
-- into the team's zone and stopping for nothing, whatever the job; escorting
-- it, walking on once ESCORT_FOLLOW behind the carrier; attacking the
-- defenders round the enemy's flag stand (CTFBotAttackFlagDefenders).
local DELIVER = {
	arrive = TOUCH,
	leash = COURIER_LEASH,
	tactic = "attack",
	chases = false,
	patrols = false,
	heals = false,
	squads = false,
	Zone = false,
	Goal = function(field, member) return ObjectivesOf(field, member).zone end,
	Urgent = function() return true end,
}
local ESCORT = {
	arrive = ESCORT_FOLLOW,
	Goal = function(field, member) return ObjectivesOf(field, member).enemy.pos end,
}
local ATTACK_DEFENDERS = {
	chases = "opportunist",
	arrive = Orders.DEFEND_ARRIVE,
	leash = DEFENDER_LEASH,
	Goal = function(field, member) return Orders.Ring(ObjectivesOf(field, member).enemy.home, member.slot, GUARD_RING) end,
}

local function DefenderStage(field, member)
	local o = ObjectivesOf(field, member)
	if o.stolen then return "ChaseCarrier" end
	if o.own.state == DROPPED then return "GuardDroppedFlag" end
	return "GuardFlag"
end

local function OperativeStage(field, member)
	local outpost = ObjectivesOf(field, member).outpost
	if not outpost then return "GuardFlag" end
	if member.pos and Distance(member.pos, outpost) <= OUTPOST_RADIUS then return "HoldOutpost" end
	return "EstablishOutpost"
end

local ROLES = {
	-- CTFBotFetchFlag: fights on the way but chases nobody
	[AiWar.COURIER] = {
		name = "CTFCourier",
		tactic = "attack",
		arrive = TOUCH,
		leash = COURIER_LEASH,
		rushes = false,
		Goal = CourierGoal,
		Stage = CourierStage,
		STAGES = { ReturnHome = DELIVER, EscortFlagCarrier = ESCORT, AttackFlagDefenders = ATTACK_DEFENDERS },
		Urgent = function(field, member) return Rushes(ObjectivesOf(field, member), member) end,
	},
	[AiWar.CTF_DEFEND] = {
		name = "CTFDefender",
		chases = "opportunist",
		patrols = true,
		tactic = "defend",
		arrive = Orders.DEFEND_ARRIVE,
		leash = DEFENDER_LEASH,
		rushes = false,
		Goal = DefenderGoal,
		Stage = Delivering(DefenderStage),
		STAGES = { ReturnHome = DELIVER },
		Urgent = function(field, member) return ObjectivesOf(field, member).stolen end,
	},
	[AiWar.OPERATIVE] = {
		name = "CTFOperative",
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
		Stage = Delivering(OperativeStage),
		STAGES = { ReturnHome = DELIVER },
		Zone = function(field, member)
			local outpost = ObjectivesOf(field, member).outpost
			if not outpost then return nil end
			return outpost, OUTPOST_RADIUS
		end,
	},
	[AiWar.MEDIC] = {
		name = "Medic",
		heals = true,
		arrive = Orders.SUPPORT_ARRIVE,
		leash = Orders.SUPPORT_LEASH,
		rushes = false,
		Goal = DefenderGoal,
		Stage = Delivering(nil),
		STAGES = { ReturnHome = DELIVER },
	},
}
-- every scenario's job (features.aiwar.orders), delivering the flag too
do
	local explore = {}
	for k, v in pairs(Orders.EXPLORE_ROLE) do explore[k] = v end
	explore.Stage, explore.STAGES = Delivering(nil), { ReturnHome = DELIVER }
	ROLES[AiWar.EXPLORE] = explore
end

DOCTRINE = {
	NAME = "ctf",
	ROLES = ROLES,
	WaitsForSetup = function(field, member)
		return field.setup == true and member.role == AiWar.COURIER
	end,
	-- couriers chase about the enemy's flag, the rest about their own or
	-- their outpost
	ChaseAnchor = function(field, member)
		local o = ObjectivesOf(field, member)
		if member.role == AiWar.COURIER then return o.enemy.pos end
		if member.role == AiWar.OPERATIVE and o.outpost then return o.outpost end
		return o.own.pos
	end,
	-- each job its own side action; medics (and explorers) the defenders';
	-- whoever carries the enemy's flag the couriers'
	SIDES = { courier = "CaptureFlagCourier", defender = "CaptureFlagDefender", operative = "CaptureFlagOperative" },
	SHORT_SIDES = { courier = "CTFCourier", defender = "CTFDefender", operative = "CTFOperative" },
	Side = function(field, member)
		if member.role == AiWar.COURIER or Carries(ObjectivesOf(field, member), member) then return "courier" end
		if member.role == AiWar.OPERATIVE then return "operative" end
		return "defender"
	end,
	-- the enemy comes from its base
	Threat = function(field, member)
		return field.bases[EnemyOf(member.team)]
	end,
	PatrolMark = function(field, member)
		return { state = ObjectivesOf(field, member).own.state }
	end,
	PatrolHolds = function(mark, field, member)
		local own = ObjectivesOf(field, member).own
		if own.state ~= mark.state then return false, "the flag moved" end
		return true
	end,
}

-------------------------------------------------------------------------------
-- The scenario

Scenario = Base.Scenario:Extend(MODE)
-- Its Brief reads both teams' bases and flags.
Scenario.NEEDS = { Base.BASES, Base.FLAGS }

-- What it remembers of the round: each team's outpost and escorts.
function Scenario:New()
	local scenario = Base.Scenario.New(self)
	scenario.memory = { outposts = {}, escorts = {} }
	return scenario
end

function Scenario:Reset()
	Base.Scenario.Reset(self)
	self.memory = { outposts = {}, escorts = {} }
end

-- Briefed, each team carrying the enemy's flag picks its escorts from its
-- members (ChooseEscorts), then the stances are allocated.
function Scenario:Command(war, field, now)
	self:Explore(field).explore:Survey(war:Members(), now)
	self:Brief(field, now)
	self:ChooseEscorts(field, war:Members())
	self:Allocate(war, field, now)
end

-- Each team carrying the enemy's flag: its escorts (objectives' escorts,
-- handle -> true), the couriers that escorted it still within
-- ESCORT_GIVE_UP of the carrier, then the nearest others within
-- ESCORT_RANGE, MAX_ESCORTS in all.
function Scenario:ChooseEscorts(field, members)
	for _, team in ipairs(TEAMS) do
		local o = field.objectives[team]
		local before = self.memory.escorts[team] or {}
		local chosen = {}
		if o.carrying then
			local carrier, candidates = o.enemy.pos, {}
			for _, member in ipairs(members) do
				if member.team == team and member.role == AiWar.COURIER and member.pos and member.handle ~= o.enemy.carrier then
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
		self.memory.escorts[team] = chosen
		o.escorts = chosen
	end
end

function Scenario:Objectives(field, team)
	local enemy = EnemyOf(team)
	local own, theirs = field.flags[team], field.flags[enemy]
	local outposts = self.memory.outposts
	outposts[team] = outposts[team] or Outpost(field.waypoints or {}, own.home, field.zones[enemy])
	return {
		own = own,
		enemy = theirs,
		zone = field.zones[team],
		stolen = own.state == CARRIED and own.carrierTeam == enemy,
		carrying = theirs.state == CARRIED and theirs.carrierTeam == team,
		outpost = outposts[team],
	}
end

function Scenario:Brief(field, now)
	-- explore is every doctrine's job: its board on the field
	self:Explore(field)
	local objectives = {}
	for _, team in ipairs(TEAMS) do objectives[team] = self:Objectives(field, team) end
	field.doctrine = DOCTRINE
	field.objectives = objectives
end

-- Stances: couriers lead, to keep the round's start lively; defenders join
-- only mid-game, once the round's captures, both teams' together, reach
-- two thirds of the capture limit (field.captures, field.caplimit: 2 of 3,
-- one each or two by either; 4 of 5), TF2's default limit standing in for
-- none. Early, couriers and operatives 7:3, or 6:4 while
-- the enemy carries the team's flag (the operatives intercepting);
-- mid-game couriers, operatives and defenders 6:2:2, or 4:2:4 while it is
-- carried, at once.
DEFAULT_CAPLIMIT = 3 -- tf_flag_caplimit's
local MIDGAME_SHARE = 2 / 3

function MidGameAt(caplimit)
	if caplimit <= 0 then caplimit = DEFAULT_CAPLIMIT end
	return ceil(caplimit * MIDGAME_SHARE - 1e-9)
end

function MidGame(captures, caplimit)
	local at = MidGameAt(caplimit)
	return captures[RED] + captures[BLUE] >= at
end

local function Stance(shares)
	local stance = {}
	for _, share in ipairs(shares) do stance[#stance + 1] = { role = share[1], weight = share[2] } end
	return stance
end

local STANCES = {
	early = Stance({ { AiWar.COURIER, 7 }, { AiWar.OPERATIVE, 3 } }),
	early_stolen = Stance({ { AiWar.COURIER, 6 }, { AiWar.OPERATIVE, 4 } }),
	mid = Stance({ { AiWar.COURIER, 6 }, { AiWar.OPERATIVE, 2 }, { AiWar.CTF_DEFEND, 2 } }),
	mid_stolen = Stance({ { AiWar.COURIER, 4 }, { AiWar.CTF_DEFEND, 4 }, { AiWar.OPERATIVE, 2 } }),
}

function Scenario:Stances(field, now)
	local phase = MidGame(field.captures, field.caplimit) and "mid" or "early"
	local entries = {}
	for _, team in ipairs(TEAMS) do
		local stolen = field.objectives[team].stolen
		local key = phase .. (stolen and "_stolen" or "")
		entries[team] = {
			stance = STANCES[key],
			key = key,
			critical = stolen and phase == "mid",
		}
	end
	return entries, {}
end

-- A team's lanes lead to the enemy's flag.
function Scenario:Front(field, team)
	return field.objectives[team].enemy.pos
end

-- No team comes out through setup gates for the flag.
function Scenario:SetupAttacks(field) return {} end
