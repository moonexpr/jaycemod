-- NavAreaBuildPath (nav_pathfind.h) over a graph the caller describes, for
-- NPCs that cannot use the engine's search: HL2's engine NPCs, which path
-- over AI nodes that TF2 maps do not have. It is the engine's A* rule for
-- rule, so a path strategy (foundation.npc.path) gives the same route here
-- as through Path:Compute, and it runs a few expansions at a time, so a
-- search can be spread over ticks. The graph is a port:
--   graph:Neighbors(node) -> list of nodes, in the engine's order
--   graph:Cost(from, to, costSoFar) -> the total cost of reaching `to`
--     through `from`, negative (IMPASSABLE) for a dead end: a path
--     strategy's Cost
--   graph:Estimate(node, goal) -> the straight-line distance left
-- Nodes are any values usable as table keys (nav area ids). A blocked area
-- is the cost's to refuse (IsAreaTraversable), not the search's.
local ipairs, setmetatable = ipairs, setmetatable
module(...)

RUNNING, FOUND, FAILED = "running", "found", "failed"

-- How many nodes a search may expand before it gives up (a goal cut off
-- from the start would otherwise flood the whole mesh).
MAX_EXPANDED = 4000

-- NavAreaBuildPath: a NaN cost is clamped to this, not treated as a dead end.
NAN_COST = 1e30
-- Every step costs at least a little more than its parent.
local MIN_STEP_SCALE, MIN_STEP_ADD = 1.00001, 0.00001

-- The open list: a binary min-heap ordered by total cost, then by when an
-- entry was pushed. The engine keeps a sorted list in which a new or
-- cheapened node goes after every node of equal cost, so the push order
-- breaks ties the same way. A node pushed again leaves its old entry
-- behind, skipped when it comes up.
local Heap = {}
Heap.__index = Heap

local function NewHeap()
	return setmetatable({ n = 0, entries = {} }, Heap)
end

local function Before(a, b)
	if a.total ~= b.total then return a.total < b.total end
	return a.seq < b.seq
end

function Heap:Push(entry)
	local entries = self.entries
	local n = self.n + 1
	self.n = n
	while n > 1 do
		local parent = (n - n % 2) / 2
		if not Before(entry, entries[parent]) then break end
		entries[n] = entries[parent]
		n = parent
	end
	entries[n] = entry
end

function Heap:Pop()
	local entries = self.entries
	local top, last = entries[1], entries[self.n]
	entries[self.n] = nil
	self.n = self.n - 1
	local n, i = self.n, 1
	while true do
		local child = i * 2
		if child > n then break end
		if child < n and Before(entries[child + 1], entries[child]) then child = child + 1 end
		if not Before(entries[child], last) then break end
		entries[i] = entries[child]
		i = child
	end
	if n > 0 then entries[i] = last end
	return top
end

local Search = {}
Search.__index = Search

-- A search from start to goal that has not run yet. maxExpanded defaults
-- to MAX_EXPANDED.
function New(graph, start, goal, maxExpanded)
	local search = setmetatable({
		graph = graph,
		start = start,
		goal = goal,
		maxExpanded = maxExpanded or MAX_EXPANDED,
		expanded = 0,
		status = RUNNING,
		open = NewHeap(),
		seq = 0,
		costSoFar = { [start] = 0 },
		entryOf = {}, -- node -> its live open-list entry
		closed = {},
		parent = {},
		closest = start,
	}, Search)
	if start == goal then
		search.status = FOUND
		return search
	end
	local estimate = graph:Estimate(start, goal)
	search.closestDistance = estimate
	search:Open(start, estimate)
	return search
end

function Search:Open(node, total)
	self.seq = self.seq + 1
	local entry = { node = node, total = total, seq = self.seq }
	self.entryOf[node] = entry
	self.open:Push(entry)
end

-- The next live entry's node, or nil when the open list is empty.
function Search:PopOpen()
	while self.open.n > 0 do
		local entry = self.open:Pop()
		if self.entryOf[entry.node] == entry then
			self.entryOf[entry.node] = nil
			return entry.node
		end
	end
	return nil
end

function Search:Relax(node, nextNode)
	local graph = self.graph
	local cost = graph:Cost(node, nextNode, self.costSoFar[node])
	if cost ~= cost then cost = NAN_COST end
	if cost < 0 then return end
	local floor = self.costSoFar[node] * MIN_STEP_SCALE + MIN_STEP_ADD
	if cost < floor then cost = floor end
	local known = self.entryOf[nextNode] ~= nil or self.closed[nextNode]
	if known and self.costSoFar[nextNode] <= cost then return end
	local remaining = graph:Estimate(nextNode, self.goal)
	if remaining < self.closestDistance then
		self.closest = nextNode
		self.closestDistance = remaining
	end
	self.costSoFar[nextNode] = cost
	self.closed[nextNode] = nil
	self.parent[nextNode] = node
	self:Open(nextNode, cost + remaining)
end

function Search:Expand(node)
	local parent = self.parent[node]
	for _, nextNode in ipairs(self.graph:Neighbors(node)) do
		if nextNode ~= parent and nextNode ~= node then self:Relax(node, nextNode) end
	end
	self.closed[node] = true
end

-- Runs up to `budget` expansions and returns the status: RUNNING, FOUND,
-- or FAILED (the goal is out of reach, or the search hit maxExpanded).
function Search:Step(budget)
	while self.status == RUNNING and budget > 0 do
		local node = self:PopOpen()
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
			self:Expand(node)
		end
	end
	return self.status
end

-- The nodes from the start to `last` (default: the goal once found, else
-- the node that came closest), both included.
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

-- The whole search at once: the route to the goal or nil, and the route to
-- the node that came closest (Path::Compute follows that one when the goal
-- is out of reach).
function Find(graph, start, goal, maxExpanded)
	local search = New(graph, start, goal, maxExpanded)
	while search:Step(search.maxExpanded + 1) == RUNNING do end
	local closest = search:Route()
	if search.status == FOUND then return closest, closest end
	return nil, closest
end
