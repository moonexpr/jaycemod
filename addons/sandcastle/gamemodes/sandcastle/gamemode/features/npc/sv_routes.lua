-- Part of the npc controller (sv.lua): the path costs, the nav graph the Lua
-- route search walks, the route requests and searches, and the waypoints
-- along a route. Its NavGraph goes to sv_profile, which records its costs.
local Controller = ...
local Pathfinder = graph.pathfinder
local NavSearch = wetsands.navsearch
local Portal = nextsoldier.portal
local Path = wetsands.path
local ReachMemo = nextsoldier.reach_memo

local NOBODY = WS.TEAM_UNASSIGNED

-------------------------------------------------------------------------------
-- Path costs: one step builder for both searches. A path strategy
-- (foundation.wetsands.path) reads the same step whether the engine's search
-- (Path:Compute on a NextBot) or the Lua one (foundation.graph.pathfinder, for
-- NPCs that are not NextBots) asks.

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

-- What the engine's path computations for a team know (a wetsands.navsearch
-- Told): the areas closed to it (ClosedFor, and also.areas when the caller
-- adds some, stamped also.stamp), the links WS.NavLinkCrossable refuses (a
-- players' map's clip along a rail, which the nav mesh links a drop past),
-- and the spawn rooms. Made again only when one of those changes; nil
-- until the mesh snapshot is ready.
function Controller:EngineKnown(team, also)
	if not self:NavMeshReady() then return nil end
	local closed, rooms = self:ClosedFor(team), self:SpawnRooms()
	local held = self.engineKnown[team]
	if held and held.mesh == self.navMesh and held.closed == closed and held.rooms == rooms
		and held.also == (also and also.areas) and held.stamp == (also and also.stamp) then
		return held.known
	end
	local told = closed
	if also and next(also.areas) then
		told = {}
		for id in pairs(closed) do told[id] = true end
		for id in pairs(also.areas) do told[id] = true end
	end
	held = {
		mesh = self.navMesh,
		closed = closed,
		rooms = rooms,
		also = also and also.areas,
		stamp = also and also.stamp,
		known = NavSearch.Told(self.navMesh, { closed = told, rooms = rooms, uncrossable = self.navUncrossable }),
	}
	self.engineKnown[team] = held
	return held.known
end

-- What a route search with these closed areas (a ClosedFor table) knows
-- from the start (a wetsands.navsearch Told): the closed areas, the spawn
-- rooms, and, for a request crossing by WS.NavLinkCrossable, the links it
-- refuses. Held while closed, the rooms and the mesh hold, so a search
-- reads no table of them.
function Controller:SearchKnown(closed, mapCrossable)
	local rooms, held = self:SpawnRooms(), self.searchKnown[closed]
	if not (held and held.mesh == self.navMesh and held.rooms == rooms) then
		held = { mesh = self.navMesh, rooms = rooms }
		self.searchKnown[closed] = held
	end
	local key = mapCrossable and "crossing" or "walking"
	if not held[key] then
		held[key] = NavSearch.Told(self.navMesh,
			{ closed = closed, rooms = rooms, uncrossable = mapCrossable and self.navUncrossable or nil })
	end
	return held[key]
end

-- The cost callback Path:Compute takes (IPathCost) for one compute: a
-- wetsands.navsearch Calculator of the strategy over the team's
-- EngineKnown, which prices each move natively; nil while the mesh snapshot
-- is not ready, when a NextBot has no path yet. bot is the strategy's bot
-- table, read as the calculator is made.
function Controller:EngineCost(team, strategy, limits, bot, also)
	local known = self:EngineKnown(team, also)
	return known and NavSearch.Calculator(known, strategy, limits, bot)
end

