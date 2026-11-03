-- Rooms (docs/special-missions-plan.md §2.1): the spaces of the map, indoors
-- and outdoors, on its levels, and the corridors, doors and windows joining
-- them, which the special missions are planned on (an ambush at a room's
-- door, an assault on a guarded room, an enemy's support base). Rooms are
-- big blocks: they need not follow the walls, so long as their doors,
-- windows and connections are right. The converted TF2 meshes name no
-- places, and a mesh may cut open floor into small areas, so width is
-- measured across the floor: an area's clearance is its walk to the nearest
-- wall, starting from its own middle's distance to a wall it stands by. No
-- room or corridor crosses a func_door, the threshold between indoors and
-- outdoors, an areaportal (the map's own areas), or a drop (floors more
-- than LEVEL_GAP apart: a ledge over a yard is a level above it, the drop a
-- door). A patch of indoors or outdoors too small to be a room takes the
-- side of what surrounds it, and floor too small to be a room with nothing
-- on its own floor to join (a crate's top) is the room or corridor it drops
-- into.
--
-- Floor wider than a corridor (clearance over half CORRIDOR_WIDTH) forms the
-- cores of rooms, joined where such floor meets; a core of ROOM_MIN_FLOOR or
-- more is a room, which reaches out from its core to its walls, ROOM_REACH.
-- What no room reaches: a run of flights (areas steeper than STAIR_SLOPE)
-- and the landings between them climbing STOREY_RISE is a stairwell, a room
-- of its own; the rest falls in pieces, a long narrow one (twice
-- CORRIDOR_WIDTH long, its floor no wider on the whole) a corridor (a
-- hallway, an alley) unless it is a dead end, and any other part of the
-- room it shares the widest edge with on its side, or a room of its own. A
-- doorway is a door: where a room or corridor meets another. A room indoors
-- whose openings to the outdoors are together wider than SEAL_OPENING of
-- its perimeter is not sealed, and counts as outdoors (a porch, a shed open
-- on a side); a stairwell under its roof is indoors however open.
--
-- Partition(graph[, yield[, windows]]) -> { rooms, passages, levels, of,
--   passageOf }: graph is area id -> { center, lo, hi (its extent), floor
--   (its floor's size), outdoor, bsp (the map's own area it stands in, which
--   areaportals seal; nil for none), wall (for an area by a wall, a side not
--   wholly met by neighbours or by the threshold: its middle's distance to
--   it), open (the width of its sides onto the open air, no area there: a
--   balcony's front; nil for none), links = { { to, width (of the shared
--   edge), middle (of it), door (a func_door over either area) } } }, a
--   link listed from each side. yield(),
--   when given, is called as the work goes on (a slow-lane transaction's
--   CheckYield). windows: { pos, from, to (the area ids on its two sides) },
--   breakable glass and areaportal windows, which no link crosses.
--   rooms: { id, kind (ROOM or STAIRWELL), outdoor, level, top (the levels of
--   its foot and head: the same but on a stairwell), areas (ids, ascending),
--   floor, center (the floor-weighted middle), lo, hi (its block: its areas'
--   extent), doors, windows }, the rooms numbered in order of their lowest
--   open area, then the stairwells, then the rooms found in what was left.
--   passages: { id, kind (CORRIDOR), outdoor, level, top, areas, floor,
--   center, lo, hi, joins (the ids of the rooms it opens on, ascending),
--   doors }. levels: { id, low, high (its rooms' floor heights), rooms (the
--   ids of the rooms on it, stairwells left out) }, from the ground up. A door
--   is { pos (the middle of a shared edge), width (of all its links), area
--   (the room's area at it), leads (the rooms on the other side, through a
--   passage those it joins, as a list), passage (its id, or nil), outside
--   (from indoors out) }; links within DOOR_MERGE of a door's, leading to
--   the same rooms, are one doorway. A room's windows are { pos, leads,
--   passage } as a door's, one for each window onto another room or a
--   passage.
-- RoomOf(partition, areaId) -> the area's room, or nil (in a passage).
-- PassageOf(partition, areaId) -> the area's passage, or nil.
-- Positions are { x, y, z } tables.
local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable
local huge, sqrt, max, min = math.huge, math.sqrt, math.max, math.min
local sort, concat, table_remove = table.sort, table.concat, table.remove
local Components = graph.search.Components
local Heap = tree.heap
local Distance = math.geometry.Distance
module(...)

