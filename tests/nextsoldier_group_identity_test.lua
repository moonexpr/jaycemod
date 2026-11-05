-- nextsoldier.behavior.group_identity: the tree beside a soldier's main one, as L4D2's legs
-- beside its survivors' behaviour. The engine runs it on a server (native/nextsoldier).
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local GroupIdentity = nextsoldier.behavior.group_identity

T.test("its root is the engine's own, holding what it does first", function()
	local given
	local engine = { GroupIdentityBehavior = function(config) given = config return { name = "root" } end }
	local root = GroupIdentity.InitialAction(engine)
	T.eq(root.name, "root", "what the engine made")
	T.eq(given.initial.name, "LegsWait", "it starts by waiting")
end)

T.test("with no group to be part of, it waits", function()
	local wait = GroupIdentity.LegsWait:New()
	T.eq(wait:Update({}).type, Action.CONTINUE, "stays")
end)

T.test("it is given to a soldier beside its main tree", function()
	local placed
	local engine = {
		GroupIdentityBehavior = function() return "root" end,
		InsertGroup = function(ent, action, me) placed = { ent, action, me } end,
	}
	GroupIdentity.Give("ent", engine, "me")
	T.eq(placed[1], "ent", "on it")
	T.eq(placed[2], "root", "its root")
	T.eq(placed[3], "me", "told to whoever it is told to")
end)

T.test("where the binary lacks it, a soldier goes without", function()
	T.eq(GroupIdentity.Give("ent", {}, "me"), false, "nothing given")
	T.eq(GroupIdentity.Give("ent", nil, "me"), false, "nor with no engine")
end)

T.test("it can be started on what it is given, for a soldier with no other tree", function()
	local given
	local engine = { GroupIdentityBehavior = function(config) given = config return "root" end }
	GroupIdentity.InitialAction(engine, GroupIdentity.LegsAtEase:New())
	T.eq(given.initial.name, "LegsAtEase", "what it was given")
end)

local SPACING = 72

local function Crowd(count)
	local crowd = {}
	for i = 1, count do crowd[i] = { x = i * 10, y = -i * 7, z = 5 } end
	return crowd
end

