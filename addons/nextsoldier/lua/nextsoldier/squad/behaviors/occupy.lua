-- An occupation: a squad holds a room. A guard for each GUARD_SPAN of a loop PATROL_OUT round the
-- room outside, up to half the squad, walks it one way round from stops evenly apart, standing
-- PATROL_STOP at each corner (LegsGuard); the rest hold inside (LegsHold). Every CHECK_INTERVAL the
-- leader asks each guard for a status report; one silent CHECK_TIMEOUT after is missing: the leader
-- tells its director, and the squad stacks up inside by the exit nearest where it was last heard
-- from, out of sight from outside (LegsStackUp), its members holding their fire. Before it leaves
-- the room the leader asks its director for clearance (nextsoldier.squad.interactions.director)
-- and waits: cleared, it gives the word ("Move in!") once all are stacked (STACK_PATIENCE after it
-- is), and the squad runs to where the guard was last heard from; told to stand by, the squad
-- stands down, its leader appointing the holder nearest the missing guard's round to take it up;
-- told to defend or attack, it acknowledges and waits stacked for the order that brings. Contact
-- while stacked up, the squad fights where it is. Stacking up raises the room's alarms (the mode
-- hosting it, on the STACK_UP call).
--
-- Occupy(room) -> an order (room: with watched(point, entrance) and its exits): Places(members,
-- spacing, admit, admitAt) (the first, its leader to be, never on patrol); PatrolOf(place) (the stop
-- a guard starts from, or nil); a guard's reports: OnPatrol(member, at, stop), Ask(member, now),
-- Asked(member), Answered(member, at), Silent(now, timeout), Miss(member), LastHeard(member); the
-- alarm: Alarm(at, spacing, admit) (true the once), StackAt(member), StandDown(), Appoint(member),
-- AppointedTo(member).
local Action = nextsoldier.behavior.action
local Orders = nextsoldier.squad.orders
local Radio = nextsoldier.squad.comms.radio
local Director = nextsoldier.squad.interactions.director
local Legs = nextsoldier.squad.behaviors.legs
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors
local Geometry = math.geometry
local Select = list.select
local ipairs, pairs, error, floor, min, max, sort = ipairs, pairs, error, math.floor, math.min, math.max, table.sort
local getmetatable = getmetatable
module("nextsoldier.squad.behaviors.occupy")

-- The loop PATROL_OUT outside the room, a guard for each GUARD_SPAN of it.
PATROL_OUT, GUARD_SPAN = 160, 1200
-- A guard stops PATROL_STOP at each corner; its leader asks each for a status report every
-- CHECK_INTERVAL, and takes one silent CHECK_TIMEOUT after as missing.
PATROL_STOP, CHECK_INTERVAL, CHECK_TIMEOUT = 4, 20, 6

local Hold = Orders.Kind()

