-- nextsoldier.behavior.gib_behaviors: what GroupIdentityBehavior does under its root, as L4D2's
-- legs do beside its survivors' behaviour: an order's action, and under it its squad's mode's.
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors
local MODE, GAIT = GroupIdentity.MODE, GIB.GAIT

for _, name in ipairs({ "PATROL_RADIUS", "PATROL_REST", "WANDER_RADIUS", "WANDER_REST", "EVACUATE_DISTANCE",
	"REST_RADIUS", "EXIT_CLEARANCE", "STAY_CLOSE_RANGE", "STAY_CLOSE_RADIUS", "REGROUP_RANGE", "REGROUP_NEAR" }) do
	T.defined(GIB[name], name)
end

T.eq(type(GIB.FALL_BACK_LINE), "string", "the line its leader calls")

local function Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- A member as its legs see it: told an order and its place in it, asked to sense its group each
-- update, and heading where they say; where it stands, its clock, its draws (0 to 1, in turn),
-- the map's word on a spot (admit) and the seats it finds are the test's.
local function Member(order, place)
	local me = { order = order, place = place or { x = 100, y = 0, z = 0 }, sensed = 0, headed = 0, now = 0,
		draws = { 0.5 }, drawn = 0, refuse = function() return false end, seats = {}, asked = 0, said = {} }
	function me:NSLegsOrder() return self.order end
	function me:NSLegsSense() self.sensed = self.sensed + 1 end
	function me:NSLegsPlace() return self.place end
	function me:NSLegsAt() return self.at or self.place end
	function me:Now() return self.now end
	function me:NSLegsDraw()
		self.drawn = self.drawn + 1
		return self.draws[(self.drawn - 1) % #self.draws + 1]
	end
	function me:NSLegsAdmit()
		return function(spot) if self.refuse(spot) then return nil end return spot end
	end
	function me:NSLegsSeats() self.asked = self.asked + 1 return self.seats end
	function me:NSLegsHeadFor(spot, gait) self.headed, self.spot, self.gait = self.headed + 1, spot, gait end
	function me:NSLegsSay(line) self.said[#self.said + 1] = line end
	function me:NSLegsDanger() return self.danger end
	return me
end

local function Muster() return GroupIdentity.Muster({ x = 0, y = 0, z = 0 }) end

-- A member on its order, and the action its squad's mode puts under the order's.
local function OnOrder(order, place)
	local me = Member(order, place)
	local orders = GIB.LegsAtEase:New():Update(me).action
	return me, orders:InitialContainedAction(me), orders
end

T.test("its root is the engine's own, waiting first", function()
	local given
	local engine = { GroupIdentityBehavior = function(config) given = config return "root" end }
	GroupIdentity.InitialAction(engine)
	T.eq(given.initial.name, "LegsWait", "it starts by waiting")
end)

T.test("with no group to be part of, it waits", function()
	T.eq(GIB.LegsWait:New():Update({}).type, Action.CONTINUE, "stays")
end)

T.test("at ease, a member stays so and senses its group", function()
	local me = Member(nil)
	T.eq(GIB.LegsAtEase:New():Update(me).type, Action.CONTINUE, "stays")
	T.eq(me.sensed, 1, "sensed")
end)

T.test("told an order, a member takes the action for it", function()
	local result = GIB.LegsAtEase:New():Update(Member(Muster()))
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.name, "LegsMuster", "to muster")
	local fallBack = GroupIdentity.FallBack({ x = 0, y = 0, z = 0 }, { x = 500, y = 0, z = 0 })
	T.eq(GIB.LegsAtEase:New():Update(Member(fallBack)).action.name, "LegsFallBack", "or fall back")
end)

T.test("on its order, a member keeps to it and senses its group, heading nowhere itself", function()
	local me, _, orders = OnOrder(Muster())
	T.eq(orders:Update(me).type, Action.CONTINUE, "stays")
	T.eq(me.sensed, 2, "each update")
	T.eq(me.headed, 0, "its squad's mode heads")
end)

T.test("a new order, even of the same kind, replaces the one it is on", function()
	local me, _, orders = OnOrder(Muster())
	me.order = Muster()
	local result = orders:Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.order, me.order, "on the new one")
end)

