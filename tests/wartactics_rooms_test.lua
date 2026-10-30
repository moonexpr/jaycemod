-- wartactics.rooms: the nav mesh's areas grouped into rooms, indoors and
-- outdoors, and the passages joining them (corridors and doorways, which
-- are no rooms). A mesh cuts open floor into small areas, so width is
-- measured across the floor, not along a link: an area's clearance is its
-- walk to the nearest wall; floor wider than a corridor forms the cores of
-- rooms, a room reaches from its core to its walls, and what is left is
-- passages, but for a stairwell climbing a storey, a room of its own. No
-- room or passage crosses a func_door or the threshold between indoors and
-- outdoors. The fixtures are grids of CELL-square areas, as a nav mesh's are.
local T = dofile("tests/harness.lua")
local Rooms = wartactics.rooms

local CELL = 50

-- A mesh built cell by cell: Cell(col, row[, z[, outdoor]]), Join(a, b[,
-- door]); an area touches a wall when it has fewer than four neighbours or
-- one across the threshold.
local function Mesh()
	local mesh = { graph = {}, at = {}, next = 1 }
	function mesh:Cell(col, row, z, outdoor)
		local id = self.next
		self.next = id + 1
		local x, y = col * CELL, row * CELL
		z = z or 0
		self.graph[id] = { center = { x = x, y = y, z = z }, floor = CELL * CELL, outdoor = outdoor == true, links = {},
			lo = { x = x - CELL / 2, y = y - CELL / 2, z = z }, hi = { x = x + CELL / 2, y = y + CELL / 2, z = z } }
		self.at[col .. ":" .. row] = id
		return id
	end
	function mesh:Join(a, b, door)
		local ca, cb = self.graph[a].center, self.graph[b].center
		local middle = { x = (ca.x + cb.x) / 2, y = (ca.y + cb.y) / 2, z = (ca.z + cb.z) / 2 }
		self.graph[a].links[#self.graph[a].links + 1] = { to = b, width = CELL, middle = middle, door = door }
		self.graph[b].links[#self.graph[b].links + 1] = { to = a, width = CELL, middle = middle, door = door }
	end
	-- a block of cols x rows cells from (col, row), joined to each other
	function mesh:Block(col, row, cols, rows, z, outdoor)
		for c = col, col + cols - 1 do
			for r = row, row + rows - 1 do self:Cell(c, r, z, outdoor) end
		end
		for c = col, col + cols - 1 do
			for r = row, row + rows - 1 do
				if c > col then self:Join(self.at[(c - 1) .. ":" .. r], self.at[c .. ":" .. r]) end
				if r > row then self:Join(self.at[c .. ":" .. (r - 1)], self.at[c .. ":" .. r]) end
			end
		end
	end
	function mesh:Id(col, row) return self.at[col .. ":" .. row] end
	function mesh:Graph()
		for _, area in pairs(self.graph) do
			local inside, threshold = 0, false
			for _, link in ipairs(area.links) do
				if self.graph[link.to].outdoor == area.outdoor then inside = inside + 1 else threshold = true end
			end
			area.wall = (inside < 4 or threshold) and CELL / 2 or nil
		end
		return self.graph
	end
	return mesh
end

-- Two 10 x 10 halls, side by side, ten cells apart (cols 0-9 and 20-29).
local function TwoHalls()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10)
	return mesh
end

-- A corridor one cell wide along row `row`, from col 10 to 19, joining them;
-- its floor sloping up `rise` from the first hall to the second, each cell
-- spanning its part of the climb, as a nav area on stairs does.
local function Corridor(mesh, row, rise)
	rise = rise or 0
	local step = rise / 11
	for c = 10, 19 do
		local id = mesh:Cell(c, row, step * (c - 9))
		local area = mesh.graph[id]
		area.lo.z, area.hi.z = area.center.z - step / 2, area.center.z + step / 2
	end
	for c = 9, 19 do mesh:Join(mesh:Id(c, row), mesh:Id(c + 1, row)) end
end

T.test("the tuning is defined", function()
	for _, name in ipairs({ "DOOR_WIDTH", "ROOM_MIN_FLOOR", "DOOR_MERGE", "SEAL_OPENING", "CORRIDOR_WIDTH", "ROOM_REACH",
		"STOREY_RISE", "STAIR_SLOPE" }) do
		T.defined(Rooms[name], name)
	end
	T.eq(Rooms.STOREY_RISE * 1.5 / 11 / CELL > Rooms.STAIR_SLOPE, true, "the fixtures' stairs: steeper than a stair")
	T.eq(Rooms.STOREY_RISE / 2 / 11 / CELL < Rooms.STAIR_SLOPE, true, "their ramps: gentler")
	T.eq(Rooms.DOOR_WIDTH, 96, "settled with the operator")
	T.eq(Rooms.CORRIDOR_WIDTH > Rooms.DOOR_WIDTH, true, "a corridor is wider than a door")
end)

T.test("two halls joined by a corridor are two rooms, the corridor a passage between them and in neither", function()
	local mesh = TwoHalls()
	Corridor(mesh, 5)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2)
	local a, b = Rooms.RoomOf(p, mesh:Id(0, 0)), Rooms.RoomOf(p, mesh:Id(29, 9))
	T.eq(a ~= b, true, "two rooms")
	T.eq(a.kind, Rooms.ROOM)
	T.eq(Rooms.RoomOf(p, mesh:Id(5, 5)), a, "the hall's middle")
	T.eq(Rooms.RoomOf(p, mesh:Id(0, 9)), a, "its corner, by the wall")
	T.eq(Rooms.RoomOf(p, mesh:Id(9, 5)), a, "its edge, where the corridor opens")
	for c = 11, 18 do T.eq(Rooms.RoomOf(p, mesh:Id(c, 5)), nil, "the corridor, in no room: " .. c) end
	local corridor = Rooms.PassageOf(p, mesh:Id(14, 5))
	T.eq(corridor.kind, Rooms.CORRIDOR)
	T.eq(Rooms.PassageOf(p, mesh:Id(18, 5)), corridor, "one passage, end to end")
	T.eq(table.concat(corridor.joins, ","), a.id .. "," .. b.id, "joining the two")
	T.eq(Rooms.PassageOf(p, mesh:Id(5, 5)), nil, "a room's area is in no passage")
	T.eq(#a.doors, 1)
	T.eq(a.doors[1].leads[1], b.id, "the door leads on through the corridor to the other")
	T.eq(a.doors[1].passage, corridor.id, "through it")
	T.eq(math.abs(a.doors[1].pos.x - 9.5 * CELL) <= CELL, true, "at the corridor's mouth: " .. a.doors[1].pos.x)
	T.eq(b.doors[1].leads[1], a.id)
	T.eq(#corridor.doors, 2, "the corridor's own doorways, one at each end")
	local leads = { corridor.doors[1].leads[1], corridor.doors[2].leads[1] }
	table.sort(leads)
	T.eq(table.concat(leads, ","), a.id .. "," .. b.id, "into each hall")
end)

T.test("where two corridors meet, each has a doorway into the other", function()
	local mesh = TwoHalls()
	Corridor(mesh, 5)
	for r = 6, 15 do mesh:Cell(14, r) end -- a second corridor off the first's middle, behind a door
	mesh:Join(mesh:Id(14, 5), mesh:Id(14, 6), true)
	for r = 6, 14 do mesh:Join(mesh:Id(14, r), mesh:Id(14, r + 1)) end
	mesh:Block(10, 16, 10, 10) -- a third hall at its far end
	mesh:Join(mesh:Id(14, 15), mesh:Id(14, 16))
	local p = Rooms.Partition(mesh:Graph())
	local first, second = Rooms.PassageOf(p, mesh:Id(12, 5)), Rooms.PassageOf(p, mesh:Id(14, 10))
	T.eq(first ~= nil and second ~= nil and first ~= second, true, "two corridors")
	local through
	for _, door in ipairs(first.doors) do if door.passage == second.id then through = door end end
	T.eq(through ~= nil, true, "a doorway from the first into the second")
end)

T.test("a hallway wider than a door but narrower than a corridor's width is a corridor, however much floor it has", function()
	local mesh = Mesh()
	local across = math.floor(Rooms.CORRIDOR_WIDTH / CELL) -- cells
	T.eq(across * CELL > Rooms.DOOR_WIDTH, true, "the fixture: wider than a door")
	local length = math.ceil(4 * Rooms.ROOM_MIN_FLOOR / (across * CELL * CELL))
	mesh:Block(0, 0, 10, 10)
	mesh:Block(10, 0, length, across)
	mesh:Block(10 + length, 0, 10, 10)
	for r = 0, across - 1 do
		mesh:Join(mesh:Id(9, r), mesh:Id(10, r))
		mesh:Join(mesh:Id(9 + length, r), mesh:Id(10 + length, r))
	end
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2, "the halls alone")
	local hallway = Rooms.PassageOf(p, mesh:Id(10 + math.floor(length / 2), 1))
	T.eq(hallway and hallway.kind, Rooms.CORRIDOR)
end)

T.test("a short gap between two halls is a door between their rooms, in the gap", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(11, 0, 10, 10)
	mesh:Cell(10, 5)
	mesh:Join(mesh:Id(9, 5), mesh:Id(10, 5))
	mesh:Join(mesh:Id(10, 5), mesh:Id(11, 5))
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2)
	T.eq(#p.passages, 0, "no passage")
	local a, b = Rooms.RoomOf(p, mesh:Id(0, 0)), Rooms.RoomOf(p, mesh:Id(20, 9))
	T.eq(#a.doors, 1)
	T.eq(a.doors[1].leads[1], b.id)
	local x = a.doors[1].pos.x
	T.eq(x >= 9.5 * CELL and x <= 10.5 * CELL, true, "in the gap: " .. x)
end)

T.test("a stairwell climbing a storey between two halls is a room of its own", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE * 1.5
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10, rise)
	Corridor(mesh, 5, rise)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 3, "the halls and the stairwell")
	local stairs = Rooms.RoomOf(p, mesh:Id(14, 5))
	T.eq(stairs.kind, Rooms.STAIRWELL)
	T.eq(Rooms.PassageOf(p, mesh:Id(14, 5)), nil, "no passage")
	local a = Rooms.RoomOf(p, mesh:Id(0, 0))
	T.eq(a.doors[1].leads[1], stairs.id, "the hall's door leads into it")
	T.eq(#stairs.doors, 2, "a door at each end")
end)

T.test("a stairwell's flights and the landing between them are one stairwell, climbing a storey together", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE * 1.5
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10, rise)
	Corridor(mesh, 5, rise)
	for c = 14, 15 do -- a landing halfway: flat, each flight below a storey
		local area = mesh.graph[mesh:Id(c, 5)]
		area.center.z, area.lo.z, area.hi.z = rise / 2, rise / 2, rise / 2
	end
	local p = Rooms.Partition(mesh:Graph())
	local stairs = Rooms.RoomOf(p, mesh:Id(12, 5))
	T.eq(stairs and stairs.kind, Rooms.STAIRWELL)
	T.eq(Rooms.RoomOf(p, mesh:Id(14, 5)), stairs, "the landing in it")
	T.eq(Rooms.RoomOf(p, mesh:Id(18, 5)), stairs, "and the flight above")
	T.eq(#stairs.doors, 2, "a doorway at the foot and one at the top")
end)

T.test("a landing several areas long still joins the flights at either end into one stairwell", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE * 1.5
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10, rise)
	Corridor(mesh, 5, rise)
	for c = 13, 16 do -- a landing four areas long, each flight below a storey
		local area = mesh.graph[mesh:Id(c, 5)]
		area.center.z, area.lo.z, area.hi.z = rise / 2, rise / 2, rise / 2
	end
	local p = Rooms.Partition(mesh:Graph())
	local stairs = Rooms.RoomOf(p, mesh:Id(11, 5))
	T.eq(stairs and stairs.kind, Rooms.STAIRWELL)
	T.eq(Rooms.RoomOf(p, mesh:Id(18, 5)), stairs, "one stairwell, both flights")
end)

