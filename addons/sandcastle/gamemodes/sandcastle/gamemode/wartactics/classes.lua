-- Room classes from the incursion (docs/incursion-native-plan.md,
-- docs/places-plan.md §2.3): what each room is for when a round starts, in
-- stages, each on what the ones before it found. .devtools/bin/classes.py
-- and places.py are the reference.
--
-- 1. RESTRICTED rooms: a team's spawn rooms and the rooms the enemy reaches
--    only through them, where every door out of them is sealed by a respawn
--    room visualizer (within SEAL_REACH of its box). HIGHWAYS: a room holding
--    an objective, or one at least HIGHWAY_SHARE of each team's highways
--    cross; never a room holding a team's spawns, objective or not.
-- 2. Each team's spanning tree over the spaces (rooms and corridors): each
--    hangs from the space its team's walk enters it from. Lanes are planned
--    on it.
-- 3. Places: buildings (indoor spaces joined without going out of doors) and
--    grounds (outdoor ones), owned by the team whose spawns are in them; one
--    holding both teams' spawns split where their walks meet, NEUTRAL_SHARE
--    of the walk between the spawns no one's.
-- 4. A team's building is its STRONGHOLD. Any other room is on the side of
--    the team whose walk reaches it first (none within margin: COMMONS),
--    with a gradient d_highway / (d_highway + d_building), 1 at the team's
--    buildings and 0 on the highways (a highway in a building counting as
--    highway): half or more its STRONGHOLD, less COMMONS; farther than far
--    from both, UNOCCUPIED indoors and WILDS outdoors.
-- 5. Junctions: where a team's tree forks, in any room or corridor, the
--    floor of its space within reach of the fork, if there is enough of it.
--
-- Spaces are the partition's own room and passage tables (wartactics.rooms);
-- region(area) is the space an area is in.
local ipairs, pairs, next, sort, huge, sqrt, min = ipairs, pairs, next, table.sort, math.huge, math.sqrt, math.min
local Distances = graph.search.Distances
local RoomOf, PassageOf = wartactics.rooms.RoomOf, wartactics.rooms.PassageOf
module(...)

RESTRICTED, STRONGHOLD, OUTPOST, HIGHWAY = "restricted", "stronghold", "outpost", "highway"
COMMONS, UNOCCUPIED, WILDS = "commons", "unoccupied", "wilds"
BUILDING, GROUNDS = "building", "grounds"
-- A highway: half or more of each team's highways cross it. A door is
-- sealed by a visualizer whose box, grown by SEAL_REACH, holds it: a door is
-- where two nav areas meet, up to about an area's depth from the brush. The
-- middle of a place holding both teams' spawns: a fifth of the walk between
-- them.
HIGHWAY_SHARE, SEAL_REACH, NEUTRAL_SHARE = 0.5, 128, 0.2

local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

