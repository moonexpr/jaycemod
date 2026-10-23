-- games.npc.astar: NavAreaBuildPath (nav_pathfind.h) over any graph
-- the caller describes, run here on small grids whose costs the tests
-- control, whole or a few expansions at a time.
local T = dofile("tests/harness.lua")
local Pathfinder = graph.pathfinder
local AStar = npc.astar
local Path = nextsoldier.path

-- A graph of named nodes at 2D positions, with the given edges both ways.
-- Cost is the running total plus the edge length, or IMPASSABLE for a
-- blocked edge; the estimate is the straight-line distance.
local function Graph(nodes, edges, blocked)
	local graph = { nodes = nodes, adjacent = {}, blocked = blocked or {}, costed = 0 }
	for name in pairs(nodes) do graph.adjacent[name] = {} end
	for _, e in ipairs(edges) do
		table.insert(graph.adjacent[e[1]], e[2])
		table.insert(graph.adjacent[e[2]], e[1])
	end
	local function Distance(a, b)
		local p, q = nodes[a], nodes[b]
		return math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2)
	end
	function graph:Neighbors(node) return self.adjacent[node] end
	function graph:Cost(from, to, costSoFar)
		self.costed = self.costed + 1
		if self.blocked[from .. to] or self.blocked[to .. from] then return Path.IMPASSABLE end
		return costSoFar + Distance(from, to)
	end
	function graph:Estimate(node, goal) return Distance(node, goal) end
	return graph
end

local function Joined(list)
	return list and table.concat(list, " ") or "nil"
end

--  a - b - c
--  |       |
--  d - e - f
local RING = {
	nodes = { a = { 0, 0 }, b = { 1, 0 }, c = { 2, 0 }, d = { 0, 1 }, e = { 1, 1 }, f = { 2, 1 } },
	edges = { { "a", "b" }, { "b", "c" }, { "a", "d" }, { "d", "e" }, { "e", "f" }, { "c", "f" } },
}

T.test("the route runs from start to goal along the cheapest edges", function()
	local graph = Graph(RING.nodes, RING.edges)
	T.eq(Joined(AStar.Find(graph, "a", "c")), "a b c", "top row")
	T.eq(Joined(AStar.Find(graph, "d", "f")), "d e f", "bottom row")
end)

T.test("an impassable edge sends the route the long way round", function()
	local graph = Graph(RING.nodes, RING.edges, { bc = true })
	T.eq(Joined(AStar.Find(graph, "a", "c")), "a d e f c", "around the block")
end)

T.test("a start that is the goal is a route of one node", function()
	T.eq(Joined(AStar.Find(Graph(RING.nodes, RING.edges), "e", "e")), "e", "no move")
end)

T.test("no route when the goal cannot be reached", function()
	local graph = Graph(RING.nodes, RING.edges, { bc = true, ef = true })
	T.eq(AStar.Find(graph, "a", "c"), nil, "cut off")
end)