T.test("a stairwell open along its side to a yard is still indoors, under its roof", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE * 1.5
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10, rise)
	Corridor(mesh, 5, rise)
	mesh:Block(10, 6, 10, 10, 0, true) -- a yard all along the flight
	for c = 10, 19 do mesh:Join(mesh:Id(c, 5), mesh:Id(c, 6)) end
	local p = Rooms.Partition(mesh:Graph())
	local stairs = Rooms.RoomOf(p, mesh:Id(14, 5))
	T.eq(stairs and stairs.kind, Rooms.STAIRWELL)
	T.eq(stairs.outdoor, false)
end)

T.test("sloping ground outdoors, however far it climbs, is no stairwell", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE * 1.5
	mesh:Block(0, 0, 10, 10, 0, true)
	mesh:Block(20, 0, 10, 10, rise, true)
	Corridor(mesh, 5, rise)
	for c = 10, 19 do mesh.graph[mesh:Id(c, 5)].outdoor = true end
	local p = Rooms.Partition(mesh:Graph())
	for _, room in ipairs(p.rooms) do T.eq(room.kind, Rooms.ROOM, "room " .. room.id) end
end)

T.test("rooms storeys apart are on levels numbered from the ground up; a stairwell spans the levels it joins", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE * 1.5
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10, rise)
	mesh:Block(0, 20, 10, 10, rise / 4) -- a hall a few steps up: the ground floor still
	Corridor(mesh, 5, rise)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.levels, 2, "two levels")
	local low, high, raised = Rooms.RoomOf(p, mesh:Id(0, 0)), Rooms.RoomOf(p, mesh:Id(29, 9)), Rooms.RoomOf(p, mesh:Id(0, 25))
	T.eq(low.level, 1, "the ground floor")
	T.eq(raised.level, 1, "a few steps up is the same floor")
	T.eq(high.level, 2, "the floor above")
	T.eq(low.top, 1, "a room on one level reaches no other")
	local stairs = Rooms.RoomOf(p, mesh:Id(14, 5))
	T.eq(stairs.level, 1, "the stairwell's foot")
	T.eq(stairs.top, 2, "its head")
	T.eq(table.concat(p.levels[2].rooms, ","), tostring(high.id), "each level's rooms, the stairwell in neither")
