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

-- A room 800 square about the origin, its door in the west wall (a doorway 128 wide through a
-- wall 32 thick), what its inside sees out through the doorway (a wedge widening four times as
-- fast as it goes out), and the map's word on a slot around a point: inside the room, or outside
-- it beyond the wall, not across it.
local DOOR_HALF, WALL, SLANT = 64, 32, 4

local function Seen(p)
	if p.x > -400 then return true end
	local out = -400 - WALL - p.x
	if out < 0 then return math.abs(p.y) < DOOR_HALF end -- in the wall: only its doorway
	return math.abs(p.y) < DOOR_HALF + out * SLANT
end

-- What a point in the room is worth to fight from: in the test, the nearer the east wall's
-- middle (a door the enemy would come by), the more.
local function Score(p) return -math.sqrt((p.x - 400) ^ 2 + p.y ^ 2) end

local ROOM = { center = { x = 0, y = 0, z = 0 }, lo = { x = -400, y = -400, z = 0 }, hi = { x = 400, y = 400, z = 0 },
	entry = { x = -400, y = 0, z = 0 }, seen = Seen, score = Score }

local function Inside(p) return p.x > ROOM.lo.x and p.x < ROOM.hi.x and p.y > ROOM.lo.y and p.y < ROOM.hi.y end

local function AdmitAt(around)
	local inside = Inside(around)
	return function(slot) if Inside(slot) == inside then return { x = slot.x, y = slot.y, z = slot.z } end return nil end
end

-- Five members on the grass west of the room, coming to its door.
local function Squad5()
	local squad = {}
	for i = 1, 5 do squad[i] = { x = -700 - (i % 2) * 60, y = -120 + i * 40, z = 0 } end
	return squad
end

local function Assaulting()
	local order = GroupIdentity.Assault(ROOM)
	local squad = Squad5()
	local places = order:Places(squad, SPACING, AdmitAt(ROOM.center), AdmitAt)
	return order, squad, places
end

T.test("the tuning of an assault is defined", function()
	for _, name in ipairs({ "ROOM_INSET", "STACK_REACH", "STACK_COVER", "BREACH_REACH", "BREACH_FUNNEL", "ENCIRCLE_RADIUS",
		"ENCIRCLE_BAND", "ENCIRCLE_MIN" }) do T.defined(GroupIdentity[name], name) end
end)