-- A NextBot's cost maker: () -> EngineCost for this compute, its bot's
-- `now` set. While a path profile measures a compute, or the nbdebug
-- feature watches it, ent.pathProbe counts the calls and their time, and
-- its recorder (if any) each cost.
function Controller:EnginePathCost(ent, strategy, limits, bot)
	return function()
		bot.now = CurTime()
		local cost = self:EngineCost(WS.TeamNumber(ent), strategy, limits, bot)
		local probe = ent.pathProbe
		if not (cost and probe) then return cost end
		return function(area, fromArea, ladder, elevator, length)
			return self:ProbedCost(probe, cost, area, fromArea, ladder, elevator, length)
		end
	end
end

-- One call of cost, counted and timed by a path probe, and recorded.
function Controller:ProbedCost(probe, cost, area, fromArea, ladder, elevator, length)
	local started = SysTime()
	local price = cost(area, fromArea, ladder, elevator, length)
	probe.costCalls = probe.costCalls + 1
	probe.costSeconds = probe.costSeconds + SysTime() - started
	if probe.recorder then probe.recorder:Record(area:GetID(), IsValid(fromArea) and fromArea:GetID() or nil, price) end
	return price
end

-- The graph foundation.graph.pathfinder searches: nav area ids, their floor
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

local function AreasOf(ids)
	local areas = {}
	for i, id in ipairs(ids) do areas[i] = Area(id) end
	return areas
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
	if self.crossable and not self.crossable(Area(fromId), Area(toId)) then return Path.IMPASSABLE end
	self.controller:FillStep(self.step, Area(toId), Area(fromId), nil, Center(toId):Distance(Center(fromId)), costSoFar, self.traversable)
	self.bot.now = CurTime()
	return self.strategy.Cost(self.step, self.limits, self.bot)
end

function NavGraph:Estimate(id)
	return Center(id):Distance(self.goalPos)
end

-- The mesh as the route searches walk it: a wetsands.navsearch mesh (native
-- on a server that loads native/wetsands), holding every area and its floor
-- links as NavGraph walks them, with the centre distance and height change
-- FillStep gives. Built once a map, and again when the mesh's links change
-- (WSNavLinked), as a search task an area at a time in the searches' slice;
-- a search waits for it. True once it is ready. The build also asks
-- WS.NavLinkCrossable of every link (traces, about 150 ms a map, spread
-- over the slices), keeping those a soldier cannot cross as navUncrossable
-- (from -> to -> true), so a search is told them instead of asking.
function Controller:NavMeshReady()
	if self.navMesh then return true end
	if self.navMeshBuilding == self.navMeshGeneration then return false end
	local generation, scheduler = self.navMeshGeneration, self.searches
	self.navMeshBuilding = generation
	scheduler:Spawn(function()
		local mesh, areas, uncrossable = NavSearch.Mesh(), navmesh.GetAllNavAreas(), {}
		for _, area in ipairs(areas) do
			local center = Center(area:GetID())
			-- the engine reads the flags back signed: an area with the top flag set
			-- (cp_sunshine has one) comes back negative, which the mesh's u32 refuses
			mesh:Area(area:GetID(), center.x, center.y, center.z, area:GetAttributes() % 4294967296)
		end
		for _, area in ipairs(areas) do
			local id = area:GetID()
			for _, to in ipairs(NavGraph:Neighbors(id)) do
				local other = Area(to)
				mesh:Link(id, to, Center(to):Distance(Center(id)), area:ComputeAdjacentConnectionHeightChange(other))
				if not WS.NavLinkCrossable(area, other) then
					uncrossable[id] = uncrossable[id] or {}
					uncrossable[id][to] = true
				end
			end
			scheduler:CheckYield()
		end
		mesh:Seal()
		if self.navMeshGeneration == generation then self.navMesh, self.navUncrossable = mesh, uncrossable end
	end)
	return false
end

