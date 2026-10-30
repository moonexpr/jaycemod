-- Part of the AI war controller (sv.lua): the map's rooms
-- (wartactics.rooms, docs/special-missions-plan.md §2.1). The nav mesh is
-- read into Partition's graph, each link's shared edge measured from the
-- two areas' extents and marked a door where a func_door stands over
-- either area, each area by a wall where a side is not wholly met, and
-- partitioned once a map on the slow lane (a transaction, yielding as it
-- goes); the rooms are kept in the map's data
-- (roomStore), found again only when the mesh's area count changes.
-- ns_rooms_print says what was found.
local Controller = ...
local Rooms = wartactics.rooms
local Transaction = transaction

-- The slow lane gives 2 ms a second; pl_upward's 5,410 areas take some
-- 0.46 s of work, so several minutes, once a map: the rooms are kept.
local ROOMS_TIME = 900
local DOOR_CLASSES = { "func_door", "func_door_rotating", "prop_door_rotating" }

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

-- The areas a door stands over.
local function DoorAreas()
	local under = {}
	for _, class in ipairs(DOOR_CLASSES) do
		for _, door in ipairs(ents.FindByClass(class)) do
			local mins, maxs = door:WorldSpaceAABB()
			for _, area in ipairs(navmesh.FindInBox(mins, maxs)) do under[area:GetID()] = true end
		end
	end
	return under
end

-- Whether an area is by a wall: one of its sides (north and south along x,
-- east and west along y) not wholly met by the neighbours on it.
local EDGE_SLACK = 4

local function ByWall(area)
	for dir = 0, 3 do
		local length = (dir == 0 or dir == 2) and area:GetSizeX() or area:GetSizeY()
		local met = 0
		for _, other in ipairs(area:GetAdjacentAreasAtSide(dir) or {}) do met = met + (SharedEdge(area, other)) end
		if met < length - EDGE_SLACK then return true end
	end
	return false
end

-- The nav mesh as Partition's graph, yielding as it goes.
function Controller:RoomGraph(work)
	local under, graph = DoorAreas(), {}
	for i, area in ipairs(navmesh.GetAllNavAreas()) do
		local id, links = area:GetID(), {}
		for _, other in ipairs(area:GetAdjacentAreas()) do
			local width, middle = SharedEdge(area, other)
			links[#links + 1] = { to = other:GetID(), width = width, middle = middle,
				door = under[id] == true or under[other:GetID()] == true }
		end
		graph[id] = { center = Point(area:GetCenter()), floor = area:GetSizeX() * area:GetSizeY(), edge = ByWall(area),
			links = links }
		if i % 64 == 0 then work:CheckYield() end
	end
	return graph
end

-- What is kept: the rooms with their areas and doors, and the mesh's size.
local function Saved(partition, areas)
	local rooms = {}
	for i, room in ipairs(partition.rooms) do
		local doors = {}
		for j, door in ipairs(room.doors) do
			doors[j] = { pos = door.pos, width = door.width, area = door.area, leads = door.leads }
		end
		rooms[i] = { id = room.id, areas = room.areas, floor = room.floor, center = room.center, doors = doors }
	end
	return { areas = areas, rooms = rooms }
end

local function Loaded(saved)
	local of = {}
	for _, room in ipairs(saved.rooms) do
		for _, id in ipairs(room.areas) do of[id] = room end
	end
	return { rooms = saved.rooms, of = of }
end

-- The map's rooms, or nil while they are being found (the first ask starts
-- that, on the slow lane).
function Controller:Rooms()
	if self.rooms then return self.rooms end
	local areas = #navmesh.GetAllNavAreas()
	local saved = self.roomStore:Read()
	if saved and saved.areas == areas and saved.rooms then
		self.rooms = Loaded(saved)
		return self.rooms
	end
	if self.roomsFinding then return nil end
	self.roomsFinding = Transaction.Spawn(WS.SlowTransactions, function(work)
		return Rooms.Partition(self:RoomGraph(work), function() work:CheckYield() end)
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

function Controller:RoomLabel(room, now)
	local label = string.format("room %d: %d areas", room.id, #room.areas)
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

function Controller:SendRoomsDebug(viewers, now)
	if now < (self.nextRoomsDebug or 0) then return end
	self.nextRoomsDebug = now + ROOMS_DEBUG_INTERVAL
	local partition = self:Rooms()
	if not partition then return end
	local rooms = {}
	for i = 1, math.min(#partition.rooms, ROOMS_MAX) do
		local room = partition.rooms[i]
		local doors = {}
		for j = 1, math.min(#room.doors, DOORS_MAX) do
			local door = room.doors[j]
			doors[j] = { pos = Vector(door.pos.x, door.pos.y, door.pos.z), leads = door.leads[1] or 0 }
		end
		rooms[i] = { id = room.id, center = Vector(room.center.x, room.center.y, room.center.z),
			label = self:RoomLabel(room, now), doors = doors }
	end
	WS.Events.Fire("game_aiwar_rooms", { rooms = rooms }, viewers)
end

-- ns_rooms_print's lines: how many rooms, doors and dead ends, the areas in
-- passages, and the largest rooms with their doors.
local LARGEST = 8

function Controller:RoomReport()
	local rooms = self:Rooms()
	if not rooms then return { "ns_rooms_print: the rooms are being found; ask again in a moment" } end
	local doors, dead, passages = 0, 0, 0
	for _, room in ipairs(rooms.rooms) do
		doors = doors + #room.doors
		for _, door in ipairs(room.doors) do if #door.leads == 0 then dead = dead + 1 end end
	end
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if not rooms.of[area:GetID()] then passages = passages + 1 end
	end
	local lines = { string.format("ns_rooms_print: %d rooms, %d doors (%d dead ends), %d nav areas in passages",
		#rooms.rooms, doors, dead, passages) }
	local largest = {}
	for _, room in ipairs(rooms.rooms) do largest[#largest + 1] = room end
	table.sort(largest, function(a, b) return a.floor > b.floor end)
	for i = 1, math.min(LARGEST, #largest) do
		local room = largest[i]
		lines[#lines + 1] = string.format("  room %d: %d areas, floor %d, at (%d, %d, %d), %d doors", room.id, #room.areas,
			room.floor, room.center.x, room.center.y, room.center.z, #room.doors)
	end
	return lines
end
