-- Part of the AI war controller (sv.lua): the map's rooms
-- (wartactics.rooms, docs/special-missions-plan.md §2.1). The nav mesh is
-- read into Partition's graph, each link's shared edge measured from the
-- two areas' extents and marked a door where a func_door stands over
-- either area, each area by a wall where a side is not wholly met, and
-- partitioned once a map on the slow lane (a transaction, yielding as it
-- goes); the rooms are kept in the map's data
-- (roomStore), found again only when the mesh's area count or the way of
-- finding them (ROOMS_VERSION) changes. Only the playable areas indoors
-- count: those reached from the spawns, under a ceiling.
-- ns_rooms_print says what was found.
local Controller = ...
local Rooms = wartactics.rooms
local Transaction = transaction

-- The slow lane gives 2 ms a second; pl_upward's 5,410 areas take some
-- 0.46 s of work, so several minutes, once a map: the rooms are kept.
local ROOMS_TIME = 900
-- The doors no room crosses: the map's doors, and the respawn room
-- visualizers sealing a spawn's doorways, so a spawn room ends at them.
local DOOR_CLASSES = { "func_door", "func_door_rotating", "prop_door_rotating", "func_respawnroomvisualizer" }

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

-- The edge two touching areas share: its length and middle, from their
-- extents (an overlap along one axis, touching on the other).
local function SharedEdge(a, b)
	local ea, eb = a:GetExtentInfo(), b:GetExtentInfo()
	local x0, x1 = math.max(ea.lo.x, eb.lo.x), math.min(ea.hi.x, eb.hi.x)
	local y0, y1 = math.max(ea.lo.y, eb.lo.y), math.min(ea.hi.y, eb.hi.y)
	local width = math.max(x1 - x0, y1 - y0, 0)
	local z = (a:GetCenter().z + b:GetCenter().z) / 2
	return width, { x = (x0 + x1) / 2, y = (y0 + y1) / 2, z = z }
end

-- The areas a door stands over: its box reaches DOOR_FLOOR below it, as the
-- npc blockers' does, for a door or visualizer hung a little above the floor.
local DOOR_FLOOR = Vector(0, 0, 32)

local function DoorAreas()
	local under = {}
	for _, class in ipairs(DOOR_CLASSES) do
		for _, door in ipairs(ents.FindByClass(class)) do
			local mins, maxs = door:WorldSpaceAABB()
			for _, area in ipairs(navmesh.FindInBox(mins - DOOR_FLOOR, maxs)) do under[area:GetID()] = true end
		end
	end
	return under
end

-- Whether an area is by a wall: one of its sides (north and south along x,
-- east and west along y) not wholly met by the neighbours on it.
local EDGE_SLACK = 4

-- The distance from an area's middle to the nearest of its sides that is a
-- wall (not wholly met by neighbours: north and south run along x, east and
-- west along y), or that opens outdoors (outdoor(other)); nil when none is.
local function WallDistance(area, outdoor)
	local nearest
	for dir = 0, 3 do
		local along = (dir == 0 or dir == 2) and area:GetSizeX() or area:GetSizeY()
		local across = (dir == 0 or dir == 2) and area:GetSizeY() or area:GetSizeX()
		local met, open = 0, false
		for _, other in ipairs(area:GetAdjacentAreasAtSide(dir) or {}) do
			met = met + (SharedEdge(area, other))
			open = open or outdoor(other)
		end
		if met < along - EDGE_SLACK or open then nearest = math.min(nearest or math.huge, across / 2) end
	end
	return nearest
end

-- A team's spawns: TF2's team spawns live this round (WS.SpawnPoints), and
-- on a CS:S map its side's (gameplay.spawn's SideClass).
function Controller:TeamSpawns(team)
	local spawns = WS.SpawnPoints(team)
	local class = gameplay.spawn.SideClass(team)
	if class then table.Add(spawns, ents.FindByClass(class)) end
	return spawns
end

