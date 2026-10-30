-- Rooms (docs/special-missions-plan.md §2.1): sealed spaces of the map,
-- walls and a roof round them, entered through doors, which the special
-- missions are planned on (an ambush at a room's door, an assault on a
-- guarded room, an enemy's support base). The graph holds the playable
-- areas indoors alone (the controller's: reached from the spawns, under a
-- ceiling); a link out to open ground is a way outside. The converted TF2
-- meshes name no places, and a mesh may cut open floor into small areas,
-- so width is measured across the floor: an area's clearance is its walk
-- to the nearest wall, starting from its own middle's distance to a wall it
-- stands by. Open floor (clearance over half DOOR_WIDTH) forms the cores of
-- rooms, joined where open floor meets open floor and no func_door stands;
-- a core of ROOM_MIN_FLOOR or more is a room. Every other area (in a
-- doorway, a corridor) joins the nearest room by walking, never across a
-- func_door, so a corridor is shared between the rooms at its ends. A room
-- whose ways outside are together wider than SEAL_OPENING of its perimeter
-- is no room (a porch, a shed open on a side).
--
-- Partition(graph[, yield]) -> { rooms, of }: graph is area id -> { center,
--   floor (its floor's size), wall (for an area by a wall, a side not wholly
--   met by neighbours, or open to the outside: its middle's distance to it),
--   links = { { to, width (of the shared edge), middle (of it), door (a
--   func_door over either area) } } }, a link listed from each side, one to
--   an area not in the graph a way outside. yield(), when given, is called
--   as the work goes on (a slow-lane transaction's CheckYield). rooms: { id,
--   areas (ids, ascending), floor, center (the floor-weighted middle), doors
--   }, numbered in order of their lowest open area. A door is { pos (the
--   middle of a shared edge), width (of all its links), area (the room's
--   area at it), leads (the room on the other side, as a list; none for a
--   way outside), outside }; links within DOOR_MERGE of a door's are one
--   doorway.
-- RoomOf(partition, areaId) -> the area's room, or nil (cut off from any).
-- Positions are { x, y, z } tables.
local ipairs, pairs = ipairs, pairs
local huge, sqrt = math.huge, math.sqrt
local sort = table.sort
local Components = graph.search.Components
local Heap = tree.heap
local Distance = math.geometry.Distance
module(...)

-- About two soldiers abreast; a room at least about 200 square of open floor;
-- its ways outside no wider than a fifth of its perimeter.
DOOR_WIDTH, ROOM_MIN_FLOOR, DOOR_MERGE, SEAL_OPENING = 96, 40000, 128, 0.2
local YIELD_EVERY = 64

-- Dijkstra from seeds ({ id, label[, distance] }) over links admit(link) lets through,
-- each costing the walk between centres: area id -> distance, and the
-- label of the seed it is nearest.
local function Walk(graph, seeds, admit, yield)
	local distance, label, heap = {}, {}, Heap.New()
	for _, seed in ipairs(seeds) do
		local start = seed[3] or 0
		distance[seed[1]], label[seed[1]] = start, seed[2]
		heap:Push(start, seed[1])
	end
	local steps = 0
	while heap:Size() > 0 do
		local id, d = heap:Pop()
		if d <= distance[id] then
			local area = graph[id]
			for _, link in ipairs(area.links) do
				local to = graph[link.to]
				if to and admit(link) then
					local nd = d + Distance(area.center, to.center)
					if nd < (distance[link.to] or huge) then
						distance[link.to], label[link.to] = nd, label[id]
						heap:Push(nd, link.to)
					end
				end
			end
		end
		steps = steps + 1
		if steps % YIELD_EVERY == 0 then yield() end
	end
	return distance, label
end

local function Any() return true end
local function NoDoor(link) return not link.door end

local function Open(graph, ids, yield)
	local seeds = {}
	for _, id in ipairs(ids) do
		local wall = graph[id].wall
		if wall then seeds[#seeds + 1] = { id, true, wall } end
	end
	local clearance = Walk(graph, seeds, Any, yield)
	local open = {}
	for _, id in ipairs(ids) do open[id] = (clearance[id] or huge) > DOOR_WIDTH / 2 end
	return open
end

-- The cores of rooms: groups of open floor of ROOM_MIN_FLOOR or more, in
-- order of their lowest area.
local function Cores(graph, ids, open)
	local group = Components(ids, function(id)
		local next = {}
		if open[id] then
			for _, link in ipairs(graph[id].links) do
				if open[link.to] and not link.door then next[#next + 1] = link.to end
			end
		end
		return next
	end)
	local members, order = {}, {}
	for _, id in ipairs(ids) do
		if open[id] then
			local g = group[id]
			if not members[g] then members[g], order[#order + 1] = {}, g end
			members[g][#members[g] + 1] = id
		end
	end
	local cores = {}
	for _, g in ipairs(order) do
		local floor = 0
		for _, id in ipairs(members[g]) do floor = floor + graph[id].floor end
		if floor >= ROOM_MIN_FLOOR then cores[#cores + 1] = members[g] end
	end
	return cores
end

local function Measure(graph, room)
	local floor, x, y, z = 0, 0, 0, 0
	for _, id in ipairs(room.areas) do
		local a = graph[id]
		floor = floor + a.floor
		x, y, z = x + a.center.x * a.floor, y + a.center.y * a.floor, z + (a.center.z or 0) * a.floor
	end
	room.floor, room.center = floor, { x = x / floor, y = y / floor, z = z / floor }
end

local function Near(door, p)
	for _, q in ipairs(door.points) do
		if Distance(q, p) <= DOOR_MERGE then return true end
	end
	return false
end

-- A room's doors: its links to another room, and its ways outside (a link to
-- open ground, or to an area in no room).
local function Doors(graph, room, of)
	room.doors = {}
	for _, id in ipairs(room.areas) do
		for _, link in ipairs(graph[id].links) do
			local other = of[link.to]
			if other ~= room then
				local key = other and other.id or false
				local found
				for _, door in ipairs(room.doors) do
					if door.key == key and Near(door, link.middle) then
						found = door
						break
					end
				end
				if found then
					found.width = found.width + link.width
					found.points[#found.points + 1] = link.middle
				else
					room.doors[#room.doors + 1] = { pos = link.middle, width = link.width, area = id, key = key,
						leads = other and { other.id } or {}, outside = other == nil, points = { link.middle } }
				end
			end
		end
	end
	for _, door in ipairs(room.doors) do door.points, door.key = nil, nil end
end

-- Sealed: its ways outside together no wider than SEAL_OPENING of its
-- perimeter (taken as a square's of its floor).
local function Sealed(room)
	local opening = 0
	for _, door in ipairs(room.doors) do
		if door.outside then opening = opening + door.width end
	end
	return opening <= SEAL_OPENING * 4 * sqrt(room.floor)
end

function Partition(graph, yield)
	yield = yield or function() end
	local ids = {}
	for id in pairs(graph) do ids[#ids + 1] = id end
	sort(ids)
	local open = Open(graph, ids, yield)
	local rooms, seeds = {}, {}
	for i, core in ipairs(Cores(graph, ids, open)) do
		local room = { id = i, areas = {}, doors = {} }
		rooms[i] = room
		for _, id in ipairs(core) do seeds[#seeds + 1] = { id, room } end
	end
	local _, label = Walk(graph, seeds, NoDoor, yield)
	local of = {}
	for _, id in ipairs(ids) do
		local room = label[id]
		if room then
			of[id] = room
			room.areas[#room.areas + 1] = id
		end
	end
	for _, room in ipairs(rooms) do Measure(graph, room) end
	-- the doors, then only the sealed rooms kept; a room let go opens its
	-- neighbours' doors to the outside, so until none is let go
	repeat
		for i, room in ipairs(rooms) do room.id = i end
		local kept = {}
		for _, room in ipairs(rooms) do
			Doors(graph, room, of)
			if Sealed(room) then kept[#kept + 1] = room else for _, id in ipairs(room.areas) do of[id] = nil end end
			yield()
		end
		local changed = #kept < #rooms
		rooms = kept
	until not changed
	return { rooms = rooms, of = of }
end

function RoomOf(partition, areaId)
	return partition.of[areaId]
end
