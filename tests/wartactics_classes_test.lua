-- wartactics.classes (.devtools/bin/classes.py and places.py the reference).
-- The stages over the spaces are plain Lua, tested in both passes; the
-- gradient and the junctions walk the incursion's graph.paths, native only.
local T = dofile("tests/harness.lua")
local Classes = wartactics.classes
local Incursion = wartactics.incursion

local RED, BLU = "RED", "BLU"
local STEP, CELL = 400, 100

-- A partition by hand: rooms at (x, y) * STEP, a single area each (its id),
-- joined by Door(a, b) or through a Corridor(pid, a, b).
local function Map()
	local map = { rooms = {}, passages = {}, of = {}, passageOf = {}, byId = {}, seals = {} }
	function map:Room(id, x, y, outdoor)
		local room = { id = id, kind = "room", outdoor = outdoor == true, center = { x = x * STEP, y = (y or 0) * STEP, z = 0 },
			doors = {}, areas = { id } }
		self.rooms[#self.rooms + 1], self.byId[id], self.of[id] = room, room, room
		return self
	end
	local function Between(a, b) return { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, z = 0 } end
	function map:Door(a, b)
		local ra, rb = self.byId[a], self.byId[b]
		local pos = Between(ra.center, rb.center)
		ra.doors[#ra.doors + 1] = { pos = pos, leads = { b } }
		rb.doors[#rb.doors + 1] = { pos = pos, leads = { a } }
		return self
	end
	function map:Corridor(pid, a, b)
		local ra, rb = self.byId[a], self.byId[b]
		local mid = Between(ra.center, rb.center)
		local pa, pb = Between(ra.center, mid), Between(rb.center, mid)
		local passage = { id = pid, kind = "corridor", outdoor = false, center = mid, areas = { 100 + pid },
			doors = { { pos = pa, leads = { a } }, { pos = pb, leads = { b } } } }
		self.passages[#self.passages + 1], self.passageOf[100 + pid] = passage, passage
		ra.doors[#ra.doors + 1] = { pos = pa, leads = { b }, passage = pid }
		rb.doors[#rb.doors + 1] = { pos = pb, leads = { a }, passage = pid }
		return self
	end
	-- a respawn room visualizer over the door between rooms a and b
	function map:Seal(a, b)
		local p = Between(self.byId[a].center, self.byId[b].center)
		self.seals[#self.seals + 1] = { lo = { x = p.x - 8, y = p.y - 64, z = 0 }, hi = { x = p.x + 8, y = p.y + 64, z = 128 } }
		return self
	end
	function map:Homes(spawns)
		local homes = {}
		for team, ids in pairs(spawns) do
			homes[team] = {}
			for _, id in ipairs(ids) do homes[team][#homes[team] + 1] = self.byId[id] end
		end
		return homes
	end
	return map
end

-- Two buildings and a yard between: RED's (its spawn 1, a room behind it 7,
-- and 2), the yard (3, outdoors) with a field off it (8), and BLU's (its
-- spawn 5, 4, and a room off BLU's way, 6).
local function Line()
	local m = Map()
	for _, r in ipairs({ { 7, -1, 0 }, { 1, 0, 0 }, { 2, 1, 0 }, { 4, 3, 0 }, { 5, 4, 0 }, { 6, 3, 1 } }) do m:Room(r[1], r[2], r[3]) end
	m:Room(3, 2, 0, true):Room(8, 2, 3, true)
	for _, d in ipairs({ { 7, 1 }, { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 4, 6 }, { 3, 8 } }) do m:Door(d[1], d[2]) end
	return m
end

local SPAWNS = { [RED] = { 1 }, [BLU] = { 5 } }

local function Ids(set)
	local ids = {}
	for space in pairs(set) do ids[#ids + 1] = space.id end
	table.sort(ids)
	return table.concat(ids, ",")
end

T.test("restricted: a team's spawn rooms and what lies only behind them, every door out sealed", function()
	local m = Line():Seal(1, 2):Seal(4, 5)
	local restricted = Classes.Restricted(Classes.SpaceGraph(m), m:Homes(SPAWNS), m.seals)
	T.eq(restricted[m.byId[1]], RED)
	T.eq(restricted[m.byId[7]], RED, "behind RED's spawn")
	T.eq(restricted[m.byId[5]], BLU)
	T.eq(Ids(restricted), "1,5,7")
end)

T.test("restricted: one door left unsealed opens the spawn", function()
	local m = Line():Seal(4, 5)
	local restricted = Classes.Restricted(Classes.SpaceGraph(m), m:Homes(SPAWNS), m.seals)
	T.eq(Ids(restricted), "5")
end)

T.test("restricted: a corridor inside the spawn is its ground, sealed at its far door", function()
	local m = Map()
	for _, r in ipairs({ { 1, 0 }, { 2, 2 }, { 3, 3 }, { 5, 5 } }) do m:Room(r[1], r[2]) end
	m:Corridor(1, 1, 2):Door(2, 3):Door(3, 5):Seal(2, 3)
	local homes = m:Homes({ [RED] = { 1, 2 }, [BLU] = { 5 } })
	table.insert(homes[RED], m.passages[1])
	local restricted = Classes.Restricted(Classes.SpaceGraph(m), homes, m.seals)
	T.eq(Ids(restricted), "1,2")
end)

T.test("places: a building with a team's spawn is its, the yard between no one's", function()
	local m = Line()
	local _, owner = Classes.Places(Classes.SpaceGraph(m), m:Homes(SPAWNS))
	T.eq(owner[m.byId[7]], RED)
	T.eq(owner[m.byId[2]], RED)
	T.eq(owner[m.byId[6]], BLU)
	T.eq(owner[m.byId[3]], nil, "the yard")
	T.eq(owner[m.byId[8]], nil)
end)

T.test("places: a building holding both spawns is split where their walks meet, the middle no one's", function()
	local m = Map()
	for i = 1, 5 do m:Room(i, i - 1) end
	for i = 1, 4 do m:Door(i, i + 1) end
	local places, owner = Classes.Places(Classes.SpaceGraph(m), m:Homes(SPAWNS))
	T.eq(owner[m.byId[2]], RED)
	T.eq(owner[m.byId[3]], nil)
	T.eq(owner[m.byId[4]], BLU)
	T.eq(#places, 3)
end)

T.test("highways: half or more of each team's highways, or an objective; never a spawn room or restricted", function()
	-- areas 0-1 room A, 2-3 room B, 4-5 room C, 6-7 room D, 8 room E; RED spawns at 0 and 6, BLU at 5
	local rooms = {}
	for _, id in ipairs({ "A", "B", "C", "D", "E" }) do rooms[id] = { id = id, kind = "room" } end
	local of = { [0] = rooms.A, rooms.A, rooms.B, rooms.B, rooms.C, rooms.C, rooms.D, rooms.D, rooms.E }
	local function region(a) return of[a] end
	local spawns = { [RED] = { 0, 6 }, [BLU] = { 5 } }
	local routes = { { team = RED, areas = { 0, 1, 2, 3, 4, 5 }, alternative = false },
		{ team = BLU, areas = { 5, 4, 3, 2, 1, 0 }, alternative = false }, { team = BLU, areas = { 5, 4 }, alternative = false } }
	local found = Classes.Highways(routes, region, {}, {}, spawns)
	T.eq(found[rooms.B], true, "half of BLU's, all of RED's")
	T.eq(found[rooms.A], nil, "RED's spawn room")
	T.eq(found[rooms.C], nil, "BLU's spawn room")
	T.eq(Classes.Highways(routes, region, { 8 }, {}, spawns)[rooms.E], true, "an objective's")
	T.eq(Classes.Highways(routes, region, { 1 }, {}, spawns)[rooms.A], nil, "an objective in a spawn room")
	T.eq(Classes.Highways(routes, region, {}, { [rooms.B] = RED }, spawns)[rooms.B], nil, "restricted")
end)

T.test("the space tree: each space hangs from the space its walk enters it from, corridors too", function()
	-- areas 1-2 room A, 3-4 corridor P, 5 room B, 6-7 room C, walked from 1
	local A, P, B, C = { id = 1, kind = "room" }, { id = 1, kind = "corridor" }, { id = 2, kind = "room" }, { id = 3, kind = "room" }
	local of = { A, A, P, P, B, C, C }
	local tree = { distance = {}, parent = {} }
	for i = 1, 7 do
		tree.distance[i] = (i - 1) * CELL
		if i > 1 then tree.parent[i] = i - 1 end
	end
	local spaces = Classes.SpaceTree(tree, function(a) return of[a] end)
	T.eq(#spaces.roots, 1)
	T.eq(spaces.roots[1], A)
	T.eq(spaces.parent[P], A)
	T.eq(spaces.parent[B], P)
	T.eq(spaces.parent[C], B)
	T.eq(spaces.entry[B], 5)
	T.eq(spaces.children[A][1], P)
end)

T.test("the gradient: 1 at the building, 0 on the highway", function()
	T.eq(Classes.Gradient(400, 100), 0.8)
	T.eq(Classes.Gradient(math.huge, 100), 1)
	T.eq(Classes.Gradient(100, math.huge), 0)
end)

if not T.NATIVE then T.finish() end

-- Areas 0..12 in a row, a cell apart, each its own room; RED's building rooms
-- 0 (areas 0-1), BLU's 11 (areas 11-12), the highway room 6.
local function Valley(extra)
	local graph = {}
	for i = 0, 12 do
		local links = {}
		if i > 0 then links[#links + 1] = { to = i - 1 } end
		if i < 12 then links[#links + 1] = { to = i + 1 } end
		graph[i] = { center = { x = i * CELL, y = 0, z = 0 }, floor = CELL * CELL, links = links }
	end
	if extra then extra(graph) end
	for _, area in pairs(graph) do
		for _, link in ipairs(area.links) do
			local a, b = area.center, graph[link.to].center
			link.middle, link.width = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, z = 0 }, CELL
		end
	end
	local partition = { rooms = {}, passages = {}, of = {}, passageOf = {} }
	local byId = {}
	for id in pairs(graph) do
		local key = (id == 1 and 0) or (id == 12 and 11) or id
		if not byId[key] then
			byId[key] = { id = key, kind = "room", outdoor = false, areas = {} }
			partition.rooms[#partition.rooms + 1] = byId[key]
		end
		table.insert(byId[key].areas, id)
		partition.of[id] = byId[key]
	end
	table.sort(partition.rooms, function(a, b) return a.id < b.id end)
	local g = Incursion.Graph(graph, {})
	local fields = Incursion.Fields(g, { [RED] = { 0 }, [BLU] = { 12 } })
	return partition, g, fields, byId, graph
end

local function Classify(owner, extra)
	local partition, g, fields, byId = Valley(extra)
	local owners = {}
	for id, team in pairs(owner or { [0] = RED, [11] = BLU }) do owners[byId[id]] = team end
	return Classes.Classify(partition, g, fields, {}, { [byId[6]] = true }, owners, CELL / 2, 4 * CELL), byId
end

T.test("a team's building is its stronghold", function()
	local found, byId = Classify()
	T.eq(found[byId[0]].cls, Classes.STRONGHOLD)
	T.eq(found[byId[0]].team, RED)
end)

T.test("on a team's side, nearer its building its stronghold, nearer the highway commons", function()
	local found, byId = Classify()
	T.eq(found[byId[2]].cls, Classes.STRONGHOLD)
	T.eq(found[byId[2]].team, RED)
	T.near(found[byId[2]].gradient, 0.8)
	T.eq(found[byId[5]].cls, Classes.COMMONS)
	T.eq(found[byId[9]].team, BLU)
	T.eq(found[byId[6]].cls, Classes.HIGHWAY)
end)

T.test("a highway inside a team's building counts as highway, not building", function()
	local found, byId = Classify({ [0] = RED, [6] = RED, [11] = BLU })
	T.eq(found[byId[5]].gradient < 0.5, true)
end)

T.test("far from both buildings and the highway is unoccupied indoors", function()
	local found, byId = Classify(nil, function(graph)
		table.insert(graph[2].links, { to = 20 })
		graph[20] = { center = { x = 2 * CELL, y = 6 * CELL, z = 0 }, floor = CELL * CELL, links = { { to = 2 } } }
	end)
	T.eq(found[byId[20]].cls, Classes.UNOCCUPIED)
end)

T.test("junctions: the floor within reach of a fork in its space, if enough; once a fork", function()
	local partition, g, _, _, graph = Valley()
	local function region(a) return Classes.Region(partition, a) end
	-- areas 3-5 one room, the forks at 4 and 5 in it
	local wide = { id = 99, kind = "room", areas = { 3, 4, 5 } }
	local of = setmetatable({ [3] = wide, [4] = wide, [5] = wide }, { __index = partition.of })
	local function wider(a) return of[a] end
	local found = Classes.Junctions({ 4, 5 }, graph, g, wider, 1.5 * CELL, 3 * CELL * CELL)
	T.eq(#found, 1)
	T.eq(table.concat(found[1].areas, ","), "3,4,5")
	T.eq(found[1].space, wide)
	T.eq(#Classes.Junctions({ 4 }, graph, g, wider, 1.5 * CELL, 4 * CELL * CELL), 0, "too little floor")
	T.eq(#Classes.Junctions({ 4 }, graph, g, region, CELL, CELL), 1, "any room")
end)

T.finish()