local function Sorted(set, before)
	local list = {}
	for value in pairs(set) do list[#list + 1] = value end
	sort(list, before)
	return list
end

-- Spaces in a fixed order: rooms by id, then passages by id.
local function Before(a, b)
	if (a.kind == "corridor") ~= (b.kind == "corridor") then return b.kind == "corridor" end
	return a.id < b.id
end

-- The space an area is in.
function Region(partition, area)
	return RoomOf(partition, area) or PassageOf(partition, area)
end

local function IsRoom(space) return space.kind ~= "corridor" end

local function Pop(list)
	local last = list[#list]
	list[#list] = nil
	return last
end

-- The spaces' graph from their doors: space -> { { node, cost, pos } }, each
-- door to the passage it goes through, or to the room it leads to.
function SpaceGraph(partition)
	local rooms, passages = {}, {}
	for _, room in ipairs(partition.rooms) do rooms[room.id] = room end
	for _, passage in ipairs(partition.passages) do passages[passage.id] = passage end
	local edges = {}
	local function Add(space)
		local list = {}
		for _, door in ipairs(space.doors) do
			local to = door.passage and passages[door.passage] or rooms[door.leads[1]]
			if to and to ~= space then
				list[#list + 1] = { node = to, cost = Distance(space.center, door.pos) + Distance(door.pos, to.center),
					pos = door.pos }
			end
		end
		edges[space] = list
	end
	for _, room in ipairs(partition.rooms) do Add(room) end
	for _, passage in ipairs(partition.passages) do Add(passage) end
	return edges
end

local function Walk(edges, starts, admit)
	return Distances(starts, function(node)
		if not admit then return edges[node] end
		local list = {}
		for _, e in ipairs(edges[node]) do
			if admit(e.node) then list[#list + 1] = e end
		end
		return list
	end, huge)
end

local function Sealed(pos, seals)
	for _, box in ipairs(seals) do
		local lo, hi = box.lo, box.hi
		if pos.x >= lo.x - SEAL_REACH and pos.x <= hi.x + SEAL_REACH and pos.y >= lo.y - SEAL_REACH
			and pos.y <= hi.y + SEAL_REACH and pos.z >= lo.z - SEAL_REACH and pos.z <= hi.z + SEAL_REACH then
			return true
		end
	end
	return false
end

-- homes: team -> the spaces its spawns take; seals: the visualizers' boxes,
-- { lo, hi }. -> room -> team.
function Restricted(edges, homes, seals)
	local teams = Sorted(homes)
	local restricted = {}
	for _, team in ipairs(teams) do
		local reach = Walk(edges, homes[team])
		local own, ground = {}, {}
		for _, space in ipairs(homes[team]) do own[space] = true end
		for _, enemy in ipairs(teams) do
			if enemy ~= team then
				local open = Walk(edges, homes[enemy], function(space) return not own[space] end)
				for space in pairs(edges) do
					if reach[space] and (own[space] or not open[space]) then ground[space] = true end
				end
			end
		end
		local seen = {}
		for _, start in ipairs(Sorted(ground, Before)) do
			if not seen[start] then
				local piece, stack = { start }, { start }
				seen[start] = true
				while #stack > 0 do
					local space = Pop(stack)
					for _, e in ipairs(edges[space]) do
						if ground[e.node] and not seen[e.node] then
							seen[e.node] = true
							piece[#piece + 1], stack[#stack + 1] = e.node, e.node
						end
					end
				end
				local inside, sealed = {}, true
				for _, space in ipairs(piece) do inside[space] = true end
				for _, space in ipairs(piece) do
					for _, e in ipairs(edges[space]) do
						if not inside[e.node] and not Sealed(e.pos, seals) then sealed = false end
					end
				end
				if sealed then
					for _, space in ipairs(piece) do
						if IsRoom(space) then restricted[space] = team end
					end
				end
			end
		end
	end
	return restricted
end

-- Pieces of nodes joined over edges joined(a, b) lets through, each sorted.
local function Pieces(nodes, edges, joined)
	local pieces, seen = {}, {}
	for _, start in ipairs(Sorted(nodes, Before)) do
		if not seen[start] then
			local piece, stack = { start }, { start }
			seen[start] = true
			while #stack > 0 do
				local space = Pop(stack)
				for _, e in ipairs(edges[space]) do
					if nodes[e.node] and not seen[e.node] and joined(space, e.node) then
						seen[e.node] = true
						piece[#piece + 1], stack[#stack + 1] = e.node, e.node
					end
				end
			end
			sort(piece, Before)
			pieces[#pieces + 1] = piece
		end
	end
	return pieces
end

-- The places: { { kind, owner, members (a list of spaces) } }, and space ->
-- the team whose place it is in (or nil).
function Places(edges, homes)
	local all = {}
	for space in pairs(edges) do all[space] = true end
	local teams = Sorted(homes)
	local places, owner = {}, {}
	local function Add(members, kind, team)
		places[#places + 1] = { kind = kind, owner = team, members = members }
		for _, space in ipairs(members) do owner[space] = team end
	end
	for _, piece in ipairs(Pieces(all, edges, function(a, b) return (a.outdoor == true) == (b.outdoor == true) end)) do
		local kind = piece[1].outdoor and GROUNDS or BUILDING
		local inside = {}
		for _, space in ipairs(piece) do inside[space] = true end
		local held = {}
		for _, team in ipairs(teams) do
			local mine = {}
			for _, space in ipairs(homes[team]) do
				if inside[space] then mine[#mine + 1] = space end
			end
			if #mine > 0 then held[#held + 1] = { team = team, homes = mine } end
		end
		if #held < 2 then
			Add(piece, kind, held[1] and held[1].team)
		else
			local reach, between = {}, huge
			for _, h in ipairs(held) do reach[h.team] = Walk(edges, h.homes, function(s) return inside[s] end) end
			for _, a in ipairs(held) do
				for _, b in ipairs(held) do
					if a ~= b then
						for _, space in ipairs(b.homes) do between = min(between, reach[a.team][space] or huge) end
					end
				end
			end
			local label = {}
			for _, space in ipairs(piece) do
				local ds = {}
				for _, h in ipairs(held) do ds[#ds + 1] = { reach[h.team][space] or huge, h.team } end
				sort(ds, function(x, y) return x[1] < y[1] or (x[1] == y[1] and x[2] < y[2]) end)
				label[space] = ds[2][1] - ds[1][1] <= NEUTRAL_SHARE * between and "" or ds[1][2]
			end
			for _, part in ipairs(Pieces(inside, edges, function(a, b) return label[a] == label[b] end)) do
				local team = label[part[1]]
				Add(part, kind, team ~= "" and team or nil)
			end
		end
	end
	return places, owner
end

-- The highway rooms: a set. routes: wartactics.incursion's; region(area) ->
-- its space; spawns: team -> its spawn area ids.
function Highways(routes, region, objectives, restricted, spawns)
	local spawnRooms, highways = {}, {}
	for _, areas in pairs(spawns) do
		for _, a in ipairs(areas) do
			local space = region(a)
			if space then spawnRooms[space] = true end
		end
	end
	for _, a in ipairs(objectives) do
		local space = region(a)
		if space and IsRoom(space) then highways[space] = true end
	end
	local count, crossed = {}, {}
	for _, route in ipairs(routes) do
		if not route.alternative then
			count[route.team] = (count[route.team] or 0) + 1
			local spaces = {}
			for _, a in ipairs(route.areas) do
				local space = region(a)
				if space and IsRoom(space) then spaces[space] = true end
			end
			for space in pairs(spaces) do
				crossed[space] = crossed[space] or {}
				crossed[space][route.team] = (crossed[space][route.team] or 0) + 1
			end
		end
	end
	for space, by in pairs(crossed) do
		local all = next(count) ~= nil
		for team, n in pairs(count) do
			if (by[team] or 0) < HIGHWAY_SHARE * n then all = false end
		end
		if all then highways[space] = true end
	end
	for space in pairs(highways) do
		if restricted[space] or spawnRooms[space] then highways[space] = nil end
	end
	return highways
end

-- A team's tree (wartactics.incursion's Tree) over the spaces: { roots,
-- parent (space -> space), children (space -> { spaces }), entry (space ->
-- the area its walk first reaches it by) }.
function SpaceTree(tree, region)
	local reached = Sorted(tree.distance, function(a, b)
		return tree.distance[a] < tree.distance[b] or (tree.distance[a] == tree.distance[b] and a < b)
	end)
	local entry, order = {}, {}
	for _, area in ipairs(reached) do
		local space = region(area)
		if space and not entry[space] then entry[space], order[#order + 1] = area, space end
	end
	local parent, children, roots = {}, {}, {}
	for _, space in ipairs(order) do children[space] = {} end
	for _, space in ipairs(order) do
		local above = entry[space]
		while tree.parent[above] and region(above) == space do above = tree.parent[above] end
		local up = region(above)
		if up and up ~= space then
			parent[space] = up
			children[up][#children[up] + 1] = space
		else
			roots[#roots + 1] = space
		end
	end
	for _, list in pairs(children) do sort(list, Before) end
	sort(roots, Before)
	return { roots = roots, parent = parent, children = children, entry = entry }
end

-- 1 at the building, 0 on the highway; with no building in reach 0, with no
-- highway 1.
function Gradient(toHighway, toBuilding)
	if toBuilding == huge then return 0 end
	if toHighway == huge then return 1 end
	return toHighway / (toHighway + toBuilding)
end

-- Each room's class: room -> { cls, team, gradient }. g: wartactics.incursion's
-- graph; fields: team -> its walk; owner: space -> team or nil.
function Classify(partition, g, fields, restricted, highways, owner, margin, far)
	local teams = Sorted(fields)
	local areasOf = {}
	for _, room in ipairs(partition.rooms) do areasOf[room] = room.areas end
	local function Starts(admit)
		local nodes = {}
		for n, area in ipairs(g.area) do
			local space = Region(partition, area)
			if space and admit(space) then nodes[#nodes + 1] = n end
		end
		return nodes
	end
	local building = {}
	for _, team in ipairs(teams) do
		local starts = Starts(function(s) return owner[s] == team and IsRoom(s) and not highways[s] end)
		building[team] = #starts > 0 and g.paths:Tree(starts) or nil
	end
	local highwayStarts = Starts(function(s) return highways[s] end)
	local highway = #highwayStarts > 0 and g.paths:Tree(highwayStarts) or nil
	local function Nearest(walk, areas)
		local best = huge
		if not walk then return best end
		for _, a in ipairs(areas) do
			local d = g.node[a] and walk:Distance(g.node[a])
			if d and d < best then best = d end
		end
		return best
	end
	local found = {}
	for _, room in ipairs(partition.rooms) do
		local mine = areasOf[room]
		if restricted[room] then
			found[room] = { cls = RESTRICTED, team = restricted[room], gradient = 1 }
		elseif highways[room] then
			found[room] = { cls = HIGHWAY, gradient = 0 }
		elseif owner[room] then
			found[room] = { cls = STRONGHOLD, team = owner[room], gradient = 1 }
		else
			local reach = {}
			for _, team in ipairs(teams) do reach[#reach + 1] = { Nearest(fields[team], mine), team } end
			sort(reach, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
			local side = reach[1][2]
			if #reach > 1 and reach[2][1] - reach[1][1] <= margin then side = nil end
			local toHighway = Nearest(highway, mine)
			local toBuilding = huge
			if side then
				toBuilding = Nearest(building[side], mine)
			else
				for _, team in ipairs(teams) do toBuilding = min(toBuilding, Nearest(building[team], mine)) end
			end
			local gradient = Gradient(toHighway, toBuilding)
			if toHighway > far and toBuilding > far then
				found[room] = { cls = room.outdoor and WILDS or UNOCCUPIED, gradient = gradient }
			elseif side and gradient >= 0.5 then
				found[room] = { cls = STRONGHOLD, team = side, gradient = gradient }
			else
				found[room] = { cls = COMMONS, gradient = gradient }
			end
		end
	end
	return found
end

-- The rooms carved around the forks: { { space, areas, fork } }, the areas
-- of the fork's space within reach of it when their floor is at least
-- floor; a fork already carved into one is not carved again. graph: the
-- room graph (areas' floor); g: wartactics.incursion's graph.
function Junctions(forks, graph, g, region, reach, floor)
	local carved, found = {}, {}
	for _, fork in ipairs(forks) do
		local space = region(fork)
		if space and not carved[fork] then
			local near = Distances({ fork }, function(area)
				local list = {}
				for to, crossing in pairs(g.crossings[area] or {}) do
					if region(to) == space then list[#list + 1] = { node = to, cost = crossing.cost } end
				end
				sort(list, function(a, b) return a.node < b.node end)
				return list
			end, reach)
			local areas, total = {}, 0
			for area in pairs(near) do
				if not carved[area] then
					areas[#areas + 1] = area
					total = total + (graph[area].floor or 0)
				end
			end
			if total >= floor then
				sort(areas)
				found[#found + 1] = { space = space, areas = areas, fork = fork }
				for _, area in ipairs(areas) do carved[area] = true end
			end
		end
	end
	return found
end
