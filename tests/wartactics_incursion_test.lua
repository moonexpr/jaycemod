-- wartactics.incursion stands on graph.paths, native only: its walks are
-- tested in the native pass (.devtools/bin/test_incursion.py the reference).
local T = dofile("tests/harness.lua")
local Incursion = wartactics.incursion

local RED, BLU = "RED", "BLU"
local CELL = 100

if not T.NATIVE then
	T.test("it stands on graph.paths, whose Lua twin is a stub", function()
		T.eq(pcall(Incursion.Graph, {}, {}), false)
	end)
	T.finish()
end

local function Area(x, y, z, links)
	return { center = { x = x * CELL, y = (y or 0) * CELL, z = z or 0 }, floor = CELL * CELL, links = links or {} }
end

-- Each link's middle halfway between the two centres and a cell wide, as the
-- room graph gives them.
local function Middles(graph)
	for _, area in pairs(graph) do
		for _, link in ipairs(area.links) do
			local a, b = area.center, graph[link.to].center
			link.middle = { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, z = (a.z + b.z) / 2 }
			link.width = CELL
		end
	end
	return graph
end

-- Areas 1..n in a row, each linked both ways to the next.
local function Line(n)
	local graph = {}
	for i = 1, n do
		local links = {}
		if i > 1 then links[#links + 1] = { to = i - 1 } end
		if i < n then links[#links + 1] = { to = i + 1 } end
		graph[i] = Area(i, 0, 0, links)
	end
	return Middles(graph)
end

local function Window(a, b, graph, breakable)
	local ca, cb = graph[a].center, graph[b].center
	return { from = a, to = b, pos = { x = (ca.x + cb.x) / 2, y = (ca.y + cb.y) / 2, z = (ca.z + cb.z) / 2 },
		breakable = breakable ~= false }
end

local function Same(a, b, what) T.eq(table.concat(a or {}, ","), table.concat(b or {}, ","), what) end

T.test("a team's walk is from its spawns, a route its shortest walk to each enemy spawn area", function()
	local g = Incursion.Graph(Line(5), {})
	local fields = Incursion.Fields(g, { [RED] = { 1 }, [BLU] = { 5 } })
	T.eq(fields[RED]:Distance(g.node[5]), 4 * CELL)
	local routes = Incursion.Routes(g, { [RED] = { 1 }, [BLU] = { 5 } })
	local highway = {}
	for _, r in ipairs(routes) do if not r.alternative then highway[r.team] = r end end
	Same(highway[RED].areas, { 1, 2, 3, 4, 5 })
	Same(highway[BLU].areas, { 5, 4, 3, 2, 1 })
	T.near(highway[RED].length, 4 * CELL)
end)

T.test("a drop is walked down, never up", function()
	local graph = Line(5)
	graph[1].links[#graph[1].links + 1] = { to = 5 }
	local g = Incursion.Graph(Middles(graph), {})
	local routes = Incursion.Routes(g, { [RED] = { 1 }, [BLU] = { 5 } })
	for _, r in ipairs(routes) do
		if not r.alternative and r.team == RED then Same(r.areas, { 1, 5 }, "RED drops") end
		if not r.alternative and r.team == BLU then Same(r.areas, { 5, 4, 3, 2, 1 }, "BLU walks round") end
	end
end)

T.test("a breakable window is a way through both ways at the break's cost, up only within a climb", function()
	local graph = Line(5)
	graph[9] = Area(2, 1)
	graph = Middles(graph)
	local g = Incursion.Graph(graph, { Window(2, 9, graph) })
	local through = g.crossings[2][9]
	T.eq(through.window, true)
	T.near(through.cost, CELL + Incursion.WINDOW_COST)
	T.eq(through.width, Incursion.WINDOW_WIDTH)
	T.eq(g.crossings[9][2] ~= nil, true, "and back")
	local high = Line(5)
	high[9] = Area(2, 1, 3 * Incursion.CLIMB)
	high = Middles(high)
	local up = Incursion.Graph(high, { Window(2, 9, high) })
	T.eq(up.crossings[2][9], nil, "no climbing up to it")
	T.eq(up.crossings[9][2] ~= nil, true, "jumping out of it down")
	local shut = Incursion.Graph(graph, { Window(2, 9, graph, false) })
	T.eq(shut.crossings[2][9], nil, "an areaportal window is only seen through")
end)

T.test("the front gives each area to the team that reaches it first, the middle to no one", function()
	local g = Incursion.Graph(Line(5), {})
	local fields = Incursion.Fields(g, { [RED] = { 1 }, [BLU] = { 5 } })
	local side = Incursion.Front(g, fields, CELL / 2)
	T.eq(side[1], RED)
	T.eq(side[2], RED)
	T.eq(side[3], false, "no one's")
	T.eq(side[5], BLU)
end)

T.test("a second way a little longer is an option beside the highway", function()
	-- RED's spawn 1 and BLU's 2, ten cells apart, straight through 3 and round through 10, a fifth longer
	local side = math.sqrt((5 * 1.2) ^ 2 - 25)
	local graph = { [1] = Area(0, 0, 0, { { to = 3 }, { to = 10 } }), [2] = Area(10, 0, 0, { { to = 3 }, { to = 10 } }),
		[3] = Area(5, 0, 0, { { to = 1 }, { to = 2 } }), [10] = Area(5, side, 0, { { to = 1 }, { to = 2 } }) }
	local g = Incursion.Graph(Middles(graph), {})
	local mine = {}
	for _, r in ipairs(Incursion.Routes(g, { [RED] = { 1 }, [BLU] = { 2 } })) do
		if r.team == RED then mine[#mine + 1] = r end
	end
	T.eq(#mine, 2)
	Same(mine[1].areas, { 1, 3, 2 })
	T.eq(mine[1].alternative, false)
	Same(mine[2].areas, { 1, 10, 2 })
	T.eq(mine[2].alternative, true)
end)

T.test("a team's tree weighs its branches by floor; its breaches cover the share with the fewest paths", function()
	-- 1 the spawn, 2 a hall, from it two ways: 3-4 and 5
	local graph = { [1] = Area(0, 0, 0, { { to = 2 } }), [2] = Area(1, 0, 0, { { to = 1 }, { to = 3 }, { to = 5 } }),
		[3] = Area(2, 1, 0, { { to = 2 }, { to = 4 } }), [4] = Area(3, 1, 0, { { to = 3 } }),
		[5] = Area(2, -1, 0, { { to = 2 } }) }
	local g = Incursion.Graph(Middles(graph), {})
	local fields = Incursion.Fields(g, { [RED] = { 1 } })
	local tree = Incursion.Tree(g, fields[RED])
	T.eq(tree.weight[2], 4 * CELL * CELL)
	Same(tree.children[2], { 3, 5 })
	Same(Incursion.Forks(g, fields[RED], 0.2), { 2 })
	local breaches = Incursion.Breaches(g, fields[RED], 1)
	T.eq(#breaches, 2)
	Same(breaches[1].areas, { 1, 2, 3, 4 })
end)

T.finish()
