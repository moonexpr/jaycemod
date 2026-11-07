-- What TacticalLeggings does under its root (group_identity), as L4D2's survivors' legs:
-- an order's action (LegsMuster, LegsFallBack, LegsAssault), and under it the action its squad's mode says,
-- each moving its member about the squad's point and its place, never the point itself:
--   STATIONARY  LegsStationary  rests at a seat near its place, one no other member holds
--   ALERT       LegsPatrol      patrols spots round the squad's point on its own side
--   CAUTIOUS    LegsWander      wanders near its own place
--   PANIC       LegsEvacuate    runs out of the room by the way out furthest from the threat, to
--                               hide out of its sight where its room is known (else past the door)
--   CLOSE       LegsStayClose   keeps near its leader, running to it when too far
-- A member strayed far from its squad's point suspends what it does for LegsRegroup, running
-- back to its place. A full squad's leader calls the fall back once (FALL_BACK_LINE) and its
-- squad evacuates: its casualties heavy, or a danger near its squad's point, which it evacuates
-- away from.
--
-- An assault comes first: under LegsAssault each member stages (LegsStage) at its place in the
-- stack around the entrance, out of the room's sight, and waits there ready; its leader signals
-- (SIGNAL_LINE) once all are staged, or STACK_PATIENCE after it is; then each goes in (LegsEnter),
-- running for its assault point, and holds it (LegsClear) until the room is clear (CLEAR_LINE),
-- then runs its squad's mode's action about its place in the room. With more than one entrance,
-- the member nearest the front is the decoy (LegsDecoy): hidden beside it until the rest are
-- staged, it shows itself there until it draws the enemy or DECOY_PATIENCE passes, then hides
-- again, and the rest go in by the sides and back only once it has. Falling back (half the squad
-- lost: its leader calls it, the first to see the leader lost taking the lead), every part of an
-- assault leaves off and evacuates. Staging round the room, a member hops from door to door: crouched
-- HOP_PAUSE on a doorway's near side, then across its sight at a run.
--
-- An ambush (LegsAmbush): each runs to its place beside the entrance the enemy comes by, hidden
-- from its approach, and lies there crouched; an enemy seen within SPRING_RANGE of the entrance, or
-- a member hurt, has its leader spring it (SPRING_LINE). Lying in wait or staging, a member's main
-- stack holds its fire (nextsoldier.behavior.squad_member) until its leader springs or signals; its
-- leader killed with the mission under way, the first to see it abandons it and calls the fall back.
--
-- A member on orders is told them by NSLegsOrder(), senses its group by NSLegsSense() each
-- update, and heads where its action says by NSLegsHeadFor(spot, gait[, keepOut]) (keepOut: nav area ids
-- its way there keeps out of). Its place is
-- NSLegsPlace(), where it stands NSLegsAt(), its clock Now(), its draws NSLegsDraw() (0 to 1),
-- NSLegsAdmit(around) the map's word on a spot near around, as Places takes it,
-- NSLegsSeats(place, radius) the spots near its place it could rest at, NSLegsDanger(point) a
-- danger near point its squad should leave (nil for none), NSLegsContact() whether it is fighting
-- an enemy now, NSLegsEnemyAt() where that enemy is (nil for none), NSLegsHurt() whether it has
-- been hurt, NSLegsNameOf(member) a member's name on the radio, and NSLegsSay(line, call) what it
-- calls out: each call over its squad's radio (group_identity's Radio: its leader to the director,
-- the squad or a member, a member only to its leader).
local Action = nextsoldier.behavior.action
local GroupIdentity = nextsoldier.behavior.group_identity
local Enum = core.enum
local Geometry = math.geometry
local Select = list.select
local pi, atan2 = math.pi, math.atan2
local ipairs, pairs, getmetatable = ipairs, pairs, getmetatable
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
-- How far apart the members of a squad hide, evacuated.
HIDE_APART = 72
-- How far from its place a member looks for a seat.
REST_RADIUS = 192
-- How far from its leader a member staying close lets itself be, and how near it runs back.
STAY_CLOSE_RANGE, STAY_CLOSE_RADIUS = 256, 128
-- How far from its squad's point a member has strayed, and how near its place it has regrouped.
REGROUP_RANGE, REGROUP_NEAR = 1024, 96
FALL_BACK_LINE = GroupIdentity.CALLS.FALL_BACK
-- An assault: how near its place in the stack a member is staged, how long its leader waits there
-- for the rest before it signals with those it has, the line it signals by, and how near its place
-- in the room a member going in has arrived.
STAGE_REACH, STACK_PATIENCE, ENTER_REACH = 24, 10, 48
SIGNAL_LINE = GroupIdentity.CALLS.MOVE_IN
-- Going in: the room is clear once every member holds its assault point and none has met the
-- enemy for CLEAR_GRACE; its leader calls it so.
CLEAR_GRACE = 5
CLEAR_LINE = GroupIdentity.CALLS.ROOM_CLEAR
-- Shown at the front and drawing no one for DECOY_PATIENCE, the decoy takes the enemy as drawn
-- (or never there) and hides again.
DECOY_PATIENCE = 4
-- Hopping door to door on its way to its stack, how long a member waits crouched on the near side
-- of a doorway before it runs across.
HOP_PAUSE = 1.5
-- An ambush: lying in wait, an enemy seen within SPRING_RANGE of the entrance it waits by (or a
-- member hurt) has its leader spring it, calling SPRING_LINE.
SPRING_RANGE = 300
SPRING_LINE = GroupIdentity.CALLS.NOW
-- An occupation: a guard stops PATROL_STOP at each corner of its loop; its leader asks each for a
-- status report every CHECK_INTERVAL, and takes one silent CHECK_TIMEOUT after as missing.
PATROL_STOP, CHECK_INTERVAL, CHECK_TIMEOUT = 4, 20, 6
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
LegsAssault = Action.Extend("LegsAssault")
LegsStage = Action.Extend("LegsStage")
LegsEnter = Action.Extend("LegsEnter")
LegsClear = Action.Extend("LegsClear")
LegsDecoy = Action.Extend("LegsDecoy")
LegsAmbush = Action.Extend("LegsAmbush")
LegsOccupy = Action.Extend("LegsOccupy")
LegsGuard = Action.Extend("LegsGuard")
LegsHold = Action.Extend("LegsHold")
LegsStackUp = Action.Extend("LegsStackUp")

