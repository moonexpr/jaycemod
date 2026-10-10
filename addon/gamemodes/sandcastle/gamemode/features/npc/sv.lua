-- The npc feature's controller. It owns one foundation.npc Npc per NPC
-- entity, the foundation.npc.spawner models, a registry by kind and the
-- per-variant shared state, and checks the navigation mesh once per map.
-- The rules live in the models; this file only feeds them engine events and
-- turns their answers into entities.
local NpcSystem = WS.require("foundation.npc")
local Spawner = WS.require("foundation.npc.spawner")
local Profile = WS.require("foundation.npc.profile")
local Route = WS.require("foundation.npc.route")
local Portal = WS.require("foundation.npc.portal")
local Doors = WS.require("foundation.npc.doors")
local Brushes = WS.require("foundation.npc.brushes")

local NAV_MESSAGE = "ws_nextbot: %s has no usable navigation mesh; run mp_nav_generate (or .devtools/bin/nav_convert.py for TF2's own)"
local BOSS_HEALTH = "ws_boss_health" -- the boss bar's fraction; 0 hides it

local Controller = {
	npcs = {}, -- entity -> Npc
	variantNames = {}, -- entity -> variant name
	kinds = {}, -- kind -> { [entity] = true }
	shared = {}, -- variant name -> table
	precached = {}, -- variant name -> true once its particle systems are precached
	spawners = {}, -- spawner entity -> Spawner
	spawnedBy = {}, -- NPC entity -> Spawner
	navChecked = false,
	pathProfile = nil, -- a foundation.npc.profile while ws_path_profile's window is open
	pathWatch = {}, -- entity index -> { costs } while the nbdebug feature watches its path searches
	spawnRoomTeams = {}, -- nav area id -> the team whose spawn room holds it, this round
	searches = {}, -- the Lua route searches still running, oldest first
	neighbors = {}, -- nav area id -> its floor neighbours' ids (the mesh is fixed for the map)
	centers = {}, -- nav area id -> its centre
	navBlocked = {}, -- nav area id -> the teams its doors and brushes block (foundation.npc.doors)
	nextBlockerRefresh = 0,
	blockerGeneration = 0,
	brushAreas = setmetatable({}, { __mode = "k" }), -- func_brush -> { pos, areas it stands in }
}

function Controller:CheckNavMesh()
	if self.navChecked then return end
	self.navChecked = true
	if not navmesh.IsLoaded() or navmesh.GetNavAreaCount() == 0 then
		print(string.format(NAV_MESSAGE, game.GetMap()))
	end
end