-- The playable areas: those reached over the mesh's links from the teams'
-- spawns (off-map ledges, cliffs and water the mesh also covers are left
-- out, and so is a box of spawns for no team under the map: pl_upward's).
local function Playable(work)
	local reached, stack = {}, {}
	for _, team in ipairs({ WS.TEAM_RED, WS.TEAM_BLUE }) do
		for _, spawn in ipairs(Controller:TeamSpawns(team)) do
			local area = navmesh.GetNearestNavArea(spawn:GetPos())
			if IsValid(area) and not reached[area:GetID()] then
				reached[area:GetID()] = area
				stack[#stack + 1] = area
			end
		end
	end
	local steps = 0
	while #stack > 0 do
		local area = table.remove(stack)
		for _, other in ipairs(area:GetAdjacentAreas()) do
			if not reached[other:GetID()] then
				reached[other:GetID()] = other
				stack[#stack + 1] = other
			end
		end
		steps = steps + 1
		if steps % 256 == 0 then work:CheckYield() end
	end
	return reached
end

-- The map's own areas (sealed from each other by areaportals, the mapper's
-- doors and windows): the BSP area of the leaf a point stands in, read from
-- the map's .bsp (WS.MapFile, the vendored bsp3); the low bits of a leaf's
-- areaflags are its area.
local AREA_BITS = 0x1FF
local AREA_LIFT = Vector(0, 0, 16)

local function BspAreas()
	local lumps = WS.MapFile({ "PLANES", "NODES", "LEAFS" })
	local root = lumps.NODES[1]
	return function(pos)
		local node = root
		while not node.contents do
			local plane = node.plane
			node = plane.normal:Dot(pos) - plane.dist >= 0 and node.children[1] or node.children[2]
		end
		return bit.band(node.areaflags, AREA_BITS)
	end
end

-- The map's windows, which no nav link crosses: areaportal windows and
-- breakable glass, each with the nav areas a little way out from either
-- face, on its side of the glass.
local WINDOW_CLASSES = { "func_areaportalwindow", "func_breakable_surf" }
local WINDOW_REACH, WINDOW_SEARCH = 24, 160

local function Windows(playable)
	local windows = {}
	for _, class in ipairs(WINDOW_CLASSES) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			local mins, maxs = ent:WorldSpaceAABB()
			local size, middle = maxs - mins, (mins + maxs) / 2
			local across = size.x < size.y and Vector(size.x / 2 + WINDOW_REACH, 0, 0) or Vector(0, size.y / 2 + WINDOW_REACH, 0)
			local sides = {}
			for i, at in ipairs({ middle + across, middle - across }) do
				local area = navmesh.GetNearestNavArea(at, false, WINDOW_SEARCH, true, true)
				sides[i] = IsValid(area) and playable[area:GetID()] and area:GetID()
			end
			if sides[1] and sides[2] and sides[1] ~= sides[2] then
				windows[#windows + 1] = { pos = Point(middle), from = sides[1], to = sides[2] }
			end
		end
	end
	return windows
end

-- Indoors: a ceiling over most of the area. A trace straight up from its
-- middle and from a point in each quarter meets the world within
-- ROOF_HEIGHT, not the sky, at more than half of them, so a lamp's gap or
-- a skylight over the middle (ctf_2fort's bridge) leaves a roofed area
-- roofed.
local ROOF_HEIGHT, ROOF_LIFT = 1024, Vector(0, 0, 32)
local ROOF_SAMPLES = { { 0.5, 0.5 }, { 0.25, 0.25 }, { 0.75, 0.25 }, { 0.25, 0.75 }, { 0.75, 0.75 } }

local function Roofed(area)
	local extent, z = area:GetExtentInfo(), area:GetCenter().z
	local covered = 0
	for _, at in ipairs(ROOF_SAMPLES) do
		local from = Vector(extent.lo.x + (extent.hi.x - extent.lo.x) * at[1],
			extent.lo.y + (extent.hi.y - extent.lo.y) * at[2], z) + ROOF_LIFT
		local tr = util.TraceLine({ start = from, endpos = from + Vector(0, 0, ROOF_HEIGHT), mask = MASK_SOLID_BRUSHONLY })
		if tr.Hit and not tr.HitSky then covered = covered + 1 end
	end
	return covered * 2 > #ROOF_SAMPLES
end

-- How much of an area's sides opens onto the open air (a balcony's
-- front over a drop): on each side neighbours on its floor (within
-- LEVEL_GAP; the yard a drop lands in is none) do not wholly meet, a trace out from points along it at OPEN_HEIGHT, over a
-- railing, that goes OPEN_REACH without meeting anything and ends under the
-- sky (no roof within ROOF_HEIGHT) is that share of the side open. Every
-- area is measured: a strip of outdoors too small to stand alone takes the
-- side of the roofed room around it, its open front with it.
local OPEN_HEIGHT, OPEN_REACH, OPEN_INSET = 64, 256, 2
local OPEN_SAMPLES = { 0.25, 0.5, 0.75 }
-- Source's nav directions: north is -y, east +x, south +y, west -x.
local OUTWARD = { [0] = Vector(0, -1, 0), Vector(1, 0, 0), Vector(0, 1, 0), Vector(-1, 0, 0) }

local function Open(area)
	local extent, open = area:GetExtentInfo(), 0
	for dir = 0, 3 do
		local alongX = dir == 0 or dir == 2
		local along = alongX and area:GetSizeX() or area:GetSizeY()
		local met = 0
		for _, other in ipairs(area:GetAdjacentAreasAtSide(dir) or {}) do
			local oe = other:GetExtentInfo()
			if math.max(oe.lo.z - extent.hi.z, extent.lo.z - oe.hi.z) <= Rooms.LEVEL_GAP then
				met = met + (SharedEdge(area, other))
			end
		end
		if met < along - EDGE_SLACK then
			local out, clear = OUTWARD[dir], 0
			for _, t in ipairs(OPEN_SAMPLES) do
				local x = alongX and extent.lo.x + (extent.hi.x - extent.lo.x) * t
					or (dir == 1 and extent.hi.x - OPEN_INSET or extent.lo.x + OPEN_INSET)
				local y = alongX and (dir == 2 and extent.hi.y - OPEN_INSET or extent.lo.y + OPEN_INSET)
					or extent.lo.y + (extent.hi.y - extent.lo.y) * t
				local from = Vector(x, y, area:GetZ(Vector(x, y, 0)) + OPEN_HEIGHT)
				local across = util.TraceLine({ start = from, endpos = from + out * OPEN_REACH, mask = MASK_SOLID })
				if not across.Hit then
					local up = util.TraceLine({ start = across.HitPos, endpos = across.HitPos + Vector(0, 0, ROOF_HEIGHT),
						mask = MASK_SOLID_BRUSHONLY })
					if not up.Hit or up.HitSky then clear = clear + 1 end
				end
			end
			open = open + (along - met) * clear / #OPEN_SAMPLES
		end
	end
	return open > 0 and open or nil
end

-- The nav mesh as Partition's graph, and the map's windows, yielding as it
-- goes: the playable areas, each indoors or outdoors and in its BSP area;
-- an area by the threshold between indoors and outdoors is by a wall for
-- its clearance.
function Controller:RoomGraph(work)
	local under, graph = DoorAreas(), {}
	local playable = Playable(work)
	local AreaAt = BspAreas()
	work:CheckYield()
	local indoor = {}
	local i = 0
	for id, area in pairs(playable) do
		if Roofed(area) then indoor[id] = true end
		i = i + 1
		if i % 64 == 0 then work:CheckYield() end
	end
	for id, area in pairs(playable) do
		local function Across(other) return not indoor[other:GetID()] ~= not indoor[id] end
		local links = {}
		for _, other in ipairs(area:GetAdjacentAreas()) do
			local otherId = other:GetID()
			if playable[otherId] then
				local width, middle = SharedEdge(area, other)
				links[#links + 1] = { to = otherId, width = width, middle = middle,
					door = under[id] == true or under[otherId] == true }
			end
		end
		local extent = area:GetExtentInfo()
		graph[id] = { center = Point(area:GetCenter()), floor = area:GetSizeX() * area:GetSizeY(),
			outdoor = not indoor[id], lo = Point(extent.lo), hi = Point(extent.hi), open = Open(area),
			bsp = AreaAt(area:GetCenter() + AREA_LIFT), wall = WallDistance(area, Across), links = links }
		i = i + 1
		if i % 64 == 0 then work:CheckYield() end
	end
	return graph, Windows(playable)
end

-- What is kept: the rooms with their areas, doors and windows, the passages,
-- and the mesh's size. A save is of ROOMS_VERSION's way of finding rooms;
-- another's is found again.
local ROOMS_VERSION = 5

local function Connections(list)
	local kept = {}
	for i, c in ipairs(list) do
		kept[i] = { pos = c.pos, width = c.width, area = c.area, leads = c.leads, passage = c.passage, outside = c.outside }
	end
	return kept
end

local function Saved(partition, areas)
	local rooms, passages = {}, {}
	for i, room in ipairs(partition.rooms) do
		rooms[i] = { id = room.id, kind = room.kind, outdoor = room.outdoor, level = room.level, top = room.top,
			areas = room.areas, floor = room.floor, center = room.center, lo = room.lo, hi = room.hi,
			doors = Connections(room.doors), windows = Connections(room.windows) }
	end
	for i, passage in ipairs(partition.passages) do
		passages[i] = { id = passage.id, kind = passage.kind, outdoor = passage.outdoor, level = passage.level,
			top = passage.top, areas = passage.areas, floor = passage.floor, center = passage.center, lo = passage.lo,
			hi = passage.hi, joins = passage.joins, doors = Connections(passage.doors) }
	end
	return { version = ROOMS_VERSION, areas = areas, rooms = rooms, passages = passages, levels = partition.levels }
end

local function Find(graph, windows, yield)
	return Rooms.Partition(graph, yield, windows)
end

-- Finds the rooms now, at once, and keeps them (ns_rooms_find, for tuning on
-- a bench map): the seconds it took.
function Controller:FindRoomsNow()
	local started = SysTime()
	local work = { CheckYield = function() end }
	self.rooms = Find(self:RoomGraph(work))
	self.roomStore:Write(Saved(self.rooms, #navmesh.GetAllNavAreas()))
	return SysTime() - started
end

local function Loaded(saved)
	local of, passageOf = {}, {}
	for _, room in ipairs(saved.rooms) do
		for _, id in ipairs(room.areas) do of[id] = room end
	end
	for _, passage in ipairs(saved.passages) do
		for _, id in ipairs(passage.areas) do passageOf[id] = passage end
	end
	return { rooms = saved.rooms, passages = saved.passages, levels = saved.levels, of = of, passageOf = passageOf }
end

-- The map's rooms, or nil while they are being found (the first ask starts
-- that, on the slow lane).
function Controller:Rooms()
	if self.rooms then return self.rooms end
	local areas = #navmesh.GetAllNavAreas()
	local saved = self.roomStore:Read()
	if saved and saved.version == ROOMS_VERSION and saved.areas == areas and saved.rooms then
		self.rooms = Loaded(saved)
		return self.rooms
	end
	if self.roomsFinding then return nil end
	self.roomsFinding = Transaction.Spawn(WS.SlowTransactions, function(work)
		local graph, windows = self:RoomGraph(work)
		return Find(graph, windows, function() work:CheckYield() end)
	end):Within(WS.Deadline(ROOMS_TIME))
	self.roomsFinding:OnSettle(function(settled)
		self.roomsFinding = nil
		if settled:State() ~= Transaction.COMMITTED then
			ErrorNoHalt("AI war: the rooms were not found: " .. tostring(settled:Error() or Transaction.Message(settled:Refusal())) .. "\n")
			return
		end
		self.rooms = settled:Value()
		self.roomStore:Write(Saved(self.rooms, areas))
	end)
	return nil
end

-- The rooms for the debug overlay (the game_aiwar_rooms event,
-- features/nbdebug/sh.lua; its rooms part), every ROOMS_DEBUG_INTERVAL to
-- the admins viewing it: each room's centre, doors and label, the label
-- with what each team knows of it (wartactics.intel's Guarded and Traffic,
-- and a support base's strength).
local ROOMS_DEBUG_INTERVAL = 5
local ROOMS_MAX, DOORS_MAX = 255, 63
local TEAM_TAG = { [WS.TEAM_RED] = "RED", [WS.TEAM_BLUE] = "BLU" }

-- Indoors or out, and its level (from its foot to its head on a stairwell).
local function Where(room)
	local level = room.level == room.top and "level " .. room.level or string.format("levels %d-%d", room.level, room.top)
	return (room.outdoor and "outdoors, " or "indoors, ") .. level
end

function Controller:RoomLabel(room, now)
	local label = string.format("%s %d (%s): %d areas", room.kind, room.id, Where(room), #room.areas)
	for _, team in ipairs({ WS.TEAM_RED, WS.TEAM_BLUE }) do
		local intel = self.intel and self.intel[team]
		if intel then
			local held, traffic = intel:Guarded(room.id, now), intel:Traffic(room.id, now)
			if held > 0 or traffic > 0 then
				label = label .. string.format("; %s knows: held %d, traffic %d", TEAM_TAG[team], held, traffic)
			end
			for _, base in ipairs(intel:SupportBases(now)) do
				if base.room == room.id then label = label .. string.format(", support base %d", base.strength) end
			end
		end
	end
	return label
end

local function V(p) return Vector(p.x, p.y, p.z) end

local function Sent(connections)
	local sent = {}
	for j = 1, math.min(#connections, DOORS_MAX) do
		local c = connections[j]
		sent[j] = { pos = V(c.pos), leads = c.leads[1] or 0 }
	end
	return sent
end

function Controller:SendRoomsDebug(viewers, now)
	if now < (self.nextRoomsDebug or 0) then return end
	self.nextRoomsDebug = now + ROOMS_DEBUG_INTERVAL
	local partition = self:Rooms()
	if not partition then return end
	local rooms, passages = {}, {}
	for i = 1, math.min(#partition.rooms, ROOMS_MAX) do
		local room = partition.rooms[i]
		rooms[i] = { id = room.id, center = V(room.center), lo = V(room.lo), hi = V(room.hi), outdoor = room.outdoor,
			label = self:RoomLabel(room, now), doors = Sent(room.doors), windows = Sent(room.windows) }
	end
	for i = 1, math.min(#partition.passages, ROOMS_MAX) do
		local passage = partition.passages[i]
		passages[i] = { lo = V(passage.lo), hi = V(passage.hi),
			label = string.format("%s %d: joins %s", passage.kind, passage.id, table.concat(passage.joins, ", ")) }
	end
	WS.Events.Fire("game_aiwar_rooms", { rooms = rooms, passages = passages }, viewers)
end

-- ns_rooms_print's lines: how many rooms of each kind, indoors and out, the
-- corridors, doors and windows, the areas in no room or corridor, and the
-- largest rooms with their doors and windows.
local LARGEST = 8

function Controller:RoomReport()
	local rooms = self:Rooms()
	if not rooms then return { "ns_rooms_print: the rooms are being found; ask again in a moment" } end
	local kinds, doors, windows, loose = {}, 0, 0, 0
	for _, room in ipairs(rooms.rooms) do
		local key = room.kind .. " " .. Where(room)
		kinds[key] = (kinds[key] or 0) + 1
		doors, windows = doors + #room.doors, windows + #room.windows
	end
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if not rooms.of[area:GetID()] and not rooms.passageOf[area:GetID()] then loose = loose + 1 end
	end
	local counts = {}
	for key, n in SortedPairs(kinds) do counts[#counts + 1] = n .. " " .. key end
	local lines = { string.format("ns_rooms_print: %d levels, %d rooms (%s), %d corridors, %d doors, %d windows, %d nav areas in neither",
		#rooms.levels, #rooms.rooms, table.concat(counts, ", "), #rooms.passages, doors, windows, loose) }
	for _, level in ipairs(rooms.levels) do
		lines[#lines + 1] = string.format("  level %d: floors at %d to %d, rooms %s", level.id, level.low, level.high,
			table.concat(level.rooms, ", "))
	end
	local largest = {}
	for _, room in ipairs(rooms.rooms) do largest[#largest + 1] = room end
	table.sort(largest, function(a, b) return a.floor > b.floor end)
	for i = 1, math.min(LARGEST, #largest) do
		local room = largest[i]
		lines[#lines + 1] = string.format("  %s %d (%s): %d areas, floor %d, at (%d, %d, %d), %d doors, %d windows", room.kind,
			room.id, Where(room), #room.areas, room.floor, room.center.x, room.center.y, room.center.z, #room.doors,
			#room.windows)
	end
	return lines
end
