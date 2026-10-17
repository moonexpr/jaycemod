-- foundation.core.pathfinder: the search a path solver fills in. A
-- breadth-first solver, written here against the contract, drives it.
local T = dofile("tests/harness.lua")
local Pathfinder = T.require("foundation.core.pathfinder")

-- a - b - c - d, and e alone.
local LINE = {
	a = { "b" },
	b = { "a", "c" },
	c = { "b", "d" },
	d = { "c" },
	e = {},
}
local POSITION = { a = 0, b = 1, c = 2, d = 3, e = 10 }

local function Graph()
	local graph = {}
	function graph:Neighbors(node) return LINE[node] end
	function graph:Estimate(node, goal) return math.abs(POSITION[goal] - POSITION[node]) end
	return graph
end

local BreadthFirst = Pathfinder.Solver("breadth-first")

function BreadthFirst:Begin()
	self.queue, self.head, self.seen = { self.start }, 1, { [self.start] = true }
	self.begun = true
end

function BreadthFirst:Next()
	local node = self.queue[self.head]
	if node ~= nil then self.head = self.head + 1 end
	return node
end

function BreadthFirst:Expand(node)
	for _, next in ipairs(self.graph:Neighbors(node)) do
		if not self.seen[next] then
			self.seen[next] = true
			self:Reach(next, node)
			self:Approach(next, self.graph:Estimate(next, self.goal))
			self.queue[#self.queue + 1] = next
		end
	end
end

local function Joined(list)
	return list and table.concat(list, " ") or "nil"
end

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

T.test("a solver's search runs from start to goal and gives the route", function()
	local found, closest = BreadthFirst.Find(Graph(), "a", "d")
	T.eq(Joined(found), "a b c d", "found")
	T.eq(Joined(closest), "a b c d", "the closest is the goal")
end)

T.test("a start that is the goal is found before the solver begins", function()
	local search = BreadthFirst.New(Graph(), "c", "c")
	T.eq(search.status, Pathfinder.FOUND, "found")
	T.eq(search.begun, nil, "the solver never began")
	T.eq(Joined(search:Route()), "c", "a route of one node")
end)

T.test("a search runs a budget of expansions at a time", function()
	local search = BreadthFirst.New(Graph(), "a", "d")
	T.eq(search:Step(1), Pathfinder.RUNNING, "one expansion")
	T.eq(search.expanded, 1, "counted")
	T.eq(search:Step(1), Pathfinder.RUNNING, "two")
	T.eq(search:Step(10), Pathfinder.FOUND, "the rest")
	T.eq(search.expanded, 3, "a, b and c expanded; d is the goal")
	T.eq(Joined(search:Route()), "a b c d", "same route")
end)

T.test("an unreachable goal fails, and the route leads to the node that came closest", function()
	local search = BreadthFirst.New(Graph(), "a", "e")
	T.eq(search:Step(100), Pathfinder.FAILED, "the frontier ran out")
	T.eq(Joined(search:Route()), "a b c d", "to d, nearest e")
	local found, closest = BreadthFirst.Find(Graph(), "a", "e")
	T.eq(found, nil, "nothing found")
	T.eq(Joined(closest), "a b c d", "the closest route")
end)

T.test("a search that reaches its expansion cap fails", function()
	local search = BreadthFirst.New(Graph(), "a", "d", 2)
	T.eq(search:Step(100), Pathfinder.FAILED, "capped")
	T.eq(search.expanded, 2, "no further")
	T.eq(Joined(search:Route()), "a b c", "to the closest reached")
end)

T.test("a search's cap defaults to MAX_EXPANDED", function()
	T.eq(BreadthFirst.New(Graph(), "a", "d").maxExpanded, Pathfinder.MAX_EXPANDED, "the default")
end)

T.test("a solver needs a name, and one missing a hook fails loudly", function()
	Raises(Pathfinder.Solver, "")
	local Hollow = Pathfinder.Solver("hollow")
	local err = Raises(Hollow.New, Graph(), "a", "d")
	T.eq(err:find("hollow", 1, true) ~= nil, true, "names the solver")
	T.eq(err:find("Begin", 1, true) ~= nil, true, "names the hook")
end)

T.finish()
