-- Rooms (docs/special-missions-plan.md §2.1): the nav mesh's areas grouped
-- into rooms by the mesh's shape, and the doors between them, which the
-- special missions are planned on (an ambush at a room's doors, an assault
-- on a guarded room, an enemy's support base). The converted TF2 meshes
-- name no places, and a mesh cuts open floor into small areas, so width is
-- measured across the floor: an area's clearance is its walk to the
-- nearest area by a wall. Open floor (clearance over half DOOR_WIDTH) forms
-- the cores of rooms, joined where open floor meets open floor and no
-- func_door stands; a core of ROOM_MIN_FLOOR or more is a room. Every other
-- area (by a wall, in a doorway, in a corridor) joins the nearest room by
-- walking, never across a func_door, so a corridor is shared between the
-- rooms at its ends. Doors are where two rooms meet.
--
-- Partition(graph[, yield]) -> { rooms, of }: graph is area id -> { center,
--   floor (its floor's size), edge (by a wall: a side not wholly met by
--   neighbours), links = { { to, width (of the shared edge), middle (of it),
--   door (a func_door over either area) } } }, a link listed from each side.
--   yield(), when given, is called as the work goes on (a slow-lane
--   transaction's CheckYield). rooms: { id, areas (ids, ascending), floor,
--   center (the floor-weighted middle), doors }, numbered by their lowest
--   open area, so a map's rooms keep their numbers. A door is { pos (the
--   middle of a shared edge), width (of all its links), area (the room's
--   area at it), leads (the room on the other side, as a list) }; links
--   within DOOR_MERGE of a door's are one doorway.
-- RoomOf(partition, areaId) -> the area's room, or nil (cut off from any).
-- Positions are { x, y, z } tables.
local ipairs, pairs = ipairs, pairs
local huge = math.huge
local sort = table.sort
local Components = graph.search.Components
local Heap = tree.heap
local Distance = math.geometry.Distance
module(...)

-- About two soldiers abreast; a room at least about 200 square of open floor.
DOOR_WIDTH, ROOM_MIN_FLOOR, DOOR_MERGE = 96, 40000, 128
local YIELD_EVERY = 64

-- Dijkstra from seeds ({ id, label }) over links admit(link) lets through,
-- each costing the walk between centres: area id -> distance, and the
-- label of the seed it is nearest.
local function Walk(graph, seeds, admit, yield)
	local distance, label, heap = {}, {}, Heap.New()
	for _, seed in ipairs(seeds) do
		distance[seed[1]], label[seed[1]] = 0, seed[2]
		heap:Push(0, seed[1])
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
		if graph[id].edge then seeds[#seeds + 1] = { id, true } end
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

local function Doors(graph, room, of)
	for _, id in ipairs(room.areas) do
		for _, link in ipairs(graph[id].links) do
			local other = graph[link.to] and of[link.to]
			if other and other ~= room then
				local found
				for _, door in ipairs(room.doors) do
					if door.leads[1] == other.id and Near(door, link.middle) then
						found = door
						break
					end
				end
				if found then
					found.width = found.width + link.width
					found.points[#found.points + 1] = link.middle
				else
					room.doors[#room.doors + 1] = { pos = link.middle, width = link.width, area = id, leads = { other.id },
						points = { link.middle } }
				end
			end
		end
	end
	for _, door in ipairs(room.doors) do door.points = nil end
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
	for _, room in ipairs(rooms) do
		Measure(graph, room)
		Doors(graph, room, of)
		yield()
	end
	return { rooms = rooms, of = of }
end

function RoomOf(partition, areaId)
	return partition.of[areaId]
end
