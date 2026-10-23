-- An AI node graph for HL2's engine NPCs, made from the nav mesh. TF2 maps
-- ship without one, so the engine's cover, retreat, flanking, patrol and
-- hint searches find nothing. This model picks the nodes, proposes the
-- links, assigns the zones and reads and writes the graph file the engine
-- loads (maps/graphs/<map>.ain), after CAI_NetworkManager::SaveNetworkGraph
-- and LoadNetworkGraph (ai_networkmanager.cpp); the nodegraph feature feeds
-- it the mesh and checks each link with hull traces.
--
-- Positions are plain { x, y, z } tables. Node and link ids in the file are
-- 0-based; here nodes are a 1-based list.
local concat, sort, sqrt = table.concat, table.sort, math.sqrt
local ipairs, pairs = ipairs, pairs
local Buffer = require("foundation.file.buffer")
local Graph = require("foundation.graph.search")
local Grid = require("foundation.world.grid")
module(...)

VERSION = 37 -- AINET_VERSION_NUMBER
NUM_HULLS = 10
MAX_NODES = 1500 -- the 2013 SDK's MAX_NODES
MAX_NODE_LINKS = 30 -- AI_MAX_NODE_LINKS
MAX_LINK_DISTANCE = 720 -- MAX_NODE_LINK_DIST
NODE_GROUND = 2
ZONE_SOLO, FIRST_ZONE = 1, 4
CAP_MOVE_GROUND = 1
NODE_HEIGHT = 8 -- a ground node stands this far above the floor
NO_NODE = -1

-- Hull_t, with ai_hull.cpp's boxes. Centered hulls fly and take no ground
-- links.
HULLS = {
	[0] = { name = "human", mins = { -13, -13, 0 }, maxs = { 13, 13, 72 }, ground = true },
	[1] = { name = "small centered", mins = { -20, -20, -20 }, maxs = { 20, 20, 20 }, ground = false },
	[2] = { name = "wide human", mins = { -15, -15, 0 }, maxs = { 15, 15, 72 }, ground = true },
	[3] = { name = "tiny", mins = { -12, -12, 0 }, maxs = { 12, 12, 24 }, ground = true },
	[4] = { name = "wide short", mins = { -35, -35, 0 }, maxs = { 35, 35, 32 }, ground = true },
	[5] = { name = "medium", mins = { -16, -16, 0 }, maxs = { 16, 16, 64 }, ground = true },
	[6] = { name = "tiny centered", mins = { -8, -8, -4 }, maxs = { 8, 8, 4 }, ground = false },
	[7] = { name = "large", mins = { -40, -40, 0 }, maxs = { 40, 40, 100 }, ground = true },
	[8] = { name = "large centered", mins = { -38, -38, -38 }, maxs = { 38, 38, 38 }, ground = false },
	[9] = { name = "medium tall", mins = { -18, -18, 0 }, maxs = { 18, 18, 100 }, ground = true },
}

local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)
end

