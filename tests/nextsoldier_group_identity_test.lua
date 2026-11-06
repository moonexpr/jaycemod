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
	GroupIdentity.InitialAction(engine, nextsoldier.behavior.gib_behaviors.LegsAtEase:New())
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

T.test("a muster's last ring, partly filled, faces the members it takes in", function()
	local point = { x = 500, y = 200, z = 40 }
	local fromSouth = {}
	for i = 1, 5 do fromSouth[i] = { x = 400 + i * 40, y = -300, z = 40 } end
	for _, place in ipairs(GroupIdentity.Muster(point):Places(fromSouth, SPACING)) do
		T.eq(place.y <= point.y + 0.001, true, "on the members' side of the point: " .. place.x .. "," .. place.y)
	end
	local fromNorth = {}
	for i = 1, 5 do fromNorth[i] = { x = 400 + i * 40, y = 700, z = 40 } end
	for _, place in ipairs(GroupIdentity.Muster(point):Places(fromNorth, SPACING)) do
		T.eq(place.y >= point.y - 0.001, true, "and from the north, the north: " .. place.x .. "," .. place.y)
	end
end)

-- Whether segments ab and cd cross, apart from touching at an end.
local function Cross(a, b, c, d)
	local function Side(p, q, r) return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) end
	return Side(a, b, c) * Side(a, b, d) < 0 and Side(c, d, a) * Side(c, d, b) < 0
end

T.test("no two members' ways to their places cross", function()
	-- five at a spawn room's starts, west and south-west of the muster's point, as on dev_3house
	local members = { { x = -224, y = -216, z = 0 }, { x = -224, y = -72, z = 0 }, { x = -224, y = 72, z = 0 },
		{ x = -224, y = 216, z = 0 }, { x = -128, y = -216, z = 0 } }
	local places = GroupIdentity.Muster({ x = 0, y = 0, z = 0 }):Places(members, SPACING)
	for i = 1, #members do
		for j = i + 1, #members do
			T.eq(Cross(members[i], places[i], members[j], places[j]), false, "members " .. i .. " and " .. j)
		end
	end
end)

T.test("a squad coming in single file sends its front deepest, so none stops in the way of those behind", function()
	local file = {}
	for i = 1, 5 do file[i] = { x = -228 - i * SPACING, y = 0, z = 0 } end -- member 1 at the front
	local places = GroupIdentity.Muster({ x = 0, y = 0, z = 0 }):Places(file, SPACING)
	for i = 2, #file do
		T.eq(places[1].x >= places[i].x, true, "the front member's place is deepest: member " .. i .. "'s is not past it")
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

-- The squad's mode: one whole number on its order, what its members do about their places.
local MODE = GroupIdentity.MODE

T.test("a squad's mode is a whole number, stationary unless it is told otherwise", function()
	T.eq(MODE.STATIONARY .. MODE.ALERT .. MODE.CAUTIOUS .. MODE.PANIC .. MODE.CLOSE, "01234", "its numbers")
	local order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	T.eq(order.mode, MODE.STATIONARY, "stationary at first")
	order:SetMode(MODE.PANIC)
	T.eq(order.mode, MODE.PANIC, "told")
	T.eq(pcall(order.SetMode, order, 9), false, "no such mode")
end)

T.defined(GroupIdentity.CASUALTY_SHARE, "CASUALTY_SHARE")

-- An order placing count members, led by the first given it.
local function Squad(count)
	local order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	local members = Crowd(count)
	order:Places(members, SPACING)
	order:Lead(members[1])
	return order, members
end

-- The casualties a squad of count takes before they are heavy.
local function Heavy(count) return math.ceil(count * GroupIdentity.CASUALTY_SHARE) end

T.test("a full squad's casualties are heavy once it has lost its share of those it placed", function()
	local order, members = Squad(6)
	for i = 2, Heavy(6) do order:Casualty(members[i]) end
	T.eq(order:HeavyCasualties(), false, "one short")
	order:Casualty(members[Heavy(6) + 1])
	T.eq(order:HeavyCasualties(), true, "heavy")
end)

T.test("a squad with no leader, or of one, is no full squad: its casualties are never heavy", function()
	local order, members = Squad(4)
	order:Leave(members[1])
	for i = 2, 4 do order:Casualty(members[i]) end
	T.eq(order:HeavyCasualties(), false, "leaderless")
	local alone = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	local me = { x = 0, y = 0, z = 0 }
	alone:Places({ me }, SPACING)
	alone:Lead(me)
	alone:Casualty({})
	T.eq(alone:HeavyCasualties(), false, "alone")
end)

T.test("its leader lost, a squad has none", function()
	local order, members = Squad(3)
	order:Casualty(members[1])
	T.eq(order.leader, nil, "none")
end)

T.test("a squad routs once, on heavy casualties, and evacuates", function()
	local order, members = Squad(4)
	T.eq(order:Rout(), false, "not whole")
	for i = 2, Heavy(4) + 1 do order:Casualty(members[i]) end
	T.eq(order:Rout(), true, "routed")
	T.eq(order.mode, MODE.PANIC, "evacuating")
	order:SetMode(MODE.STATIONARY)
	T.eq(order:Rout(), false, "once")
end)

T.test("a squad's members take seats apart: the nearest one no other holds", function()
	local order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	local a, b = {}, {}
	local seats = function() return { { x = 10, y = 0, z = 0 }, { x = 200, y = 0, z = 0 } } end
	T.eq(order:Seat(a, seats(), { x = 0, y = 0, z = 0 }).x, 10, "the nearest")
	T.eq(order:Seat(b, seats(), { x = 0, y = 0, z = 0 }).x, 200, "the one left")
	T.eq(order:Seat(a, seats(), { x = 0, y = 0, z = 0 }).x, 10, "its own again")
	T.eq(order:Seat({}, seats(), { x = 0, y = 0, z = 0 }), nil, "none left")
	order:Leave(b)
	T.eq(order:Seat({}, seats(), { x = 0, y = 0, z = 0 }).x, 200, "freed as it leaves")
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

T.test("a squad endangered evacuates away from the danger, once", function()
	local order = Squad(4)
	local danger = { x = 300, y = 0, z = 0 }
	T.eq(order:Endanger(danger), true, "endangered")
	T.eq(order.mode, MODE.PANIC, "evacuating")
	T.eq(order.from, danger, "away from it")
	T.eq(order:Endanger({ x = 0, y = 300, z = 0 }), false, "once")
	T.eq(order:Rout(), false, "its fall back called already")
end)

T.finish()
