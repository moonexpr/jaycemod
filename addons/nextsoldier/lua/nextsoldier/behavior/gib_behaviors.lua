-- What GroupIdentityBehavior does under its root (group_identity), as L4D2's survivors' legs:
-- an order's action (LegsMuster, LegsFallBack), and under it the action its squad's mode says,
-- each moving its member about the squad's point and its place, never the point itself:
--   STATIONARY  LegsStationary  rests at a seat near its place, one no other member holds
--   ALERT       LegsPatrol      patrols spots round the squad's point on its own side
--   CAUTIOUS    LegsWander      wanders near its own place
--   PANIC       LegsEvacuate    runs out of the room by the way out furthest from the threat
--   CLOSE       LegsStayClose   keeps near its leader, running to it when too far
-- A member strayed far from its squad's point suspends what it does for LegsRegroup, running
-- back to its place. A full squad's leader calls the fall back once (FALL_BACK_LINE) and its
-- squad evacuates: its casualties heavy, or a danger near its squad's point, which it evacuates
-- away from.
--
-- A member on orders is told them by NSLegsOrder(), senses its group by NSLegsSense() each
-- update, and heads where its action says by NSLegsHeadFor(spot, gait). Its place is
-- NSLegsPlace(), where it stands NSLegsAt(), its clock Now(), its draws NSLegsDraw() (0 to 1),
-- NSLegsAdmit(around) the map's word on a spot near around, as Places takes it,
-- NSLegsSeats(place, radius) the spots near its place it could rest at, NSLegsDanger(point) a
-- danger near point its squad should leave (nil for none), and NSLegsSay(line) what it calls out.
local Action = nextsoldier.behavior.action
local GroupIdentity = nextsoldier.behavior.group_identity
local Enum = core.enum
local Geometry = math.geometry
local Select = list.select
local pi, atan2 = math.pi, math.atan2
local ipairs, getmetatable = ipairs, getmetatable
module("nextsoldier.behavior.gib_behaviors")

local MODE = GroupIdentity.MODE

-- How a member heads for a spot: walking, running, or to rest there.
GAIT = Enum.New("LegsGait", 0, { "WALK", "RUN", "REST" })

-- The war's own: a defender's rounds near its post, an attacker's wander in setup.
PATROL_RADIUS, PATROL_REST = 384, 6
WANDER_RADIUS, WANDER_REST = 300, 12
-- How far from the threat an evacuating member runs with no way out known, and how far past a
-- way out it runs, clear of the room.
EVACUATE_DISTANCE, EXIT_CLEARANCE = 768, 192
-- How far from its place a member looks for a seat.
REST_RADIUS = 192
-- How far from its leader a member staying close lets itself be, and how near it runs back.
STAY_CLOSE_RANGE, STAY_CLOSE_RADIUS = 256, 128
-- How far from its squad's point a member has strayed, and how near its place it has regrouped.
REGROUP_RANGE, REGROUP_NEAR = 1024, 96
FALL_BACK_LINE = "Fall back!"
-- How many spots a member draws before it keeps to its place.
local TRIES = 6

LegsWait = Action.Extend("LegsWait")

function LegsWait:Update() return self:Continue() end

LegsAtEase = Action.Extend("LegsAtEase")
LegsMuster = Action.Extend("LegsMuster")
LegsFallBack = Action.Extend("LegsFallBack")
LegsStationary = Action.Extend("LegsStationary")
LegsPatrol = Action.Extend("LegsPatrol")
LegsWander = Action.Extend("LegsWander")
LegsEvacuate = Action.Extend("LegsEvacuate")
LegsStayClose = Action.Extend("LegsStayClose")
LegsRegroup = Action.Extend("LegsRegroup")

local ORDER_ACTIONS = { Muster = LegsMuster, FallBack = LegsFallBack }

MODE_ACTIONS = {
	[MODE.STATIONARY] = LegsStationary,
	[MODE.ALERT] = LegsPatrol,
	[MODE.CAUTIOUS] = LegsWander,
	[MODE.PANIC] = LegsEvacuate,
	[MODE.CLOSE] = LegsStayClose,
}

-- What a member told order runs.
local function ActionFor(order)
	if not order then return LegsAtEase:New() end
	return ORDER_ACTIONS[order.kind]:New({ order = order })
end

local function Orders(self, me)
	me:NSLegsSense()
	local order = me:NSLegsOrder()
	if order == self.order then return self:Continue() end
	return self:ChangeTo(ActionFor(order), order and ("Told to " .. order.kind) or "Dissolved")
end

-- On orders, it hears whether they have changed; kept to them, its leader calls the fall back
-- when the squad routs.
local function OnOrders(self, me)
	local result = Orders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local order = self.order
	if order.leader ~= me then return result end
	local danger = not order.routed and me:NSLegsDanger(order.point)
	if (danger and order:Endanger(danger)) or order:Rout() then me:NSLegsSay(FALL_BACK_LINE) end
	return result
end

-- What it does on them, its squad's mode's.
local function ModeAction(self) return MODE_ACTIONS[self.order.mode]:New({ order = self.order }) end

LegsAtEase.Update = Orders
LegsMuster.Update, LegsMuster.InitialContainedAction = OnOrders, ModeAction
LegsFallBack.Update, LegsFallBack.InitialContainedAction = OnOrders, ModeAction