-- The loop round the room PATROL_OUT outside its block: its corners, where a guard stops, and its
-- sides' middles, each where admitAt lets, counter-clockwise from the south-west.
local function Loop(room, admitAt)
	local x0, y0 = room.lo.x - PATROL_OUT, room.lo.y - PATROL_OUT
	local x1, y1 = room.hi.x + PATROL_OUT, room.hi.y + PATROL_OUT
	local mx, my, z = (x0 + x1) / 2, (y0 + y1) / 2, room.center.z
	local loop = {}
	for _, at in ipairs({ { x0, y0, true }, { mx, y0 }, { x1, y0, true }, { x1, my }, { x1, y1, true }, { mx, y1 },
		{ x0, y1, true }, { x0, my } }) do
		local p = { x = at[1], y = at[2], z = z }
		local spot = admitAt(p)(p)
		if spot then loop[#loop + 1] = { point = spot, stop = at[3] == true } end
	end
	return loop
end

-- Each member's place: its guards' first stops on the loop, evenly round it (the members furthest
-- from the room's middle, never the first), the rest's a muster's at the room's middle.
function Hold:Places(members, spacing, admit, admitAt)
	if not admitAt then error("an occupation patrols round its room as well as holding it: admitAt", 2) end
	self.size, self.spacing = #members, spacing
	self.loop, self.patrol, self.guards, self.holding = Loop(self.room, admitAt), {}, {}, {}
	local length = 0
	for i, stop in ipairs(self.loop) do
		length = length + Geometry.Distance2D(stop.point, self.loop[i % #self.loop + 1].point)
	end
	local count = #self.loop > 0 and min(floor(#members / 2), max(1, floor(length / GUARD_SPAN + 0.5))) or 0
	local rest = {}
	for i = 2, #members do rest[#rest + 1] = i end
	local center = self.room.center
	sort(rest, function(a, b) return Geometry.Distance2D(members[a], center) > Geometry.Distance2D(members[b], center) end)
	local places, holders, positions = {}, { 1 }, { members[1] }
	for k, m in ipairs(rest) do
		if k <= count then
			local start = floor((k - 1) * #self.loop / count) + 1
			places[m] = self.loop[start].point
			self.patrol[places[m]] = start
		else
			holders[#holders + 1], positions[#positions + 1] = m, members[m]
		end
	end
	for i, slot in pairs(GroupIdentity.Muster(center):Places(positions, spacing, admit)) do places[holders[i]] = slot end
	return places
end

function Hold:PatrolOf(place) return self.patrol and self.patrol[place] end

-- member holding inside (holding its place or stacked up, not on patrol) from now on, or not;
-- gone from the squad, neither.
function Hold:Holding(member, holding) self.holding[member] = holding or nil end

function Hold:Leave(member)
	self.holding[member] = nil
	return getmetatable(Hold).Leave(self, member)
end

function Hold:OnPatrol(member, at, stop)
	if not self.guards[member] then self.guards[member] = { heard = at } end
	self.guards[member].stop = stop
end

function Hold:Miss(member)
	local guard = self.guards[member]
	self.guards[member] = nil
	self.missing = { member = member, heard = guard.heard, stop = guard.stop }
end

function Hold:Ask(member, now) self.guards[member].asked = now end
function Hold:Asked(member) return self.guards[member] ~= nil and self.guards[member].asked ~= nil end

function Hold:Answered(member, at)
	local guard = self.guards[member]
	guard.asked, guard.heard = nil, at
end

function Hold:Silent(now, timeout)
	for member, guard in pairs(self.guards) do
		if guard.asked and now - guard.asked > timeout then return member end
	end
	return nil
end

function Hold:LastHeard(member)
	local guard = self.guards[member] or (self.missing and self.missing.member == member and self.missing)
	return guard.heard
end

-- A guard missing, last heard from at: the spots to stack on inside, out of sight from outside the
-- exit nearest it, spacing apart, nearest that exit, where admit lets.
function Hold:Alarm(at, spacing, admit)
	if self.alarm then return false end
	local exit = Select.Nearest(self.exits or {}, at)
	local hidden = {}
	for _, p in ipairs(Legs.Floor(self.room, spacing, admit)) do
		if not exit or not self.room.watched(p, exit) then hidden[#hidden + 1] = p end
	end
	self.alarm = { at = at, exit = exit, spots = Legs.Nearest(hidden, exit or at, self.size, spacing), taken = {} }
	return true
end

function Hold:StackAt(member)
	local alarm = self.alarm
	if alarm.taken[member] then return alarm.taken[member] end
	local held = {}
	for _, spot in pairs(alarm.taken) do held[spot] = true end
	for _, spot in ipairs(alarm.spots) do
		if not held[spot] then
			alarm.taken[member] = spot
			return spot
		end
	end
	return nil
end

-- Told to stand by: the alarm let go, none stacked, the request and its answer forgotten.
function Hold:StandDown()
	self.alarm, self.stagedAt, self.engaged = nil, nil, nil
	Director.Forget(self)
end

function Hold:Appoint(member)
	self.appointed = self.appointed or {}
	self.appointed[member] = self.missing and self.missing.stop or 1
end

function Hold:AppointedTo(member) return self.appointed and self.appointed[member] end

function Occupy(room)
	if not room.watched then error("an occupation stacks up out of sight from outside: the room's watched", 2) end
	return Orders.New(Hold, { kind = "Occupy", point = room.center, room = room, exits = room.exits })
end

LegsOccupy = Action.Extend("LegsOccupy")
LegsGuard = Action.Extend("LegsGuard")
LegsHold = Action.Extend("LegsHold")
LegsStackUp = Action.Extend("LegsStackUp")

function LegsOccupy:InitialContainedAction(me)
	local place = me and me:NSLegsPlace()
	if place and self.order:PatrolOf(place) then return LegsGuard:New({ order = self.order }) end
	return LegsHold:New({ order = self.order })
end

-- Of the squad's members holding inside (not on patrol, nor its leader), the one nearest the missing
-- guard's last stop.
local function Relief(order, leader)
	local stop = order.loop[order.missing and order.missing.stop or 1]
	local best
	for member in pairs(order.holding) do
		if member ~= leader and not order.guards[member] and stop and (not best
			or Geometry.Distance2D(member:NSLegsAt(), stop.point) < Geometry.Distance2D(best:NSLegsAt(), stop.point)) then
			best = member
		end
	end
	return best
end

-- The leader's part, the alarm raised: clearance asked, then acted on.
local function Clearance(order, me, now)
	if not Director.Requested(order) then
		Legs.Speak(me, order, Radio.DIRECTOR, "REQUEST_VACATE")
		Director.Request(order, { kind = "VACATE", at = order.alarm.at })
	end
	local directive = Director.Directive(order)
	if not directive then return end
	if directive.kind == "VACATE" then
		local since = order:StagedAt(me)
		if order:AllStaged() or (since and now - since >= GIB.STACK_PATIENCE) then
			order:Signal()
			Legs.Speak(me, order, Radio.SQUAD, "MOVE_IN")
		end
	elseif directive.kind == "STANDBY" then
		local relief = Relief(order, me)
		order:StandDown()
		if relief then
			order:Appoint(relief)
			Legs.Speak(me, order, relief, "TAKE_PATROL")
		end
	elseif not directive.acknowledged then
		directive.acknowledged = true
		Legs.Speak(me, order, Radio.DIRECTOR, "COPY")
	end
end

function LegsOccupy:Update(me)
	local result = Legs.OnOrders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local order, now = self.order, me:Now()
	if order.leader ~= me or order.routed then return result end
	if not order.alarm then
		if now - (order.checkedAt or 0) >= CHECK_INTERVAL then
			order.checkedAt = now
			for guard in pairs(order.guards) do
				order:Ask(guard, now)
				Legs.Speak(me, order, guard, "STATUS")
			end
		end
		local missing = order:Silent(now, CHECK_TIMEOUT)
		if missing then
			local heard = order:LastHeard(missing)
			Legs.Speak(me, order, Radio.DIRECTOR, "LOST", me:NSLegsNameOf(missing))
			order:Miss(missing)
			order:Alarm(heard, order.spacing, me:NSLegsAdmit(order.point))
			Legs.Speak(me, order, Radio.SQUAD, "STACK_UP")
		end
	elseif not order:Signalled() and not order:Engaged() then
		Clearance(order, me, now)
	end
	return result
end

-- Holding inside, at its place, ready; the alarm raised, it stacks up.
function LegsHold:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	order:Holding(me, true)
	if order.alarm then return self:ChangeTo(LegsStackUp:New({ order = order }), "Stack up") end
	local place = me:NSLegsPlace() or me:NSLegsAt()
	me:NSLegsHeadFor(place, Geometry.Distance2D(me:NSLegsAt(), place) <= GIB.STAGE_REACH and GIB.GAIT.REST or GIB.GAIT.WALK)
	return self:Continue()
end

-- On patrol: round the loop one way, from its own stop (or the round it was appointed to), standing
-- PATROL_STOP at each corner; asked for a status report, it answers its leader, telling of any
-- contact; the alarm raised, it stacks up.
function LegsGuard:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	if order.alarm then return self:ChangeTo(LegsStackUp:New({ order = order }), "Stack up") end
	local now, at = me:Now(), me:NSLegsAt()
	order:Holding(me, false)
	self.stop = self.stop or order:AppointedTo(me) or order:PatrolOf(me:NSLegsPlace())
	order:OnPatrol(me, at, self.stop)
	if order:Asked(me) and order.leader then
		Legs.Speak(me, order, order.leader, me:NSLegsContact() and "CONTACT" or "ALL_CLEAR")
		order:Answered(me, at)
	end
	local stop = order.loop[self.stop]
	if Geometry.Distance2D(at, stop.point) <= GIB.STAGE_REACH then
		if stop.stop then
			self.stoppedAt = self.stoppedAt or now
			if now - self.stoppedAt < PATROL_STOP then
				me:NSLegsHeadFor(stop.point, GIB.GAIT.WALK)
				return self:Continue()
			end
		end
		self.stop, self.stoppedAt = self.stop % #order.loop + 1, nil
		stop = order.loop[self.stop]
	end
	me:NSLegsHeadFor(stop.point, GIB.GAIT.WALK)
	return self:Continue()
end

-- The alarm raised: to its spot by the exit, there staged, ready; contact, the squad engaged; on
-- its leader's word, at a run to where the guard was last heard from; stood down, back to holding,
-- or to patrol where it was appointed. Falling back, it evacuates.
function LegsStackUp:Update(me)
	local order = self.order
	if me:NSLegsOrder() ~= order then return self:Continue() end
	local fall = Legs.Evacuating(self)
	if fall then return fall end
	order:Holding(me, true)
	if not order.alarm then
		if order:AppointedTo(me) then return self:ChangeTo(LegsGuard:New({ order = order }), "Take over the patrol") end
		return self:ChangeTo(LegsHold:New({ order = order }), "Stand by")
	end
	if me:NSLegsContact() then order:Engage() end
	if order:Signalled() then
		me:NSLegsHeadFor(order.alarm.at, GIB.GAIT.RUN)
		return self:Continue()
	end
	local at, spot = me:NSLegsAt(), order:StackAt(me)
	if not spot or Geometry.Distance2D(at, spot) <= GIB.STAGE_REACH then
		order:Staged(me, me:Now())
		me:NSLegsHeadFor(spot or at, GIB.GAIT.REST)
	else
		me:NSLegsHeadFor(spot, GIB.GAIT.WALK)
	end
	return self:Continue()
end

Orders.Register({
	kind = "Occupy",
	action = LegsOccupy,
	awaiting = function(order) return order.alarm ~= nil and not order.routed and not order:Signalled() and not order:Engaged() end,
	underway = function(order) return order.alarm ~= nil and not order.routed end,
})
