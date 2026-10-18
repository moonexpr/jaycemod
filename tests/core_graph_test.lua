-- foundation.core.graph: breadth-first floods and connected components over
-- a graph the caller describes.
local T = dofile("tests/harness.lua")
local Graph = T.require("foundation.core.graph")

-- 1 - 2 - 3 - 4 - 5, and 6 - 7 apart.
local EDGES = {
	[1] = { 2 },
	[2] = { 1, 3 },
	[3] = { 2, 4 },
	[4] = { 3, 5 },
	[5] = { 4 },
	[6] = { 7 },
	[7] = { 6 },
}
local function Neighbors(id) return EDGES[id] end
local function Any() return true end

local function Joined(list) return table.concat(list, " ") end

T.test("a flood reaches every admitted node, nearest first", function()
	local reached, cut = Graph.Flood({ 3 }, Neighbors, Any, 100)
	T.eq(Joined(reached), "3 2 4 1 5", "breadth first")
	T.eq(cut, false, "it ran out of nodes")
end)

T.test("a node not admitted is neither reached nor passed through", function()
	local reached = Graph.Flood({ 1 }, Neighbors, function(id) return id ~= 3 end, 100)
	T.eq(Joined(reached), "1 2", "held back at 3")
end)

T.test("the starts are taken as given, each once, in order", function()
	local reached = Graph.Flood({ 6, 1, 6 }, Neighbors, function(id) return id ~= 6 end, 100)
	T.eq(Joined(reached), "6 1 7 2 3 4 5", "6 starts though not admitted")
end)

T.test("a flood is cut when it would reach more than its limit", function()
	local reached, cut = Graph.Flood({ 1 }, Neighbors, Any, 3)
	T.eq(Joined(reached), "1 2 3", "the limit")
	T.eq(cut, true, "cut")
	local _, exact = Graph.Flood({ 6 }, Neighbors, Any, 2)
	T.eq(exact, false, "exactly the limit and no more: not cut")
end)

T.test("a flood is cut at the first node it reaches where stop answers true", function()
	local reached, cut = Graph.Flood({ 1 }, Neighbors, Any, 100, function(id) return id == 3 end)
	T.eq(cut, true, "cut")
	T.eq(Joined(reached), "1 2 3", "stopped on taking 3 up")
end)

-- Weighted edges: a -> b costs 1, b -> c 1, a -> c 5 (dearer than going
-- round), c -> d 10, and e on its own.
local EDGES = {
	a = { { node = "b", cost = 1 }, { node = "c", cost = 5 } },
	b = { { node = "c", cost = 1 } },
	c = { { node = "d", cost = 10 } },
	d = {},
	e = {},
}
local function Weighted(node) return EDGES[node] end

T.test("distances are the cheapest walk from the nearest start, round a dear shortcut", function()
	local dist = Graph.Distances({ "a" }, Weighted, 100)
	T.eq(dist.a, 0, "a start")
	T.eq(dist.b, 1)
	T.eq(dist.c, 2, "round by b, not the shortcut")
	T.eq(dist.d, 12)
	T.eq(dist.e, nil, "unreached")
end)

T.test("from several starts each node's distance is from the nearest", function()
	local dist = Graph.Distances({ "a", "c" }, Weighted, 100)
	T.eq(dist.c, 0, "a start itself")
	T.eq(dist.d, 10, "from c")
	T.eq(dist.b, 1, "from a")
end)

T.test("nodes farther than the limit are left out", function()
	local dist = Graph.Distances({ "a" }, Weighted, 5)
	T.eq(dist.c, 2)
	T.eq(dist.d, nil, "12 is past 5")
end)

T.test("components number the nodes' connected groups in the nodes' order", function()
	local component = Graph.Components({ 6, 1, 2, 3, 4, 5, 7 }, Neighbors)
	T.eq(component[6], 1, "the first group")
	T.eq(component[7], 1, "6's")
	for id = 1, 5 do T.eq(component[id], 2, "the line, " .. id) end
	T.eq(Graph.Components({ 5 }, function() return {} end)[5], 1, "a node alone is a group")
end)

T.finish()