-- About two soldiers abreast; a room at least about 200 square of open floor;
-- its ways outside no wider than a fifth of its perimeter.
DOOR_WIDTH, ROOM_MIN_FLOOR, DOOR_MERGE, SEAL_OPENING = 96, 40000, 128, 0.2
-- A hallway three soldiers abreast; a room's walls about two of its areas
-- past its open floor; a storey about two soldiers' height; stairs climbing
-- more than about one in seven.
CORRIDOR_WIDTH, ROOM_REACH, STOREY_RISE, STAIR_SLOPE = 160, 100, 96, 0.15
-- Floors no further apart than a player standing, less a step, are one
-- level: no floor can lie over another so close.
LEVEL_GAP = 64
ROOM, STAIRWELL, CORRIDOR = "room", "stairwell", "corridor"
local YIELD_EVERY = 64

-- A link a room or passage never crosses: through a func_door, over the
-- threshold between indoors and outdoors, between two of the map's own
-- areas (sealed from each other by an areaportal), or a drop: floors more
-- than LEVEL_GAP apart, a ledge over a yard, are two levels, the drop a door
-- between them.
local function Drop(area, to)
	return max(to.lo.z - area.hi.z, area.lo.z - to.hi.z) > LEVEL_GAP
end

local function Within(area, link, to)
	return not link.door and (area.outdoor == true) == (to.outdoor == true) and area.bsp == to.bsp
		and not Drop(area, to)
end

-- Over a drop alone: what a crate's top, too small to be a room, is part of.
local function Over(area, link, to)
	return not link.door and (area.outdoor == true) == (to.outdoor == true) and area.bsp == to.bsp
		and Drop(area, to)
end

local function Centres(area, _, to) return Distance(area.center, to.center) end

-- Dijkstra from seeds ({ id, label[, distance] }) over links admit(area,
-- link, to) lets through, each costing cost(area, link, to): area id ->
-- distance, and the label of the seed it is nearest.
local function Walk(graph, seeds, admit, cost, yield)
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
				if to and admit(area, link, to) then
					local nd = d + cost(area, link, to)
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


