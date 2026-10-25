-- The search a path solver runs (a template method): the search owns the
-- loop, its budget and cap, its status, and the route back from any node;
-- a solver (foundation.pathfinder.<name>) owns its frontier and how it
-- grows. A search runs a few expansions at a time, so it can be spread
-- over ticks.
--
-- Solver(name) makes a solver class, which fills in:
--   solver:Begin()       open the frontier at self.start
--   solver:Next()        take the next node to expand, or nil when the
--                        frontier is empty
--   solver:Expand(node)  grow the frontier from node, calling
--                        self:Reach(next, node) for each node it reaches
--                        by a new best way and self:Approach(next, distance)
--                        with its distance left to the goal
-- and gets New(graph, start, goal[, maxExpanded]) -> a search, and
-- Find(graph, start, goal[, maxExpanded]) -> the route to the goal or nil,
-- and the route to the node that came closest.
--
-- The graph is the solver's port; the search reads nothing of it. Nodes
-- are any values usable as table keys.
-- Core-rule exception: stays Lua. A template method whose hooks are Lua; the
-- native search is its concrete solver (wetsands.navsearch), not this base.
local Class = core.class
local error, setmetatable, tostring, type = error, setmetatable, tostring, type
module(...)

RUNNING, FOUND, FAILED = "running", "found", "failed"

-- How many nodes a search may expand before it gives up (a goal cut off
-- from the start would otherwise flood the whole graph).
MAX_EXPANDED = 4000

local Search = {}
Search.__index = Search

local function Missing(hook)
	return function(self)
		error("path solver " .. self.solverName .. " has no " .. hook, 2)
	end
end

Search.Begin = Missing("Begin")
Search.Next = Missing("Next")
Search.Expand = Missing("Expand")

-- Records that node was reached from parent by its best way so far.
function Search:Reach(node, parent)
	self.parent[node] = parent
end

-- Records node's distance left to the goal; the nearest becomes the closest.
function Search:Approach(node, distance)
	if self.closestDistance == nil or distance < self.closestDistance then
		self.closest = node
		self.closestDistance = distance
	end
end

-- Runs up to `budget` expansions and returns the status: RUNNING, FOUND,
-- or FAILED (the goal is out of reach, or the search hit maxExpanded).
function Search:Step(budget)
	while self.status == RUNNING and budget > 0 do
		local node = self:Next()
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

function Solver(name)
	if type(name) ~= "string" or name == "" then error("a path solver needs a name, not " .. tostring(name), 2) end
	local class = Class.Extend(Search, { solverName = name })

	function class.New(graph, start, goal, maxExpanded)
		local search = setmetatable({
			graph = graph,
			start = start,
			goal = goal,
			maxExpanded = maxExpanded or MAX_EXPANDED,
			expanded = 0,
			status = RUNNING,
			parent = {},
			closest = start,
		}, class)
		if start == goal then
			search.status = FOUND
			return search
		end
		search:Begin()
		return search
	end

	function class.Find(graph, start, goal, maxExpanded)
		local search = class.New(graph, start, goal, maxExpanded)
		while search:Step(search.maxExpanded + 1) == RUNNING do end
		local closest = search:Route()
		if search.status == FOUND then return closest, closest end
		return nil, closest
	end

	return class
end
