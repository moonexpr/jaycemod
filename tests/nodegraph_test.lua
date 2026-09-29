-- foundation.nodegraph: an AI node graph made from the nav mesh, written in
-- the engine's .ain format (CAI_NetworkManager::SaveNetworkGraph).
local T = dofile("tests/harness.lua")
local Graph = T.require("foundation.nodegraph")

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

T.finish()
