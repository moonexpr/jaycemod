-- An A* search over a graph the caller describes, for NPCs that cannot run
-- the engine's own path search (NavAreaBuildPath in NextBot): HL2's engine
-- NPCs, which path over AI nodes that TF2 maps do not have. The graph is a
-- port:
--   graph:Neighbors(node) -> list of nodes
--   graph:Cost(from, to, costSoFar) -> the total cost of reaching `to` through
--     `from`, or foundation.npc.path's IMPASSABLE (a path strategy's Cost)
--   graph:Estimate(node, goal) -> a lower bound on the cost left
-- Nodes are any values usable as table keys (nav area ids).
local ipairs, setmetatable = ipairs, setmetatable
local IMPASSABLE = require("foundation.npc.path").IMPASSABLE
module(...)

-- How many nodes a search may expand before it gives up (a goal cut off
-- from the start would otherwise flood the whole mesh).
MAX_EXPANDED = 4000

-- A binary min-heap of nodes keyed by their estimated total cost.
local Heap = {}
Heap.__index = Heap

local function NewHeap()
	return setmetatable({ n = 0, items = {}, keys = {} }, Heap)
end

function Heap:Push(item, key)
	local n = self.n + 1
	self.n = n
	local items, keys = self.items, self.keys
	while n > 1 do
		local parent = (n - n % 2) / 2
		if keys[parent] <= key then break end
		items[n], keys[n] = items[parent], keys[parent]
		n = parent
	end
	items[n], keys[n] = item, key
end

function Heap:Pop()
	local items, keys = self.items, self.keys
	local top = items[1]
	local last, lastKey = items[self.n], keys[self.n]
	items[self.n], keys[self.n] = nil, nil
	self.n = self.n - 1
	local n, i = self.n, 1
	while true do
		local child = i * 2
		if child > n then break end
		if child < n and keys[child + 1] < keys[child] then child = child + 1 end
		if lastKey <= keys[child] then break end
		items[i], keys[i] = items[child], keys[child]
		i = child
	end
	if n > 0 then items[i], keys[i] = last, lastKey end
	return top
end

local function Unwind(cameFrom, node)
	local reversed = { node }
	while cameFrom[node] ~= nil do
		node = cameFrom[node]
		reversed[#reversed + 1] = node
	end
	local route = {}
	for i = #reversed, 1, -1 do route[#route + 1] = reversed[i] end
	return route
end

-- The cheapest list of nodes from start to goal, both included, or nil when
-- the goal is out of reach or the search expanded more than maxExpanded
-- (default MAX_EXPANDED) nodes. A node reached again more cheaply is pushed
-- again; its stale entries are skipped once it is closed.
function Find(graph, start, goal, maxExpanded)
	maxExpanded = maxExpanded or MAX_EXPANDED
	local open = NewHeap()
	local costSoFar, cameFrom, closed = { [start] = 0 }, {}, {}
	open:Push(start, graph:Estimate(start, goal))
	local expanded = 0
	while open.n > 0 do
		local node = open:Pop()
		if node == goal then return Unwind(cameFrom, node) end
		if not closed[node] then
			closed[node] = true
			expanded = expanded + 1
			if expanded > maxExpanded then return nil end
			for _, nextNode in ipairs(graph:Neighbors(node)) do
				if not closed[nextNode] then
					local cost = graph:Cost(node, nextNode, costSoFar[node])
					if cost ~= IMPASSABLE and (costSoFar[nextNode] == nil or cost < costSoFar[nextNode]) then
						costSoFar[nextNode] = cost
						cameFrom[nextNode] = node
						open:Push(nextNode, cost + graph:Estimate(nextNode, goal))
					end
				end
			end
		end
	end
	return nil
end
