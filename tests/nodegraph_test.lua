-- foundation.nodegraph: an AI node graph made from the nav mesh, written in
-- the engine's .ain format (CAI_NetworkManager::SaveNetworkGraph).
local T = dofile("tests/harness.lua")
local Graph = nodegraph

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

T.test("nodes are the largest areas' centres, spaced apart, up to the limit", function()
	local areas = {
		{ pos = P(0, 0), size = 100 },
		{ pos = P(50, 0), size = 400 }, -- the largest, crowds the first
		{ pos = P(500, 0), size = 50 },
		{ pos = P(1000, 0), size = 10 },
	}
	local nodes = Graph.PickNodes(areas, 128, 10)
	T.eq(#nodes, 3, "the crowded one left out")
	T.eq(nodes[1].pos.x, 50, "largest first")
	T.eq(#Graph.PickNodes(areas, 128, 2), 2, "no more than the limit")
end)

T.test("a seam's node goes in the middle of the edge two areas share", function()
	local function Rect(x1, y1, x2, y2) return { lo = { x = x1, y = y1 }, hi = { x = x2, y = y2 } } end
	local stairs = Rect(0, 0, 100, 400)
	local x, y = Graph.SeamPoint(stairs, Rect(-50, -200, 60, 0), 0)
	T.eq(x .. "," .. y, "30,0", "north: the middle of the overlap, on the stairs' top edge")
	x, y = Graph.SeamPoint(stairs, Rect(0, 400, 100, 600), 2)
	T.eq(x .. "," .. y, "50,400", "south")
	x, y = Graph.SeamPoint(stairs, Rect(100, 100, 300, 200), 1)
	T.eq(x .. "," .. y, "100,150", "east")
	x, y = Graph.SeamPoint(stairs, Rect(-200, 300, 0, 500), 3)
	T.eq(x .. "," .. y, "0,350", "west")
end)

T.test("candidate links are each node's nearest within range, each pair once, nearest first", function()
	local positions = { P(0, 0), P(100, 0), P(250, 0), P(2000, 0) }
	local links = Graph.Candidates(positions, 300, 2)
	for _, link in ipairs(links) do T.eq(link.a < link.b, true, "ordered pair") end
	T.eq(links[1].a .. "-" .. links[1].b, "1-2", "nearest first")
	local far = false
	for _, link in ipairs(links) do far = far or link.b == 4 end
	T.eq(far, false, "nothing reaches the far node")
end)

T.test("bridges are tried only between nodes of different zones", function()
	local positions = { P(0, 0), P(50, 0), P(120, 0), P(5000, 0) }
	local zones = { 4, 4, 5, 1 }
	local bridges = Graph.Bridges(positions, zones, 720, 2)
	T.eq(#bridges, 2, "the two nodes of zone 4 to zone 5's node")
	T.eq(bridges[1].a .. "-" .. bridges[1].b, "2-3", "nearest first")
	for _, link in ipairs(bridges) do T.eq(zones[link.a] ~= zones[link.b], true, "across zones") end
end)

T.test("no node keeps more than the link limit", function()
	local links = {}
	for i = 2, 40 do links[#links + 1] = { a = 1, b = i, distance = i } end
	T.eq(#Graph.CapLinks(links, Graph.MAX_NODE_LINKS), Graph.MAX_NODE_LINKS, "capped")
end)

T.test("linked nodes share a zone, from FIRST_ZONE; lone nodes are SOLO", function()
	local zones = Graph.Zones(5, { { a = 1, b = 2 }, { a = 2, b = 3 }, { a = 4, b = 5 } })
	T.eq(zones[1] .. zones[2] .. zones[3], "444", "one zone")
	T.eq(zones[4] .. zones[5], "55", "another")
	T.eq(Graph.Zones(1, {})[1], Graph.ZONE_SOLO, "alone")
end)

T.test("a graph written and read back is the same graph, byte for byte in layout", function()
	local graph = {
		mapVersion = 4521,
		nodes = {
			{ pos = P(1.5, -2.25, 100), yaw = 90, offsets = { [0] = -7.9, [3] = -8.1 }, zone = 4 },
			{ pos = P(-300, 42, 0.125), zone = 4 },
		},
		links = { { a = 1, b = 2, moves = { [0] = Graph.CAP_MOVE_GROUND, [2] = Graph.CAP_MOVE_GROUND } } },
	}
	local data = Graph.Encode(graph)
	-- header 12, nodes 2 * (16 + 40 + 1 + 2 + 2), link count 4, link 4 + 10, lookup 2 * 4
	T.eq(#data, 12 + 2 * 61 + 4 + 14 + 8, "the engine's layout")
	local back = assert(Graph.Decode(data))
	T.eq(back.version, Graph.VERSION, "version")
	T.eq(back.mapVersion, 4521, "map version")
	T.eq(#back.nodes, 2, "nodes")
	T.near(back.nodes[1].pos.y, -2.25, 1e-6, "floats")
	T.near(back.nodes[1].offsets[0], -7.9, 1e-5, "offsets")
	T.eq(back.nodes[1].type, Graph.NODE_GROUND, "ground nodes")
	T.eq(back.nodes[2].zone, 4, "zone")
	T.eq(back.links[1].b, 2, "link")
	T.eq(back.links[1].moves[2], Graph.CAP_MOVE_GROUND, "per hull moves")
	T.eq(back.links[1].moves[1], 0, "no flying")
	T.eq(back.nodes[2].hammerId, 2, "lookup table")
end)

T.test("the header alone can be read, to tell whether an installed graph fits the map", function()
	local data = Graph.Encode({ mapVersion = 7, nodes = { { pos = P(0, 0) } }, links = {} })
	local header = Graph.Decode(data, true)
	T.eq(header.mapVersion .. " " .. header.nodeCount, "7 1", "version and size")
	T.eq(Graph.Decode("short"), nil, "too short")
end)

-- The pair searches, through both twins: the Lua module's and
-- native/foundation's, which a server patches over them. Ties are part of
-- the contract: nearer first, then the lower index; links nearest first,
-- then by a, then by b; areas largest first, then in the order given.
local TWINS = {
	{ "lua", Graph },
	{ "native", T.native("foundation").pending.nodegraph },
}

local function Links(links)
	local out = {}
	for i, link in ipairs(links) do out[i] = link.a .. "-" .. link.b .. "@" .. string.format("%.6f", link.distance) end
	return table.concat(out, " ")
end

local function Scatter(n, seed, span, height)
	local points, x = {}, seed
	for i = 1, n do
		local c = {}
		for k = 1, 3 do
			x = (x * 1103515245 + 12345) % 2147483648
			c[k] = x % (k == 3 and height or span) - (k == 3 and 0 or span / 2)
		end
		points[i] = P(c[1], c[2], c[3])
	end
	return points
end

local SQUARE = { P(0, 0), P(100, 0), P(0, 100), P(100, 100) }

local PAIR_CASES = {
	{ "equal distances break by the lower index", function(G)
		return { Links(G.Candidates(SQUARE, 150, 2)), Links(G.Candidates(SQUARE, 150, 1)) }
	end },
	{ "a node exactly at the range is in it; none past it", function(G)
		return { Links(G.Candidates({ P(0, 0), P(300, 0), P(600.5, 0) }, 300, 4)) }
	end },
	{ "negative coordinates bucket like positive ones", function(G)
		return { Links(G.Candidates({ P(-10, -10), P(10, 10), P(-130, 5), P(-1000, -1000) }, 128, 4)) }
	end },
	{ "nothing in, nothing out; none per node, none at all", function(G)
		return { #G.Candidates({}, 100, 4), #G.Candidates(SQUARE, 150, 0), #G.Bridges({}, {}, 100, 4), #G.PickNodes({}, 100, 5) }
	end },
	{ "bridges join only across zones, ties as candidates", function(G)
		return { Links(G.Bridges(SQUARE, { 4, 4, 5, 5 }, 720, 1)), Links(G.Bridges(SQUARE, { 4, 4, 4, 4 }, 720, 4)) }
	end },
	{ "areas of equal size are picked in the order given", function(G)
		local areas = { { pos = P(0, 0), size = 5 }, { pos = P(50, 0), size = 5 }, { pos = P(500, 0), size = 9 }, { pos = P(520, 0), size = 9 } }
		local chosen = G.PickNodes(areas, 100, math.huge)
		local out = {}
		for i, area in ipairs(chosen) do
			for j, given in ipairs(areas) do
				if area == given then out[i] = j end
			end
		end
		return { table.concat(out, " "), #G.PickNodes(areas, 100, 1) }
	end },
	{ "a map's worth of candidates and bridges", function(G)
		local positions = Scatter(1200, 11, 6000, 400)
		local zones = {}
		for i, p in ipairs(positions) do zones[i] = 4 + math.floor((p.x + 3000) / 900) end
		return { Links(G.Candidates(positions, 512, 16)), Links(G.Bridges(positions, zones, 720, 4)) }
	end },
	{ "a map's worth of areas", function(G)
		local areas = {}
		for i, p in ipairs(Scatter(4000, 5, 8000, 400)) do areas[i] = { pos = p, size = i % 37 } end
		local out = {}
		for i, area in ipairs(G.PickNodes(areas, 96, 1500)) do out[i] = area.size .. ":" .. area.pos.x end
		return { #out, table.concat(out, " ") }
	end },
	{ "a position without its z is refused", function(G)
		return { (pcall(G.Candidates, { P(0, 0), { x = 1, y = 2 } }, 100, 4)) }
	end },
}

local seenPairs = {}
for _, case in ipairs(PAIR_CASES) do
	for _, twin in ipairs(TWINS) do
		local name, G = twin[1], twin[2]
		T.test(name .. ": " .. case[1], function()
			local ok, result = pcall(case[2], G)
			T.eq(ok, true, "ran: " .. tostring(result))
			local parts = {}
			for i, v in ipairs(ok and result or {}) do parts[i] = tostring(v) end
			seenPairs[case[1]] = seenPairs[case[1]] or {}
			seenPairs[case[1]][name] = table.concat(parts, " | ")
		end)
	end
end

T.test("the two twins agree on every pair search", function()
	for _, case in ipairs(PAIR_CASES) do T.eq(seenPairs[case[1]].native, seenPairs[case[1]].lua, case[1]) end
end)

T.test("the Lua twin's ties are the contract's", function()
	T.eq(seenPairs["equal distances break by the lower index"].lua,
		"1-2@100.000000 1-3@100.000000 2-4@100.000000 3-4@100.000000 | 1-2@100.000000 1-3@100.000000 2-4@100.000000", "ties")
	T.eq(seenPairs["a node exactly at the range is in it; none past it"].lua, "1-2@300.000000", "range")
	T.eq(seenPairs["bridges join only across zones, ties as candidates"].lua, "1-3@100.000000 2-4@100.000000 | ", "bridges")
	T.eq(seenPairs["areas of equal size are picked in the order given"].lua, "3 1 | 1", "areas")
	T.eq(seenPairs["nothing in, nothing out; none per node, none at all"].lua, "0 | 0 | 0 | 0", "empty")
	T.eq(seenPairs["a position without its z is refused"].lua, "false", "no z")
end)

T.finish()
