-- The orders of an AI war soldier: an NPC variant (foundation.npc) whose
-- Actions run over the soldier port (foundation.aiwar.soldier). The engine's
-- own AI does the fighting; the orders decide where a soldier should be and
-- walk it there over the nav mesh, since TF2 maps have no AI node graph for
-- the engine's pathfinder.
--
-- Each role is a strategy: Goal(field, member) -> a position or nil, how
-- close counts as there (arrive), how far from its goal it may fight
-- (leash), and whether it ignores enemies on the way (rushes: cart pushers
-- and blockers, who must stand on the cart to count).
--
--   SoldierBehavior        ends when the soldier dies
--     Push/Escort/Block/Defend/Idle   the objective of the member's role:
--                          hold or fight near the goal (pushers and
--                          blockers keep to their spot as the cart moves),
--                          else SuspendFor
--       Travel             run straight at the goal while nothing is in the
--                          way, following it as it moves; otherwise follow a
--                          Lua route, re-routing as the goal moves or when
--                          the soldier stops moving
--
-- For the war report, a soldier's state shows its goal, route and waypoint
-- (goal, route, routeIndex) and how its last trip ended (trip).
local ceil, cos, floor, min, sin, sqrt = math.ceil, math.cos, math.floor, math.min, math.sin, math.sqrt
local pairs = pairs
local N = require("foundation.npc")
local AiWar = require("foundation.aiwar")
local Track = require("foundation.aiwar.track")
module(...)

KIND = "aiwar"

-- Goals
PUSH_RING = 56 -- just outside a cart's body, inside its capture area
PUSH_ARRIVE, PUSH_LEASH = 72, 110
ESCORT_LEAD = 300
ESCORT_ARRIVE, ESCORT_LEASH = 150, 700
DEFEND_LEAD, DEFEND_DEPTH, DEFEND_ROWS = 600, 250, 3
DEFEND_ARRIVE, DEFEND_LEASH = 150, 900
LATERAL, LATERAL_STEPS = 80, 2
-- In setup the defending side lines up past each gate the attackers must
-- come through (field.gates: { pos, dir } with dir the way attackers pass
-- it): defenders GATE_STANDOFF past it, blockers a row behind, spaced
-- GATE_SPACING along the line from its middle out.
GATE_STANDOFF, GATE_ROW, GATE_SPACING = 256, 96, 64
local GOLDEN_ANGLE = 2.39996323 -- radians: ring slots never line up

-- A pusher or blocker at its cart runs to its spot again once the cart
-- has carried the spot this far away.
STATION = 36

-- Travel
WAYPOINT_RADIUS = 48
LOOKAHEAD = 3 -- waypoints past the current one tested for a straight walk
REPATH_INTERVAL, REPATH_DISTANCE = 2, 150
-- Stuck: moved less than STUCK_PROGRESS in STUCK_TIME while running.
STUCK_TIME, STUCK_PROGRESS = 3, 24
MAX_REPATHS = 2
CHASE_BACKOFF = 3 -- after a straight run got stuck, routes only for this long
-- A stuck soldier first steps this far aside, for this long, in a direction
-- that turns with each attempt and differs between soldiers: most are held
-- by a corner, a door frame or someone in the way, not by the route.
SIDESTEP_DISTANCE, SIDESTEP_TIME = 96, 1.5
-- Last resort, when every step aside and new route has failed: a hop of
-- up to this far toward the waypoint, where a player could walk (a brush
-- only NPCs collide with, a lip their step cannot take).
HOP_DISTANCE = 160
-- A soldier stuck on a waypoint this much above its feet is climbing
-- (stairs players take on a smooth clip ramp and NPCs on the steps), and
-- hops at once rather than stepping aside first.
CLIMB_RISE = 12
-- A soldier stuck against a solid entity (a cart, a prop) walks to a point
-- beside it, for up to this long, then goes on along its route.
DETOUR_TIME = 3