-- Nodes: the centres of the areas, largest areas first, none within
-- `spacing` of another, at most `limit`. areas: { pos, size }. Returns the
-- chosen areas in order.
function PickNodes(areas, spacing, limit)
	local order = {}
	for i, area in ipairs(areas) do order[i] = area end
	sort(order, function(a, b) return a.size > b.size end)
	local chosen, grid = {}, Grid.New(spacing)
	for _, area in ipairs(order) do
		if #chosen >= limit then break end
		local crowded = grid:Near(area.pos, function(other) return Distance(other.pos, area.pos) < spacing end)
		if not crowded then
			chosen[#chosen + 1] = area
			grid:Put(area.pos, area)
		end
	end
	return chosen
end

-- The middle of the edge two connected areas share: from and to are
-- rectangles { lo = { x, y }, hi = { x, y } } (a nav area's extent), `to`
-- lying in direction dir of `from` (NavDirType: 0 north (-y), 1 east (+x),
-- 2 south (+y), 3 west (-x)). Returns x, y.
function SeamPoint(from, to, dir)
	if dir == 0 or dir == 2 then
		local low = from.lo.x > to.lo.x and from.lo.x or to.lo.x
		local high = from.hi.x < to.hi.x and from.hi.x or to.hi.x
		return (low + high) / 2, dir == 0 and from.lo.y or from.hi.y
	end
	local low = from.lo.y > to.lo.y and from.lo.y or to.lo.y
	local high = from.hi.y < to.hi.y and from.hi.y or to.hi.y
	return dir == 3 and from.lo.x or from.hi.x, (low + high) / 2
end

-- The links worth testing: each node's `perNode` nearest within
-- maxDistance, each pair once. positions: a list; returns { a, b, distance }
-- with a < b, nearest first.
function Candidates(positions, maxDistance, perNode)
	local grid = Grid.New(maxDistance)
	for i, p in ipairs(positions) do grid:Put(p, i) end
	local seen, pairsOut = {}, {}
	for i, p in ipairs(positions) do
		local near = {}
		grid:Near(p, function(j)
			if j ~= i then
				local d = Distance(p, positions[j])
				if d <= maxDistance then near[#near + 1] = { j = j, d = d } end
			end
		end)
		sort(near, function(a, b) return a.d < b.d end)
		for k = 1, perNode < #near and perNode or #near do
			local j = near[k].j
			local a, b = i < j and i or j, i < j and j or i
			local key = a * 65536 + b
			if not seen[key] then
				seen[key] = true
				pairsOut[#pairsOut + 1] = { a = a, b = b, distance = near[k].d }
			end
		end
	end
	sort(pairsOut, function(x, y) return x.distance < y.distance end)
	return pairsOut
end

-- Links that would join zones: for each node, its `perNode` nearest nodes
-- of other zones within maxDistance, each pair once, nearest first. A
-- node's nearest few may all lie on its own side of a wall or doorway, so
-- Candidates alone can leave rooms unjoined.
function Bridges(positions, zones, maxDistance, perNode)
	local grid = Grid.New(maxDistance)
	for i, p in ipairs(positions) do grid:Put(p, i) end
	local seen, out = {}, {}
	for i, p in ipairs(positions) do
		local near = {}
		grid:Near(p, function(j)
			if zones[j] ~= zones[i] then
				local d = Distance(p, positions[j])
				if d <= maxDistance then near[#near + 1] = { j = j, d = d } end
			end
		end)
		sort(near, function(a, b) return a.d < b.d end)
		for k = 1, perNode < #near and perNode or #near do
			local j = near[k].j
			local a, b = i < j and i or j, i < j and j or i
			local key = a * 65536 + b
			if not seen[key] then
				seen[key] = true
				out[#out + 1] = { a = a, b = b, distance = near[k].d }
			end
		end
	end
	sort(out, function(x, y) return x.distance < y.distance end)
	return out
end

-- Keeps the shortest links, at most `limit` on any node. links: { a, b,
-- distance, ... } nearest first (Candidates' order).
function CapLinks(links, limit)
	local counts, kept = {}, {}
	for _, link in ipairs(links) do
		if (counts[link.a] or 0) < limit and (counts[link.b] or 0) < limit then
			counts[link.a] = (counts[link.a] or 0) + 1
			counts[link.b] = (counts[link.b] or 0) + 1
			kept[#kept + 1] = link
		end
	end
	return kept
end

-- CAI_NetworkBuilder::InitZones: a node with no links is SOLO; each set of
-- linked nodes gets its own zone from FIRST_ZONE. Returns zone per node.
function Zones(count, links)
	local neighbors = {}
	for i = 1, count do neighbors[i] = {} end
	for _, link in ipairs(links) do
		local a, b = neighbors[link.a], neighbors[link.b]
		a[#a + 1] = link.b
		b[#b + 1] = link.a
	end
	local linked = {}
	for i = 1, count do
		if #neighbors[i] > 0 then linked[#linked + 1] = i end
	end
	local component = Graph.Components(linked, function(i) return neighbors[i] end)
	local zones = {}
	for i = 1, count do zones[i] = component[i] and FIRST_ZONE + component[i] - 1 or ZONE_SOLO end
	return zones
end

-------------------------------------------------------------------------------
-- The file: little-endian, as CUtlBuffer writes on x86.

-- graph = { mapVersion, nodes = { { pos, yaw, offsets[0..NUM_HULLS-1],
-- type, info, zone, hammerId } }, links = { { a, b (1-based), moves[0..] } } }
function Encode(graph)
	local out = { Buffer.Int32(VERSION), Buffer.Int32(graph.mapVersion), Buffer.Int32(#graph.nodes) }
	for _, node in ipairs(graph.nodes) do
		out[#out + 1] = Buffer.Float32(node.pos.x) .. Buffer.Float32(node.pos.y) .. Buffer.Float32(node.pos.z) .. Buffer.Float32(node.yaw or 0)
		for hull = 0, NUM_HULLS - 1 do out[#out + 1] = Buffer.Float32(node.offsets and node.offsets[hull] or 0) end
		out[#out + 1] = Buffer.Byte(node.type or NODE_GROUND) .. Buffer.Int16(node.info or 0) .. Buffer.Int16(node.zone or ZONE_SOLO)
	end
	out[#out + 1] = Buffer.Int32(#graph.links)
	for _, link in ipairs(graph.links) do
		local moves = {}
		for hull = 0, NUM_HULLS - 1 do moves[#moves + 1] = Buffer.Byte(link.moves and link.moves[hull] or 0) end
		out[#out + 1] = Buffer.Int16(link.a - 1) .. Buffer.Int16(link.b - 1) .. concat(moves)
	end
	for i, node in ipairs(graph.nodes) do out[#out + 1] = Buffer.Int32(node.hammerId or i) end
	return concat(out)
end

-- Reading, for the debug overlay and tests.

-- Returns the graph, or nil and why. With headerOnly, only { version,
-- mapVersion, nodeCount }.
function Decode(data, headerOnly)
	if #data < 12 then return nil, "too short" end
	local r = Buffer.Reader(data)
	local graph = { version = r:Int32(), mapVersion = r:Int32(), nodes = {}, links = {} }
	graph.nodeCount = r:Int32()
	if headerOnly then return graph end
	if graph.version ~= VERSION then return nil, "version " .. graph.version end
	for i = 1, graph.nodeCount do
		local node = { pos = { x = r:Float32(), y = r:Float32(), z = r:Float32() }, offsets = {} }
		node.yaw = r:Float32()
		for hull = 0, NUM_HULLS - 1 do node.offsets[hull] = r:Float32() end
		node.type = r:Byte()
		node.info = r:UInt16()
		node.zone = r:Int16()
		graph.nodes[i] = node
	end
	local linkCount = r:Int32()
	for i = 1, linkCount do
		local link = { a = r:Int16() + 1, b = r:Int16() + 1, moves = {} }
		for hull = 0, NUM_HULLS - 1 do link.moves[hull] = r:Byte() end
		graph.links[i] = link
	end
	for i = 1, graph.nodeCount do graph.nodes[i].hammerId = r:Int32() end
	if r:Consumed() ~= #data then return nil, "trailing or missing bytes" end
	return graph
end
