-- wartactics.rooms: the nav mesh's areas grouped into rooms by the mesh's
-- shape, and the doors between them. A mesh cuts open floor into small
-- areas, so width is measured across the floor, not along a link: an
-- area's clearance is its walk to the nearest wall; open floor (clearance
-- over half DOOR_WIDTH) forms the cores of rooms, every other area joins
-- the nearest core by walking (never across a func_door), and the doors
-- are where two rooms meet. The fixtures are grids of CELL-square areas,
-- as a nav mesh's are.
local T = dofile("tests/harness.lua")
local Rooms = wartactics.rooms

local CELL = 50

-- A mesh built cell by cell: Cell(id, col, row), Join(a, b[, door]); an area
-- touches a wall (edge) when it has fewer than four neighbours.
local function Mesh()
	local mesh = { graph = {}, at = {}, next = 1 }
	function mesh:Cell(col, row)
		local id = self.next
		self.next = id + 1
		self.graph[id] = { center = { x = col * CELL, y = row * CELL, z = 0 }, floor = CELL * CELL, links = {} }
		self.at[col .. ":" .. row] = id
		return id
	end
	function mesh:Join(a, b, door)
		local ca, cb = self.graph[a].center, self.graph[b].center
		local middle = { x = (ca.x + cb.x) / 2, y = (ca.y + cb.y) / 2, z = 0 }
		self.graph[a].links[#self.graph[a].links + 1] = { to = b, width = CELL, middle = middle, door = door }
		self.graph[b].links[#self.graph[b].links + 1] = { to = a, width = CELL, middle = middle, door = door }
	end
	-- a block of cols x rows cells from (col, row), joined to each other
	function mesh:Block(col, row, cols, rows)
		for c = col, col + cols - 1 do
			for r = row, row + rows - 1 do self:Cell(c, r) end
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
		for _, area in pairs(self.graph) do area.edge = #area.links < 4 end
		return self.graph
	end
	return mesh
end

-- Two 10 x 10 rooms, side by side, ten cells apart (cols 0-9 and 20-29).
local function TwoRooms()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 10)
	mesh:Block(20, 0, 10, 10)
	return mesh
end

-- A corridor one cell wide along row `row`, from col 10 to 19, joining them.
local function Corridor(mesh, row)
	for c = 10, 19 do mesh:Cell(c, row) end
	for c = 9, 19 do mesh:Join(mesh:Id(c, row), mesh:Id(c + 1, row)) end
end

T.test("the tuning is defined", function()
	T.defined(Rooms.DOOR_WIDTH, "DOOR_WIDTH")
	T.defined(Rooms.ROOM_MIN_FLOOR, "ROOM_MIN_FLOOR")
	T.defined(Rooms.DOOR_MERGE, "DOOR_MERGE")
	T.eq(Rooms.DOOR_WIDTH, 96, "settled with the operator")
	T.eq(CELL > Rooms.DOOR_WIDTH / 2, true, "the fixtures' cells: one step from a wall is open floor")
end)

T.test("two halls joined by a corridor are two rooms, the corridor shared between them, a door where they meet", function()
	local mesh = TwoRooms()
	Corridor(mesh, 5)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2)
	local a, b = Rooms.RoomOf(p, mesh:Id(0, 0)), Rooms.RoomOf(p, mesh:Id(29, 9))
	T.eq(a ~= b, true, "two rooms")
	T.eq(Rooms.RoomOf(p, mesh:Id(5, 5)), a, "the hall's middle")
	T.eq(Rooms.RoomOf(p, mesh:Id(0, 9)), a, "its corner, by the wall")
	T.eq(Rooms.RoomOf(p, mesh:Id(11, 5)), a, "the corridor's near end")
	T.eq(Rooms.RoomOf(p, mesh:Id(18, 5)), b, "its far end")
	T.eq(#a.doors, 1)
	T.eq(a.doors[1].leads[1], b.id, "leads to the other")
	T.eq(math.abs(a.doors[1].pos.x - 14.5 * CELL) <= CELL, true, "in the corridor's middle: " .. a.doors[1].pos.x)
	T.eq(b.doors[1].leads[1], a.id)
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

T.test("a nook too small to be a room joins the room it opens on", function()
	local mesh = TwoRooms()
	Corridor(mesh, 5)
	mesh:Block(0, 10, 3, 3) -- a 3 x 3 nook above the first hall, its middle open floor
	for c = 0, 2 do mesh:Join(mesh:Id(c, 9), mesh:Id(c, 10)) end
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 2, "still two")
	T.eq(Rooms.RoomOf(p, mesh:Id(1, 11)), Rooms.RoomOf(p, mesh:Id(0, 0)), "in the hall's room")
end)

T.test("corridors side by side are one doorway; far apart, two", function()
	local mesh = TwoRooms()
	Corridor(mesh, 4)
	Corridor(mesh, 5)
	local doors = Rooms.RoomOf(Rooms.Partition(mesh:Graph()), mesh:Id(0, 0)).doors
	T.eq(#doors, 1, "one doorway")
	T.eq(doors[1].width, 2 * CELL, "as wide as both")
	mesh = TwoRooms()
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
end)

T.test("rooms are numbered by their lowest area, so a map's rooms keep their numbers", function()
	local mesh = TwoRooms()
	Corridor(mesh, 5)
	local p = Rooms.Partition(mesh:Graph())
	T.eq(Rooms.RoomOf(p, 1).id, 1)
	T.eq(Rooms.RoomOf(p, mesh:Id(29, 9)).id, 2)
	T.eq(Rooms.RoomOf(p, 1).areas[1], 1, "areas ascending")
end)

T.test("a mesh with no open floor has no rooms", function()
	local mesh = Mesh()
	mesh:Block(0, 0, 10, 1) -- a strip one cell wide: every area by a wall
	local p = Rooms.Partition(mesh:Graph())
	T.eq(#p.rooms, 0)
	T.eq(Rooms.RoomOf(p, 1), nil)
end)

T.test("the work yields to its caller as it goes", function()
	local mesh = TwoRooms()
	Corridor(mesh, 5)
	local yields = 0
	Rooms.Partition(mesh:Graph(), function() yields = yields + 1 end)
	T.eq(yields > 0, true)
end)

T.finish()
