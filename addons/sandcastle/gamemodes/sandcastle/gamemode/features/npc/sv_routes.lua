-- Part of the npc controller (sv.lua): the path costs, the nav graph the Lua
-- route search walks, the route requests and searches, and the waypoints
-- along a route. Its NavGraph goes to sv_profile, which records its costs.
local Controller = ...
local Pathfinder = WS.require("foundation.core.pathfinder")
local AStar = WS.require("foundation.pathfinder.astar")
local Portal = WS.require("foundation.npc.portal")
local Doors = WS.require("foundation.npc.doors")
local Path = WS.require("foundation.npc.path")

local NOBODY = WS.TEAM_UNASSIGNED

-------------------------------------------------------------------------------
-- Path costs: one step builder for both searches. A path strategy
-- (foundation.npc.path) reads the same step whether the engine's search
-- (Path:Compute on a NextBot) or the Lua one (foundation.pathfinder.astar, for
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

-- The cost callback Path:Compute takes (IPathCost), for a NextBot. bot is
-- the strategy's bot table; its `now` is kept current. Areas a door or a
-- brush closes to the bot's team are not traversable, nor links its body
-- cannot cross (WS.NavLinkCrossable: a players' map's clip along a rail,
-- which the nav mesh links a drop past). While a path profile
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
		if IsValid(fromArea) and not WS.NavLinkCrossable(fromArea, area) then return Path.IMPASSABLE end
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

-- The graph foundation.pathfinder.astar searches: nav area ids, their floor
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

-- request = { from, to (positions), strategy, limits, bot (the strategy's,
-- with team), avoid(area) -> bool (optional: areas to route around, as
-- if blocked; the goal's area is never avoided), crossable(fromArea,
-- area) -> bool (optional: links to route around), ignoreBlockers (optional:
-- route through doors shut to the team and solid brushes), onDone(route, found) } where route is the list of nav areas
-- from the start's to the goal's (found), or to the one that came closest
-- when the goal is out of reach, and nil when either end is off the mesh.
local NEAREST_AREA_RANGE = 200
-- Each tick the searches run in turn as tasks (foundation.core.scheduler),
-- checking the clock after every expansion, until SEARCH_SECONDS of the tick
-- are spent. A search may cover the whole mesh, as the engine's may: spread
-- over ticks, that costs time, not a hitch.
local SEARCH_SECONDS = 0.002

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
		crossable = request.crossable,
		traversable = function(area)
			if avoid and area:GetID() ~= goalId and avoid(area) then return false end
			if not ignoreBlockers and Doors.Blocks(self.navBlocked[area:GetID()], team) then return false end
			return not self:EngineBlocks(area, team)
		end,
	}, NavGraph)
	local watch = self.pathWatch[request.bot.entIndex]
	local observed = watch and self:ObserveRoute(graph, request, start, watch) or nil
	local search = AStar.New(graph, start:GetID(), goal:GetID(), navmesh.GetNavAreaCount())
	local scheduler = self.searches
	scheduler:Spawn(function()
		local status = search.status
		while status == Pathfinder.RUNNING do
			local began = observed and SysTime()
			status = search:Step(1)
			if observed then observed.seconds = observed.seconds + SysTime() - began end
			scheduler:CheckYield()
		end
		local areas, found = AreasOf(search:Route()), status == Pathfinder.FOUND
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
-- past the edge and lands on the floor under that, maybe in the open beside
-- a room the lower area reaches into under the upper floor.
local DROP_STEP, LANDING_OUT, LANDING_DEPTH = 18, 24, 1000

local function Landing(crossing, dir)
	local x, y = Portal.Past(crossing.x, crossing.y, dir, LANDING_OUT)
	local above = Vector(x, y, crossing.z + DROP_STEP)
	local floor = util.TraceLine({ start = above, endpos = above - Vector(0, 0, LANDING_DEPTH), mask = WS.ClipMasks().brushes })
	return floor.Hit and floor.HitPos or nil
end

-- The points along a route: each crossing into the next area, then the
-- goal (or the nearest the route came). For a lane (middles): each crossing
-- in the middle of its opening, and after each drop its landing, so a
-- lane's line goes out over the edge and down, not through the floor.
function Controller:RouteWaypoints(areas, goal, found, start, middles)
	local points = {}
	local pos = start or areas[1]:GetCenter()
	for i = 2, #areas do
		local dir
		pos, dir = Crossing(areas[i - 1], areas[i], pos, middles)
		points[#points + 1] = pos
		if middles and dir and areas[i]:GetCenter().z < pos.z - DROP_STEP then
			local landing = Landing(pos, dir)
			if landing then
				points[#points + 1] = landing
				pos = landing
			end
		end
	end
	points[#points + 1] = found and goal or areas[#areas]:GetClosestPointOnArea(goal)
	return points
end

return NavGraph