-- Groups of the ids member(id) admits, joined over links Within lets through
-- between members: lists of ids, ascending, in order of their lowest.
local function Groups(graph, ids, member)
	local group = Components(ids, function(id)
		local next = {}
		if member(id) then
			local area = graph[id]
			for _, link in ipairs(area.links) do
				local to = graph[link.to]
				if to and member(link.to) and Within(area, link, to) then next[#next + 1] = link.to end
			end
		end
		return next
	end)
	local members, order = {}, {}
	for _, id in ipairs(ids) do
		if member(id) then
			local g = group[id]
			if not members[g] then members[g], order[#order + 1] = {}, g end
			members[g][#members[g] + 1] = id
		end
	end
	local groups = {}
	for i, g in ipairs(order) do groups[i] = members[g] end
	return groups
end

-- Floor wider than a corridor: clearance over half CORRIDOR_WIDTH.
local function Open(graph, ids, yield)
	local seeds = {}
	for _, id in ipairs(ids) do
		local wall = graph[id].wall
		if wall then seeds[#seeds + 1] = { id, true, wall } end
	end
	local clearance = Walk(graph, seeds, Within, Centres, yield)
	local open = {}
	for _, id in ipairs(ids) do open[id] = (clearance[id] or huge) > CORRIDOR_WIDTH / 2 end
	return open, clearance
end

local function FloorOf(graph, areas)
	local floor = 0
	for _, id in ipairs(areas) do floor = floor + graph[id].floor end
	return floor
end

local function Measure(graph, space)
	local floor, x, y, z = 0, 0, 0, 0
	local lo, hi = { x = huge, y = huge, z = huge }, { x = -huge, y = -huge, z = -huge }
	for _, id in ipairs(space.areas) do
		local a = graph[id]
		floor = floor + a.floor
		x, y, z = x + a.center.x * a.floor, y + a.center.y * a.floor, z + (a.center.z or 0) * a.floor
		lo.x, lo.y, lo.z = min(lo.x, a.lo.x), min(lo.y, a.lo.y), min(lo.z, a.lo.z)
		hi.x, hi.y, hi.z = max(hi.x, a.hi.x), max(hi.y, a.hi.y), max(hi.z, a.hi.z)
	end
	space.floor, space.center, space.lo, space.hi = floor, { x = x / floor, y = y / floor, z = z / floor }, lo, hi
end

-- How far a piece climbs, and how long it runs across the ground.
local function Rise(graph, areas)
	local low, high = huge, -huge
	for _, id in ipairs(areas) do
		local a = graph[id]
		low, high = min(low, a.lo.z), max(high, a.hi.z)
	end
	return high - low
end

local function Length(graph, areas)
	local x0, y0, x1, y1 = huge, huge, -huge, -huge
	for _, id in ipairs(areas) do
		local a = graph[id]
		x0, y0, x1, y1 = min(x0, a.lo.x), min(y0, a.lo.y), max(x1, a.hi.x), max(y1, a.hi.y)
	end
	return max(x1 - x0, y1 - y0)
end

-- A corridor runs at least twice CORRIDOR_WIDTH, its floor on the whole no
-- wider (twice its floor-weighted clearance), however it branches.
local function Elongated(graph, areas, clearance)
	if Length(graph, areas) < 2 * CORRIDOR_WIDTH then return false end
	local floor, weighted = 0, 0
	for _, id in ipairs(areas) do
		local a = graph[id]
		floor, weighted = floor + a.floor, weighted + a.floor * min(clearance[id] or huge, CORRIDOR_WIDTH)
	end
	return 2 * weighted / floor <= CORRIDOR_WIDTH
end

-- On stairs: the area climbs a step's rounding or more across it, steeper
-- than STAIR_SLOPE.
local STEP = 8

local function Stair(area)
	local climb = area.hi.z - area.lo.z
	return climb >= STEP and climb > STAIR_SLOPE * max(area.hi.x - area.lo.x, area.hi.y - area.lo.y)
end

-- The flights indoors and their landings, among the areas free(id) lets
-- through: the stair areas, and the areas too small to be rooms within
-- LANDING_REACH of one, walking over such areas (a landing several areas
-- long, at the foot or head of a flight or between two). Sloping ground
-- outdoors is no stair.
local LANDING_REACH = 240

local function Flights(graph, ids, free, yield)
	local seeds = {}
	for _, id in ipairs(ids) do
		local area = graph[id]
		if free(id) and not area.outdoor and Stair(area) then seeds[#seeds + 1] = { id, true } end
	end
	local reach = Walk(graph, seeds, function(area, link, to)
		return Within(area, link, to) and free(link.to) and (Stair(to) or to.floor < ROOM_MIN_FLOOR)
	end, Centres, yield)
	return function(id) return free(id) and (reach[id] or huge) <= LANDING_REACH end
end

-- The rooms a piece opens on (by any link, as a set), and the one it shares
-- the widest edge with over links joined lets through (by default Within:
-- its own side and floor, no door, no threshold between), or nil.
local function Neighbours(graph, areas, of, joined)
	joined = joined or Within
	local rooms, widths = {}, {}
	for _, id in ipairs(areas) do
		local area = graph[id]
		for _, link in ipairs(area.links) do
			local to = graph[link.to]
			local room = to and of[link.to]
			if room then
				rooms[room] = true
				if joined(area, link, to) then widths[room] = (widths[room] or 0) + link.width end
			end
		end
	end
	local widest
	for room, width in pairs(widths) do
		if not widest or width > widths[widest] or (width == widths[widest] and room.id < widest.id) then widest = room end
	end
	return rooms, widest
end

local function Near(door, p)
	for _, q in ipairs(door.points) do
		if Distance(q, p) <= DOOR_MERGE then return true end
	end
	return false
end

local function Without(ids, id)
	local list = {}
	for _, other in ipairs(ids) do if other ~= id then list[#list + 1] = other end end
	return list
end

-- A room's or passage's doors: its links to another room or passage, those
-- leading to the same rooms and near each other one doorway.
local function Doors(graph, space, of, passageOf)
	space.doors = {}
	for _, id in ipairs(space.areas) do
		local area = graph[id]
		for _, link in ipairs(area.links) do
			local to = graph[link.to]
			local other, passage = of[link.to], passageOf[link.to]
			if to and (other or passage) and other ~= space and passage ~= space then
				local leads = other and { other.id } or Without(passage.joins, space.kind ~= CORRIDOR and space.id)
				local key = (passage and "p" or "r") .. concat(leads, ",")
				local found
				for _, door in ipairs(space.doors) do
					if door.key == key and Near(door, link.middle) then
						found = door
						break
					end
				end
				if found then
					found.width = found.width + link.width
					found.points[#found.points + 1] = link.middle
				else
					space.doors[#space.doors + 1] = { pos = link.middle, width = link.width, area = id, key = key,
						leads = leads, passage = passage and passage.id, points = { link.middle },
						outside = not space.outdoor and to.outdoor == true }
				end
			end
		end
	end
	for _, door in ipairs(space.doors) do door.points, door.key = nil, nil end
end

-- The rooms' windows: each window joining two rooms (or a room and a
-- passage) is one in each, leading to the other side.
local function Windows(rooms, windows, of, passageOf)
	for _, room in ipairs(rooms) do room.windows = {} end
	for _, window in ipairs(windows) do
		local sides = { { window.from, window.to }, { window.to, window.from } }
		for _, side in ipairs(sides) do
			local room, other, passage = of[side[1]], of[side[2]], passageOf[side[2]]
			if room and other ~= room and (other or passage) then
				room.windows[#room.windows + 1] = { pos = window.pos,
					leads = other and { other.id } or Without(passage.joins, room.id), passage = passage and passage.id }
			end
		end
	end
end

-- The map's levels, numbered from the ground up: the rooms' floors (their
-- floor-weighted heights; a stairwell's left out), a gap of more than
-- LEVEL_GAP between one and the next starting a level. Each room and
-- passage is given the level its foot is nearest (level) and the one its
-- head is (top), the same but on a stairwell or a climbing corridor.
local function Levels(rooms, passages)
	local floors = {}
	for _, room in ipairs(rooms) do if room.kind == ROOM then floors[#floors + 1] = room end end
	sort(floors, function(a, b) return a.center.z < b.center.z or (a.center.z == b.center.z and a.id < b.id) end)
	local levels = {}
	for _, room in ipairs(floors) do
		local level = levels[#levels]
		if not level or room.center.z - level.high > LEVEL_GAP then
			level = { id = #levels + 1, low = room.center.z, rooms = {} }
			levels[level.id] = level
		end
		level.high = room.center.z
	end
	local function At(z)
		local best, gap
		for _, level in ipairs(levels) do
			local d = z < level.low and level.low - z or z > level.high and z - level.high or 0
			if not best or d < gap then best, gap = level, d end
		end
		return best and best.id
	end
	for _, room in ipairs(rooms) do
		if room.kind == ROOM then
			room.level = At(room.center.z)
			room.top = room.level
			local list = levels[room.level].rooms
			list[#list + 1] = room.id
		else
			room.level, room.top = At(room.lo.z), At(room.hi.z)
		end
	end
	for _, passage in ipairs(passages) do passage.level, passage.top = At(passage.lo.z), At(passage.hi.z) end
	for _, level in ipairs(levels) do sort(level.rooms) end
	return levels
end

-- Sealed: its openings to the outdoors (its links to outdoor areas, and its
-- sides onto the open air: a balcony's front over a drop) together no wider
-- than SEAL_OPENING of its perimeter (taken as a square's of its floor).
local function Sealed(graph, room)
	local opening = 0
	for _, id in ipairs(room.areas) do
		opening = opening + (graph[id].open or 0)
		for _, link in ipairs(graph[id].links) do
			local to = graph[link.to]
			if to and to.outdoor then opening = opening + link.width end
		end
	end
	return opening <= SEAL_OPENING * 4 * sqrt(room.floor)
end

local function Sorted(set)
	local list = {}
	for room in pairs(set) do list[#list + 1] = room.id end
	sort(list)
	return list
end

-- The graph with each patch of indoors or outdoors too small to be a room
-- (under ROOM_MIN_FLOOR) on the side of what surrounds it: an awning over a
-- yard, a skylight's gap in a hall. The graph given is left as it was.
local function Sides(graph, ids)
	local seen, view = {}, {}
	for _, start in ipairs(ids) do
		view[start] = view[start] or graph[start]
		if not seen[start] then
			local side = graph[start].outdoor == true
			local patch, stack, floor, across = {}, { start }, 0, false
			seen[start] = true
			while stack[1] do
				local id = table_remove(stack)
				patch[#patch + 1] = id
				floor = floor + graph[id].floor
				for _, link in ipairs(graph[id].links) do
					local to = graph[link.to]
					if to and not link.door then
						if (to.outdoor == true) ~= side then
							across = true
						elseif not seen[link.to] then
							seen[link.to] = true
							stack[#stack + 1] = link.to
						end
					end
				end
			end
			if across and floor < ROOM_MIN_FLOOR then
				for _, id in ipairs(patch) do view[id] = setmetatable({ outdoor = not side }, { __index = graph[id] }) end
			end
		end
	end
	return view
end

function Partition(graph, yield, windows)
	yield = yield or function() end
	local ids = {}
	for id in pairs(graph) do ids[#ids + 1] = id end
	sort(ids)
	graph = Sides(graph, ids)
	local open, clearance = Open(graph, ids, yield)
	local rooms, seeds, core = {}, {}, {}
	for _, group in ipairs(Groups(graph, ids, function(id) return open[id] end)) do
		if FloorOf(graph, group) >= ROOM_MIN_FLOOR then
			local room = { id = #rooms + 1, kind = ROOM, areas = {} }
			rooms[room.id] = room
			for _, id in ipairs(group) do seeds[#seeds + 1], core[id] = { id, room }, true end
		end
	end
	-- a room reaches out from its core, its first step from the core's edge
	local reach, label = Walk(graph, seeds, Within, function(area, link, to)
		return (core[area] and 0 or Distance(area.center, link.middle)) + Distance(link.middle, to.center)
	end, yield)
	local of = {}
	for _, id in ipairs(ids) do
		if label[id] and reach[id] <= ROOM_REACH then of[id] = label[id] end
	end
	-- what no room reaches: stairs climbing a storey first, each run of
	-- flights and the landings between them a stairwell, a room of its own
	local Flight = Flights(graph, ids, function(id) return not of[id] end, yield)
	for _, run in ipairs(Groups(graph, ids, Flight)) do
		if Rise(graph, run) >= STOREY_RISE then
			local room = { id = #rooms + 1, kind = STAIRWELL, areas = {} }
			rooms[room.id] = room
			for _, id in ipairs(run) do of[id] = room end
		end
	end
	-- then the rest, in pieces: a long narrow one a corridor, any other part
	-- of the room it shares the widest edge with; while none has a room to
	-- join, the largest left is a room of its own, the rest joining it
	local passages, passageOf, left = {}, {}, {}
	for _, piece in ipairs(Groups(graph, ids, function(id) return not of[id] end)) do
		if Elongated(graph, piece, clearance) then
			local passage = { id = #passages + 1, kind = CORRIDOR, outdoor = graph[piece[1]].outdoor == true,
				areas = piece }
			passages[passage.id] = passage
			Measure(graph, passage)
			for _, id in ipairs(piece) do passageOf[id] = passage end
		else
			left[#left + 1] = piece
		end
	end
	while left[1] do
		local still = {}
		for _, piece in ipairs(left) do
			local small = FloorOf(graph, piece) < ROOM_MIN_FLOOR
			local _, widest = Neighbours(graph, piece, of)
			local _, along = Neighbours(graph, piece, passageOf)
			local _, below = Neighbours(graph, piece, of, Over)
			local _, under = Neighbours(graph, piece, passageOf, Over)
			if widest then
				for _, id in ipairs(piece) do of[id] = widest end
			elseif along and small then
				for _, id in ipairs(piece) do
					passageOf[id], along.areas[#along.areas + 1] = along, id
				end
			elseif below and small then
				for _, id in ipairs(piece) do of[id] = below end
			elseif under and small then
				for _, id in ipairs(piece) do
					passageOf[id], under.areas[#under.areas + 1] = under, id
				end
			else
				still[#still + 1] = piece
			end
		end
		if #still == #left then
			local largest = 1
			for i, piece in ipairs(still) do
				if FloorOf(graph, piece) > FloorOf(graph, still[largest]) then largest = i end
			end
			local room = { id = #rooms + 1, kind = ROOM, areas = {} }
			rooms[room.id] = room
			for _, id in ipairs(table_remove(still, largest)) do of[id] = room end
		end
		left = still
		yield()
	end
	-- a corridor opening on one room alone, and on no other corridor, is a
	-- dead end of it
	local kept = {}
	for _, passage in ipairs(passages) do
		local joins, widest = Neighbours(graph, passage.areas, of)
		local count = 0
		for _ in pairs(joins) do count = count + 1 end
		for other in pairs((Neighbours(graph, passage.areas, passageOf))) do
			if other ~= passage then count = count + 1 end
		end
		if count <= 1 and widest then
			for _, id in ipairs(passage.areas) do of[id], passageOf[id] = widest, nil end
		else
			passage.id, passage.joins = #kept + 1, joins
			kept[passage.id] = passage
			sort(passage.areas)
			Measure(graph, passage)
		end
	end
	passages = kept
	for _, id in ipairs(ids) do
		local room = of[id]
		if room then room.areas[#room.areas + 1] = id end
	end
	for _, passage in ipairs(passages) do passage.joins = Sorted(passage.joins) end
	for _, room in ipairs(rooms) do
		Measure(graph, room)
		room.outdoor = graph[room.areas[1]].outdoor == true or (room.kind == ROOM and not Sealed(graph, room))
	end
	for _, space in ipairs(rooms) do
		Doors(graph, space, of, passageOf)
		yield()
	end
	for _, space in ipairs(passages) do Doors(graph, space, of, passageOf) end
	Windows(rooms, windows or {}, of, passageOf)
	local levels = Levels(rooms, passages)
	return { rooms = rooms, passages = passages, levels = levels, of = of, passageOf = passageOf }
end

function RoomOf(partition, areaId)
	return partition.of[areaId]
end

function PassageOf(partition, areaId)
	return partition.passageOf[areaId]
end
