-- Part of the npc controller (sv.lua): the spawn rooms' teams, and the
-- blockers on the nav mesh (func_door and func_brush), as the path costs
-- and route searches see them.
local Controller = ...
local Doors = nextsoldier.doors
local Brushes = nextsoldier.brushes

local NOBODY = WS.TEAM_UNASSIGNED

-- games.gameplay.spawn, required on first use: only maps with spawn rooms, which
-- have rounds, need it.
local Spawn

-- The teams of the enabled spawn points inside a func_respawnroom, and the
-- team of the spawn point nearest its centre (nil on a map without any).
local function SpawnTeamsIn(room)
	local teams, nearest, nearestDistance = {}, nil, nil
	local center = room:WorldSpaceCenter()
	for _, spawn in ipairs(ents.FindByClass("info_player_teamspawn")) do
		local s = WS.SpawnState(spawn)
		if not s.disabled and s.team > WS.TEAM_SPECTATOR then
			if room:PointIsWithin(spawn:GetPos()) then teams[#teams + 1] = s.team end
			local d = spawn:GetPos():DistToSqr(center)
			if not nearestDistance or d < nearestDistance then nearest, nearestDistance = s.team, d end
		end
	end
	return teams, nearest
end

-- TF_NAV_SPAWN_ROOM_RED/_BLUE, which GMod's nav areas do not carry: the
-- areas in spawn rooms, nav area id -> the team of the func_respawnroom
-- holding the area's centre, as its spawns say (games.gameplay.spawn's
-- RoomTeam), the first room in FindByClass' order taking an area; areas in
-- none left out. Found again as a round starts (rooms take their teams at
-- round start, some only once the round is active) and as a room or a spawn
-- changes mid-round (WSSpawnRoomsChanged: a payload map's forward spawn
-- becomes the attackers' as a point falls), for every area at once, so a
-- route search is told them (wetsands.navsearch's told.rooms).
function Controller:SpawnRooms()
	local rooms = self.spawnRooms
	if rooms then return rooms end
	rooms = {}
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		Spawn = Spawn or gameplay.spawn
		local team = Spawn.RoomTeam(room.team, SpawnTeamsIn(room))
		local mins, maxs = room:WorldSpaceAABB()
		for _, area in ipairs(navmesh.FindInBox(mins, maxs)) do
			local id = area:GetID()
			if not rooms[id] and room:PointIsWithin(area:GetCenter()) then rooms[id] = team end
		end
	end
	for id, team in pairs(rooms) do
		if team == NOBODY then rooms[id] = nil end
	end
	self.spawnRooms = rooms
	return rooms
end

-- The team whose spawn room holds the area, or NOBODY.
function Controller:SpawnRoomTeam(area)
	return self:SpawnRooms()[area:GetID()] or NOBODY
end

-- Blockers on the nav mesh, as TF2's nav mesh has them
-- (CTFNavMesh::ComputeBlockedAreas): which areas each func_door blocks to
-- whom (nextsoldier.doors), and which a solid func_brush stands in
-- (nextsoldier.brushes), taken again every BLOCKER_REFRESH seconds a
-- route is asked for, as doors open and shut and brushes are toggled with
-- the round (setup gates, doors opened by captures, walls map logic turns
-- on). The box searched reaches DOOR_FLOOR below a door, so the areas on
-- the floor it closes on count.
local BLOCKER_REFRESH = 1
local DOOR_FLOOR = Vector(0, 0, 32)
local UNASSIGNED = WS.TEAM_UNASSIGNED

local Overlapping = math.box.Overlaps

-- The enabled trigger_multiples, with their boxes and the team their
-- filter_activator_tfteam admits (or nil).
local function DoorTriggers()
	local triggers = {}
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		if not trigger:GetInternalVariable("m_bDisabled") then
			local mins, maxs = trigger:WorldSpaceAABB()
			local filter, owner = trigger:GetInternalVariable("m_hFilter"), nil
			if IsValid(filter) and filter:GetClass() == "filter_activator_tfteam" and filter.team ~= UNASSIGNED then owner = filter.team end
			triggers[#triggers + 1] = { mins = mins, maxs = maxs, owner = owner, outputs = WS.KeyValues(trigger).outputs }
		end
	end
	return triggers
end

local function Block(blocked, area, team)
	local id = area:GetID()
	blocked[id] = blocked[id] or {}
	table.insert(blocked[id], team)
end

-- TestAndBlockOverlappingAreas: the areas the brush stands in.
local NW, NE, SE, SW = 0, 1, 2, 3

local function BrushIn(brush, area)
	local from, to, mins, maxs = Brushes.Sweep(area:GetCorner(NW), area:GetCorner(NE), area:GetCorner(SE), area:GetCorner(SW),
		area:GetSizeX(), area:GetSizeY())
	local tr = util.TraceHull({
		start = from,
		endpos = to,
		mins = Vector(mins.x, mins.y, mins.z),
		maxs = Vector(maxs.x, maxs.y, maxs.z),
		mask = MASK_PLAYERSOLID,
		filter = function(ent) return ent == brush end,
		ignoreworld = true,
	})
	return tr.Hit and tr.Entity == brush
end

-- A brush's areas, swept again only once it has moved: a map may have
-- many func_brushes, some over hundreds of areas.
function Controller:BrushAreas(brush)
	local pos, cached = brush:GetPos(), self.brushAreas[brush]
	if cached and cached.pos == pos then return cached.areas end
	local mins, maxs = brush:WorldSpaceAABB()
	local areas = {}
	for _, area in ipairs(navmesh.FindInBox(mins, maxs)) do
		if BrushIn(brush, area) then areas[#areas + 1] = area end
	end
	self.brushAreas[brush] = { pos = pos, areas = areas }
	return areas
end

-- A floor door's span (nextsoldier.doors): the box of areas on it where
-- it lies closed (m_vecPosition1, a func_door's; a rotating door has none
-- and is taken where it stands), inset FLOOR_INSET so the
-- ground it bridges stays open, and up to a step above its top.
local FLOOR_INSET = Vector(16, 16, 0)
local FLOOR_STEP = Vector(0, 0, 18)

local function FloorSpan(door, mins, maxs)
	local closed = door:GetInternalVariable("m_vecPosition1")
	local shift = isvector(closed) and closed - door:GetPos() or Vector(0, 0, 0)
	return mins + shift + FLOOR_INSET, maxs + shift - FLOOR_INSET + FLOOR_STEP
end

function Controller:RefreshBlockers(now)
	if now < self.nextBlockerRefresh then return end
	self.nextBlockerRefresh = now + BLOCKER_REFRESH
	local blocked, triggers, states, walls = {}, DoorTriggers(), setmetatable({}, { __mode = "k" }), {}
	local doorAreas = {}
	self.doorAreas = doorAreas
	self.doorStates = states
	self.doorWalls = walls
	-- exactly func_brush: func_respawnroomvisualizer, a func_brush too, is not one
	for _, brush in ipairs(ents.FindByClass("func_brush")) do
		if brush:IsSolid() then
			for _, area in ipairs(self:BrushAreas(brush)) do Block(blocked, area, Doors.ANY) end
		end
	end
	for _, door in ipairs(ents.FindByClass("func_door*")) do
		local mins, maxs = door:WorldSpaceAABB()
		local size = maxs - mins
		local state = {
			floor = Doors.IsFloor(size),
			closed = Doors.IsClosed(door:GetInternalVariable("m_toggle_state")),
			locked = door:GetInternalVariable("m_bLocked") == true,
			touchOpens = Doors.TouchOpens(door:GetSpawnFlags()),
			controlled = false,
		}
		-- a trigger controls the door when it opens it; an unnamed door, which
		-- no output can name, when it overlaps it
		local name = door:GetName()
		for _, trigger in ipairs(triggers) do
			if Overlapping(mins, maxs, trigger.mins, trigger.maxs) and (name == "" or Doors.Opens(trigger.outputs, name)) then
				state.controlled = true
				state.owner = trigger.owner or state.owner
			end
		end
		states[door] = state
		local team = Doors.BlockedTeam(state)
		state.blocks = team
		if state.floor then mins, maxs = FloorSpan(door, mins, maxs) end
		for _, area in ipairs(navmesh.FindInBox(mins - DOOR_FLOOR, maxs)) do
			doorAreas[area:GetID()] = true
			if team then Block(blocked, area, team) end
			if Doors.IsWall(state) then walls[area:GetID()] = true end
		end
	end
	local before = self.navBlocked
	self.navBlocked = blocked
	self.closedFor, self.engineClosedFor = {}, {}
	local signature = {}
	for id, teams in SortedPairs(blocked) do signature[#signature + 1] = id .. "=" .. table.concat(teams, "+") end
	signature = table.concat(signature, ",")
	if signature ~= self.blockerSignature then
		self.blockerSignature = signature
		self:NoteBlockerChange(Doors.Changed(before, blocked))
	end
end

-- The blocker generations kept, and which areas each changed.
local BLOCKER_LOG = 64

-- A new generation: changes (area id -> true), or nil when what changed is
-- not known (the mesh's links: WSNavLinked).
function Controller:NoteBlockerChange(changes)
	self.blockerGeneration = self.blockerGeneration + 1
	local log = self.blockerLog
	log[#log + 1] = {
		generation = self.blockerGeneration,
		changes = changes,
	}
	if #log > BLOCKER_LOG then table.remove(log, 1) end
end

-- The areas whose blocking changed after generation: area id -> true, or
-- nil when that is not known (a change of unknown extent, or older than the
-- log keeps).
function Controller:BlockerChangesSince(generation)
	self:RefreshBlockers(CurTime())
	local log = self.blockerLog
	if generation >= self.blockerGeneration then return {} end
	if #log == 0 or log[1].generation > generation + 1 then return nil end
	local merged = {}
	for _, entry in ipairs(log) do
		if entry.generation > generation then
			if entry.changes == nil then return nil end
			for id in pairs(entry.changes) do merged[id] = true end
		end
	end
	return merged
end

-- Whether a door or brush blocks the area to anyone.
function Controller:AreaBlocked(id)
	self:RefreshBlockers(CurTime())
	local teams = self.navBlocked[id]
	return teams ~= nil and #teams > 0
end

-- The areas a shut door no trigger opens stands in (a setup gate): a copy,
-- area id -> true.
function Controller:DoorWalls()
	self:RefreshBlockers(CurTime())
	local walls = {}
	for id in pairs(self.doorWalls or {}) do walls[id] = true end
	return walls
end

-- Counts the changes to what the blockers block (a door shutting on a
-- capture, a brush switched on), and to the mesh's links (seams linked,
-- ws/sv_nav.lua): a route planned under an older count may lead into a
-- blocker, or miss a way.
function Controller:BlockerGeneration()
	self:RefreshBlockers(CurTime())
	return self.blockerGeneration
end

-- How the blockers see a func_door: { closed, locked, controlled, owner, blocks
-- (the team it blocks, foundation.npc.doors.ANY, or nil) }, or nil.
function Controller:DoorState(door)
	self:RefreshBlockers(CurTime())
	return self.doorStates and self.doorStates[door]
end

-- Whether a shut door no trigger opens (a setup gate) stands in the area.
function Controller:DoorWallIn(area)
	self:RefreshBlockers(CurTime())
	return self.doorWalls ~= nil and self.doorWalls[area:GetID()] == true
end

-- The engine's own blocked flag (CNavArea::IsBlocked), without what it
-- makes of doors: it marks an area blocked wherever its hull test finds a
-- solid entity, a shut door among them, and TF2 maps put an area under
-- every door. Doors are judged by nextsoldier.doors instead; the
-- map's func_nav_blockers still count.
function Controller:EngineBlocks(area, team)
	if not area:IsBlocked(team) then return false end
	self:RefreshBlockers(CurTime())
	return not (self.doorAreas and self.doorAreas[area:GetID()])
end

-- The areas closed to the team, nav area id -> true, as a route search is
-- told them (wetsands.navsearch's told.closed): those a door or brush
-- closes to it (unless ignoreBlockers), and those the engine blocks
-- (EngineBlocks). Taken again with the blockers, so as fresh as they are:
-- the engine's flag read for every area at once costs about a
-- millisecond, where read as a search reaches each area it cost every
-- search a call into Lua an area.
function Controller:ClosedFor(team, ignoreBlockers)
	self:RefreshBlockers(CurTime())
	local engine = self.engineClosedFor[team]
	if not engine then
		engine = {}
		local doorAreas = self.doorAreas or {}
		for _, area in ipairs(navmesh.GetAllNavAreas()) do
			local id = area:GetID()
			if area:IsBlocked(team) and not doorAreas[id] then engine[id] = true end
		end
		self.engineClosedFor[team] = engine
	end
	if ignoreBlockers then return engine end
	local closed = self.closedFor[team]
	if not closed then
		closed = {}
		for id in pairs(engine) do closed[id] = true end
		for id, teams in pairs(self.navBlocked) do
			if Doors.Blocks(teams, team) then closed[id] = true end
		end
		self.closedFor[team] = closed
	end
	return closed
end

-- Whether a door or brush closes the area to the team.
function Controller:NavBlocks(area, team)
	self:RefreshBlockers(CurTime())
	return Doors.Blocks(self.navBlocked[area:GetID()], team)
end

local function ForgetSpawnRooms()
	Controller.spawnRooms = nil
end
hook.Add("PostCleanupMap", "ws_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("WSRoundActivate", "ws_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("WSRoundActive", "ws_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("WSSpawnRoomsChanged", "ws_npc_spawn_rooms", ForgetSpawnRooms)