local function Distance2D(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function HeldApart(places, spacing)
	for i = 1, #places do
		for j = i + 1, #places do
			T.eq(Distance2D(places[i], places[j]) >= spacing - 0.001, true, "places " .. i .. " and " .. j .. " apart")
		end
	end
end

local ORDERS = {
	Muster = GroupIdentity.Muster({ x = 500, y = 200, z = 40 }),
	FallBack = GroupIdentity.FallBack({ x = 500, y = 200, z = 40 }, { x = 900, y = 200, z = 40 }),
}

for kind, order in pairs(ORDERS) do
	T.test(kind .. " gives each member a place of its own, its spacing apart, at the order's height", function()
		for _, count in ipairs({ 1, 2, 6, 7, 8, 20 }) do
			local places = order:Places(Crowd(count), SPACING)
			T.eq(#places, count, "one each")
			HeldApart(places, SPACING)
			for _, place in ipairs(places) do T.eq(place.z, 40, "at its height") end
		end
	end)

	T.test(kind .. " has a member's place near it where it can", function()
		local members = { { x = 0, y = -5000, z = 0 }, { x = 0, y = 5000, z = 0 } }
		local places = order:Places(members, SPACING)
		T.eq(places[1].y <= places[2].y, true, "the one to the south stays south of the one to the north")
	end)

	T.test(kind .. " has a straggler choose first, so it keeps to its own side", function()
		local members = { { x = 500, y = 200, z = 40 }, { x = 530, y = 200, z = 40 }, { x = 500, y = 230, z = 40 }, { x = 500, y = 5000, z = 40 } }
		local places = order:Places(members, SPACING)
		for i = 1, 3 do
			T.eq(places[4].y >= places[i].y, true, "north of the crowd's place " .. i)
		end
	end)

	-- A wall along x = 520: only ground to its west is a place.
	local function WestOfWall(slot)
		if slot.x >= 520 then return nil end
		return { x = slot.x, y = slot.y, z = slot.z }
	end

	T.test(kind .. " leaves out what the map refuses, and still places everyone, spaced apart", function()
		for _, count in ipairs({ 1, 4, 7, 12 }) do
			local places = order:Places(Crowd(count), SPACING, WestOfWall)
			local placed = 0
			for i = 1, count do
				if places[i] then
					placed = placed + 1
					T.eq(places[i].x < 520, true, "no place past the wall")
				end
			end
			T.eq(placed, count, "everyone has a place")
			local list = {}
			for i = 1, count do list[i] = places[i] end
			HeldApart(list, SPACING)
		end
	end)

	T.test(kind .. " takes a place where the map puts it", function()
		local places = order:Places(Crowd(3), SPACING, function(slot) return { x = slot.x, y = slot.y, z = -99 } end)
		for i = 1, 3 do T.eq(places[i].z, -99, "on the ground the map found") end
	end)

	T.test(kind .. " leaves a member without a place where the map has no room near", function()
		local places = order:Places(Crowd(3), SPACING, function() return nil end)
		for i = 1, 3 do T.eq(places[i], nil, "none") end
	end)

	T.test(kind .. " has no places for nobody", function()
		T.eq(#order:Places({}, SPACING), 0, "none")
	end)
end

T.test("a muster fills from its point outward", function()
	local places = ORDERS.Muster:Places(Crowd(1), SPACING)
	T.eq(places[1].x, 500, "the first on the point")
	T.eq(places[1].y, 200, "the first on the point")
end)

T.test("a muster stays gathered: none further out than it needs for its number", function()
	for _, place in ipairs(ORDERS.Muster:Places(Crowd(7), SPACING)) do
		T.eq(Distance2D(place, { x = 500, y = 200 }) <= SPACING + 0.001, true, "the point and the ring around it")
	end
end)

T.test("a fall back forms across the way from the threat, nobody nearer it than the point", function()
	for _, place in ipairs(ORDERS.FallBack:Places(Crowd(8), SPACING)) do
		T.eq(place.x <= 500 + 0.001, true, "on the point's far side from the threat")
	end
end)

T.test("a fall back onto the threat has no way to fall: there is no such order", function()
	T.eq(GroupIdentity.FallBack({ x = 1, y = 2, z = 3 }, { x = 1, y = 2, z = 90 }), nil, "no direction across the ground")
end)

-- A member as its legs see it: told an order, and asked to sense its group each update.
local function Member(order)
	local me = { order = order, sensed = 0, headed = 0 }
	function me:NSLegsOrder() return self.order end
	function me:NSLegsSense() self.sensed = self.sensed + 1 end
	function me:NSLegsHeadForPlace() self.headed = self.headed + 1 end
	return me
end

T.test("on its order, a member heads for its place each update; at ease, it does not", function()
	local me = Member(ORDERS.Muster)
	local action = GroupIdentity.LegsAtEase:New():Update(me).action
	T.eq(me.headed, 0, "not while at ease")
	action:Update(me)
	action:Update(me)
	T.eq(me.headed, 2, "each update on it")
end)

T.test("at ease, a member stays so and senses its group", function()
	local me = Member(nil)
	T.eq(GroupIdentity.LegsAtEase:New():Update(me).type, Action.CONTINUE, "stays")
	T.eq(me.sensed, 1, "sensed")
end)

T.test("told an order, a member takes the action for it", function()
	local result = GroupIdentity.LegsAtEase:New():Update(Member(ORDERS.Muster))
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.name, "LegsMuster", "to muster")
	T.eq(GroupIdentity.LegsAtEase:New():Update(Member(ORDERS.FallBack)).action.name, "LegsFallBack", "or fall back")
end)

T.test("on its order, a member keeps to it and senses its group", function()
	local me = Member(ORDERS.Muster)
	local action = GroupIdentity.LegsAtEase:New():Update(me).action
	T.eq(action:Update(me).type, Action.CONTINUE, "stays")
	T.eq(me.sensed, 2, "each update")
end)

T.test("a new order, even of the same kind, replaces the one it is on", function()
	local me = Member(ORDERS.Muster)
	local action = GroupIdentity.LegsAtEase:New():Update(me).action
	me.order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	local result = action:Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.order, me.order, "on the new one")
end)

T.test("dissolved, a member goes back to ease", function()
	local me = Member(ORDERS.FallBack)
	local action = GroupIdentity.LegsAtEase:New():Update(me).action
	me.order = nil
	T.eq(action:Update(me).action.name, "LegsAtEase", "at ease")
end)

local ENT = { GetClass = function() return "player" end }

T.test("the debug layer shows both trees, the group's after the main's", function()
	local npc = Action.DebugNpc(ENT, function() return { { name = "Main", depth = 1 } } end, function()
		return { { name = "GroupIdentityBehavior", depth = 1 }, { name = "LegsWait", depth = 2 } }
	end)
	local _, frames = npc:Stack()
	T.eq(#frames, 3, "all of them")
	T.eq(frames[1].name, "Main", "its main tree first")
	T.eq(frames[3].name, "LegsWait", "then the group's")
end)

T.test("a change in the group's tree is logged as one in its main's is", function()
	local legs = "LegsWait"
	local logged = {}
	local npc = Action.DebugNpc(ENT, function() return { { name = "Main", depth = 1 } } end, function()
		return { { name = legs, depth = 1 } }
	end)
	npc:Watch({ Event = function(_, text) logged[#logged + 1] = text end })
	npc:Stack()
	legs = "LegsFollow"
	npc:Stack()
	T.eq(logged[2]:find("LegsFollow", 1, true) ~= nil, true, "what it went to")
end)

T.test("an engine behaviour counts as empty by its main tree alone", function()
	local engine = {
		Stack = function() return { { name = "Root", depth = 1 } } end,
		GroupStack = function() return { { name = "GroupIdentityBehavior", depth = 1 }, { name = "LegsWait", depth = 2 } } end,
	}
	T.eq(Action.EngineBehavior(ENT, "first", "actor", "KIND", engine):IsEmpty(), true, "the group's tree does not keep it going")
end)

T.finish()