local ORDER_ACTIONS = { Muster = LegsMuster, FallBack = LegsFallBack, Assault = LegsAssault, Ambush = LegsAmbush,
	Occupy = LegsOccupy }

-- A call over its squad's radio, said aloud: the entry the channel keeps.
local function Radio(me, order, to, call, ...)
	local entry = order:Radio(me, to, call, ...)
	me:NSLegsSay(entry.text, entry)
	return entry
end

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
	-- its leader lost, the first of the squad to see it takes the lead; killed with the mission
	-- under way, it abandons it first and calls the fall back
	if order.leader == nil then
		order:Lead(me)
		if order.leaderKilled and order:Underway() and order:Abandon() then Radio(me, order, GroupIdentity.SQUAD, "FALL_BACK") end
	end
	if order.leader ~= me then return result end
	local danger = not order.routed and me:NSLegsDanger(order.point)
	if (danger and order:Endanger(danger)) or order:Rout() then Radio(me, order, GroupIdentity.SQUAD, "FALL_BACK") end
	return result
end

-- What it does on them, its squad's mode's.
local function ModeAction(self) return MODE_ACTIONS[self.order.mode]:New({ order = self.order }) end

LegsAtEase.Update = Orders
LegsMuster.Update, LegsMuster.InitialContainedAction = OnOrders, ModeAction
LegsFallBack.Update, LegsFallBack.InitialContainedAction = OnOrders, ModeAction