-- In setup the attackers cannot push their cart (TF2 lets no point be
-- captured) and the gates are shut, so they wander the ground behind the
-- gates: to a spot (the soldier port's WanderSpot), which may be rooms
-- away, travelling there as to any goal, resting WANDER_REST there,
-- giving a spot up after WANDER_GIVE_UP; when setup ends they go to work.
WANDER_ARRIVE, WANDER_REST, WANDER_GIVE_UP = 48, 3, 20
RETRY_WAIT = 1 -- after a failed trip, before the next

local Distance = Track.Distance

-- Slot 0 on the line, then alternately left and right, out to LATERAL_STEPS.
local function Lateral(k)
	if k == 0 then return 0 end
	local magnitude = min(ceil(k / 2), LATERAL_STEPS) * LATERAL
	return k % 2 == 1 and magnitude or -magnitude
end

local function Ring(pos, slot, radius)
	local angle = slot * GOLDEN_ANGLE
	return { x = pos.x + cos(angle) * radius, y = pos.y + sin(angle) * radius, z = pos.z }
end

-- 0 in the middle, then alternately left and right, one spacing further
-- out each pair.
local function AlongLine(k)
	if k == 0 then return 0 end
	local magnitude = ceil(k / 2) * GATE_SPACING
	return k % 2 == 1 and magnitude or -magnitude
end

-- The member's spot in the setup line, or nil when there is no setup
-- line to stand in (not in setup, or no gate found).
local function GateSpot(field, member, row)
	local gates = field.setup and field.gates and field.gates[AiWar.EnemyOf(member.team)]
	if not gates or #gates == 0 then return nil end
	local gate = gates[member.slot % #gates + 1]
	local lateral = AlongLine(floor(member.slot / #gates))
	local depth = GATE_STANDOFF + row
	local dir, pos = gate.dir, gate.pos
	return { x = pos.x + dir.x * depth - dir.y * lateral, y = pos.y + dir.y * depth + dir.x * lateral, z = pos.z }
end

local function OwnCart(field, member) return field.carts[member.team] end
local function EnemyCart(field, member) return field.carts[AiWar.EnemyOf(member.team)] end

ROLES = {
	[AiWar.PUSH] = {
		name = "Push",
		arrive = PUSH_ARRIVE,
		leash = PUSH_LEASH,
		rushes = true,
		Goal = function(field, member)
			local cart = OwnCart(field, member)
			return cart and Ring(cart.pos, member.slot, PUSH_RING)
		end,
	},
	[AiWar.BLOCK] = {
		name = "Block",
		arrive = PUSH_ARRIVE,
		leash = PUSH_LEASH,
		rushes = true,
		Goal = function(field, member)
			local spot = GateSpot(field, member, GATE_ROW)
			if spot then return spot end
			local cart = EnemyCart(field, member)
			return cart and Ring(cart.pos, member.slot, PUSH_RING)
		end,
	},
	-- An escort establishes its line at a post pushed ahead of its cart
	-- (field.forwardPosts), else leads the cart along the track.
	[AiWar.ESCORT] = {
		name = "Escort",
		arrive = ESCORT_ARRIVE,
		leash = ESCORT_LEASH,
		rushes = false,
		Goal = function(field, member)
			local posts = field.forwardPosts and field.forwardPosts[member.team]
			if posts and posts[member.slot + 1] then return posts[member.slot + 1] end
			local cart = OwnCart(field, member)
			return cart and cart.track:Offset(cart.distance + ESCORT_LEAD, Lateral(member.slot))
		end,
	},
	-- EstablishLine: a post found for the defenders (field.posts, from
	-- foundation.aiwar.posts: high or low ground, hiding spots, watching
	-- the checkpoint the attackers head for), where it waits for them.
	[AiWar.DEFEND] = {
		name = "EstablishLine",
		arrive = DEFEND_ARRIVE,
		leash = DEFEND_LEASH,
		rushes = false,
		Goal = function(field, member)
			local spot = GateSpot(field, member, 0)
			if spot then return spot end
			local posts = field.posts and field.posts[member.team]
			if posts and posts[member.slot + 1] then return posts[member.slot + 1] end
			local cart = EnemyCart(field, member)
			if not cart then return nil end
			local row, column = member.slot % DEFEND_ROWS, floor(member.slot / DEFEND_ROWS)
			return cart.track:Offset(cart.distance + DEFEND_LEAD + row * DEFEND_DEPTH, Lateral(column))
		end,
	},
}

-- The member's goal on the field, or nil (no role, or no cart for it).
function Goal(field, member)
	local role = ROLES[member.role]
	return role and role.Goal(field, member)
end

local function OrdersRun(field)
	return field ~= nil and field.phase.orders
end

-- An attacker (a team with a cart the other side lacks) in setup.
local function WaitingForSetup(field, member)
	return field.setup == true and field.carts[member.team] ~= nil and field.carts[AiWar.EnemyOf(member.team)] == nil
end

-------------------------------------------------------------------------------
-- Travel: follow a route to the role's goal, or (in setup) to a wander spot

local Travel = N.Action:Extend("Travel")

-- A wander spot is travelled to as a role's goal is, with WANDER's terms.
local WANDER = { name = "Wander", arrive = WANDER_ARRIVE, leash = 0, rushes = false }

-- spot: a wander spot to go to instead of the role's goal.
function Travel:Init(state, role, spot)
	self.state = state
	self.role = role
	self.spot = spot
	self.repaths = 0
	self.failed = false
	self.requested = false
	self.chaseBlockedUntil = 0
end

function Travel:OnStart(me)
	if self.spot then self.giveUpAt = me:Now() + WANDER_GIVE_UP end
	self:SetRoute(nil)
	self:ResetProgress(me)
	return self:Continue()
end

function Travel:SetRoute(route)
	self.route = route
	self.index = 1
	self.state.route = route
	self.state.routeIndex = 1
end

function Travel:Plan(me, goal)
	self.goal = goal
	self.plannedAt = me:Now()
	self.requested = true
	self:SetRoute(nil)
	me:RequestRoute(goal)
end

function Travel:End(reason)
	self.state.trip = reason
	return self:Done(reason)
end

function Travel:Fail(reason)
	self.failed = true
	return self:End(reason)
end

-- Stuck is judged by the soldier's own movement, so a soldier running
-- after a goal that moves away as fast is not stuck.
function Travel:ResetProgress(me)
	self.anchor = me:Position()
	self.progressAt = me:Now()
end

function Travel:IsStuck(me)
	if Distance(me:Position(), self.anchor) > STUCK_PROGRESS then self:ResetProgress(me) end
	return me:Now() - self.progressAt > STUCK_TIME
end

-- A hop of up to HOP_DISTANCE toward the waypoint (or the goal) the
-- soldier is stuck on, if the soldier port allows it there.
function Travel:HopOn(me, goal)
	local target = self:StuckTarget(goal)
	local here = me:Position()
	local dx, dy, dz = target.x - here.x, target.y - here.y, target.z - here.z
	local length = sqrt(dx * dx + dy * dy + dz * dz)
	local t = length > HOP_DISTANCE and HOP_DISTANCE / length or 1
	if not me:Hop({ x = here.x + dx * t, y = here.y + dy * t, z = here.z + dz * t }) then return false end
	self.state.hops = (self.state.hops or 0) + 1
	self.repaths = 0
	self:ResetProgress(me)
	return true
end

-- What the soldier is stuck heading for: its waypoint, or the goal it
-- runs straight at.
function Travel:StuckTarget(goal)
	return self.route and self.route[self.index] or goal
end

-- Stuck: first, if what holds it is something only NPCs collide with, it
-- is let through and runs on; if it is a solid entity (a cart), it walks
-- round it; if it is climbing, it hops; otherwise a step aside and a new
-- route; after too many, a hop, or the end of the trip.
function Travel:Unstick(me, goal)
	local target = self:StuckTarget(goal)
	if me:PassBlocker(target) then
		self.state.passed = (self.state.passed or 0) + 1
		self:ResetProgress(me)
		return self:Continue()
	end
	local detour = me:Detour(target)
	if detour then
		self.detour, self.detourUntil = detour, me:Now() + DETOUR_TIME
		self:ResetProgress(me)
		me:MoveTo(detour)
		return self:Continue()
	end
	if target.z - me:Position().z > CLIMB_RISE and self:HopOn(me, goal) then return self:Continue() end
	self.repaths = self.repaths + 1
	if self.repaths > MAX_REPATHS then
		if self:HopOn(me, goal) then return self:Continue() end
		return self:Fail("stuck")
	end
	self:ResetProgress(me)
	self:Plan(me, goal)
	local angle = ((self.state.member.seq or 0) + self.repaths) * GOLDEN_ANGLE
	local here = me:Position()
	self.sidestep = { x = here.x + cos(angle) * SIDESTEP_DISTANCE, y = here.y + sin(angle) * SIDESTEP_DISTANCE, z = here.z }
	self.sidestepUntil = me:Now() + SIDESTEP_TIME
	me:MoveTo(self.sidestep)
	return self:Continue()
end

-- Past waypoints already reached, then to the farthest of the next few that
-- can be walked to in a straight line.
function Travel:Advance(me)
	local route, index = self.route, self.index
	while index < #route and me:RangeTo(route[index]) <= WAYPOINT_RADIUS do index = index + 1 end
	for k = min(#route, index + LOOKAHEAD), index + 1, -1 do
		if me:CanWalkTo(route[k]) then
			index = k
			break
		end
	end
	self.index = index
	self.state.routeIndex = index
end

-- A route came back: start walking it, or fail without one.
function Travel:TakeRoute(me)
	local result = me:RouteResult()
	if result == nil then return nil end
	if result == false then return self:Fail("no route") end
	self:SetRoute(result)
	return nil
end

-- Straight at the goal, wherever it has moved to. A run that goes nowhere
-- hands over to routes for a while.
function Travel:Chase(me, goal)
	if self:IsStuck(me) then
		self.chaseBlockedUntil = me:Now() + CHASE_BACKOFF
		return self:Unstick(me, goal)
	end
	me:MoveTo(goal)
	return self:Continue()
end

function Travel:FollowRoute(me, goal)
	if not self.requested then self:Plan(me, goal) end
	if self.route == nil then
		local failed = self:TakeRoute(me)
		if failed then return failed end
		if self.route == nil then
			-- waiting on the search is not being stuck
			me:Release()
			self:ResetProgress(me)
			return self:Continue()
		end
	end
	if Distance(goal, self.goal) > REPATH_DISTANCE and me:Now() - self.plannedAt >= REPATH_INTERVAL then
		self:Plan(me, goal)
		return self:Continue()
	end
	self:Advance(me)
	if self:IsStuck(me) then return self:Unstick(me, goal) end
	me:MoveTo(self.route[self.index])
	return self:Continue()
end

-- The goal to travel to now, or nil and why the trip is over.
function Travel:Goal(me, field)
	local state = self.state
	if state.member.role == nil or not OrdersRun(field) then return nil, "orders changed" end
	if self.spot then
		if not WaitingForSetup(field, state.member) then return nil, "setup ended" end
		if me:Now() >= self.giveUpAt then return nil, "gave up" end
		return self.spot
	end
	if ROLES[state.member.role] ~= self.role then return nil, "orders changed" end
	if WaitingForSetup(field, state.member) then return nil, "setup began" end
	local goal = self.role.Goal(field, state.member)
	if goal == nil then return nil, "no goal" end
	return goal
end

function Travel:Update(me)
	local state, role = self.state, self.role
	local goal, over = self:Goal(me, state.war:Field())
	if goal == nil then
		if over == "gave up" then return self:Fail(over) end
		return self:End(over)
	end
	state.goal = goal
	local range = me:RangeTo(goal)
	if range <= role.arrive then return self:End("arrived") end
	if not role.rushes and me:HasEnemy() and range <= role.leash then return self:End("engaging") end
	if self.detour then
		if me:Now() < self.detourUntil and me:RangeTo(self.detour) > WAYPOINT_RADIUS then
			me:MoveTo(self.detour)
			return self:Continue()
		end
		self.detour = nil
	end
	if self.sidestep then
		if me:Now() < self.sidestepUntil then
			me:MoveTo(self.sidestep)
			return self:Continue()
		end
		-- a step aside that moved counts as progress by itself
		self.sidestep = nil
	end
	if me:Now() >= self.chaseBlockedUntil and me:CanWalkTo(goal) then return self:Chase(me, goal) end
	return self:FollowRoute(me, goal)
end

-------------------------------------------------------------------------------
-- Objectives: one Action per role

local Objective = N.Action:Extend("Objective")
local OBJECTIVE_OF = {}

local function ObjectiveFor(state)
	local class = OBJECTIVE_OF[state.member.role] or OBJECTIVE_OF.idle
	return class:New(state)
end

function Objective:Init(state)
	self.state = state
	self.retryAt = 0
end

-- Setup's wandering: a spot, a trip there, a rest, another spot.
function Objective:Wander(me)
	local state, now = self.state, me:Now()
	state.wandering = true
	if now < (self.restUntil or 0) then
		me:Release()
		return self:Continue()
	end
	local spot = me:WanderSpot()
	if not spot then
		self.restUntil = now + WANDER_REST
		me:Release()
		return self:Continue()
	end
	state.goal = spot
	return self:SuspendFor(Travel:New(state, WANDER, spot), "wandering")
end

function Objective:Update(me)
	local state = self.state
	if state.member.role ~= self.roleName then return self:ChangeTo(ObjectiveFor(state), "new role") end
	local field = state.war:Field()
	if OrdersRun(field) and WaitingForSetup(field, state.member) then return self:Wander(me) end
	state.wandering = false
	self.restUntil = nil
	local goal = OrdersRun(field) and self.role.Goal(field, state.member)
	if not goal then
		me:Release()
		return self:Continue()
	end
	state.goal = goal
	local range = me:RangeTo(goal)
	-- at the cart: keep to the spot as the cart carries it off
	if self.role.rushes and range <= self.role.arrive then
		if range > STATION and me:CanWalkTo(goal) then me:MoveTo(goal) else me:Release() end
		return self:Continue()
	end
	local fighting = me:HasEnemy() and range <= self.role.leash
	if range <= self.role.arrive or fighting or me:Now() < self.retryAt then
		me:Release()
		return self:Continue()
	end
	return self:SuspendFor(Travel:New(state, self.role), "to the objective")
end

function Objective:OnResume(me, interrupting)
	if interrupting.spot then
		-- rest where it got to; a spot given up is traded for another at once
		self.restUntil = interrupting.failed and 0 or me:Now() + WANDER_REST
	elseif interrupting.failed then
		self.retryAt = me:Now() + RETRY_WAIT
	end
	return self:Continue()
end

for roleName, role in pairs(ROLES) do
	local class = Objective:Extend(role.name)
	class.roleName = roleName
	class.role = role
	OBJECTIVE_OF[roleName] = class
end

-- No role: the engine's AI has the soldier until it is given one.
local Idle = N.Action:Extend("Idle")
OBJECTIVE_OF.idle = Idle

function Idle:Init(state)
	self.state = state
end

function Idle:Update(me)
	if self.state.member.role ~= nil then return self:ChangeTo(ObjectiveFor(self.state), "given a role") end
	me:Release()
	return self:Continue()
end

-------------------------------------------------------------------------------
-- The variant

local SoldierBehavior = N.Action:Extend("SoldierBehavior")

function SoldierBehavior:Init(state)
	self.state = state
end

function SoldierBehavior:InitialContainedAction(me)
	return ObjectiveFor(self.state)
end

function SoldierBehavior:Update(me)
	if not me:IsAlive() then return self:Done("dead") end
	return self:Continue()
end

-- config = { war (foundation.aiwar War), member (its roster entry) }
function NewState(config, me)
	return { war = config.war, member = config.member }
end

function InitialAction(state)
	return SoldierBehavior:New(state)
end
