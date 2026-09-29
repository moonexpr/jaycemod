-- The npc feature's controller. It owns one foundation.npc Npc per NPC
-- entity, the foundation.npc.spawner models, a registry by kind and the
-- per-variant shared state, and checks the navigation mesh once per map.
-- The rules live in the models; this file only feeds them engine events and
-- turns their answers into entities.
local NpcSystem = WETSAND.require("foundation.npc")
local Spawner = WETSAND.require("foundation.npc.spawner")
local Profile = WETSAND.require("foundation.npc.profile")
local Route = WETSAND.require("foundation.npc.route")
local Portal = WETSAND.require("foundation.npc.portal")

local NAV_MESSAGE = "wetsand_nextbot: %s has no usable navigation mesh; run .devtools/bin/nav_convert.py or nav_generate"
local BOSS_HEALTH = "wetsand_boss_health" -- the boss bar's fraction; 0 hides it

local Controller = {
	npcs = {}, -- entity -> Npc
	variantNames = {}, -- entity -> variant name
	kinds = {}, -- kind -> { [entity] = true }
	shared = {}, -- variant name -> table
	spawners = {}, -- spawner entity -> Spawner
	spawnedBy = {}, -- NPC entity -> Spawner
	navChecked = false,
	pathProfile = nil, -- a foundation.npc.profile while wetsand_path_profile's window is open
	spawnRoomTeams = {}, -- nav area id -> the team whose spawn room holds it, this round
	searches = {}, -- the Lua route searches still running, oldest first
	neighbors = {}, -- nav area id -> its floor neighbours' ids (the mesh is fixed for the map)
	centers = {}, -- nav area id -> its centre
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

function Controller:Bind(ent, variantName, config)
	self:CheckNavMesh()
	local variant = WETSAND.require(variantName)
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

local NOBODY = WETSAND.TEAM_UNASSIGNED

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

local function ForgetSpawnRooms()
	Controller.spawnRoomTeams = {}
end
hook.Add("PostCleanupMap", "wetsand_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("TF2RoundActivate", "wetsand_npc_spawn_rooms", ForgetSpawnRooms)
hook.Add("TF2RoundActive", "wetsand_npc_spawn_rooms", ForgetSpawnRooms)

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
-- the strategy's bot table; its `now` is kept current. While a path profile
-- measures a compute, ent.pathProbe counts the calls and their time.
function Controller:EnginePathCost(ent, strategy, limits, bot)
	local step = {}
	local function Traversable(area) return ent.loco:IsAreaTraversable(area) end
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
-- with team), onDone(route, found) } where route is the list of nav areas
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
	local graph = setmetatable({
		controller = self,
		step = {},
		strategy = request.strategy,
		limits = request.limits,
		bot = request.bot,
		goalPos = request.to,
		traversable = function(area) return not area:IsBlocked(team) end,
	}, NavGraph)
	local search = Route.New(graph, start:GetID(), goal:GetID(), navmesh.GetNavAreaCount())
	self.searches[#self.searches + 1] = { search = search, onDone = request.onDone }
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
		if running.search:Step(SEARCH_CHUNK) == Route.RUNNING then
			self.searches[#self.searches + 1] = running
		else
			running.onDone(AreasOf(running.search:Route()), running.search.status == Route.FOUND)
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

-- Runs compute(), a Path:Compute through bot's cost function, and records
-- how long it took and how much of that was the cost callback.
function Controller:MeasureCompute(profile, label, bot, compute)
	local probe = { costCalls = 0, costSeconds = 0 }
	bot.pathProbe = probe
	local started = SysTime()
	local found = compute()
	local seconds = SysTime() - started
	bot.pathProbe = nil
	profile:Record({
		label = label,
		seconds = seconds,
		costCalls = probe.costCalls,
		costSeconds = probe.costSeconds,
		found = found,
	})
	return found
end

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

concommand.Add("wetsand_path_profile", function(ply, _, args)
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
concommand.Add("wetsand_path_bench", function(ply, _, args)
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

hook.Add("Think", "wetsand_npc_spawners", function()
	Controller:ThinkSpawners(CurTime())
	Controller:ThinkSearches()
end)

-- The model's FilterDamage decides what an NPC takes.
hook.Add("EntityTakeDamage", "wetsand_npc_filter_damage", function(ent, dmg)
	local npc = Controller.npcs[ent]
	if npc and not npc:FilterDamage(ent:DamageEvent(dmg)) then return true end
end)

return Controller