-- An assault: its members stage around the entrance, out of the room's sight, then go in on its
-- leader's signal, given once all are staged, or STACK_PATIENCE after the leader is.
function LegsAssault:Update(me)
	local result = OnOrders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local order = self.order
	if order.leader ~= me or order:Signalled() or order.mode == MODE.PANIC then return result end
	local since = order:StagedAt(me)
	local staged = order:AllStaged() or (since and me:Now() - since >= STACK_PATIENCE)
	-- with a decoy, the rest go in only once it has drawn the enemy
	if staged and (not order.decoy or order:Engaged()) then
		order:Signal()
		Radio(me, order, GroupIdentity.SQUAD, "MOVE_IN")
	end
	return result
end

-- The decoy's own part, or staging with the rest.
function LegsAssault:InitialContainedAction(me)
	local place = me and me:NSLegsPlace()
	if place and self.order:DecoyOf(place) then return LegsDecoy:New({ order = self.order }) end
	return LegsStage:New({ order = self.order })
end

-- The ground a member staging or hiding keeps out of: the room's own (room.inside, area ids), so
-- a flank walks round it, not through; nil where the room gives none.
local function KeepOut(order) return order.room and order.room.inside end

-- Falling back, an assault leaves off whatever part it is at and evacuates.
local function Evacuating(self)
	if self.order.mode ~= MODE.PANIC then return nil end
	return self:ChangeTo(LegsEvacuate:New({ order = self.order }), "Fall back")
end

-- The decoy: hidden beside the front, staged, until the rest are; then out to show itself in the
-- room's sight, until it draws the enemy (its contact) or DECOY_PATIENCE passes; then back to hide,
-- holding there as the rest's points are held, until the room is clear; then its squad's mode's.
function LegsDecoy:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local fall = Evacuating(self)
	if fall then return fall end
	order:Decoy(me)
	local part, now, at = order:DecoyOf(me:NSLegsPlace()), me:Now(), me:NSLegsAt()
	if order.cleared then return self:ChangeTo(ModeAction(self), "Clear") end
	if me:NSLegsContact() then
		order:Engage()
		order:Contact(now)
	end
	if not order:Engaged() then
		if order:StagedAt(me) and order:AllStaged() and part.show then
			if Geometry.Distance2D(at, part.show) <= STAGE_REACH then
				self.shownAt = self.shownAt or now
				if now - self.shownAt >= DECOY_PATIENCE then order:Engage() end
			end
			if not order:Engaged() then
				me:NSLegsHeadFor(part.show, GAIT.RUN, KeepOut(order))
				return self:Continue()
			end
		elseif part.hide and Geometry.Distance2D(at, part.hide) > STAGE_REACH then
			me:NSLegsHeadFor(part.hide, GAIT.WALK, KeepOut(order))
			return self:Continue()
		else
			order:Staged(me, now)
			me:NSLegsHeadFor(part.hide or at, GAIT.REST, KeepOut(order))
			return self:Continue()
		end
	end
	local hide = part.hide or at
	if Geometry.Distance2D(at, hide) <= STAGE_REACH then
		order:Breached(me, now)
		if order:AllBreached() and now - order:QuietSince() >= CLEAR_GRACE then
			if order.leader == me and order:CallClear() then Radio(me, order, GroupIdentity.SQUAD, "ROOM_CLEAR") end
			return self:ChangeTo(ModeAction(self), "Clear")
		end
		me:NSLegsHeadFor(hide, GAIT.REST, KeepOut(order))
	else
		me:NSLegsHeadFor(hide, GAIT.RUN, KeepOut(order))
	end
	return self:Continue()
end

-- An ambush: to its place at a run, and there lying in wait, crouched; an enemy it sees by the
-- entrance, or a hurt, it reports, and its leader springs the ambush on the first report. Sprung,
-- it fights from where it lies; its leader lost or the squad routed, it evacuates.
function LegsAmbush:InitialContainedAction() return nil end