end)

T.test("a map on one floor has one level", function()
	local mesh = TwoHalls()
	Corridor(mesh, 5)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.levels, 1)
	T.eq(p.passages[1].level, 1, "its corridor on it too")
end)

T.test("a ramp rising less than a storey is still a corridor", function()
	local mesh = Mesh()
	local rise = Rooms.STOREY_RISE / 2
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10, rise)
	Corridor(mesh, 5, rise)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2)
	T.eq(Rooms.PassageOf(p, mesh:Id(14, 5)).kind, Rooms.CORRIDOR)
end)

T.test("halls joined along a whole side are one room", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(10, 0, 10, 10)
	for r = 0, 9 do mesh:Join(mesh:Id(9, r), mesh:Id(10, r)) end
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 1)
	T.eq(#p.rooms[1].doors, 0, "no doors inside it")
end)

T.test("a func_door across the join makes two rooms however wide it is", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(10, 0, 10, 10)
	for r = 0, 9 do mesh:Join(mesh:Id(9, r), mesh:Id(10, r), true) end
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2)
	T.eq(#Rooms.RoomOf(p, mesh:Id(0, 0)).doors, 1, "one doorway, the door's whole width")
	T.eq(Rooms.RoomOf(p, mesh:Id(0, 0)).doors[1].width, 10 * CELL)
end)