-- A spot drawn around center, angle within half a turn of side (or any way, for none), radius
-- between least and most, its height z; nil if the map refuses TRIES of them.
local function Drawn(me, admit, center, z, side, least, most)
	for _ = 1, TRIES do
		local angle = side and side + (me:NSLegsDraw() - 0.5) * pi or me:NSLegsDraw() * 2 * pi
		local spot = Geometry.Polar(center, least + (most - least) * me:NSLegsDraw(), angle)
		local admitted = admit({ x = spot.x, y = spot.y, z = z })
		if admitted then return admitted end
	end
	return nil
end

-- The side of point place stands on, an angle; nil on the point itself.
local function Side(point, place)
	if place.x == point.x and place.y == point.y then return nil end
	return atan2(place.y - point.y, place.x - point.x)
end

-- The spot it keeps to rest seconds, then draws again (draw() -> a spot, nil: its place).
local function Kept(self, me, place, rest, draw)
	local now = me:Now()
	if not self.spot or now >= self.spotUntil then
		self.spot, self.spotUntil = draw() or place, now + rest
	end
	return self.spot
end

-- The modes' template: kept to its order and its squad's mode, a member strayed from the point
-- regroups (where its mode does), else heads where its mode says (Head(me, place) -> spot, gait).
local function OnMode(self, me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local class = MODE_ACTIONS[order.mode]
	if class ~= getmetatable(self) then return self:ChangeTo(class:New({ order = order }), "Squad " .. MODE[order.mode]) end
	local place = me:NSLegsPlace()
	if not place then return self:Continue() end
	if self.regroups and Geometry.Distance2D(me:NSLegsAt(), order.point) > REGROUP_RANGE then
		return self:SuspendFor(LegsRegroup:New({ order = order }), "Strayed")
	end
	me:NSLegsHeadFor(self:Head(me, place))
	return self:Continue()
end

for _, class in ipairs({ LegsStationary, LegsPatrol, LegsWander, LegsEvacuate, LegsStayClose }) do
	class.Update = OnMode
end
LegsStationary.regroups, LegsPatrol.regroups, LegsWander.regroups = true, true, true

function LegsStationary:Head(me, place)
	if not self.seat then
		self.seat = self.order:Seat(me, me:NSLegsSeats(place, REST_RADIUS), place) or place
	end
	return self.seat, GAIT.REST
end

function LegsPatrol:Head(me, place)
	local point = self.order.point
	return Kept(self, me, place, PATROL_REST, function()
		return Drawn(me, me:NSLegsAdmit(point), point, place.z, Side(point, place), PATROL_RADIUS / 2, PATROL_RADIUS)
	end), GAIT.WALK
end

function LegsWander:Head(me, place)
	return Kept(self, me, place, WANDER_REST, function()
		return Drawn(me, me:NSLegsAdmit(place), place, place.z, nil, 0, WANDER_RADIUS)
	end), GAIT.WALK
end

-- The way out from at furthest from the threat, beyond it the nearer, and past it, clear of the
-- room (EXIT_CLEARANCE out from the squad's point, where the map admits it), else the way out
-- itself; with none the map admits, straight away from the threat, nearer each try.
local function WayOut(me, order, at, admit)
	local threat, exits = order.from or order.point, order.exits or {}
	local ranked = Select.Order(exits, function(a, b)
		return Geometry.Distance2D(threat, a) - Geometry.Distance2D(at, a)
			> Geometry.Distance2D(threat, b) - Geometry.Distance2D(at, b)
	end)
	for _, i in ipairs(ranked) do
		local exit = exits[i]
		local spot = admit(exit)
		if spot then
			local past = me:NSLegsAdmit(exit)(Geometry.Offset2D(exit, order.point, EXIT_CLEARANCE, 0))
			return past or spot
		end
	end
	for try = 0, TRIES - 1 do
		local spot = admit(Geometry.Offset2D(at, threat, EVACUATE_DISTANCE / 2 ^ try, 0))
		if spot then return spot end
	end
	return nil
end

function LegsEvacuate:Head(me, place)
	if not self.exit then
		local at = me:NSLegsAt()
		self.exit = WayOut(me, self.order, at, me:NSLegsAdmit(at)) or place
	end
	return self.exit, GAIT.RUN
end

-- Near its leader, where it stands or the spot it last ran to; too far, a spot near the leader
-- on its own side, running. The leader, or a member of a squad with none, keeps to its place.
function LegsStayClose:Head(me, place)
	local leader = self.order.leader
	if not leader or leader == me then return place, GAIT.WALK end
	local near = leader:NSLegsAt()
	if self.spot and Geometry.Distance2D(self.spot, near) <= STAY_CLOSE_RANGE then return self.spot, self.gait end
	local at = me:NSLegsAt()
	if Geometry.Distance2D(at, near) <= STAY_CLOSE_RANGE then
		self.spot, self.gait = at, GAIT.WALK
	else
		self.spot = Drawn(me, me:NSLegsAdmit(near), near, near.z, Side(near, at), 0, STAY_CLOSE_RADIUS) or near
		self.gait = GAIT.RUN
	end
	return self.spot, self.gait
end

-- Back to its place, running, until it is near it; done at once when its squad evacuates.
function LegsRegroup:Update(me)
	local order = self.order
	local place = me:NSLegsPlace()
	if me:NSLegsOrder() ~= order or order.mode == MODE.PANIC or not place then return self:Done("Evacuating") end
	if Geometry.Distance2D(me:NSLegsAt(), place) <= REGROUP_NEAR then return self:Done("Regrouped") end
	me:NSLegsHeadFor(place, GAIT.RUN)
	return self:Continue()
end