function LegsAmbush:Update(me)
	local result = OnOrders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local order = self.order
	if order.mode == MODE.PANIC then return self:ChangeTo(LegsEvacuate:New({ order = order }), "Fall back") end
	if not order:Sprung() then
		local enemy = me:NSLegsEnemyAt()
		if (enemy and Geometry.Distance2D(enemy, order.entrance) <= SPRING_RANGE) or me:NSLegsHurt() then order.reported = true end
		if order.reported and order.leader == me and order:Spring() then Radio(me, order, GroupIdentity.SQUAD, "NOW") end
	end
	local place = me:NSLegsPlace() or me:NSLegsAt()
	local there = Geometry.Distance2D(me:NSLegsAt(), place) <= STAGE_REACH
	me:NSLegsHeadFor(place, there and GAIT.REST or GAIT.RUN)
	return self:Continue()
end

-- An occupation: its leader holds inside and asks each guard for a status report every
-- CHECK_INTERVAL; one silent CHECK_TIMEOUT after is missing: the leader tells the director and the
-- squad to stack up by the exit nearest where it was last heard from, and once all are stacked
-- (STACK_PATIENCE after it is, or on contact) gives the word to move in.
function LegsOccupy:InitialContainedAction(me)
	local place = me and me:NSLegsPlace()
	if place and self.order:PatrolOf(place) then return LegsGuard:New({ order = self.order }) end
	return LegsHold:New({ order = self.order })
end

function LegsOccupy:Update(me)
	local result = OnOrders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local order, now = self.order, me:Now()
	if order.leader ~= me or order.routed then return result end
	if not order.alarm then
		if now - (order.checkedAt or 0) >= CHECK_INTERVAL then
			order.checkedAt = now
			for guard in pairs(order.guards) do
				order:Ask(guard, now)
				Radio(me, order, guard, "STATUS")
			end
		end
		local missing = order:Silent(now, CHECK_TIMEOUT)
		if missing then
			Radio(me, order, GroupIdentity.DIRECTOR, "LOST", me:NSLegsNameOf(missing))
			order:Alarm(order:LastHeard(missing), order.spacing, me:NSLegsAdmit(order.point))
			Radio(me, order, GroupIdentity.SQUAD, "STACK_UP")
		end
	elseif not order:Signalled() then
		local since = order:StagedAt(me)
		if order:AllStaged() or (since and now - since >= STACK_PATIENCE) or me:NSLegsContact() then
			order:Signal()
			Radio(me, order, GroupIdentity.SQUAD, "MOVE_IN")
		end
	end
	return result
end

-- Holding inside, at its place, ready; the alarm raised, it stacks up.
function LegsHold:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	if order.alarm then return self:ChangeTo(LegsStackUp:New({ order = order }), "Stack up") end
	local place = me:NSLegsPlace() or me:NSLegsAt()
	me:NSLegsHeadFor(place, Geometry.Distance2D(me:NSLegsAt(), place) <= STAGE_REACH and GAIT.REST or GAIT.WALK)
	return self:Continue()
end

-- On patrol: round the loop one way, from its own stop, standing PATROL_STOP at each corner; asked
-- for a status report, it answers its leader, telling of any contact; the alarm raised, it stacks up.
function LegsGuard:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	if order.alarm then return self:ChangeTo(LegsStackUp:New({ order = order }), "Stack up") end
	local now, at = me:Now(), me:NSLegsAt()
	order:OnPatrol(me, at)
	if order:Asked(me) and order.leader then
		Radio(me, order, order.leader, me:NSLegsContact() and "CONTACT" or "ALL_CLEAR")
		order:Answered(me, at)
	end
	self.stop = self.stop or order:PatrolOf(me:NSLegsPlace())
	local stop = order.loop[self.stop]
	if Geometry.Distance2D(at, stop.point) <= STAGE_REACH then
		if stop.stop then
			self.stoppedAt = self.stoppedAt or now
			if now - self.stoppedAt < PATROL_STOP then
				me:NSLegsHeadFor(stop.point, GAIT.WALK)
				return self:Continue()
			end
		end
		self.stop, self.stoppedAt = self.stop % #order.loop + 1, nil
		stop = order.loop[self.stop]
	end
	me:NSLegsHeadFor(stop.point, GAIT.WALK)
	return self:Continue()
end

