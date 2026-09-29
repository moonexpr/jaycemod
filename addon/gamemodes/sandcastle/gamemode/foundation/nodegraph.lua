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
local floor, frexp, huge, ldexp = math.floor, math.frexp, math.huge, math.ldexp
local byte, char, concat, sort, sqrt = string.byte, string.char, table.concat, table.sort, math.sqrt
local ipairs, pairs = ipairs, pairs
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

-- A spatial hash of points by cell.
local function Cell(p, size) return floor(p.x / size) .. "," .. floor(p.y / size) end

local function Near(hash, p, size, visit)
	local cx, cy = floor(p.x / size), floor(p.y / size)
	for dx = -1, 1 do
		for dy = -1, 1 do
			for _, item in ipairs(hash[(cx + dx) .. "," .. (cy + dy)] or {}) do
				if visit(item) then return true end
			end
		end
	end
	return false
end

local function Put(hash, p, size, item)
	local key = Cell(p, size)
	local list = hash[key]
	if not list then
		list = {}
		hash[key] = list
	end
	list[#list + 1] = item
end

-- Nodes: the centres of the areas, largest areas first, none within
-- `spacing` of another, at most `limit`. areas: { pos, size }. Returns the
-- chosen areas in order.
function PickNodes(areas, spacing, limit)
	local order = {}
	for i, area in ipairs(areas) do order[i] = area end
	sort(order, function(a, b) return a.size > b.size end)
	local chosen, hash = {}, {}
	for _, area in ipairs(order) do
		if #chosen >= limit then break end
		local crowded = Near(hash, area.pos, spacing, function(other) return Distance(other.pos, area.pos) < spacing end)
		if not crowded then
			chosen[#chosen + 1] = area
			Put(hash, area.pos, spacing, area)
		end
	end
	return chosen
end

-- The links worth testing: each node's `perNode` nearest within
-- maxDistance, each pair once. positions: a list; returns { a, b, distance }
-- with a < b, nearest first.
function Candidates(positions, maxDistance, perNode)
	local hash = {}
	for i, p in ipairs(positions) do Put(hash, p, maxDistance, i) end
	local seen, pairsOut = {}, {}
	for i, p in ipairs(positions) do
		local near = {}
		Near(hash, p, maxDistance, function(j)
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
	local zones, zone = {}, FIRST_ZONE
	for i = 1, count do
		if #neighbors[i] == 0 then zones[i] = ZONE_SOLO end
	end
	for i = 1, count do
		if not zones[i] then
			local stack = { i }
			zones[i] = zone
			while #stack > 0 do
				local n = stack[#stack]
				stack[#stack] = nil
				for _, m in ipairs(neighbors[n]) do
					if not zones[m] then
						zones[m] = zone
						stack[#stack + 1] = m
					end
				end
			end
			zone = zone + 1
		end
	end
	return zones
end

-------------------------------------------------------------------------------
-- The file: little-endian, as CUtlBuffer writes on x86.

local function Int(n)
	n = n % 4294967296
	return char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local function Short(n)
	n = n % 65536
	return char(n % 256, floor(n / 256) % 256)
end

-- IEEE 754 single precision.
local function Float(x)
	if x == 0 then return char(0, 0, 0, 0) end
	local sign = 0
	if x < 0 then
		sign = 128
		x = -x
	end
	local mantissa, exponent = frexp(x) -- x = mantissa * 2^exponent, mantissa in [0.5, 1)
	exponent = exponent + 126
	if exponent <= 0 then
		-- subnormal
		mantissa = floor(ldexp(mantissa, 23 + exponent - 1) + 0.5)
		exponent = 0
	else
		mantissa = floor((mantissa * 2 - 1) * 8388608 + 0.5)
		if mantissa == 8388608 then
			mantissa = 0
			exponent = exponent + 1
		end
	end
	return char(mantissa % 256, floor(mantissa / 256) % 256,
		(exponent % 2) * 128 + floor(mantissa / 65536) % 128, sign + floor(exponent / 2))
end

-- graph = { mapVersion, nodes = { { pos, yaw, offsets[0..NUM_HULLS-1],
-- type, info, zone, hammerId } }, links = { { a, b (1-based), moves[0..] } } }
function Encode(graph)
	local out = { Int(VERSION), Int(graph.mapVersion), Int(#graph.nodes) }
	for _, node in ipairs(graph.nodes) do
		out[#out + 1] = Float(node.pos.x) .. Float(node.pos.y) .. Float(node.pos.z) .. Float(node.yaw or 0)
		for hull = 0, NUM_HULLS - 1 do out[#out + 1] = Float(node.offsets and node.offsets[hull] or 0) end
		out[#out + 1] = char(node.type or NODE_GROUND) .. Short(node.info or 0) .. Short(node.zone or ZONE_SOLO)
	end
	out[#out + 1] = Int(#graph.links)
	for _, link in ipairs(graph.links) do
		local moves = {}
		for hull = 0, NUM_HULLS - 1 do moves[#moves + 1] = char(link.moves and link.moves[hull] or 0) end
		out[#out + 1] = Short(link.a - 1) .. Short(link.b - 1) .. concat(moves)
	end
	for i, node in ipairs(graph.nodes) do out[#out + 1] = Int(node.hammerId or i) end
	return concat(out)
end

-- Reading, for the debug overlay and tests.
local function NewReader(data) return { data = data, at = 1 } end

local function ReadByte(r)
	local b = byte(r.data, r.at)
	r.at = r.at + 1
	return b
end

local function ReadInt(r)
	local a, b, c, d = byte(r.data, r.at, r.at + 3)
	r.at = r.at + 4
	local n = a + b * 256 + c * 65536 + d * 16777216
	if n >= 2147483648 then n = n - 4294967296 end
	return n
end

local function ReadShort(r, unsigned)
	local a, b = byte(r.data, r.at, r.at + 1)
	r.at = r.at + 2
	local n = a + b * 256
	if not unsigned and n >= 32768 then n = n - 65536 end
	return n
end

local function ReadFloat(r)
	local a, b, c, d = byte(r.data, r.at, r.at + 3)
	r.at = r.at + 4
	local sign = d >= 128 and -1 or 1
	local exponent = (d % 128) * 2 + floor(c / 128)
	local mantissa = (c % 128) * 65536 + b * 256 + a
	if exponent == 0 then
		if mantissa == 0 then return 0 end
		return sign * ldexp(mantissa, -149)
	end
	if exponent == 255 then return sign * huge end
	return sign * ldexp(mantissa + 8388608, exponent - 150)
end

-- Returns the graph, or nil and why. With headerOnly, only { version,
-- mapVersion, nodeCount }.
function Decode(data, headerOnly)
	if #data < 12 then return nil, "too short" end
	local r = NewReader(data)
	local graph = { version = ReadInt(r), mapVersion = ReadInt(r), nodes = {}, links = {} }
	graph.nodeCount = ReadInt(r)
	if headerOnly then return graph end
	if graph.version ~= VERSION then return nil, "version " .. graph.version end
	for i = 1, graph.nodeCount do
		local node = { pos = { x = ReadFloat(r), y = ReadFloat(r), z = ReadFloat(r) }, offsets = {} }
		node.yaw = ReadFloat(r)
		for hull = 0, NUM_HULLS - 1 do node.offsets[hull] = ReadFloat(r) end
		node.type = ReadByte(r)
		node.info = ReadShort(r, true)
		node.zone = ReadShort(r)
		graph.nodes[i] = node
	end
	local linkCount = ReadInt(r)
	for i = 1, linkCount do
		local link = { a = ReadShort(r) + 1, b = ReadShort(r) + 1, moves = {} }
		for hull = 0, NUM_HULLS - 1 do link.moves[hull] = ReadByte(r) end
		graph.links[i] = link
	end
	for i = 1, graph.nodeCount do graph.nodes[i].hammerId = ReadInt(r) end
	if r.at - 1 ~= #data then return nil, "trailing or missing bytes" end
	return graph
end
