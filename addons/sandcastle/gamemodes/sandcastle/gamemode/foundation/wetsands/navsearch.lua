-- Route searches on a nav mesh snapshot: NavAreaBuildPath (graph.pathfinder)
-- priced by a path strategy (wetsands.path). This is the Lua implementation,
-- the oracle; a server that loads native/wetsands (require("wetsands")) has
-- it replaced in place by the native one, which keeps this contract:
--
--   Mesh() -> a mesh to fill: mesh:Area(id, x, y, z, attributes) for every
--     area, then mesh:Link(from, to, distance, rise) for each area's floor
--     links in GetAdjacentAreas' order (the distance between centres, and
--     ComputeAdjacentConnectionHeightChange), then mesh:Seal();
--     mesh:Sealed() -> whether it is, mesh:Areas() -> how many areas a
--     sealed mesh has
--   New(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded[,
--     told[, rules]]) -> a search from area start to area goal, estimated
--     toward goalPos, priced by strategy.Cost(step, limits, bot) (natively,
--     by strategy.Model(limits, bot)), where
--     told = { closed = id -> true, uncrossable = from -> to -> true,
--       rooms = id -> spawn room team, estimates = id -> estimate }, or a
--       Told of the same mesh (held, so a search reads no table), is what
--       the search knows from the start, and
--     rules = { traversable(id) -> bool, crossable(from, to) -> bool,
--       room(id) -> spawn room team } are asked the first time the search
--       reaches an area or a link, once each (room only for an area told
--       none).
--   A search is graph.pathfinder's: status, expanded, maxExpanded, start,
--   goal, closest, parent (id -> the id it was reached from), Step(budget),
--   Route([last]) -> area ids.
--   Distances(mesh, starts, limit, limits[, told]) -> area id -> the
--     cheapest walk to it from the nearest of starts (graph.search's
--     Distances), along the links whose rise wetsands.path.Walkable allows
--     to limits and not told.uncrossable, at the link's distance; a walk
--     beyond limit is not followed.
--   Told(mesh, told) -> what a team's computations know of a sealed mesh,
--     held as a copy: told is New's (closed, uncrossable, rooms; an area or
--     link the mesh lacks is refused). Made once while they hold, not per
--     computation.
--   Calculator(known, strategy, limits, bot) -> cost(area, fromArea, ladder,
--     elevator, length): the IPathCost the engine's Path:Compute takes, a
--     consumer of the strategy's cost model over a Told. The engine is asked
--     only area:GetID(), fromArea:GetID() and fromArea:GetCostSoFar() (and,
--     for a ladder move, ladder:GetLength() and
--     fromArea:ComputeAdjacentConnectionHeightChange(area)); the rest is the
--     mesh's and the Told's. It prices a move as strategy.Cost prices the
--     step the npc controller's FillStep builds from it: the first area
--     (no fromArea) costs nothing, a length above 0 is the step's length,
--     a floor move the mesh lacks is refused. Cheap to make: one a
--     computation, as a scatter strategy's preference changes with time.
-- An area the mesh lacks is refused as start or goal, or once sealed.
local Pathfinder = graph.pathfinder
local Path = wetsands.path
local Search = graph.search
local Geometry = math.geometry
local error, getmetatable, ipairs, pairs, setmetatable, tostring = error, getmetatable, ipairs, pairs, setmetatable, tostring
module(...)

-- TEAM_UNASSIGNED: an area in no spawn room.
NO_ROOM = 0

local MeshClass = {}
MeshClass.__index = MeshClass

function Mesh()
	return setmetatable({ areas = {}, neighbors = {}, links = {}, sealed = false, count = 0 }, MeshClass)
end

local function Unsealed(mesh)
	if mesh.sealed then error("the mesh is sealed: areas and links come before Seal", 3) end
end

function MeshClass:Area(id, x, y, z, attributes)
	Unsealed(self)
	if self.areas[id] then error("area " .. tostring(id) .. " added twice", 2) end
	self.areas[id] = { x = x, y = y, z = z, attributes = attributes }
	self.neighbors[id], self.links[id] = {}, {}
	self.count = self.count + 1
end