T.test("an assault fills its room: each a place inside, spread over the floor, none at the door", function()
	local _, _, places = Assaulting()
	T.eq(#places, 5, "one each")
	for i, place in ipairs(places) do
		T.eq(Inside(place), true, "inside: " .. i)
		T.eq(math.max(math.abs(place.x), math.abs(place.y)) <= 400 - GroupIdentity.ROOM_INSET + 0.001, true, "clear of the walls: " .. i)
		T.eq(Distance2D(place, ROOM.entry) >= 2 * SPACING, true, "clear of the doorway: " .. i)
	end
	HeldApart(places, 2 * SPACING)
	local deepest = 0
	for _, place in ipairs(places) do deepest = math.max(deepest, Distance2D(place, ROOM.entry)) end
	T.eq(deepest >= 800 - 2 * GroupIdentity.ROOM_INSET, true, "out to the far side: " .. deepest)
end)

T.test("an assault stages its squad around the entrance, outside and hidden from the room", function()
	local order, _, places = Assaulting()
	local staged = {}
	for i, place in ipairs(places) do
		local stage = order:StagingOf(place)
		T.eq(stage ~= nil, true, "a staging place: " .. i)
		T.eq(stage.x < ROOM.lo.x, true, "outside, beyond the wall: " .. i)
		T.eq(Seen(stage), false, "out of the room's sight through the doorway: " .. i)
		local cover = GroupIdentity.STACK_COVER
		for _, d in ipairs({ { cover, 0 }, { -cover, 0 }, { 0, cover }, { 0, -cover } }) do
			T.eq(Seen({ x = stage.x + d[1], y = stage.y + d[2], z = 0 }), false, "with a body's breadth to spare: " .. i)
		end
		T.eq(Distance2D(stage, ROOM.entry) <= GroupIdentity.STACK_REACH + 0.001, true, "around the entrance: " .. i)
		staged[i] = stage
	end
	HeldApart(staged, SPACING)
end)

T.test("an assault on a room with no word on what it sees, or on what a point is worth, is refused", function()
	local blind = { center = ROOM.center, lo = ROOM.lo, hi = ROOM.hi, entry = ROOM.entry, score = Score }
	T.eq(pcall(GroupIdentity.Assault, blind), false, "no seen")
	local unscored = { center = ROOM.center, lo = ROOM.lo, hi = ROOM.hi, entry = ROOM.entry, seen = Seen }
	T.eq(pcall(GroupIdentity.Assault, unscored), false, "no score")
end)

-- The side of the line in through the doorway a point is on: 1 left (north), -1 right, 0 on it.
local function SideOf(p)
	if math.abs(p.y - ROOM.entry.y) < GroupIdentity.BREACH_FUNNEL then return 0 end
	return p.y > ROOM.entry.y and 1 or -1
end

T.test("going in, each member takes an assault point by the entrance, off the line in, apart", function()
	local order, _, places = Assaulting()
	local points = {}
	for i, place in ipairs(places) do
		local point = order:BreachOf(place)
		T.eq(point ~= nil, true, "a point: " .. i)
		T.eq(Inside(point), true, "inside: " .. i)
		T.eq(Distance2D(point, ROOM.entry) <= GroupIdentity.BREACH_REACH + 0.001, true, "by the entrance: " .. i)
		T.eq(SideOf(point) ~= 0, true, "off the line in through the doorway: " .. i)
		points[i] = point
	end
	HeldApart(points, SPACING)
end)

T.test("the front of the stack takes the best point; then they fan out, alternating sides", function()
	local order, _, places = Assaulting()
	local ranked = {}
	for i, place in ipairs(places) do ranked[i] = i end
	table.sort(ranked, function(a, b)
		return Distance2D(order:StagingOf(places[a]), ROOM.entry) < Distance2D(order:StagingOf(places[b]), ROOM.entry)
	end)
	local best
	for _, place in ipairs(places) do
		local point = order:BreachOf(place)
		if not best or Score(point) > best then best = Score(point) end
	end
	T.eq(Score(order:BreachOf(places[ranked[1]])), best, "the front's is the best")
	for k = 2, #ranked do
		T.eq(SideOf(order:BreachOf(places[ranked[k]])) ~= SideOf(order:BreachOf(places[ranked[k - 1]])), true,
			"in turn, the other side: " .. k)
	end
end)

-- An enemy marked in the room where the squad comes in from the west: at its centre, its rear
-- (east), its front (west, by the door), its left (north) and its right (south).
local ENEMIES = {
	center = { x = 0, y = 0, z = 0 }, rear = { x = 300, y = 0, z = 0 }, front = { x = -260, y = 0, z = 0 },
	left = { x = 0, y = 300, z = 0 }, right = { x = 0, y = -300, z = 0 },
}

-- The widest gap in angle round enemy between the points, in radians.
local function WidestGap(enemy, points)
	local angles = {}
	for i, p in ipairs(points) do angles[i] = math.atan2(p.y - enemy.y, p.x - enemy.x) end
	table.sort(angles)
	local widest = angles[1] + 2 * math.pi - angles[#angles]
	for i = 2, #angles do widest = math.max(widest, angles[i] - angles[i - 1]) end
	return widest
end

-- The room cut to `half` each way about its middle (dev_3house's bench is 375), its door where it was.
local function Cut(half)
	local room = {}
	for k, v in pairs(ROOM) do room[k] = v end
	room.lo, room.hi = { x = -half, y = -half, z = 0 }, { x = half, y = half, z = 0 }
	return room
end

for _, half in ipairs({ 400, 375 }) do for where, enemy in pairs(ENEMIES) do
	T.test("with an enemy marked at the " .. where .. " of a room " .. 2 * half .. " square, the assault points encircle it", function()
		local room = Cut(half)
		room.enemy = enemy
		local order = GroupIdentity.Assault(room)
		local places = order:Places(Squad5(), SPACING, AdmitAt(ROOM.center), AdmitAt)
		local points = {}
		for i, place in ipairs(places) do
			local point = order:BreachOf(place)
			T.eq(point ~= nil, true, "a point: " .. i)
			T.eq(Inside(point), true, "in the room: " .. i)
			local d = Distance2D(point, enemy)
			T.eq(d >= GroupIdentity.ENCIRCLE_MIN - GroupIdentity.ENCIRCLE_BAND - 0.001
				and d <= GroupIdentity.ENCIRCLE_RADIUS + GroupIdentity.ENCIRCLE_BAND + 0.001, true, "on a ring round it: " .. i .. " at " .. d)
			points[i] = point
		end
		HeldApart(points, SPACING)
		T.eq(WidestGap(enemy, points) < math.pi, true, "all round it, no half of the ring empty: " .. WidestGap(enemy, points))
	end)
end end

T.test("encircling, the front of the stack goes the furthest round", function()
	local room = {}
	for k, v in pairs(ROOM) do room[k] = v end
	room.enemy = ENEMIES.center
	local order = GroupIdentity.Assault(room)
	local places = order:Places(Squad5(), SPACING, AdmitAt(ROOM.center), AdmitAt)
	local front, furthest
	for i, place in ipairs(places) do
		if not front or Distance2D(order:StagingOf(place), ROOM.entry) < Distance2D(order:StagingOf(places[front]), ROOM.entry) then front = i end
		if not furthest or Distance2D(order:BreachOf(place), ROOM.entry) > Distance2D(order:BreachOf(places[furthest]), ROOM.entry) then furthest = i end
	end
	T.eq(front, furthest, "the front")
end)

T.test("going in, the room is clear once all the living hold their points and none has met the enemy since", function()
	local order = Assaulting()
	T.eq(order:AllBreached(), false, "none in")
	for i = 1, 4 do order:Breached("m" .. i, i) end
	T.eq(order:AllBreached(), false, "four of five")
	order:Casualty("m5")
	T.eq(order:AllBreached(), true, "all the living")
	T.eq(order:QuietSince(), 4, "since the last went in")
	order:Contact(9)
	T.eq(order:QuietSince(), 9, "since the last contact")
end)

T.test("the member at the front of the stack, nearest the door, goes deepest", function()
	local order, _, places = Assaulting()
	local front, deepest
	for i, place in ipairs(places) do
		local stage = order:StagingOf(place)
		if not front or Distance2D(stage, ROOM.entry) < Distance2D(order:StagingOf(places[front]), ROOM.entry) then front = i end
		if not deepest or Distance2D(place, ROOM.entry) > Distance2D(places[deepest], ROOM.entry) then deepest = i end
	end
	T.eq(front, deepest, "the front goes deepest")
end)

T.test("an assault is placed around its door as well as its room, or refused", function()
	T.eq(pcall(GroupIdentity.Assault(ROOM).Places, GroupIdentity.Assault(ROOM), Squad5(), SPACING, AdmitAt(ROOM.center)), false,
		"no word on the ground outside")
end)

T.test("an assault waits staged until it is signalled, once", function()
	local order = Assaulting()
	T.eq(order:AllStaged(), false, "none staged yet")
	for i = 1, 4 do order:Staged("m" .. i, 0) end
	T.eq(order:AllStaged(), false, "four of five")
	order:Casualty("m5")
	T.eq(order:AllStaged(), true, "all the living")
	T.eq(order:Signalled(), false, "not yet signalled")
	T.eq(order:Signal(), true, "signalled")
	T.eq(order:Signal(), false, "once")
	T.eq(order:Signalled(), true)
end)

T.test("a muster has no staging", function()
	local order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	local places = order:Places(Crowd(2), SPACING)
	T.eq(order:StagingOf(places[1]), nil, "none")
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
