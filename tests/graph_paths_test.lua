-- graph.paths: its native twin is the module (the Lua twin a stub), so the
-- walks are tested in the native pass; the Lua pass checks the stub refuses.
local T = dofile("tests/harness.lua")
local Paths = graph.paths

local CELL = 100

if not T.NATIVE then
	T.test("the Lua twin is a stub that refuses, naming the native twin", function()
		local ok, err = pcall(Paths.New, 3)
		T.eq(ok, false)
		T.eq(tostring(err):find("native only", 1, true) ~= nil, true, "names the native twin")
	end)
	T.finish()
end

-- Nodes 1..n in a row, each joined both ways to the next, a cell apart.
local function Line(n)
	local g = Paths.New(n)
	for i = 1, n - 1 do
		g:Step(i, i + 1, CELL)
		g:Step(i + 1, i, CELL)
	end
	return g
end

local function Same(a, b, what)
	T.eq(table.concat(a or {}, ","), table.concat(b or {}, ","), what)
end

T.test("the walk is from the nearest start, a path read off it, nil where it never reaches", function()
	local g = Line(5)
	T.eq(g:Tree({ 1 }):Distance(5), 4 * CELL)
	T.eq(g:Tree({ 1, 4 }):Distance(5), CELL, "from the nearer start")
	Same(g:Tree({ 1 }):Path(4), { 1, 2, 3, 4 })
	local apart = Paths.New(3)
	apart:Step(1, 2, CELL)
	T.eq(apart:Tree({ 1 }):Path(3), nil)
	T.eq(apart:Tree({ 1 }):Distance(3), nil)
end)

T.test("a step goes one way", function()
	local g = Line(5)
	g:Step(1, 5, CELL)
	Same(g:Tree({ 1 }):Path(5), { 1, 5 }, "the drop")
	Same(g:Tree({ 5 }):Path(1), { 5, 4, 3, 2, 1 }, "no climbing it")
end)

T.test("distances and parents are the reached nodes'", function()
	local apart = Paths.New(3)
	apart:Step(1, 2, CELL)
	local tree = apart:Tree({ 1 })
	local d, p = tree:Distances(), tree:Parents()
	T.eq(d[1], 0)
	T.eq(d[2], CELL)
	T.eq(d[3], nil)
	T.eq(p[2], 1)
	T.eq(p[1], nil, "a start has none")
end)

T.test("a node out of the graph or a cost below nothing is the caller's mistake", function()
	local g = Paths.New(2)
	T.eq(pcall(g.Step, g, 1, 3, 1), false)
	T.eq(pcall(g.Step, g, 1, 2, -1), false)
	T.eq(pcall(g.Tree, g, { 0 }), false)
	T.eq(#g, 2)
end)

-- 1 the spawn, 2 a hall, from it two ways: 3-4 and 5.
local function Fork()
	local g = Paths.New(5)
	for _, pair in ipairs({ { 1, 2 }, { 2, 3 }, { 3, 4 }, { 2, 5 } }) do
		g:Step(pair[1], pair[2], CELL)
		g:Step(pair[2], pair[1], CELL)
	end
	return g
end

local FLOOR = { 1, 1, 1, 1, 1 }

T.test("a branch weighs the floor reached through it, and forks split into ways of a share", function()
	local tree = Fork():Tree({ 1 })
	local b = tree:Branches(FLOOR)
	Same(b.children[2], { 3, 5 })
	T.eq(b.weight[1], 5)
	T.eq(b.weight[3], 2)
	Same(b.roots, { 1 })
	Same(tree:Forks(FLOOR, 0.2), { 2 })
	Same(tree:Forks(FLOOR, 0.3), {})
end)

T.test("the fewest paths covering a share, the most first, ground within reach counting", function()
	local g = Fork()
	local tree = g:Tree({ 1 })
	local all = g:Cover(tree, FLOOR, 1)
	T.eq(#all, 2)
	Same(all[1].nodes, { 1, 2, 3, 4 })
	T.eq(all[1].gain, 4)
	T.eq(all[2].gain, 1, "only what it adds")
	local near = g:Cover(tree, FLOOR, 1, CELL)
	T.eq(#near, 1, "5 lies within reach of 2")
	T.eq(near[1].gain, 5)
end)

T.test("alternatives: a way a little longer is one, its own length; a far longer is none", function()
	-- 1 and 2 joined straight through 3, and through 4, a fifth longer
	local g = Paths.New(4)
	local half = 5 * CELL
	for _, s in ipairs({ { 1, 3, half }, { 3, 2, half }, { 1, 4, half * 1.2 }, { 4, 2, half * 1.2 } }) do
		g:Step(s[1], s[2], s[3])
		g:Step(s[2], s[1], s[3])
	end
	local routes = g:Alternatives({ 1 }, 2, 4, 0.5, 3)
	T.eq(#routes, 2)
	Same(routes[1].nodes, { 1, 3, 2 })
	Same(routes[2].nodes, { 1, 4, 2 })
	T.near(routes[2].length, 12 * CELL)
	T.eq(#g:Alternatives({ 1 }, 2, 4, 0.1, 3), 1, "a fifth longer than a tenth's detour allows")
end)

T.test("near is each node's ground within reach, itself included", function()
	local near = Line(5):Near(CELL)
	Same(near[3], { 2, 3, 4 })
end)

T.finish()