function MeshClass:Link(from, to, distance, rise)
	Unsealed(self)
	local neighbors = self.neighbors[from]
	if not neighbors then error("no area " .. tostring(from) .. " in the mesh", 2) end
	neighbors[#neighbors + 1] = to
	self.links[from][to] = { distance = distance, rise = rise }
end

function MeshClass:Seal()
	Unsealed(self)
	for from, neighbors in pairs(self.neighbors) do
		for _, to in ipairs(neighbors) do
			if not self.areas[to] then error("no area " .. tostring(to) .. " in the mesh (linked from " .. tostring(from) .. ")", 2) end
		end
	end
	self.sealed = true
end

function MeshClass:Sealed()
	return self.sealed
end

function MeshClass:Areas()
	if not self.sealed then error("the mesh is not sealed yet", 2) end
	return self.count
end

local NOTHING = {}

local ToldClass = {}
ToldClass.__index = ToldClass

-- The search's graph port: the mesh's data, what it was told, its rules
-- (each answer kept), and the strategy pricing a step as the npc
-- controller's FillStep fills it (no ladders: an engine NPC climbs none).
local Graph = {}
Graph.__index = Graph

function Graph:Neighbors(id)
	return self.mesh.neighbors[id]
end

function Graph:Crossable(from, to)
	local refused = self.told.uncrossable and self.told.uncrossable[from]
	if refused and refused[to] then return false end
	local crossable = self.rules.crossable
	if not crossable then return true end
	local known = self.crossings[from]
	if not known then
		known = {}
		self.crossings[from] = known
	end
	if known[to] == nil then known[to] = crossable(from, to) == true end
	return known[to]
end

function Graph:Traversable(id)
	if self.told.closed and self.told.closed[id] then return false end
	local traversable = self.rules.traversable
	if not traversable then return true end
	if self.entered[id] == nil then self.entered[id] = traversable(id) == true end
	return self.entered[id]
end

function Graph:Room(id)
	local rooms = self.told.rooms
	if rooms and rooms[id] then return rooms[id] end
	local room = self.rules.room
	if not room then return NO_ROOM end
	if self.roomOf[id] == nil then self.roomOf[id] = room(id) or NO_ROOM end
	return self.roomOf[id]
end

function Graph:Cost(from, to, costSoFar)
	if not self:Crossable(from, to) then return Path.IMPASSABLE end
	local link, step = self.mesh.links[from][to], self.step
	step.traversable = self:Traversable(to)
	step.length = link.distance
	step.centerDistance = link.distance
	step.heightChange = link.rise
	step.fromCostSoFar = costSoFar
	step.areaId = to
	step.spawnRoomTeam = self:Room(to)
	step.attributes = self.mesh.areas[to].attributes
	return self.strategy.Cost(step, self.limits, self.bot)
end

function Graph:Estimate(id)
	local estimates = self.told.estimates
	return estimates and estimates[id] or Geometry.Distance(self.mesh.areas[id], self.goalPos)
end

function New(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded, told, rules)
	if not mesh.sealed then error("the mesh is not sealed yet", 2) end
	for _, id in ipairs({ start, goal }) do
		if not mesh.areas[id] then error("no area " .. tostring(id) .. " in the mesh", 2) end
	end
	if getmetatable(told) == ToldClass then
		if told.mesh ~= mesh then error("the Told is another mesh's", 2) end
		told = told.told
	end
	local graph = setmetatable({
		mesh = mesh,
		strategy = strategy,
		limits = limits,
		bot = bot,
		goalPos = goalPos,
		told = told or NOTHING,
		rules = rules or NOTHING,
		crossings = {},
		entered = {},
		roomOf = {},
		step = { hasFrom = true },
	}, Graph)
	return Pathfinder.New(graph, start, goal, maxExpanded)
end

function Distances(mesh, starts, limit, limits, told)
	if not mesh.sealed then error("the mesh is not sealed yet", 2) end
	for _, id in ipairs(starts) do
		if not mesh.areas[id] then error("no area " .. tostring(id) .. " in the mesh", 2) end
	end
	local uncrossable = (told or NOTHING).uncrossable
	return Search.Distances(starts, function(id)
		local edges, refused, links = {}, uncrossable and uncrossable[id], mesh.links[id]
		for _, to in ipairs(mesh.neighbors[id]) do
			local link = links[to]
			if Path.Walkable(link.rise, limits) and not (refused and refused[to]) then
				edges[#edges + 1] = { node = to, cost = link.distance }
			end
		end
		return edges
	end, limit)
end

-- told[what]'s entries whose value holds, refusing an area the mesh lacks.
local function CopyAreas(mesh, ids, what)
	local copy = {}
	for id, value in pairs(ids or NOTHING) do
		if not mesh.areas[id] then error(what .. ": no area " .. tostring(id) .. " in the mesh", 3) end
		if value then copy[id] = value end
	end
	return copy
end

function Told(mesh, told)
	if not mesh.sealed then error("the mesh is not sealed yet", 2) end
	told = told or NOTHING
	local uncrossable = {}
	for from, tos in pairs(told.uncrossable or NOTHING) do
		for to, refused in pairs(tos) do
			if not (mesh.links[from] and mesh.links[from][to]) then
				error("told.uncrossable: no link " .. tostring(from) .. " -> " .. tostring(to) .. " in the mesh", 2)
			end
			if refused then
				uncrossable[from] = uncrossable[from] or {}
				uncrossable[from][to] = true
			end
		end
	end
	return setmetatable({
		mesh = mesh,
		told = {
			closed = CopyAreas(mesh, told.closed, "told.closed"),
			rooms = CopyAreas(mesh, told.rooms, "told.rooms"),
			uncrossable = uncrossable,
		},
	}, ToldClass)
end

function Calculator(known, strategy, limits, bot)
	if getmetatable(known) ~= ToldClass then error("a calculator prices over a Told", 2) end
	local mesh = known.mesh
	local graph = setmetatable({
		mesh = mesh,
		strategy = strategy,
		limits = limits,
		bot = bot,
		told = known.told,
		rules = NOTHING,
		crossings = {},
		entered = {},
		roomOf = {},
	}, Graph)
	local step = { hasFrom = true }
	return function(area, fromArea, ladder, elevator, length)
		if fromArea == nil then return 0 end
		local from, to = fromArea:GetID(), area:GetID()
		if ladder ~= nil then
			if not mesh.areas[to] then error("no area " .. tostring(to) .. " in the mesh", 2) end
			step.ladderLength = ladder:GetLength()
			step.centerDistance = 0
			step.heightChange = fromArea:ComputeAdjacentConnectionHeightChange(area)
		else
			local link = mesh.links[from] and mesh.links[from][to]
			if not link then error("no link " .. tostring(from) .. " -> " .. tostring(to) .. " in the mesh", 2) end
			if not graph:Crossable(from, to) then return Path.IMPASSABLE end
			step.ladderLength = nil
			step.centerDistance = link.distance
			step.heightChange = link.rise
		end
		step.traversable = graph:Traversable(to)
		step.length = length or 0
		step.fromCostSoFar = fromArea:GetCostSoFar()
		step.areaId = to
		step.spawnRoomTeam = graph:Room(to)
		step.attributes = mesh.areas[to].attributes
		return strategy.Cost(step, limits, bot)
	end
end