T.test("an areaportal between halls joined along a whole side parts them, as a door does", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(10, 0, 10, 10)
	for r = 0, 9 do mesh:Join(mesh:Id(9, r), mesh:Id(10, r)) end
	local graph = mesh:Graph()
	for id, area in pairs(graph) do area.bsp = area.center.x < 10 * CELL - CELL / 2 and 1 or 2 end
	local p = Rooms.Partition(graph)
	T.eq(#p.rooms, 2, "the map's own areas, sealed by its portal")
	local doors = Rooms.RoomOf(p, mesh:Id(0, 0)).doors
	T.eq(#doors, 1)
	T.eq(doors[1].width, 10 * CELL, "the portal's whole width")
end)

T.test("a window between two halls joins their rooms, though no one walks through it", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(11, 0, 10, 10)
	local pos = { x = 10 * CELL, y = 5 * CELL, z = 32 }
	local p = Rooms.Partition(mesh:Graph(), nil, { { pos = pos, from = mesh:Id(9, 5), to = mesh:Id(11, 5) } })
	local a, b = Rooms.RoomOf(p, mesh:Id(0, 0)), Rooms.RoomOf(p, mesh:Id(20, 9))
	T.eq(#a.doors, 0, "no door")
	T.eq(#a.windows, 1, "a window")
	T.eq(a.windows[1].leads[1], b.id, "onto the other")
	T.eq(a.windows[1].pos, pos)
	T.eq(b.windows[1].leads[1], a.id, "and back")
end)

T.test("a window within one room is no connection", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	local p = Rooms.Partition(mesh:Graph(), nil, { { pos = { x = 0, y = 0, z = 0 }, from = mesh:Id(0, 0), to = mesh:Id(9, 9) } })
	T.eq(#p.rooms[1].windows, 0)
end)

T.test("a nook too small to be a room joins the room it opens on", function()
	local mesh = TwoHalls()
	Corridor(mesh, 5)
	mesh:Block(0, 10, 3, 3) -- a 3 x 3 nook above the first hall
	for c = 0, 2 do mesh:Join(mesh:Id(c, 9), mesh:Id(c, 10)) end
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2, "still two")
	T.eq(Rooms.RoomOf(p, mesh:Id(1, 12)), Rooms.RoomOf(p, mesh:Id(0, 0)), "in the hall's room")
	T.eq(#p.passages, 1, "the corridor the only passage")
end)

T.test("corridors side by side are one doorway; far apart, two", function()
	local mesh = TwoHalls()
	Corridor(mesh, 4)
	Corridor(mesh, 5)
	local doors = Rooms.RoomOf(Rooms.Partition(mesh:Graph()), mesh:Id(0, 0)).doors
	T.eq(#doors, 1, "one doorway")
	T.eq(doors[1].width, 2 * CELL, "as wide as both")
	mesh = TwoHalls()
	Corridor(mesh, 0)
	Corridor(mesh, 9)
	T.eq(#Rooms.RoomOf(Rooms.Partition(mesh:Graph()), mesh:Id(0, 0)).doors, 2, "two doorways")
end)

T.test("a room's floor is its areas', its centre their floor-weighted middle", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(p.rooms[1].floor, 100 * CELL * CELL)
	T.near(p.rooms[1].center.x, 4.5 * CELL, 1e-9)
	T.eq(p.rooms[1].lo.x, -CELL / 2, "its block: from its areas' near corner")
	T.eq(p.rooms[1].hi.y, 9.5 * CELL, "to their far corner")
end)

T.test("rooms are numbered by their lowest area, so a map's rooms keep their numbers", function()
	local mesh = TwoHalls()
	Corridor(mesh, 5)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(Rooms.RoomOf(p, 1).id, 1)
	T.eq(Rooms.RoomOf(p, mesh:Id(29, 9)).id, 2)
	T.eq(Rooms.RoomOf(p, 1).areas[1], 1, "areas ascending")
end)

T.test("a mesh with no floor wider than a corridor has no rooms", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 1) -- a strip one cell wide: every area by a wall
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 0)
	T.eq(Rooms.RoomOf(p, 1), nil)
end)

-- Indoors and outdoors: an area is one or the other, and no room or passage
-- has both.
T.test("an open yard outdoors is a room, marked outdoor", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10, 0, true)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 1)
	T.eq(p.rooms[1].outdoor, true)
end)

T.test("a building's door onto a yard leads from the room indoors to the yard's, across the threshold", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(10, 0, 10, 10, 0, true)
	mesh:Join(mesh:Id(9, 5), mesh:Id(10, 5))
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2)
	local hall, yard = Rooms.RoomOf(p, mesh:Id(0, 0)), Rooms.RoomOf(p, mesh:Id(19, 9))
	T.eq(hall.outdoor, false, "indoors")
	T.eq(yard.outdoor, true, "outdoors")
	T.eq(Rooms.RoomOf(p, mesh:Id(9, 5)), hall, "the threshold's inner side the hall's")
	T.eq(Rooms.RoomOf(p, mesh:Id(10, 5)), yard, "its outer side the yard's")
	T.eq(#hall.doors, 1)
	T.eq(hall.doors[1].leads[1], yard.id)
	T.eq(hall.doors[1].outside, true, "out of doors")
	T.eq(yard.doors[1].outside, false, "the yard's door into the building leads in, not out")
end)

T.test("a scrap of roof over a yard, too small to be a room, is the yard's", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10, 0, true)
	local graph = mesh:Graph()
	graph[mesh:Id(4, 4)].outdoor = false -- one area under an awning
	local p = Rooms.Partition(graph)
	T.eq(#p.rooms, 1, "one yard")
	T.eq(Rooms.RoomOf(p, mesh:Id(4, 4)), Rooms.RoomOf(p, mesh:Id(0, 0)), "the scrap in it")
	T.eq(graph[mesh:Id(4, 4)].outdoor, false, "the graph given left as it was")
end)

T.test("a roofed space open along a whole side is not sealed: it counts as outdoors", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(10, 0, 10, 10, 0, true)
	for r = 0, 9 do mesh:Join(mesh:Id(9, r), mesh:Id(10, r)) end
	local p = Rooms.Partition(mesh:Graph())
	T.eq(Rooms.RoomOf(p, mesh:Id(0, 0)).outdoor, true, "a porch")
	T.eq(Rooms.RoomOf(p, mesh:Id(0, 0)) ~= Rooms.RoomOf(p, mesh:Id(19, 0)), true, "still apart from the yard")
end)

T.test("a big area against walls is open floor: its clearance counts from its wall, not its middle", function()
	local side = 300
	local graph = { [1] = { center = { x = 0, y = 0, z = 0 }, floor = side * side, wall = side / 2, links = {},
		lo = { x = -side / 2, y = -side / 2, z = 0 }, hi = { x = side / 2, y = side / 2, z = 0 } } }
	local p = Rooms.Partition(graph)
	T.eq(#p.rooms, 1, "one office, one area")
	T.eq(Rooms.RoomOf(p, 1).id, 1)
end)

T.test("the work yields to its caller as it goes", function()
	local mesh = TwoHalls()
	Corridor(mesh, 5)
	local yields = 0
	Rooms.Partition(mesh:Graph(), function() yields = yields + 1 end)
	T.eq(yields > 0, true)
end)

T.finish()
