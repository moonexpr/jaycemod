-- Path search over any graph the caller describes: NavAreaBuildPath's A*
-- (nav_pathfind.h) rule for rule, so a path strategy (wetsands.path) gives
-- the same route here as through the engine's Path:Compute. A search runs a
-- few expansions at a time, so it can be spread over ticks. This is the Lua
-- twin, which clients run; a server with native/foundation has the native
-- one in its place, which keeps this contract:
--
--   New(graph, start, goal[, maxExpanded]) -> a search from start to goal
--   Find(graph, start, goal[, maxExpanded]) -> the route to the goal or nil,
--     and the route to the node that came closest
--   search.status (RUNNING, FOUND, FAILED), search.expanded,
--   search.maxExpanded (default MAX_EXPANDED), search.start, search.goal,
--   search.closest (the goal once found, else the node nearest it by the
--   estimate), search.parent (node -> the node it was reached from)
--   search:Step(budget) -> the status, after up to budget expansions
--   search:Route([last]) -> the nodes from the start to last (default: the
--     closest), both included
--   search:CostSoFar(node) -> the cost of the best way to node yet, or nil
--
-- The graph is the caller's port:
--   graph:Neighbors(node) -> list of nodes, in the engine's order
--   graph:Cost(from, to, costSoFar) -> the total cost of reaching to through
--     from, negative (wetsands.path.IMPASSABLE) for a dead end
--   graph:Estimate(node, goal) -> the straight-line distance left
-- Nodes are any values usable as table keys (nav area ids). A blocked area
-- is the cost's to refuse (IsAreaTraversable), not the search's.
--
-- The engine's rules: the open list is ordered by total cost, then by when
-- an entry was pushed (tree.heap's order: the engine keeps a sorted list in
-- which a new or cheapened node goes after every node of equal cost); a
-- node pushed again leaves its old entry behind, skipped when it comes up;
-- a NaN cost is clamped to NAN_COST, not a dead end; every step costs at
-- least a little more than its parent; a closed node reached more cheaply
-- is opened again; the node a search came from is not expanded back into.
local Heap = tree.heap
local ipairs, setmetatable = ipairs, setmetatable
module(...)

RUNNING, FOUND, FAILED = "running", "found", "failed"

-- How many nodes a search may expand before it gives up (a goal cut off
-- from the start would otherwise flood the whole graph).
MAX_EXPANDED = 4000

-- NavAreaBuildPath: a NaN cost is clamped to this, not treated as a dead end.
NAN_COST = 1e30

local MIN_STEP_SCALE, MIN_STEP_ADD = 1.00001, 0.00001

local Search = {}
Search.__index = Search

local function Approach(self, node, distance)
	if self.closestDistance == nil or distance < self.closestDistance then
		self.closest = node
		self.closestDistance = distance
	end
end

local function Open(self, node, total)
	local entry = { node = node }
	self.entryOf[node] = entry
	self.open:Push(total, entry)
end

-- The next live entry's node, or nil when the open list is empty.
local function Next(self)
	local open = self.open
	while open:Size() > 0 do
		local entry = open:Pop()
		if self.entryOf[entry.node] == entry then
			self.entryOf[entry.node] = nil
			return entry.node
		end
	end
	return nil
end

local function Relax(self, node, nextNode)
	local graph = self.graph
	local cost = graph:Cost(node, nextNode, self.costSoFar[node])
	if cost ~= cost then cost = NAN_COST end
	if cost < 0 then return end
	local floor = self.costSoFar[node] * MIN_STEP_SCALE + MIN_STEP_ADD
	if cost < floor then cost = floor end
	local known = self.entryOf[nextNode] ~= nil or self.closed[nextNode]
	if known and self.costSoFar[nextNode] <= cost then return end
	local remaining = graph:Estimate(nextNode, self.goal)
	Approach(self, nextNode, remaining)
	self.costSoFar[nextNode] = cost
	self.closed[nextNode] = nil
	self.parent[nextNode] = node
	Open(self, nextNode, cost + remaining)
end

local function Expand(self, node)
	local parent = self.parent[node]
	for _, nextNode in ipairs(self.graph:Neighbors(node)) do
		if nextNode ~= parent and nextNode ~= node then Relax(self, node, nextNode) end
	end
	self.closed[node] = true
end

function New(graph, start, goal, maxExpanded)
	local search = setmetatable({
		graph = graph,
		start = start,
		goal = goal,
		maxExpanded = maxExpanded or MAX_EXPANDED,
		expanded = 0,
		status = RUNNING,
		parent = {},
		closest = start,
		costSoFar = { [start] = 0 },
	}, Search)
	if start == goal then
		search.status = FOUND
		return search
	end
	search.open, search.entryOf, search.closed = Heap(), {}, {}
	local estimate = graph:Estimate(start, goal)
	Approach(search, start, estimate)
	Open(search, start, estimate)
	return search
end

function Search:Step(budget)
	while self.status == RUNNING and budget > 0 do
		local node = Next(self)
		if node == nil then
			self.status = FAILED
		elseif node == self.goal then
			self.closest = node
			self.status = FOUND
		elseif self.expanded >= self.maxExpanded then
			self.status = FAILED
		else
			self.expanded = self.expanded + 1
			budget = budget - 1
			Expand(self, node)
		end
	end
	return self.status
end

function Search:Route(last)
	local node = last or self.closest
	local reversed = { node }
	while self.parent[node] ~= nil do
		node = self.parent[node]
		reversed[#reversed + 1] = node
	end
	local route = {}
	for i = #reversed, 1, -1 do route[#route + 1] = reversed[i] end
	return route
end

function Search:CostSoFar(node)
	return self.costSoFar[node]
end

function Find(graph, start, goal, maxExpanded)
	local search = New(graph, start, goal, maxExpanded)
	while search:Step(search.maxExpanded + 1) == RUNNING do end
	local closest = search:Route()
	if search.status == FOUND then return closest, closest end
	return nil, closest
end