T.test("a search that expands more nodes than its limit gives up", function()
	local nodes, edges = {}, {}
	for i = 1, 50 do
		nodes["n" .. i] = { i, 0 }
		if i > 1 then edges[#edges + 1] = { "n" .. (i - 1), "n" .. i } end
	end
	T.eq(AStar.Find(Graph(nodes, edges), "n1", "n50", 10), nil, "limited")
	T.eq(#AStar.Find(Graph(nodes, edges), "n1", "n50", 100), 50, "unlimited enough")
end)

T.test("a cheaper way to a node found later replaces the first", function()
	-- s reaches m directly at cost 10, or through x at cost 2.
	local nodes = { s = { 0, 0 }, x = { 1, 0 }, m = { 2, 0 }, g = { 3, 0 } }
	local graph = Graph(nodes, { { "s", "m" }, { "s", "x" }, { "x", "m" }, { "m", "g" } })
	local Cost = graph.Cost
	function graph:Cost(from, to, costSoFar)
		if (from == "s" and to == "m") then return costSoFar + 10 end
		return Cost(self, from, to, costSoFar)
	end
	T.eq(Joined(AStar.Find(graph, "s", "g")), "s x m g", "relaxed")
end)

T.test("equal routes go by the neighbour found first, as the engine's open list keeps ties in order", function()
	--  a - b
	--  |   |
	--  c - d
	local nodes = { a = { 0, 0 }, b = { 1, 0 }, c = { 0, 1 }, d = { 1, 1 } }
	local graph = Graph(nodes, { { "a", "b" }, { "a", "c" }, { "b", "d" }, { "c", "d" } })
	T.eq(Joined(AStar.Find(graph, "a", "d")), "a b d", "b was listed first")
	graph.adjacent.a = { "c", "b" }
	T.eq(Joined(AStar.Find(graph, "a", "d")), "a c d", "c was listed first")
end)

T.test("a failed search still gives the route to the node that came closest to the goal", function()
	local graph = Graph(RING.nodes, RING.edges, { bc = true, ef = true })
	local route, closest = AStar.Find(graph, "a", "c")
	T.eq(route, nil, "no route")
	T.eq(Joined(closest), "a b", "b is nearest c")
end)

T.test("a found route is its own closest route", function()
	local route, closest = AStar.Find(Graph(RING.nodes, RING.edges), "a", "c")
	T.eq(Joined(closest), Joined(route), "the same")
end)

T.test("a search run a few expansions at a time finds what one run does", function()
	local graph = Graph(RING.nodes, RING.edges, { bc = true })
	local search = AStar.New(graph, "a", "c")
	local steps = 0
	while search:Step(1) == Pathfinder.RUNNING do steps = steps + 1 end
	T.eq(search.status, Pathfinder.FOUND, "found")
	T.eq(Joined(search:Route()), "a d e f c", "same route")
	T.eq(steps > 2, true, "it took several steps")
end)

T.test("a cost below the parent's is raised just above it, so every step costs something", function()
	local nodes = { s = { 0, 0 }, m = { 1, 0 }, g = { 2, 0 } }
	local graph = Graph(nodes, { { "s", "m" }, { "m", "g" } })
	local seen = {}
	function graph:Cost(from, to, costSoFar)
		seen[to] = costSoFar
		if to == "m" then return 10 end
		return costSoFar - 5
	end
	local search = AStar.New(graph, "s", "g")
	while search:Step(10) == Pathfinder.RUNNING do end
	T.eq(search.status, Pathfinder.FOUND, "found")
	T.near(search.costSoFar.g, 10 * 1.00001 + 0.00001, 1e-9, "clamped")
end)

T.test("a closed node reached more cheaply is opened again", function()
	-- The estimate overrates x, so y closes first by the long way; the
	-- cheaper way through x reopens it.
	local nodes = { s = { 0, 0 }, x = { 1, 0 }, y = { 2, 0 }, g = { 3, 0 } }
	local graph = Graph(nodes, { { "s", "x" }, { "s", "y" }, { "x", "y" }, { "y", "g" } })
	local COST = { sx = 1, sy = 10, xy = 1, yg = 100 }
	function graph:Cost(from, to, costSoFar) return costSoFar + (COST[from .. to] or COST[to .. from]) end
	function graph:Estimate(node) return node == "x" and 50 or 0 end
	T.eq(Joined(AStar.Find(graph, "s", "g")), "s x y g", "reopened")
end)

T.test("a cost that is not a number counts as enormous, not as a dead end", function()
	local graph = Graph(RING.nodes, RING.edges)
	function graph:Cost(from, to, costSoFar)
		if from .. to == "bc" then return 0 / 0 end
		return costSoFar + 1
	end
	T.eq(Joined(AStar.Find(graph, "a", "c")), "a d e f c", "around the NaN")
end)

T.finish()