-- The NPCs bound to one variant, oldest first.
function Controller:NpcsOf(variantName)
	local found = {}
	for ent, name in pairs(self.variantNames) do
		if name == variantName then found[#found + 1] = ent end
	end
	table.sort(found, function(a, b) return a:GetCreationID() < b:GetCreationID() end)
	local npcs = {}
	for i, ent in ipairs(found) do npcs[i] = self.npcs[ent] end
	return npcs
end

-- The first NPC of a variant precaches the particle systems it may send
-- (their files are sh.lua's), so clients can look the names up; before it
-- binds, since its first action may send one.
function Controller:PrecacheParticles(variantName, variant)
	if self.precached[variantName] then return end
	self.precached[variantName] = true
	for _, name in ipairs(NpcSystem.Particles(variant)) do PrecacheParticleSystem(name) end
end

function Controller:Bind(ent, variantName, config)
	self:CheckNavMesh()
	local variant = WS.require(variantName)
	self:PrecacheParticles(variantName, variant)
	local npc = NpcSystem.Npc.New(variant, config, ent)
	self.npcs[ent] = npc
	self.variantNames[ent] = variantName
	self.kinds[variant.KIND] = self.kinds[variant.KIND] or {}
	self.kinds[variant.KIND][ent] = true
	NpcSystem.Cull(variant, self:NpcsOf(variantName))
	return npc
end

function Controller:Unbind(ent)
	local npc = self.npcs[ent]
	npc:Destroy()
	self.kinds[npc.variant.KIND][ent] = nil
	self.npcs[ent] = nil
	self.variantNames[ent] = nil
	local spawner = self.spawnedBy[ent]
	if spawner then
		spawner:Died(ent)
		self.spawnedBy[ent] = nil
	end
end

function Controller:All(kind)
	local found = {}
	for ent in pairs(self.kinds[kind] or {}) do found[#found + 1] = ent end
	return found
end

function Controller:Shared(variantName)
	self.shared[variantName] = self.shared[variantName] or {}
	return self.shared[variantName]
end

-- Every spawnable class of this gamemode takes its config through Configure.
function Controller:Spawn(class, config, pos, ang)
	local ent = ents.Create(class)
	ent:Configure(config)
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent:Spawn()
	return ent
end

-- A boss's convars (its variant's CONVARS: TF2's names and defaults), each
-- created as a cheat the first time it is asked for, and their values now.
function Controller:BossConvars(defaults)
	local values = {}
	for name, default in pairs(defaults) do
		local convar = GetConVar(name) or CreateConVar(name, tostring(default), FCVAR_CHEAT)
		values[name] = convar:GetFloat()
	end
	return values
end

function Controller:SetBossHealth(fraction)
	SetGlobal2Float(BOSS_HEALTH, fraction)
end

function Controller:BindSpawner(ent, config)
	local spawner = Spawner.New(config)
	self.spawners[ent] = spawner
	return spawner
end

-- Spawn at the spawner's origin whatever the models ask for. A spawner the
-- map removed is forgotten.
function Controller:ThinkSpawners(now)
	for ent, spawner in pairs(self.spawners) do
		if not IsValid(ent) then
			self.spawners[ent] = nil
		else
			local request = spawner:Think(now, math.Rand)
			if request then
				local npc = self:Spawn(request.class, request.config, ent:GetPos(), ent:GetAngles())
				spawner:Spawned(npc)
				self.spawnedBy[npc] = spawner
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Path costs: one step builder for both searches. A path strategy
-- (foundation.npc.path) reads the same step whether the engine's search
-- (Path:Compute on a NextBot) or the Lua one (foundation.npc.route, for
-- NPCs that are not NextBots) asks.

local NOBODY = WS.TEAM_UNASSIGNED

-- TF_NAV_SPAWN_ROOM_RED/_BLUE, which GMod's nav areas do not carry: the
-- team of the func_respawnroom holding the area's centre, found once per
-- area per round (rooms take their teams at round start, some only once
-- the round is active).
function Controller:SpawnRoomTeam(area)
	local id = area:GetID()
	local team = self.spawnRoomTeams[id]
	if team then return team end
	team = NOBODY
	local center = area:GetCenter()
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		if room:PointIsWithin(center) then
			team = room.team
			break
		end
	end
	self.spawnRoomTeams[id] = team
	return team
end

-- Blockers on the nav mesh, as TF2's nav mesh has them
-- (CTFNavMesh::ComputeBlockedAreas): which areas each func_door blocks to
-- whom (foundation.npc.doors), and which a solid func_brush stands in
-- (foundation.npc.brushes), taken again every BLOCKER_REFRESH seconds a
-- route is asked for, as doors open and shut and brushes are toggled with
-- the round (setup gates, doors opened by captures, walls map logic turns
-- on). The box searched reaches DOOR_FLOOR below a door, so the areas on
-- the floor it closes on count.
local BLOCKER_REFRESH = 1
local DOOR_FLOOR = Vector(0, 0, 32)
local UNASSIGNED = WS.TEAM_UNASSIGNED

local function Overlapping(aMins, aMaxs, bMins, bMaxs)
	return aMins.x <= bMaxs.x and bMins.x <= aMaxs.x and aMins.y <= bMaxs.y and bMins.y <= aMaxs.y
		and aMins.z <= bMaxs.z and bMins.z <= aMaxs.z
end

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

-- A floor door's span (foundation.npc.doors): the box of areas on it where
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
	self.navBlocked = blocked
	local signature = {}
	for id, teams in SortedPairs(blocked) do signature[#signature + 1] = id .. "=" .. table.concat(teams, "+") end
	signature = table.concat(signature, ",")
	if signature ~= self.blockerSignature then
		self.blockerSignature = signature
		self.blockerGeneration = self.blockerGeneration + 1
	end
end

-- Counts the changes to what the blockers block (a door shutting on a
-- capture, a brush switched on): a route planned under an older count may
-- lead into one.
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
-- every door. Doors are judged by foundation.npc.doors instead; the
-- map's func_nav_blockers still count.
function Controller:EngineBlocks(area, team)
	if not area:IsBlocked(team) then return false end
	self:RefreshBlockers(CurTime())
	return not (self.doorAreas and self.doorAreas[area:GetID()])
end

-- Whether a door or brush closes the area to the team.
function Controller:NavBlocks(area, team)
	self:RefreshBlockers(CurTime())
	return Doors.Blocks(self.navBlocked[area:GetID()], team)
end

local function ForgetSpawnRooms()
	Controller.spawnRoomTeams = {}
end
hook.Add("PostCleanupMap", "ws_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("WSRoundActivate", "ws_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("WSRoundActive", "ws_npc_spawn_rooms", ForgetSpawnRooms)

-- Fills `step` for the move from fromArea (nil for the first area) into
-- area. traversable(area) is the mover's ILocomotion::IsAreaTraversable.
function Controller:FillStep(step, area, fromArea, ladder, length, fromCostSoFar, traversable)
	step.hasFrom = IsValid(fromArea)
	if not step.hasFrom then return step end
	step.traversable = traversable(area)
	step.ladderLength = IsValid(ladder) and ladder:GetLength() or nil
	step.length = length
	step.centerDistance = area:GetCenter():Distance(fromArea:GetCenter())
	step.heightChange = fromArea:ComputeAdjacentConnectionHeightChange(area)
	step.fromCostSoFar = fromCostSoFar
	step.areaId = area:GetID()
	step.spawnRoomTeam = self:SpawnRoomTeam(area)
	step.attributes = area:GetAttributes()
	return step
end

-- The cost callback Path:Compute takes (IPathCost), for a NextBot. bot is
-- the strategy's bot table; its `now` is kept current. Areas a door or a
-- brush closes to the bot's team are not traversable. While a path profile
-- measures a compute, or the nbdebug feature watches it, ent.pathProbe
-- counts the calls and their time, and its recorder (if any) each cost.
function Controller:EnginePathCost(ent, strategy, limits, bot)
	local step = {}
	self:RefreshBlockers(CurTime())
	local team = WS.TeamNumber(ent)
	local function Traversable(area)
		return ent.loco:IsAreaTraversable(area) and not Doors.Blocks(self.navBlocked[area:GetID()], team)
	end
	local function Cost(area, fromArea, ladder, elevator, length)
		self:FillStep(step, area, fromArea, ladder, length, IsValid(fromArea) and fromArea:GetCostSoFar() or 0, Traversable)
		bot.now = CurTime()
		return strategy.Cost(step, limits, bot)
	end
	return function(area, fromArea, ladder, elevator, length)
		local probe = ent.pathProbe
		if not probe then return Cost(area, fromArea, ladder, elevator, length) end
		local started = SysTime()
		local cost = Cost(area, fromArea, ladder, elevator, length)
		probe.costCalls = probe.costCalls + 1
		probe.costSeconds = probe.costSeconds + SysTime() - started
		if probe.recorder then probe.recorder:Record(area:GetID(), IsValid(fromArea) and fromArea:GetID() or nil, cost) end
		return cost
	end
end

-- The graph foundation.npc.route searches: nav area ids, their floor
-- neighbours in GetAdjacentAreas' order (north, east, south, west; nav
-- ladders are left out, as no engine NPC climbs them), the strategy's cost
-- with ILocomotion's default traversal rule (not blocked for the mover's
-- team), and the straight-line estimate to the goal position. The engine
-- measures a floor connection as the distance between centres, so that is
-- the step's length.
local NavGraph = {}
NavGraph.__index = NavGraph

local function Area(id)
	return navmesh.GetNavAreaByID(id)
end

local function Center(id)
	local center = Controller.centers[id]
	if not center then
		center = Area(id):GetCenter()
		Controller.centers[id] = center
	end
	return center
end

function NavGraph:Neighbors(id)
	local ids = Controller.neighbors[id]
	if not ids then
		ids = {}
		for i, area in ipairs(Area(id):GetAdjacentAreas()) do ids[i] = area:GetID() end
		Controller.neighbors[id] = ids
	end
	return ids
end

function NavGraph:Cost(fromId, toId, costSoFar)
	self.controller:FillStep(self.step, Area(toId), Area(fromId), nil, Center(toId):Distance(Center(fromId)), costSoFar, self.traversable)
	self.bot.now = CurTime()
	return self.strategy.Cost(self.step, self.limits, self.bot)
end

function NavGraph:Estimate(id)
	return Center(id):Distance(self.goalPos)
end

-- request = { from, to (positions), strategy, limits, bot (the strategy's,
-- with team), avoid(area) -> bool (optional: areas to route around, as
-- if blocked; the goal's area is never avoided), ignoreBlockers (optional:
-- route through doors shut to the team and solid brushes), onDone(route, found) } where route is the list of nav areas
-- from the start's to the goal's (found), or to the one that came closest
-- when the goal is out of reach, and nil when either end is off the mesh.
local NEAREST_AREA_RANGE = 200
-- Each tick the searches run in turn, SEARCH_CHUNK expansions at a time,
-- until SEARCH_SECONDS of the tick are spent. A search may cover the whole
-- mesh, as the engine's may: spread over ticks, that costs time, not a hitch.
local SEARCH_SECONDS = 0.002
local SEARCH_CHUNK = 16

local NEAREST_AREA_FAR = 600

-- The area under pos, else (a point over a wall, a pit or a roof, as a
-- goal offset from a cart's track can be) the nearest at any height.
local function NearestArea(pos)
	local area = navmesh.GetNearestNavArea(pos, false, NEAREST_AREA_RANGE, false, true)
	if IsValid(area) then return area end
	return navmesh.GetNearestNavArea(pos, true, NEAREST_AREA_FAR, false, false)
end

function Controller:RequestRoute(request)
	local start, goal = NearestArea(request.from), NearestArea(request.to)
	if not (IsValid(start) and IsValid(goal)) then
		request.onDone(nil)
		return
	end
	local team = request.bot.team or NOBODY
	self:RefreshBlockers(CurTime())
	local avoid, goalId, ignoreBlockers = request.avoid, goal:GetID(), request.ignoreBlockers
	local graph = setmetatable({
		controller = self,
		step = {},
		strategy = request.strategy,
		limits = request.limits,
		bot = request.bot,
		goalPos = request.to,
		traversable = function(area)
			if avoid and area:GetID() ~= goalId and avoid(area) then return false end
			if not ignoreBlockers and Doors.Blocks(self.navBlocked[area:GetID()], team) then return false end
			return not self:EngineBlocks(area, team)
		end,
	}, NavGraph)
	local watch = self.pathWatch[request.bot.entIndex]
	local observed = watch and self:ObserveRoute(graph, request, start, watch) or nil
	local search = Route.New(graph, start:GetID(), goal:GetID(), navmesh.GetNavAreaCount())
	self.searches[#self.searches + 1] = {
		search = search,
		onDone = request.onDone,
		observed = observed,
	}
end

local function AreasOf(ids)
	local areas = {}
	for i, id in ipairs(ids) do areas[i] = Area(id) end
	return areas
end

-- Runs the searches in turn within the tick's time; each that finishes
-- reports its route.
function Controller:ThinkSearches()
	local deadline = SysTime() + SEARCH_SECONDS
	while #self.searches > 0 and SysTime() < deadline do
		local running = table.remove(self.searches, 1)
		local observed = running.observed
		local began = observed and SysTime()
		local status = running.search:Step(SEARCH_CHUNK)
		if observed then observed.seconds = observed.seconds + SysTime() - began end
		if status == Route.RUNNING then
			self.searches[#self.searches + 1] = running
		else
			local areas, found = AreasOf(running.search:Route()), running.search.status == Route.FOUND
			if observed then self:PublishRoute(running, areas, found) end
			running.onDone(areas, found)
		end
	end
end

function Controller:SearchesRunning()
	return #self.searches
end

-- Where to walk along a route of areas, as the engine's Path::Compute
-- places its points: each step crosses into the next area where
-- foundation.npc.portal says (nearest the previous crossing, off the
-- opening's walled ends), from `start` (default: the first area's centre);
-- then to `goal`, or for a route that fell short of it, to the last area's
-- point nearest it.
local function Rect(area)
	local extent = area:GetExtentInfo()
	return { lo = { x = extent.lo.x, y = extent.lo.y }, hi = { x = extent.hi.x, y = extent.hi.y }, edges = {} }
end

-- The side of `from` that `to` is connected on, or nil.
local function SideOf(from, to)
	for dir = Portal.NORTH, Portal.WEST do
		if from:IsConnectedAtSide(to, dir) then return dir end
	end
	return nil
end

local function Crossing(from, to, pos)
	local dir = SideOf(from, to)
	if not dir then return to:GetClosestPointOnArea(from:GetCenter()) end
	local toRect = Rect(to)
	for side = Portal.NORTH, Portal.WEST do toRect.edges[side] = to:GetAdjacentCountAtSide(side) == 0 end
	local x, y = Portal.ClosestPointInPortal(Rect(from), toRect, dir, pos)
	local crossing = Vector(x, y, 0)
	-- walk out of `from` at a height it can reach
	crossing.z = from:GetZ(crossing)
	return crossing
end

function Controller:RouteWaypoints(areas, goal, found, start)
	local points = {}
	local pos = start or areas[1]:GetCenter()
	for i = 2, #areas do
		pos = Crossing(areas[i - 1], areas[i], pos)
		points[#points + 1] = pos
	end
	points[#points + 1] = found and goal or areas[#areas]:GetClosestPointOnArea(goal)
	return points
end

-------------------------------------------------------------------------------
-- Path profiling: whether the NextBots' path search is worth moving off the
-- main thread (a binary module), measured before anything is built.

local PROFILE_WINDOW_DEFAULT, PROFILE_WINDOW_MAX = 30, 600
local BENCH_DEFAULT, BENCH_MAX = 200, 5000

function Controller:PathProfile()
	return self.pathProfile
end

-- Runs compute(), a Path:Compute through bot's cost function, with a probe
-- on that function (and its costs to `recorder`, if given). Returns what
-- compute returned, the seconds it took, and the probe.
local function Probed(bot, recorder, compute)
	local probe = {
		costCalls = 0,
		costSeconds = 0,
		recorder = recorder,
	}
	bot.pathProbe = probe
	local started = SysTime()
	local found = compute()
	local seconds = SysTime() - started
	bot.pathProbe = nil
	return found, seconds, probe
end

local function RecordProfile(profile, label, found, seconds, probe)
	profile:Record({
		label = label,
		seconds = seconds,
		costCalls = probe.costCalls,
		costSeconds = probe.costSeconds,
		found = found,
	})
end

-- Records in the profile how long compute() took and how much of that was
-- the cost callback.
function Controller:MeasureCompute(profile, label, bot, compute)
	local found, seconds, probe = Probed(bot, nil, compute)
	RecordProfile(profile, label, found, seconds, probe)
	return found
end

-------------------------------------------------------------------------------
-- Watching path searches for the nbdebug feature (foundation.npc.debug).
-- Only the NPCs it asks for are watched; for them each search is timed and,
-- with watch.costs, every cost it asked for is recorded, and when it is done
-- a foundation.npc.debug path report goes out as the hook
-- WSNpcPathComputed(ent, report). Nothing else changes for them.

local PATH_COMPUTED_HOOK = "WSNpcPathComputed"
local ENGINE_DEFAULT_COST = "the engine's default cost"
local MICROSECONDS = 1e6

-- watch: { costs }, or nil to stop watching.
function Controller:WatchPaths(entIndex, watch)
	self.pathWatch[entIndex] = watch
end

function Controller:PathWatch(ent)
	return self.pathWatch[ent:EntIndex()]
end

-- A watched NextBot's Path:Compute (ws_nextbot's FollowPath). An open
-- path profile records it too.
function Controller:ObserveCompute(watch, bot, path, goal, compute)
	local Debug = WS.require("foundation.npc.debug")
	local recorder = watch.costs and bot.pathCost and Debug.NewCostRecorder() or nil
	local start = bot:GetPos()
	local found, seconds, probe = Probed(bot, recorder, compute)
	if self.pathProfile then RecordProfile(self.pathProfile, bot.Variant, found, seconds, probe) end
	local points, areaIds, lastArea = {}, {}, nil
	for i, segment in ipairs(path:GetAllSegments()) do
		points[i] = {
			pos = segment.pos,
			move = Debug.MoveOfSegment(segment.type),
		}
		if IsValid(segment.area) then
			lastArea = segment.area
			areaIds[#areaIds + 1] = lastArea:GetID()
		end
	end
	local variant = WS.require(bot.Variant)
	hook.Run(PATH_COMPUTED_HOOK, bot, Debug.NewPathReport({
		source = Debug.SOURCE_ENGINE,
		strategy = bot.pathCost and variant.PATH or ENGINE_DEFAULT_COST,
		start = start,
		goal = goal,
		limits = variant.LOCOMOTION,
		found = found,
		points = points,
		areaIds = areaIds,
		totalCost = lastArea and lastArea:GetCostSoFar() or nil,
		microseconds = seconds * MICROSECONDS,
		nodesExpanded = recorder and recorder:Expanded() or nil,
		explored = recorder and recorder:Explored() or nil,
		computedAt = CurTime(),
	}))
	return found
end

local function RecordedCost(graph, fromId, toId, costSoFar)
	local cost = NavGraph.Cost(graph, fromId, toId, costSoFar)
	graph.recorder:Record(toId, fromId, cost)
	return cost
end

-- A watched NPC's route search (RequestRoute): with watch.costs its graph
-- records every cost. Returns what ThinkSearches keeps of it.
function Controller:ObserveRoute(graph, request, start, watch)
	if watch.costs then
		graph.recorder = WS.require("foundation.npc.debug").NewCostRecorder()
		graph.recorder:Record(start:GetID(), nil, 0)
		graph.Cost = RecordedCost
	end
	return {
		index = request.bot.entIndex,
		request = request,
		recorder = graph.recorder,
		seconds = 0,
	}
end

-- A watched route search is done: its report, with the waypoints the NPC
-- will be given (RouteWaypoints), all on the ground.
function Controller:PublishRoute(running, areas, found)
	local Debug = WS.require("foundation.npc.debug")
	local observed, search = running.observed, running.search
	local ent, request = Entity(observed.index), observed.request
	if not IsValid(ent) then return end
	local route = search:Route()
	local points = {}
	for i, pos in ipairs(self:RouteWaypoints(areas, request.to, found, request.from)) do
		points[i] = {
			pos = pos,
			move = Debug.MOVE_GROUND,
		}
	end
	local recorder = observed.recorder
	hook.Run(PATH_COMPUTED_HOOK, ent, Debug.NewPathReport({
		source = Debug.SOURCE_ROUTE,
		strategy = request.strategy._NAME,
		start = request.from,
		goal = request.to,
		limits = request.limits,
		found = found,
		points = points,
		areaIds = route,
		totalCost = search.costSoFar[route[#route]],
		microseconds = observed.seconds * MICROSECONDS,
		nodesExpanded = search.expanded,
		explored = recorder and recorder:Explored() or nil,
		computedAt = CurTime(),
	}))
end

-- The nbdebug feature finds the NPCs it can show through the hook
-- WSNbDebugNpcs(found): each system adds its entities' foundation.npc
-- Npcs to `found` (entity -> Npc).
hook.Add("WSNbDebugNpcs", "ws_npc", function(found)
	for ent, npc in pairs(Controller.npcs) do
		if IsValid(ent) then found[ent] = npc end
	end
end)

-- Every live NextBot of this gamemode that searches with a Lua cost.
local function PathingBots()
	local bots = {}
	for ent in pairs(Controller.npcs) do
		if IsValid(ent) and ent.pathCost then bots[#bots + 1] = ent end
	end
	table.sort(bots, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return bots
end

-- One goal, computed with the engine's own cost and then with the bot's
-- Lua cost, on paths of their own so the bot's path is left alone.
function Controller:BenchGoal(profile, bot, goal)
	local enginePath = Path("Follow")
	self:MeasureCompute(profile, Profile.BENCH_ENGINE_LABEL, bot, function() return enginePath:Compute(bot, goal) end)
	local luaPath = Path("Follow")
	self:MeasureCompute(profile, bot.Variant, bot, function() return luaPath:Compute(bot, goal, bot.pathCost) end)
end

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

local function Admin(ply)
	return not IsValid(ply) or ply:IsAdmin()
end

concommand.Add("ws_path_profile", function(ply, _, args)
	if not Admin(ply) then return end
	if Controller.pathProfile then
		Tell(ply, { "path profile: a window is already open" })
		return
	end
	local seconds = math.Clamp(tonumber(args[1]) or PROFILE_WINDOW_DEFAULT, 1, PROFILE_WINDOW_MAX)
	Controller.pathProfile = Profile.New(SysTime())
	Tell(ply, { string.format("path profile: measuring every path compute for %d s", seconds) })
	timer.Simple(seconds, function()
		local profile = Controller.pathProfile
		Controller.pathProfile = nil
		Tell(ply, Profile.Format(profile:Report(SysTime()), engine.TickInterval()))
	end)
end, nil, "Measure the NextBots' path computes during play for N seconds (default 30) and print whether offloading them would pay")

-- The bench stalls the server for its whole run, on purpose.
concommand.Add("ws_path_bench", function(ply, _, args)
	if not Admin(ply) then return end
	local bots, areas = PathingBots(), navmesh.GetAllNavAreas()
	if #bots == 0 then
		Tell(ply, { "path bench: no NextBot with a path cost is alive; spawn one first" })
		return
	end
	if #areas == 0 then
		Tell(ply, { "path bench: this map has no navigation mesh" })
		return
	end
	local count = math.Clamp(tonumber(args[1]) or BENCH_DEFAULT, 1, BENCH_MAX)
	local profile = Profile.New(SysTime(), true)
	for i = 1, count do
		local bot = bots[(i - 1) % #bots + 1]
		Controller:BenchGoal(profile, bot, areas[math.random(#areas)]:GetCenter())
	end
	Tell(ply, Profile.Format(profile:Report(SysTime()), engine.TickInterval()))
end, nil, "Compute N paths (default 200) from the live NextBots to random nav areas, under the engine's cost and their Lua cost, and print the timings")

hook.Add("Think", "ws_npc_spawners", function()
	Controller:ThinkSpawners(CurTime())
	Controller:ThinkSearches()
end)

-- The model's FilterDamage decides whether an NPC takes a hit, and how much.
hook.Add("EntityTakeDamage", "ws_npc_filter_damage", function(ent, dmg)
	local npc = Controller.npcs[ent]
	if not npc then return end
	local taken, amount = npc:FilterDamage(ent:DamageEvent(dmg))
	if not taken then return true end
	if amount then dmg:SetDamage(amount) end
end)

return Controller