T.test("dissolved, a member goes back to ease, and its mode heads nowhere", function()
	local me, mode, orders = OnOrder(Muster())
	me.order = nil
	T.eq(mode:Update(me).type, Action.CONTINUE, "its order's action changes it")
	T.eq(me.headed, 0, "not for the order it no longer has")
	T.eq(orders:Update(me).action.name, "LegsAtEase", "at ease")
end)

local MODE_NAMES = {
	[MODE.STATIONARY] = "LegsStationary",
	[MODE.ALERT] = "LegsPatrol",
	[MODE.CAUTIOUS] = "LegsWander",
	[MODE.PANIC] = "LegsEvacuate",
	[MODE.CLOSE] = "LegsStayClose",
}

T.test("an order's action holds its squad's mode's", function()
	for mode, name in pairs(MODE_NAMES) do
		local order = Muster()
		order:SetMode(mode)
		local _, action = OnOrder(order)
		T.eq(action.name, name, MODE[mode])
	end
end)

T.test("told its squad's new mode, a member changes to that mode's action", function()
	local order = Muster()
	local me, action = OnOrder(order)
	order:SetMode(MODE.CAUTIOUS)
	local result = action:Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.name, "LegsWander", "to wander")
	T.eq(me.headed, 0, "heading nowhere on the old one")
end)

T.test("stationary, a member rests at the seat nearest its place", function()
	local me, action = OnOrder(Muster(), { x = 100, y = 0, z = 0 })
	me.seats = { { x = 300, y = 0, z = 0 }, { x = 120, y = 10, z = 0 } }
	action:Update(me)
	T.eq(me.spot, me.seats[2], "the nearer")
	T.eq(me.gait, GAIT.REST, "to rest")
	action:Update(me)
	T.eq(me.asked, 1, "found once and kept")
end)

T.test("stationary, members of a squad do not share a seat", function()
	local order = Muster()
	local seats = { { x = 120, y = 0, z = 0 }, { x = 400, y = 0, z = 0 } }
	local first, firstAction = OnOrder(order, { x = 100, y = 0, z = 0 })
	local second, secondAction = OnOrder(order, { x = 110, y = 0, z = 0 })
	first.seats, second.seats = seats, { { x = 120, y = 0, z = 0 }, { x = 400, y = 0, z = 0 } }
	firstAction:Update(first)
	secondAction:Update(second)
	T.eq(first.spot.x, 120, "the first takes the near one")
	T.eq(second.spot.x, 400, "the second the one left")
end)

T.test("stationary with no seat near, a member rests at its place", function()
	local me, action = OnOrder(Muster())
	action:Update(me)
	T.eq(me.spot, me.place, "its place")
	T.eq(me.gait, GAIT.REST, "resting")
end)

T.test("alert, a member patrols round the squad's point on its own side, a spot at a time", function()
	local order = Muster()
	order:SetMode(MODE.ALERT)
	local me, action = OnOrder(order, { x = 100, y = 0, z = 0 })
	me.draws = { 0.1, 0.9, 0.6 }
	action:Update(me)
	local first = me.spot
	T.eq(Distance(first, order.point) <= GIB.PATROL_RADIUS + 0.001, true, "within the patrol's reach")
	T.eq(first.x > 0, true, "on its own side of the point")
	T.eq(me.gait, GAIT.WALK, "walking")
	me.now = GIB.PATROL_REST - 0.1
	action:Update(me)
	T.eq(me.spot, first, "rests there")
	me.now = GIB.PATROL_REST
	action:Update(me)
	T.eq(me.spot ~= first, true, "then the next")
end)

T.test("cautious, a member wanders near its own place, resting longer", function()
	local order = Muster()
	order:SetMode(MODE.CAUTIOUS)
	local me, action = OnOrder(order, { x = 100, y = 0, z = 0 })
	me.draws = { 0.3, 0.8 }
	action:Update(me)
	local first = me.spot
	T.eq(Distance(first, me.place) <= GIB.WANDER_RADIUS + 0.001, true, "near its place")
	T.eq(me.gait, GAIT.WALK, "walking")
	me.now = GIB.WANDER_REST - 0.1
	action:Update(me)
	T.eq(me.spot, first, "rests there")
	T.eq(GIB.WANDER_REST > GIB.PATROL_REST, true, "longer than a patrol's")
end)

T.test("where the map refuses every spot it draws, a member keeps to its place", function()
	local order = Muster()
	order:SetMode(MODE.CAUTIOUS)
	local me, action = OnOrder(order)
	me.refuse = function(spot) return spot ~= me.place end
	action:Update(me)
	T.eq(me.spot, me.place, "its place")
end)

