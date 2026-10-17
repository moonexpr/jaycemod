-- The control point scenario (foundation.aiwar.scenario): the war fought
-- over control points, symmetric and attack/defend alike, as TF2's bots
-- fight TF_GAMETYPE_CP. King of the Hill extends it
-- (foundation.aiwar.scenario.koth).
--
-- It reads what the capture HUD shows (field.points, docs/aiwar-koth-cp.md
-- §2.4): per point { id, rank, pos, zone = { center, radius } or nil, owner,
-- locked, capping, progress, blocked, mayCapture = team -> bool, inRound,
-- hidden }, rank-ordered; with field.bases (team -> its spawn's centroid),
-- field.timeLeft (the round's clock) and field.overtime.
--
-- Brief puts on the field, per team, its Objectives (TF2's
-- CollectCapturePoints and CollectDefendPoints, tf_gamerules.cpp):
--   attack     the points it may capture now (in round, zoned, shown)
--   defend     its own points the enemy may capture now
--   target     of attack, the one it is capping, else the nearest its base
--              (CTFBot::SelectPointToCapture)
--   staging    with nothing to attack: the locked point not its own nearest
--              its base, to wait by for the unlock
--   guard      of defend, a threatened one, else the one nearest the enemy
--   focus      target or staging, else guard: where chases are leashed and
--              lanes lead
--   threatened the guard is being capped, was contested within
--              CONTESTED_MEMORY, or a point was just lost
--   justLost   a point it owned became the enemy's within JUST_LOST_TIME
--   capping    it is capping its target
--   timeLeft   the round's clock (King of the Hill: the enemy's)
--   urgent     overtime, timeLeft under MUST_PUSH_TIME, or capping
-- with the point doctrine (DOCTRINE) and each team's defense share.
-- Stances follow the objectives: attack only, defend only, or a split by
-- the points held and the threat, mirroring foundation.aiwar's Stance.
local floor, max, min = math.floor, math.max, math.min
local ipairs = ipairs
local AiWar = require("foundation.aiwar")
local Orders = require("foundation.aiwar.orders")
local Tactics = require("foundation.aiwar.tactics")
local Teams = require("foundation.teams")
local Base = require("foundation.aiwar.scenario")
local Distance = require("foundation.geometry").Distance
module(...)

MODE = "control_points"

MUST_PUSH_TIME = 120 -- tf_bot_offense_must_push_time
NEAR_POINT = 750 -- tf_bot_near_point_travel_distance
CONTESTED_MEMORY = 5 -- the LastContestedAt window, tf_bot_defend_point.cpp
JUST_LOST_TIME = 15 -- m_justLostPointTimer's 10 to 20 s, tf_bot.cpp
CRITICAL_PROGRESS = 0.5 -- tf_bot_defend_owned_point_percent

-- The share of a team that both attacks and defends: even, plus POINT_LEAD
-- per in-round point the enemy holds more, DEFENSE_THREAT more while its
-- guard is threatened and less while it caps its target.
DEFENSE_EVEN, POINT_LEAD, DEFENSE_THREAT = 0.5, 0.1, 0.2

-- Goals: capturers spread over CAPTURE_SPREAD of the zone; a locked point
-- is waited for STAGE_DISTANCE outside its zone, STAGE_SPREAD round;
-- assault squads make for an ASSAULT_SPHERE round a point ASSAULT_STANDOFF
-- short of it; holders ring the guard HOLD_RING outside its zone; defenders
-- DEFEND_RING toward the enemy, DEFEND_SPREAD round; defending raiders
-- intercept RAID_INTERCEPT out toward the enemy.
CAPTURE_SPREAD, STAGE_DISTANCE, STAGE_SPREAD = 0.6, 400, 160
ASSAULT_STANDOFF, ASSAULT_SPHERE = 300, 700
HOLD_RING, DEFEND_RING, DEFEND_SPREAD, RAID_INTERCEPT = 160, 500, 200, 900
CAPTURE_ARRIVE, CAPTURE_LEASH = 48, 300
HOLD_ARRIVE, HOLD_LEASH = 72, 200

-- Guard posts keep to their side of the point (Posts.ScoreGuard's
-- PAST_POINT_LIMIT); King of the Hill guards all round.
GUARDS_ALL_ROUND = false

local RED, BLUE, NOBODY = Teams.RED, Teams.BLUE, Teams.UNASSIGNED
local TEAMS = { RED, BLUE }
local EnemyOf = Teams.EnemyOf

local function Center(point) return point.zone.center end

-- A point a team can fight over: in the round, with a capture area, and on
-- the HUD.
function Eligible(point)
	return point.inRound and point.zone ~= nil and not point.hidden
end

-- The first of points (rank order) nearest pos that passes keep, or nil.
local function Nearest(points, pos, keep)
	local best, bestRange
	for _, point in ipairs(points) do
		if not keep or keep(point) then
			local range = Distance(Center(point), pos)
			if not bestRange or range < bestRange then best, bestRange = point, range end
		end
	end
	return best
end

local function Contested(point)
	return point.blocked or (point.capping ~= point.owner and point.capping ~= NOBODY)
end

-------------------------------------------------------------------------------
-- The point doctrine (foundation.aiwar.orders' doctrine interface)

local function ObjectivesOf(field, member) return field.objectives[member.team] end

-- What a team attacks: its target, else where it stages.
local function Offense(o) return o.target or o.staging end

-- A capturer's spot: on the unlocked target, else outside the locked target
-- or staging point on its own side; nil with neither.
local function CaptureSpot(field, team, o, slot)
	local target = o.target
	if target and not target.locked then return Orders.Ring(Center(target), slot, target.zone.radius * CAPTURE_SPREAD) end
	local stage = Offense(o)
	if not stage then return nil end
	local outside = Tactics.Toward(Center(stage), field.bases[team], stage.zone.radius + STAGE_DISTANCE)
	return Orders.Ring(outside, slot, STAGE_SPREAD)
end

-- A holder's spot: on the guard while it is threatened or in setup, else
-- round it; nil without one.
local function HoldSpot(field, o, slot)
	local guard = o.guard
	if not guard then return nil end
	if o.threatened or field.setup then return Orders.Ring(Center(guard), slot, guard.zone.radius * CAPTURE_SPREAD) end
	return Orders.Ring(Center(guard), slot, guard.zone.radius + HOLD_RING)
end

local function AssaultSphere(field, team, o)
	local point = Offense(o)
	if not point then return nil end
	return Tactics.Toward(Center(point), field.bases[team], ASSAULT_STANDOFF), ASSAULT_SPHERE
end

local function AssaultSpot(field, member, o)
	local center, radius = AssaultSphere(field, member.team, o)
	if not center then return nil end
	return Orders.EntryPoint(center, radius, member.pos or center)
end

local function DefendSpot(field, member, o)
	local guard = o.guard
	if not guard then return nil end
	local gate = Orders.GateSpot(field, member, 0)
	if gate then return gate end
	local posts = field.posts and field.posts[member.team]
	if posts and posts[member.slot + 1] then return posts[member.slot + 1] end
	local ahead = Tactics.Toward(Center(guard), field.bases[EnemyOf(member.team)], DEFEND_RING)
	return Orders.Ring(ahead, member.slot, DEFEND_SPREAD)
end

-- The side a raider or support soldier works, "offense" or "defense" (nil
-- with neither): with both, its slot spread over its team's defense share
-- by the golden ratio, as payload's Focus.
local GOLDEN = 0.6180339887

local function PointFocus(field, member, o)
	if not Offense(o) then return o.guard and "defense" or nil end
	if not o.guard then return "offense" end
	return ((member.slot + 1) * GOLDEN) % 1 < field.defense[member.team] and "defense" or "offense"
end

-- A raider's enemy line and where its side comes from: on offense the
-- point it attacks, from its base; on defense its guard, from the enemy's.
local function RaidLine(field, member)
	local o = ObjectivesOf(field, member)
	local focus = PointFocus(field, member, o)
	if focus == "offense" then return Center(Offense(o)), field.bases[member.team] end
	if focus == "defense" then return Center(o.guard), field.bases[EnemyOf(member.team)] end
	return nil
end

local function SupportSpot(field, member)
	local gate = Orders.GateSpot(field, member, Orders.GATE_ROW * 2)
	if gate then return gate end
	local point = ObjectivesOf(field, member).focus
	if not point then return nil end
	local base = field.bases[member.team]
	local behind = Tactics.Toward(Center(point), base, point.zone.radius + Orders.SUPPORT_BEHIND)
	return Orders.Across(base, behind, Orders.Lateral(member.slot))
end

-- A team that attacks and guards nothing: in setup it waits behind its
-- gates, and comes out through them.
local function Attacks(o)
	return Offense(o) ~= nil and o.guard == nil
end

local ROLES = {
	[AiWar.CAPTURE] = {
		name = "CapturePoint",
		arrive = CAPTURE_ARRIVE,
		leash = CAPTURE_LEASH,
		rushes = false,
		Goal = function(field, member)
			local o = ObjectivesOf(field, member)
			return CaptureSpot(field, member.team, o, member.slot) or HoldSpot(field, o, member.slot)
		end,
		Zone = function(field, member)
			local target = ObjectivesOf(field, member).target
			if target and not target.locked then return Center(target), target.zone.radius end
			return nil
		end,
		-- TF2's CTFBotCapturePoint pushes when time is short, a friend caps,
		-- or it is near the point
		Urgent = function(field, member)
			local o = ObjectivesOf(field, member)
			if o.urgent then return true end
			return o.target ~= nil and member.pos ~= nil and Distance(member.pos, Center(o.target)) <= NEAR_POINT
		end,
	},
	[AiWar.ASSAULT] = {
		name = "Assault",
		chases = "opportunist",
		tactic = "attack",
		arrive = Orders.ESCORT_ARRIVE,
		leash = Orders.ESCORT_LEASH,
		rushes = false,
		Sphere = function(field, member) return AssaultSphere(field, member.team, ObjectivesOf(field, member)) end,
		Goal = function(field, member)
			local o = ObjectivesOf(field, member)
			return AssaultSpot(field, member, o) or DefendSpot(field, member, o)
		end,
	},
	-- TF2's CTFBotDefendPointBlockCapture: on the point until it is safe
	[AiWar.HOLD] = {
		name = "HoldPoint",
		arrive = HOLD_ARRIVE,
		leash = HOLD_LEASH,
		rushes = false,
		Goal = function(field, member)
			local o = ObjectivesOf(field, member)
			return HoldSpot(field, o, member.slot) or CaptureSpot(field, member.team, o, member.slot)
		end,
		Zone = function(field, member)
			local o = ObjectivesOf(field, member)
			if o.guard and (o.threatened or field.setup) then return Center(o.guard), o.guard.zone.radius end
			return nil
		end,
		Urgent = function(field, member) return ObjectivesOf(field, member).threatened end,
	},
	[AiWar.DEFEND] = {
		name = "DefendPoint",
		chases = "opportunist",
		patrols = true,
		tactic = "defend",
		arrive = Orders.DEFEND_ARRIVE,
		leash = Orders.DEFEND_LEASH,
		rushes = false,
		Goal = function(field, member)
			local o = ObjectivesOf(field, member)
			return DefendSpot(field, member, o) or AssaultSpot(field, member, o)
		end,
	},
	[AiWar.RAID] = {
		name = "Raid",
		chases = "opportunist",
		tactic = "raid",
		raids = true,
		arrive = Orders.RAID_ARRIVE,
		leash = Orders.RAID_LEASH,
		rushes = false,
		Line = RaidLine,
		Goal = function(field, member)
			local gate = Orders.GateSpot(field, member, 0)
			if gate then return gate end
			local line, from = RaidLine(field, member)
			if not line then return nil end
			return Tactics.FlankPoint(from, line, member.slot % 2 == 0 and 1 or -1)
		end,
		-- The line broken: on offense onto the point, on defense out toward
		-- the enemy to meet them.
		Cleared = function(field, member)
			local o = ObjectivesOf(field, member)
			local focus = PointFocus(field, member, o)
			if focus == "offense" then return CaptureSpot(field, member.team, o, member.slot + 8) end
			if focus == "defense" then return Tactics.Toward(Center(o.guard), field.bases[EnemyOf(member.team)], RAID_INTERCEPT) end
			return nil
		end,
	},
	[AiWar.SUPPORT] = {
		name = "Support",
		tactic = "support",
		arrive = Orders.SUPPORT_ARRIVE,
		leash = Orders.SUPPORT_LEASH,
		rushes = false,
		Goal = SupportSpot,
	},
	[AiWar.MEDIC] = {
		name = "Medic",
		heals = true,
		arrive = Orders.SUPPORT_ARRIVE,
		leash = Orders.SUPPORT_LEASH,
		rushes = false,
		Goal = SupportSpot,
	},
	-- every scenario's job (foundation.aiwar.orders)
	[AiWar.EXPLORE] = Orders.EXPLORE_ROLE,
}

DOCTRINE = {
	NAME = "points",
	ROLES = ROLES,
	WaitsForSetup = function(field, member)
		return field.setup == true and Attacks(ObjectivesOf(field, member))
	end,
	ChaseAnchor = function(field, member)
		local focus = ObjectivesOf(field, member).focus
		return focus and Center(focus)
	end,
	SIDES = { attack = "ControlPointAttacker", defend = "ControlPointDefender" },
	SHORT_SIDES = { attack = "CPAttacker", defend = "CPDefender" },
	-- capturers and assaulters attack, holders and defenders defend; the
	-- rest follow their focus (PointFocus)
	Side = function(field, member)
		local job = member.role
		if job == AiWar.CAPTURE or job == AiWar.ASSAULT then return "attack" end
		if job == AiWar.HOLD or job == AiWar.DEFEND then return "defend" end
		return PointFocus(field, member, ObjectivesOf(field, member)) == "offense" and "attack" or "defend"
	end,
	-- the point it fights for, as its chases' anchor
	Threat = function(field, member)
		local focus = ObjectivesOf(field, member).focus
		return focus and Center(focus)
	end,
	PatrolMark = function(field, member)
		local guard = ObjectivesOf(field, member).guard
		return { guard = guard and guard.id }
	end,
	PatrolHolds = function(mark, field, member)
		local o = ObjectivesOf(field, member)
		if (o.guard and o.guard.id) ~= mark.guard then return false, "the guard moved" end
		if o.threatened then return false, "the point is threatened" end
		return true
	end,
}

-------------------------------------------------------------------------------
-- The scenario

Scenario = Base.Scenario:Extend(MODE)
Scenario.GUARDS_ALL_ROUND = GUARDS_ALL_ROUND
-- Its Brief reads the points and both teams' bases.
Scenario.NEEDS = { Base.BASES, Base.POINTS }

-- What the scenario remembers of the round: per point id when it was last
-- contested and who owned it; per team when it last lost a point.
local function Memory()
	return {
		contestedAt = {},
		owner = {},
		lostAt = {},
	}
end

function Scenario:New()
	local scenario = Base.Scenario.New(self)
	scenario.memory = Memory()
	return scenario
end

-- A new round: its owners are no loss, its old contests no threat.
function Scenario:Reset()
	Base.Scenario.Reset(self)
	self.memory = Memory()
end

function Scenario:Remember(points, now)
	local memory = self.memory
	for _, point in ipairs(points) do
		if Contested(point) then memory.contestedAt[point.id] = now end
		local was = memory.owner[point.id]
		if was ~= nil and EnemyOf(was) == point.owner then memory.lostAt[was] = now end
		memory.owner[point.id] = point.owner
	end
end

-- The parts of a team's objectives a variant may override.

function Scenario:Attack(field, team)
	local list = {}
	for _, point in ipairs(field.points) do
		if Eligible(point) and point.mayCapture[team] then list[#list + 1] = point end
	end
	return list
end

function Scenario:Defend(field, team)
	local enemy = EnemyOf(team)
	local list = {}
	for _, point in ipairs(field.points) do
		if Eligible(point) and point.owner == team and point.mayCapture[enemy] then list[#list + 1] = point end
	end
	return list
end

function Scenario:Staging(field, team, attack)
	if #attack > 0 then return nil end
	return Nearest(field.points, field.bases[team], function(point)
		return Eligible(point) and point.locked and point.owner ~= team
	end)
end

function Scenario:TimeLeft(field, team)
	return field.timeLeft
end

function Scenario:Threatened(point, team, now)
	local at = self.memory.contestedAt[point.id]
	return point.capping == EnemyOf(team) or (at ~= nil and now - at < CONTESTED_MEMORY)
end

function Scenario:Objectives(field, team, now)
	local enemy = EnemyOf(team)
	local attack, defend = self:Attack(field, team), self:Defend(field, team)
	local target = Nearest(attack, field.bases[team], function(point) return point.capping == team end)
		or Nearest(attack, field.bases[team])
	local staging = self:Staging(field, team, attack)
	local guard = Nearest(defend, field.bases[enemy], function(point) return self:Threatened(point, team, now) end)
		or Nearest(defend, field.bases[enemy])
	local lostAt = self.memory.lostAt[team]
	local justLost = lostAt ~= nil and now - lostAt < JUST_LOST_TIME
	local capping = target ~= nil and target.capping == team
	local timeLeft = self:TimeLeft(field, team)
	return {
		attack = attack,
		defend = defend,
		target = target,
		staging = staging,
		guard = guard,
		focus = target or staging or guard,
		threatened = guard ~= nil and (justLost or self:Threatened(guard, team, now)),
		justLost = justLost,
		capping = capping,
		timeLeft = timeLeft,
		urgent = field.overtime == true or (timeLeft ~= nil and timeLeft < MUST_PUSH_TIME) or capping,
	}
end

function Scenario:Brief(field, now)
	-- explore is every doctrine's job: its board on the field
	self:Explore(field)
	self:Remember(field.points, now)
	local objectives = {}
	for _, team in ipairs(TEAMS) do objectives[team] = self:Objectives(field, team, now) end
	field.doctrine = DOCTRINE
	field.objectives = objectives
	local _, defense = self:Stances(field, now)
	field.defense = defense
end

-- Stances ---------------------------------------------------------------------

-- Per tenth of offense, capturers and assault 4:3; per tenth of defense,
-- defenders and holders 5:2, or 2:5 while the guard is threatened or a
-- point was just lost; raiders and support as two and one tenths of the
-- whole.
local CAPTURE_W, ASSAULT_W = 4, 3
local DEFEND_W, HOLD_W = 5, 2
local RAID_W, SUPPORT_W = 20, 10

local function Owned(points, team)
	local n = 0
	for _, point in ipairs(points) do
		if point.inRound and point.owner == team then n = n + 1 end
	end
	return n
end

-- The team's defense share in tenths, or nil with nothing to attack, stage
-- for or defend.
function Scenario:DefenseTenths(field, team, o)
	local offense, defense = #o.attack > 0 or o.staging ~= nil, #o.defend > 0
	if not offense and not defense then return nil end
	if not defense then return 0 end
	if not offense then return 10 end
	local lead = Owned(field.points, EnemyOf(team)) - Owned(field.points, team)
	local share = DEFENSE_EVEN + POINT_LEAD * lead
	if o.threatened then share = share + DEFENSE_THREAT end
	if o.capping then share = share - DEFENSE_THREAT end
	share = min(AiWar.DEFENSE_MAX, max(AiWar.DEFENSE_MIN, share))
	return floor(share * 10 + 0.5)
end

local stances = {} -- key -> stance: the same situation, the same table

local function Stance(tenths, hot)
	local key = tenths .. (hot and "t" or "")
	if stances[key] then return stances[key], key end
	local offense, defense = 10 - tenths, tenths
	local defendW, holdW = DEFEND_W, HOLD_W
	if hot then defendW, holdW = HOLD_W, DEFEND_W end
	local work = {
		offense = {
			{
				role = AiWar.CAPTURE,
				weight = offense * CAPTURE_W,
			},
			{
				role = AiWar.ASSAULT,
				weight = offense * ASSAULT_W,
			},
		},
		defense = {
			{
				role = hot and AiWar.HOLD or AiWar.DEFEND,
				weight = defense * (hot and holdW or defendW),
			},
			{
				role = hot and AiWar.DEFEND or AiWar.HOLD,
				weight = defense * (hot and defendW or holdW),
			},
		},
	}
	local order = tenths >= 5 and { "defense", "offense" } or { "offense", "defense" }
	local stance = {}
	for _, side in ipairs(order) do
		for _, share in ipairs(work[side]) do
			if share.weight > 0 then stance[#stance + 1] = share end
		end
	end
	stance[#stance + 1] = {
		role = AiWar.RAID,
		weight = RAID_W,
	}
	stance[#stance + 1] = {
		role = AiWar.SUPPORT,
		weight = SUPPORT_W,
	}
	stances[key] = stance
	return stance, key
end

function Scenario:Stances(field, now)
	local entries, defense = {}, {}
	for _, team in ipairs(TEAMS) do
		local o = field.objectives[team]
		local tenths = self:DefenseTenths(field, team, o)
		if tenths then
			local stance, key = Stance(tenths, tenths > 0 and (o.threatened or o.justLost))
			entries[team] = {
				stance = stance,
				key = key,
				critical = o.justLost or (o.threatened and o.guard.progress >= CRITICAL_PROGRESS),
			}
			defense[team] = tenths / 10
		end
	end
	return entries, defense
end

-- The team's lanes lead to its focus.
function Scenario:Front(field, team)
	local focus = field.objectives[team].focus
	return focus and Center(focus)
end

-- The teams that only attack come out through setup gates toward the point
-- they attack.
function Scenario:SetupAttacks(field)
	local attacks = {}
	for _, team in ipairs(TEAMS) do
		local o = field.objectives[team]
		if Attacks(o) then attacks[team] = Center(Offense(o)) end
	end
	return attacks
end
