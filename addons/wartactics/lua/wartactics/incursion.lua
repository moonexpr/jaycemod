-- The incursion (docs/incursion-native-plan.md): how each team walks into
-- the map from its spawns, over the room graph (the AI war controller's
-- RoomGraph, what wartactics.rooms.Partition is given), on graph.paths,
-- native. .devtools/bin/incursion.py is the reference, step for step.
--
-- A team's walk is TF2's incursion distance: each area's distance from the
-- nearest of its spawns, along the links as the mesh gives them (a drop is
-- walked down, never up), and through the breakable windows (WINDOW_COST to
-- break one and climb its sill; up into one only within CLIMB). Its routes to
-- each enemy spawn area are its highway, the shortest, and its other options
-- by the penalty method (graph.paths' Alternatives: up to ALTERNATIVES, each
-- at most DETOUR longer, PENALTY on the areas taken). The front gives each
-- area to the team whose walk reaches it first, no one's within a margin of
-- both. A team's walk is a tree, weighted by the floor reached through each
-- branch, its forks where ways part; its breaches are the fewest paths along
-- it covering a share of the map.
--
-- Graph(graph, windows) -> g: { paths (graph.paths), node (area id -> node),
--   area (node -> area id), crossings (area -> area -> { cost, via, width,
--   window }), floor (node -> floor) }; windows as RoomGraph gives them
--   ({ pos, from, to, breakable }).
-- Fields(g, spawns) -> team -> its walk (a graph.paths tree); spawns: team ->
--   its spawn area ids.
-- Routes(g, spawns[, fields]) -> { { team, areas, length, alternative } }.
-- Front(g, fields, margin) -> area -> the team first there, or false.
-- Traffic(routes) -> area -> team -> how many routes pass through.
-- Tree(g, walk) -> { parent, children, weight, distance, roots }, by area.
-- Forks(g, walk, share) -> the areas where it splits into ways of share.
-- Breaches(g, walk, share[, reach]) -> { { areas, gain } }, the fewest.
local ipairs, pairs, sort, huge, sqrt = ipairs, pairs, table.sort, math.huge, math.sqrt
local Paths = graph.paths
module(...)

ALTERNATIVES, DETOUR, PENALTY = 4, 0.5, 3
-- Breaking a window and climbing its sill costs as much as walking
-- WINDOW_COST; no one climbs up into one more than CLIMB (a crouch-jump)
-- above them; a window's opening, which the room graph does not measure, is
-- a door's width.
WINDOW_COST, CLIMB, WINDOW_WIDTH = 128, 64, 96

local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

function Graph(graph, windows)
	local ids = {}
	for id in pairs(graph) do ids[#ids + 1] = id end
	sort(ids)
	local g = { node = {}, area = {}, crossings = {}, floor = {}, paths = Paths.New(#ids) }
	for n, id in ipairs(ids) do
		g.node[id], g.area[n], g.floor[n], g.crossings[id] = n, id, graph[id].floor or 0, {}
	end
	local function Cross(a, b, cost, via, width, window)
		g.paths:Step(g.node[a], g.node[b], cost)
		g.crossings[a][b] = { cost = cost, via = via, width = width, window = window }
	end
	for _, id in ipairs(ids) do
		local area = graph[id]
		for _, link in ipairs(area.links) do
			local to = graph[link.to]
			if to then
				Cross(id, link.to, Distance(area.center, link.middle) + Distance(link.middle, to.center), link.middle,
					link.width, false)
			end
		end
	end
	for _, window in ipairs(windows) do
		if window.breakable then
			for _, pair in ipairs({ { window.from, window.to }, { window.to, window.from } }) do
				local a, b = graph[pair[1]], graph[pair[2]]
				if a and b and b.center.z - a.center.z <= CLIMB then
					Cross(pair[1], pair[2], Distance(a.center, window.pos) + Distance(window.pos, b.center) + WINDOW_COST,
						window.pos, WINDOW_WIDTH, true)
				end
			end
		end
	end
	return g
end

local function Nodes(g, areas)
	local nodes = {}
	for _, a in ipairs(areas) do
		if g.node[a] then nodes[#nodes + 1] = g.node[a] end
	end
	return nodes
end

local function Areas(g, nodes)
	local areas = {}
	for i, n in ipairs(nodes) do areas[i] = g.area[n] end
	return areas
end

local function Teams(spawns)
	local teams = {}
	for team in pairs(spawns) do teams[#teams + 1] = team end
	sort(teams)
	return teams
end

function Fields(g, spawns)
	local fields = {}
	for _, team in ipairs(Teams(spawns)) do fields[team] = g.paths:Tree(Nodes(g, spawns[team])) end
	return fields
end

function Routes(g, spawns, fields)
	fields = fields or Fields(g, spawns)
	local routes = {}
	for _, team in ipairs(Teams(spawns)) do
		local starts = Nodes(g, spawns[team])
		for _, enemy in ipairs(Teams(spawns)) do
			if enemy ~= team then
				local targets, seen = {}, {}
				for _, a in ipairs(spawns[enemy]) do
					if g.node[a] and not seen[a] then seen[a], targets[#targets + 1] = true, a end
				end
				sort(targets)
				for _, target in ipairs(targets) do
					if fields[team]:Distance(g.node[target]) then
						for i, way in ipairs(g.paths:Alternatives(starts, g.node[target], ALTERNATIVES, DETOUR, PENALTY)) do
							routes[#routes + 1] = { team = team, areas = Areas(g, way.nodes), length = way.length,
								alternative = i > 1 }
						end
					end
				end
			end
		end
	end
	return routes
end

function Front(g, fields, margin)
	local teams = {}
	for team in pairs(fields) do teams[#teams + 1] = team end
	sort(teams)
	local side = {}
	for n, area in ipairs(g.area) do
		local reach = {}
		for _, team in ipairs(teams) do reach[#reach + 1] = { fields[team]:Distance(n) or huge, team } end
		sort(reach, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
		if reach[1][1] < huge then
			if #reach > 1 and reach[2][1] - reach[1][1] <= margin then
				side[area] = false
			else
				side[area] = reach[1][2]
			end
		end
	end
	return side
end

function Traffic(routes)
	local traffic = {}
	for _, route in ipairs(routes) do
		for _, area in ipairs(route.areas) do
			local counts = traffic[area] or {}
			traffic[area] = counts
			counts[route.team] = (counts[route.team] or 0) + 1
		end
	end
	return traffic
end

function Tree(g, walk)
	local b = walk:Branches(g.floor)
	local parents, distances = walk:Parents(), walk:Distances()
	local tree = { parent = {}, children = {}, weight = {}, distance = {}, roots = Areas(g, b.roots) }
	for n, d in pairs(distances) do
		local area = g.area[n]
		tree.distance[area], tree.weight[area] = d, b.weight[n]
		tree.children[area] = Areas(g, b.children[n] or {})
		if parents[n] then tree.parent[area] = g.area[parents[n]] end
	end
	return tree
end

function Forks(g, walk, share)
	return Areas(g, walk:Forks(g.floor, share))
end

function Breaches(g, walk, share, reach)
	local found = {}
	for i, breach in ipairs(g.paths:Cover(walk, g.floor, share, reach)) do
		found[i] = { areas = Areas(g, breach.nodes), gain = breach.gain }
	end
	return found
end