T.test("a member with no place heads nowhere", function()
	for mode in pairs(MODE_NAMES) do
		local order = Muster()
		order:SetMode(mode)
		local me, action = OnOrder(order)
		me.place = nil
		action:Update(me)
		T.eq(me.spot, nil, MODE[mode])
	end
end)

local function Panicked(exits)
	local order = GroupIdentity.FallBack({ x = 0, y = 0, z = 0 }, { x = -500, y = 0, z = 0 })
	order:SetMode(MODE.PANIC)
	order:SetExits(exits)
	return order
end

T.test("evacuating, a member runs out by the way out furthest from the threat", function()
	local me, action = OnOrder(Panicked({ { x = -300, y = 50, z = 0 }, { x = 400, y = -50, z = 0 } }), { x = 50, y = 0, z = 0 })
	action:Update(me)
	T.eq(me.spot.x > 400, true, "past the far way out, out of the room")
	T.near(math.sqrt((me.spot.x - 400) ^ 2 + (me.spot.y + 50) ^ 2), GIB.EXIT_CLEARANCE, 0.001, "clear of it")
	T.eq(me.gait, GAIT.RUN, "running")
end)

T.test("evacuating where the map refuses the ground past a way out, a member makes for the way out itself", function()
	local me, action = OnOrder(Panicked({ { x = 400, y = 0, z = 0 } }), { x = 50, y = 0, z = 0 })
	me.refuse = function(spot) return spot.x > 400 end
	action:Update(me)
	T.eq(me.spot.x, 400, "the way out")
end)

T.test("evacuating, a member leaves by the way out from where it stands, not its place", function()
	local exits = { { x = 0, y = 600, z = 0 }, { x = 0, y = -600, z = 0 } }
	local me, action = OnOrder(Panicked(exits), { x = 0, y = 500, z = 0 })
	me.at = { x = 0, y = -500, z = 0 }
	action:Update(me)
	T.eq(me.spot.y < -600, true, "out by the one beside it")
end)

T.test("evacuating with no way out known, a member runs straight away from the threat", function()
	local me, action = OnOrder(Panicked(nil), { x = 50, y = 0, z = 0 })
	action:Update(me)
	T.eq(me.spot.x > me.place.x, true, "further from the threat than it stands")
	T.eq(me.gait, GAIT.RUN, "running")
end)

T.test("evacuating, a member keeps to the way out it chose", function()
	local exits = { { x = 400, y = 0, z = 0 } }
	local me, action = OnOrder(Panicked(exits), { x = 50, y = 0, z = 0 })
	action:Update(me)
	local first = me.spot
	exits[1] = { x = 900, y = 0, z = 0 }
	action:Update(me)
	T.eq(me.spot, first, "the first")
end)

-- A squad of count members staying close, the first its leader, each standing where at says.
local function Close(count, at)
	local order = Muster()
	order:SetMode(MODE.CLOSE)
	local squad = {}
	for i = 1, count do
		local me, action = OnOrder(order, { x = i * 50, y = 0, z = 0 })
		me.at = at[i]
		squad[i] = { me = me, action = action }
	end
	order:Lead(squad[1].me)
	return order, squad
end

T.test("staying close, a member near its leader stays where it stands", function()
	local _, squad = Close(2, { { x = 0, y = 0, z = 0 }, { x = 10, y = 20, z = 0 } })
	squad[2].action:Update(squad[2].me)
	T.eq(squad[2].me.spot, squad[2].me.at, "where it stands")
	T.eq(squad[2].me.gait, GAIT.WALK, "walking")
end)

T.test("staying close, a member too far from its leader runs to it, on its own side", function()
	local far = GIB.STAY_CLOSE_RANGE * 3
	local _, squad = Close(2, { { x = 0, y = 0, z = 0 }, { x = far, y = 0, z = 0 } })
	local me = squad[2].me
	me.draws = { 0.2, 0.7 }
	squad[2].action:Update(me)
	T.eq(Distance(me.spot, { x = 0, y = 0 }) <= GIB.STAY_CLOSE_RADIUS + 0.001, true, "near its leader")
	T.eq(me.spot.x >= 0, true, "on its side")
	T.eq(me.gait, GAIT.RUN, "running")
end)

