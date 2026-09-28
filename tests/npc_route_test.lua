-- foundation.npc.route: an A* search over any graph the caller describes,
-- run here on small grids whose costs the tests control.
local T = dofile("tests/harness.lua")
local Route = T.require("foundation.npc.route")
local Path = T.require("foundation.npc.path")

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
	T.eq(Joined(Route.Find(graph, "a", "c")), "a b c", "top row")
	T.eq(Joined(Route.Find(graph, "d", "f")), "d e f", "bottom row")
end)

T.test("an impassable edge sends the route the long way round", function()
	local graph = Graph(RING.nodes, RING.edges, { bc = true })
	T.eq(Joined(Route.Find(graph, "a", "c")), "a d e f c", "around the block")
end)

T.test("a start that is the goal is a route of one node", function()
	T.eq(Joined(Route.Find(Graph(RING.nodes, RING.edges), "e", "e")), "e", "no move")
end)

T.test("no route when the goal cannot be reached", function()
	local graph = Graph(RING.nodes, RING.edges, { bc = true, ef = true })
	T.eq(Route.Find(graph, "a", "c"), nil, "cut off")
end)

T.test("a search that expands more nodes than its limit gives up", function()
	local nodes, edges = {}, {}
	for i = 1, 50 do
		nodes["n" .. i] = { i, 0 }
		if i > 1 then edges[#edges + 1] = { "n" .. (i - 1), "n" .. i } end
	end
	T.eq(Route.Find(Graph(nodes, edges), "n1", "n50", 10), nil, "limited")
	T.eq(#Route.Find(Graph(nodes, edges), "n1", "n50", 100), 50, "unlimited enough")
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
	T.eq(Joined(Route.Find(graph, "s", "g")), "s x m g", "relaxed")
end)

T.finish()