-- request = { from, to (positions), strategy, limits, bot (the strategy's,
-- with team), avoid(area) -> bool (optional: areas to route around, as
-- if blocked; the goal's area is never avoided), crossable(fromArea,
-- area) -> bool (optional: links to route around), ignoreBlockers (optional:
-- route through doors shut to the team and solid brushes), onDone(route, found) } where route is the list of nav areas
-- from the start's to the goal's (found), or to the one that came closest
-- when the goal is out of reach, and nil when either end is off the mesh.
local NEAREST_AREA_RANGE = 200
-- Each tick the searches run in turn as tasks (foundation.list.schedule),
-- checking the clock after every expansion, until SEARCH_SECONDS of the tick
-- are spent. A search may cover the whole mesh, as the engine's may: spread
-- over ticks, that costs time, not a hitch.
local SEARCH_SECONDS = 0.002
-- How many expansions a search on the mesh runs between looks at the clock:
-- natively about 1 us each with the live rules, a crossing into the module
-- about 3 us, so one at a time would spend most of the slice crossing.
-- The watched Lua search, at up to 100 us an expansion live, takes one.
local MESH_STEP = 16

local NEAREST_AREA_FAR = 600

-- The area under pos, else (a point over a wall, a pit or a roof, as a
-- goal offset from a cart's track can be) the nearest at any height.
local function NearestArea(pos)
	local area = navmesh.GetNearestNavArea(pos, false, NEAREST_AREA_RANGE, false, true)
	if IsValid(area) then return area end
	return navmesh.GetNearestNavArea(pos, true, NEAREST_AREA_FAR, false, false)
end

-- Goals out of reach (nextsoldier.reach_memo): a search that runs out of
-- areas has walked all its start leads to, so a later request from inside
-- that region to a goal beyond it is answered without a search, from the
-- region's area nearest the goal, as the search would have come closest:
-- the failed search's own way there when it starts where that one did,
-- else a search to that area. Regions last REACH_TERM seconds and a round,
-- and through blocker changes (their edges are checked again) but not a
-- change to the mesh's links (BlockerChangesSince cannot say what changed).
local REACH = CreateConVar("ns_routes_reach", "1", FCVAR_ARCHIVE,
	"1: a route search knows a goal out of reach from the regions failed searches walked", 0, 1)
local REACH_TERM = 30
local REACH_KEYS = 32

Controller.reach = Controller.reach or ReachMemo.New({
	clock = { Now = function() return CurTime() end },
	term = REACH_TERM,
	capacity = REACH_KEYS,
})

local function ForgetRegions()
	Controller.reach:Clear()
end
hook.Add("PostCleanupMap", "ws_npc_reach", ForgetRegions)
hook.Add("WSRoundActivate", "ws_npc_reach", ForgetRegions)
hook.Add("WSRoundActive", "ws_npc_reach", ForgetRegions)

-- The graph's traversable and crossable, writing down each refusal: the
-- edge of the region a failed search walks. A search told the closed areas
-- never asks about them, so those at the edge are added once it fails
-- (ClosedEdge).
local function Refusals(graph)
	local refused, uncrossable = {}, {}
	local traversable, crossable = graph.traversable, graph.crossable
	graph.traversable = function(area)
		local open = traversable(area)
		if not open then refused[area:GetID()] = true end
		return open
	end
	if crossable then
		graph.crossable = function(from, to)
			local ok = crossable(from, to)
			if not ok then
				local id = from:GetID()
				uncrossable[id] = uncrossable[id] or {}
				uncrossable[id][to:GetID()] = true
			end
			return ok
		end
	end
	return refused, uncrossable
end

-- Adds what the search was told and never asked about at the region's
-- edge: to refused each closed area a link from the region leads into, to
-- uncrossable each told-uncrossable link out of it (toldUncrossable may be
-- nil). The region holds start and every area in parents.
local function ToldEdge(closed, toldUncrossable, start, parents, refused, uncrossable)
	local function Edge(id)
		local out = toldUncrossable and toldUncrossable[id]
		for _, to in ipairs(NavGraph:Neighbors(id)) do
			if closed[to] then refused[to] = true end
			if out and out[to] then
				uncrossable[id] = uncrossable[id] or {}
				uncrossable[id][to] = true
			end
		end
	end
	Edge(start)
	for id in pairs(parents) do Edge(id) end
end

function Controller:RequestRoute(request)
	local start, goal = NearestArea(request.from), NearestArea(request.to)
	if not (IsValid(start) and IsValid(goal)) then
		request.onDone(nil)
		return
	end
	local team = request.bot.team or NOBODY
	self:RefreshBlockers(CurTime())
	local avoid, goalId = request.avoid, goal:GetID()
	local closed = self:ClosedFor(team, request.ignoreBlockers)
	local graph = setmetatable({
		controller = self,
		step = {},
		strategy = request.strategy,
		limits = request.limits,
		bot = request.bot,
		goalPos = request.to,
		crossable = request.crossable,
		traversable = function(area)
			local id = area:GetID()
			if closed[id] then return false end
			return not (avoid and id ~= goalId and avoid(area))
		end,
	}, NavGraph)
	local startId, searchGoal, generation = start:GetID(), goalId, self.blockerGeneration
	local key = REACH:GetBool() and self.reach:Key(request) or nil
	local region = key and self.reach:Unreachable(key, startId, goalId,
		function(id) return graph.traversable(Area(id)) end,
		function(from, to) return not graph.crossable or graph.crossable(Area(from), Area(to)) end,
		generation, function(since) return self:BlockerChangesSince(since) ~= nil end)
	if region then
		local nearest = region:Nearest(request.to, Center)
		if region.start == startId then
			self.reachStats.answered = self.reachStats.answered + 1
			request.onDone(AreasOf(region:RouteTo(nearest)), false)
			return
		end
		self.reachStats.retargeted = self.reachStats.retargeted + 1
		searchGoal, graph.goalPos = nearest, Center(nearest)
	end
	local refused, uncrossable
	if key and not region then refused, uncrossable = Refusals(graph) end
	local watch = self.pathWatch[request.bot.entIndex]
	local observed = watch and self:ObserveRoute(graph, request, start, watch) or nil
	-- A watched search runs the Lua solver on the NavGraph, whose costs
	-- sv_profile records step by step; every other runs on the mesh, told
	-- the closed areas and the spawn rooms, and asking Lua only what the
	-- request itself adds: the areas it avoids, the links it cannot cross
	-- (but WS.NavLinkCrossable's, which the mesh's build gathered).
	local mapCrossable = request.crossable == WS.NavLinkCrossable
	local toldUncrossable
	local rules = {
		traversable = avoid and function(id) return graph.traversable(Area(id)) end or nil,
		crossable = request.crossable and not mapCrossable and function(from, to) return graph.crossable(Area(from), Area(to)) end or nil,
	}
	local scheduler = self.searches
	scheduler:Spawn(function()
		local search
		if observed then
			search = Pathfinder.New(graph, startId, searchGoal, navmesh.GetNavAreaCount())
		else
			scheduler:Wait(function() return self:NavMeshReady() end)
			if mapCrossable then toldUncrossable = self.navUncrossable end
			search = NavSearch.New(self.navMesh, request.strategy, request.limits, request.bot, startId, searchGoal,
				graph.goalPos, navmesh.GetNavAreaCount(), self:SearchKnown(closed, mapCrossable), rules)
		end
		local status, budget = search.status, observed and 1 or MESH_STEP
		while status == Pathfinder.RUNNING do
			local began = observed and SysTime()
			status = search:Step(budget)
			if observed then observed.seconds = observed.seconds + SysTime() - began end
			scheduler:CheckYield()
		end
		if refused and status == Pathfinder.FAILED and search.expanded < search.maxExpanded then
			self.reachStats.learned = self.reachStats.learned + 1
			ToldEdge(closed, toldUncrossable, startId, search.parent, refused, uncrossable)
			self.reach:Learn(key, ReachMemo.Region(startId, search.parent, refused, uncrossable), generation)
		end
		local areas, found = AreasOf(search:Route()), status == Pathfinder.FOUND and not region
		if observed then self:PublishRoute({ search = search, observed = observed }, areas, found) end
		request.onDone(areas, found)
	end)
end

-- Runs the searches in turn within the tick's time; each that finishes
-- reports its route.
function Controller:ThinkSearches()
	self.searches:Run(SEARCH_SECONDS)
end

function Controller:SearchesRunning()
	return self.searches:Count()
end

-- Where to walk along a route of areas, as the engine's Path::Compute
-- places its points: each step crosses into the next area where
-- nextsoldier.portal says (nearest the previous crossing, off the
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

local function Crossing(from, to, pos, middle)
	local dir = SideOf(from, to)
	if not dir then return to:GetClosestPointOnArea(from:GetCenter()) end
	local toRect = Rect(to)
	for side = Portal.NORTH, Portal.WEST do toRect.edges[side] = to:GetAdjacentCountAtSide(side) == 0 end
	local x, y
	if middle then x, y = Portal.MiddleOfPortal(Rect(from), toRect, dir) else x, y = Portal.ClosestPointInPortal(Rect(from), toRect, dir, pos) end
	local crossing = Vector(x, y, 0)
	-- walk out of `from` at a height it can reach
	crossing.z = from:GetZ(crossing)
	return crossing, dir
end

-- A drop (into an area more than a step below): the walker steps LANDING_OUT
-- past the edge and lands in the lower area under that (or the nearest of
-- it, held inside it): on the mesh, never on a prop or rail top beside it.
local DROP_STEP, LANDING_OUT = 18, 24

local function Landing(crossing, dir, to)
	local x, y = Portal.Past(crossing.x, crossing.y, dir, LANDING_OUT)
	x, y = Portal.Inside(Rect(to), x, y)
	local landing = Vector(x, y, 0)
	landing.z = to:GetZ(landing)
	return landing
end

-- A lane's points through the opening from `from` into `to` at crossing
-- (in direction dir): from inside `from` (Portal.Exit), then inside `to`
-- (Portal.Entry), so each leg lies within one area or squarely through an
-- opening; off a drop, out to the edge and down to its landing instead.
local function LanePoints(points, from, to, crossing, dir)
	local x, y = Portal.Exit(Rect(from), crossing.x, crossing.y, dir)
	local exit = Vector(x, y, 0)
	exit.z = from:GetZ(exit)
	points[#points + 1] = exit
	if to:GetCenter().z < crossing.z - DROP_STEP then
		points[#points + 1] = crossing
		points[#points + 1] = Landing(crossing, dir, to)
		return
	end
	x, y = Portal.Entry(Rect(to), crossing.x, crossing.y, dir)
	local entry = Vector(x, y, 0)
	entry.z = to:GetZ(entry)
	points[#points + 1] = entry
end

-- The points along a route: each crossing into the next area, then the
-- goal (or the nearest the route came). For a lane (middles): each
-- opening crossed at its middle, from inside the area left to inside the
-- area entered, and each drop out over the edge and down to its landing,
-- so a lane's line goes through doorways, never through a wall or floor.
function Controller:RouteWaypoints(areas, goal, found, start, middles)
	local points = {}
	local pos = start or areas[1]:GetCenter()
	for i = 2, #areas do
		local dir
		pos, dir = Crossing(areas[i - 1], areas[i], pos, middles)
		if middles and dir then
			LanePoints(points, areas[i - 1], areas[i], pos, dir)
			pos = points[#points]
		else
			points[#points + 1] = pos
		end
	end
	if found then
		points[#points + 1] = goal
		return points
	end
	local last = areas[#areas]
	local nearest = last:GetClosestPointOnArea(goal)
	-- a lane's end off the area's edge, where a wall or prop may stand
	if middles then
		local x, y = Portal.Inside(Rect(last), nearest.x, nearest.y)
		nearest = Vector(x, y, 0)
		nearest.z = last:GetZ(nearest)
	end
	points[#points + 1] = nearest
	return points
end

return NavGraph