T.test("staying close, the leader keeps to its place; with no leader, each does", function()
	local order, squad = Close(2, { { x = 0, y = 0, z = 0 }, { x = 5000, y = 0, z = 0 } })
	squad[1].action:Update(squad[1].me)
	T.eq(squad[1].me.spot, squad[1].me.place, "the leader")
	order:Leave(squad[1].me)
	squad[2].action:Update(squad[2].me)
	T.eq(squad[2].me.spot, squad[2].me.place, "leaderless")
end)

T.test("a member strayed far from its squad's point regroups, running for its place", function()
	for _, mode in ipairs({ MODE.STATIONARY, MODE.ALERT, MODE.CAUTIOUS }) do
		local order = Muster()
		order:SetMode(mode)
		local me, action = OnOrder(order)
		me.at = { x = GIB.REGROUP_RANGE + 1, y = 0, z = 0 }
		local result = action:Update(me)
		T.eq(result.type, Action.SUSPEND_FOR, MODE[mode] .. " suspends")
		T.eq(result.action.name, "LegsRegroup", MODE[mode] .. " for regroup")
		T.eq(result.action:Update(me).type, Action.CONTINUE, "regrouping")
		T.eq(me.spot, me.place, "for its place")
		T.eq(me.gait, GAIT.RUN, "running")
	end
end)

T.test("evacuating or staying close, a member does not regroup on its squad's point", function()
	for _, mode in ipairs({ MODE.PANIC, MODE.CLOSE }) do
		local order = Muster()
		order:SetMode(mode)
		local me, action = OnOrder(order)
		me.at = { x = GIB.REGROUP_RANGE * 2, y = 0, z = 0 }
		T.eq(action:Update(me).type, Action.CONTINUE, MODE[mode])
	end
end)

T.test("regrouped near its place, or its squad evacuating, a member's regroup is done", function()
	local order = Muster()
	local me = Member(order)
	local regroup = GIB.LegsRegroup:New({ order = order })
	me.at = { x = me.place.x + GIB.REGROUP_NEAR - 1, y = 0, z = 0 }
	T.eq(regroup:Update(me).type, Action.DONE, "near its place")
	me.at = { x = 5000, y = 0, z = 0 }
	order:SetMode(MODE.PANIC)
	T.eq(regroup:Update(me).type, Action.DONE, "evacuating")
end)

-- A full squad of count members on order, the first its leader, and its leader's order action.
local function Squad(count)
	local order = Muster()
	local members = {}
	for i = 1, count do members[i] = { x = i * 80, y = 0, z = 0 } end
	order:Places(members, 72)
	local leader, _, orders = OnOrder(order)
	order:Lead(leader)
	return order, leader, orders
end

T.test("a full squad's leader, its casualties heavy, calls the fall back once and its squad evacuates", function()
	local order, leader, orders = Squad(4)
	order:Casualty({})
	orders:Update(leader)
	T.eq(#leader.said, 0, "not yet")
	order:Casualty({})
	orders:Update(leader)
	T.eq(leader.said[1], GIB.FALL_BACK_LINE, "called")
	T.eq(order.mode, MODE.PANIC, "evacuating")
	orders:Update(leader)
	T.eq(#leader.said, 1, "once")
end)

T.test("a member who does not lead never calls the fall back", function()
	local order, leader = Squad(4)
	local me, _, orders = OnOrder(order)
	order:Casualty({})
	order:Casualty({})
	orders:Update(me)
	T.eq(#me.said, 0, "not its call")
	T.eq(order.mode, MODE.STATIONARY, "nor its squad's")
	T.eq(leader ~= me, true, "another leads")
end)

T.test("a squad's leader told of a danger near its point calls the fall back once, the squad evacuating away from it", function()
	local order, leader, orders = Squad(4)
	leader.danger = { x = 300, y = 0, z = 0 }
	orders:Update(leader)
	T.eq(leader.said[1], GIB.FALL_BACK_LINE, "called")
	T.eq(order.mode, MODE.PANIC, "evacuating")
	T.eq(order.from, leader.danger, "away from it")
	orders:Update(leader)
	T.eq(#leader.said, 1, "once")
end)

T.test("a member who does not lead is not the one to call a danger", function()
	local order = Squad(4)
	local me, _, orders = OnOrder(order)
	me.danger = { x = 300, y = 0, z = 0 }
	orders:Update(me)
	T.eq(#me.said, 0, "not its call")
	T.eq(order.mode, MODE.STATIONARY, "nor its squad's")
end)

T.finish()