-- The alarm raised: to its spot by the exit, there staged, ready; on its leader's word, at a run to
-- where the guard was last heard from. Falling back, it evacuates.
function LegsStackUp:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local fall = Evacuating(self)
	if fall then return fall end
	if order:Signalled() then
		me:NSLegsHeadFor(order.alarm.at, GAIT.RUN)
		return self:Continue()
	end
	local at, spot = me:NSLegsAt(), order:StackAt(me)
	if not spot or Geometry.Distance2D(at, spot) <= STAGE_REACH then
		order:Staged(me, me:Now())
		me:NSLegsHeadFor(spot or at, GAIT.REST)
	else
		me:NSLegsHeadFor(spot, GAIT.WALK)
	end
	return self:Continue()
end

-- To its place in the stack, walking, and there staged, ready; with none, staged where it stands.
-- Signalled, it goes in.
function LegsStage:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local fall = Evacuating(self)
	if fall then return fall end
	if order:Signalled() then return self:ChangeTo(LegsEnter:New({ order = order }), "Signalled") end
	local place = me:NSLegsPlace()
	local at = me:NSLegsAt()
	local staging = place and order:StagingOf(place)
	if not staging then
		order:Staged(me, me:Now())
		me:NSLegsHeadFor(at, GAIT.REST, KeepOut(order))
		return self:Continue()
	end
	if Geometry.Distance2D(at, staging) <= STAGE_REACH then
		order:Staged(me, me:Now())
		me:NSLegsHeadFor(staging, GAIT.REST, KeepOut(order))
		return self:Continue()
	end
	-- on its way, door to door: crouched a while on a doorway's near side, then across at a run
	local hops, now = order:HopsOf(place), me:Now()
	local hop = hops[self.hop or 1]
	if hop and Geometry.Distance2D(at, hop.point) <= STAGE_REACH then
		if hop.pause then
			self.pausedAt = self.pausedAt or now
			if now - self.pausedAt < HOP_PAUSE then
				me:NSLegsHeadFor(hop.point, GAIT.REST, KeepOut(order))
				return self:Continue()
			end
		end
		self.hop, self.pausedAt = (self.hop or 1) + 1, nil
		hop = hops[self.hop]
	end
	if hop then
		me:NSLegsHeadFor(hop.point, hop.cross and GAIT.RUN or GAIT.WALK, KeepOut(order))
	else
		me:NSLegsHeadFor(staging, GAIT.WALK, KeepOut(order))
	end
	return self:Continue()
end

-- Into the room, running for its assault point, and there holding it until the room is clear;
-- with no point, straight for its place and its squad's mode's.
function LegsEnter:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local fall = Evacuating(self)
	if fall then return fall end
	local place = me:NSLegsPlace()
	local point = place and order:BreachOf(place)
	local goal = point or place
	if not goal or Geometry.Distance2D(me:NSLegsAt(), goal) <= ENTER_REACH then
		if not point then return self:ChangeTo(ModeAction(self), "In") end
		order:Breached(me, me:Now())
		return self:ChangeTo(LegsClear:New({ order = order, point = point }), "On its point")
	end
	me:NSLegsHeadFor(goal, GAIT.RUN)
	return self:Continue()
end

-- On its assault point, ready, telling of any enemy met, until every member holds its own and
-- none has met one for CLEAR_GRACE: then the leader calls the room clear, and each goes on to its
-- squad's mode's.
function LegsClear:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local fall = Evacuating(self)
	if fall then return fall end
	local now = me:Now()
	if me:NSLegsContact() then order:Contact(now) end
	if order:AllBreached() and now - order:QuietSince() >= CLEAR_GRACE then
		if order.leader == me and order:CallClear() then Radio(me, order, GroupIdentity.SQUAD, "ROOM_CLEAR") end
		return self:ChangeTo(ModeAction(self), "Clear")
	end
	me:NSLegsHeadFor(self.point, GAIT.REST)
	return self:Continue()
end

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
			local hideout = order:Hideout(me, exit, HIDE_APART, function(around) return me:NSLegsAdmit(around) end)
			if hideout then return hideout end
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
