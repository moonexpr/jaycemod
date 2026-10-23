-- NavAreaBuildPath (nav_pathfind.h) as a path solver
-- (foundation.graph.pathfinder), for NPCs that cannot use the engine's
-- search: HL2's engine NPCs, which path over AI nodes that TF2 maps do not
-- have. It is the engine's A* rule for rule, so a path strategy
-- (games.nextsoldier.path) gives the same route here as through Path:Compute.
-- The graph is a port:
--   graph:Neighbors(node) -> list of nodes, in the engine's order
--   graph:Cost(from, to, costSoFar) -> the total cost of reaching `to`
--     through `from`, negative (IMPASSABLE) for a dead end: a path
--     strategy's Cost
--   graph:Estimate(node, goal) -> the straight-line distance left
-- Nodes are nav area ids, or any values usable as table keys. A blocked
-- area is the cost's to refuse (IsAreaTraversable), not the search's.
local Heap = tree.heap
local Pathfinder = graph.pathfinder
local ipairs = ipairs
module(...)

-- NavAreaBuildPath: a NaN cost is clamped to this, not treated as a dead end.
NAN_COST = 1e30
-- Every step costs at least a little more than its parent.
local MIN_STEP_SCALE, MIN_STEP_ADD = 1.00001, 0.00001

-- The open list is ordered by total cost, then by when an entry was pushed.
-- The engine keeps a sorted list in which a new or cheapened node goes
-- after every node of equal cost, so the push order breaks ties the same
-- way. A node pushed again leaves its old entry behind, skipped when it
-- comes up.
local function Before(a, b)
	if a.total ~= b.total then return a.total < b.total end
	return a.seq < b.seq
end

local AStar = Pathfinder.Solver("astar")

New, Find = AStar.New, AStar.Find

function AStar:Begin()
	self.open = Heap.New(Before)
	self.seq = 0
	self.costSoFar = { [self.start] = 0 }
	self.entryOf = {} -- node -> its live open-list entry
	self.closed = {}
	local estimate = self.graph:Estimate(self.start, self.goal)
	self:Approach(self.start, estimate)
	self:Open(self.start, estimate)
end

function AStar:Open(node, total)
	self.seq = self.seq + 1
	local entry = {
		node = node,
		total = total,
		seq = self.seq,
	}
	self.entryOf[node] = entry
	self.open:Push(entry)
end

-- The next live entry's node, or nil when the open list is empty.
function AStar:Next()
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

function AStar:Relax(node, nextNode)
	local graph = self.graph
	local cost = graph:Cost(node, nextNode, self.costSoFar[node])
	if cost ~= cost then cost = NAN_COST end
	if cost < 0 then return end
	local floor = self.costSoFar[node] * MIN_STEP_SCALE + MIN_STEP_ADD
	if cost < floor then cost = floor end
	local known = self.entryOf[nextNode] ~= nil or self.closed[nextNode]
	if known and self.costSoFar[nextNode] <= cost then return end
	local remaining = graph:Estimate(nextNode, self.goal)
	self:Approach(nextNode, remaining)
	self.costSoFar[nextNode] = cost
	self.closed[nextNode] = nil
	self:Reach(nextNode, node)
	self:Open(nextNode, cost + remaining)
end

function AStar:Expand(node)
	local parent = self.parent[node]
	for _, nextNode in ipairs(self.graph:Neighbors(node)) do
		if nextNode ~= parent and nextNode ~= node then self:Relax(node, nextNode) end
	end
	self.closed[node] = true
end
