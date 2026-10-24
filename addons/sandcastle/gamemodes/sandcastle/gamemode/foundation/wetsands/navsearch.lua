-- Route searches on a nav mesh snapshot: NavAreaBuildPath (wetsands.astar)
-- priced by a path strategy (wetsands.path). This is the Lua implementation,
-- the oracle; a server that loads native/wetsands (require("wetsands")) has
-- it replaced in place by the native one, which keeps this contract:
--
--   Mesh() -> a mesh to fill: mesh:Area(id, x, y, z, attributes) for every
--     area, then mesh:Link(from, to, distance, rise) for each area's floor
--     links in GetAdjacentAreas' order (the distance between centres, and
--     ComputeAdjacentConnectionHeightChange), then mesh:Seal()
--   New(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded[,
--     told[, rules]]) -> a search from area start to area goal, estimated
--     toward goalPos, priced by strategy.Cost(step, limits, bot) (natively,
--     by strategy.Model(limits, bot)), where
--     told = { closed = id -> true, uncrossable = from -> to -> true,
--       rooms = id -> spawn room team, estimates = id -> estimate } is what
--       the search knows from the start, and
--     rules = { traversable(id) -> bool, crossable(from, to) -> bool,
--       room(id) -> spawn room team } are asked the first time the search
--       reaches an area or a link, once each (room only for an area told
--       none).
--   A search is graph.pathfinder's: status, expanded, maxExpanded, start,
--   goal, closest, parent (id -> the id it was reached from), Step(budget),
--   Route([last]) -> area ids.
-- An area the mesh lacks is refused as start or goal, or once sealed.
local AStar = wetsands.astar
local Path = wetsands.path
local Geometry = math.geometry
local error, ipairs, pairs, setmetatable, tostring = error, ipairs, pairs, setmetatable, tostring
module(...)

-- TEAM_UNASSIGNED: an area in no spawn room.
NO_ROOM = 0

local MeshClass = {}
MeshClass.__index = MeshClass

function Mesh()
	return setmetatable({ areas = {}, neighbors = {}, links = {}, sealed = false }, MeshClass)
end

local function Unsealed(mesh)
	if mesh.sealed then error("the mesh is sealed: areas and links come before Seal", 3) end
end

function MeshClass:Area(id, x, y, z, attributes)
	Unsealed(self)
	if self.areas[id] then error("area " .. tostring(id) .. " added twice", 2) end
	self.areas[id] = { x = x, y = y, z = z, attributes = attributes }
	self.neighbors[id], self.links[id] = {}, {}
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

local NOTHING = {}

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
	return AStar.New(graph, start, goal, maxExpanded)
end
