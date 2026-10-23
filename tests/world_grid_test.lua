-- foundation.world.grid: a spatial hash of items by square cells on the
-- ground plane, and thinning points to one per cube.
local T = dofile("tests/harness.lua")
local Grid = T.require("foundation.world.grid")

local function P(x, y, z) return { x = x, y = y, z = z } end

local function Visited(grid, p)
	local seen = {}
	grid:Near(p, function(item) seen[#seen + 1] = item end)
	table.sort(seen)
	return table.concat(seen, " ")
end

T.test("near a point are the items in its cell and the eight around it", function()
	local grid = Grid.New(100)
	grid:Put(P(50, 50), "here")
	grid:Put(P(150, 150), "diagonal")
	grid:Put(P(-50, 50), "west")
	grid:Put(P(250, 50), "two cells east")
	grid:Put(P(50, -150), "two cells north")
	T.eq(Visited(grid, P(10, 10)), "diagonal here west", "the 3x3 block")
end)

T.test("a visit that answers true stops the search and says so", function()
	local grid = Grid.New(100)
	grid:Put(P(0, 0), "a")
	grid:Put(P(10, 0), "b")
	local visits = 0
	local found = grid:Near(P(0, 0), function()
		visits = visits + 1
		return true
	end)
	T.eq(found, true, "found")
	T.eq(visits, 1, "stopped at the first")
	T.eq(grid:Near(P(0, 0), function() end), false, "nothing answered true")
	T.eq(Grid.New(100):Near(P(0, 0), function() return true end), false, "an empty grid")
end)

T.test("negative coordinates fall in their own cells", function()
	local grid = Grid.New(100)
	grid:Put(P(-1, -1), "just below zero")
	grid:Put(P(-250, -250), "far")
	T.eq(Visited(grid, P(-50, -50)), "just below zero", "the far one is two cells off")
end)

T.test("a box goes in every cell it covers", function()
	local grid = Grid.New(100)
	grid:PutBox(P(50, 50), P(250, 120), "wide")
	local cells = 0
	for _, items in grid:Buckets() do
		cells = cells + 1
		T.eq(items[1], "wide", "the box in each")
	end
	T.eq(cells, 6, "three across, two down")
end)

T.test("a cell's size is a positive number", function()
	T.eq(pcall(Grid.New, 0), false, "zero")
	T.eq(pcall(Grid.New, -5), false, "negative")
end)

T.test("thinning keeps the first point in each cube, in order", function()
	local points = { P(10, 10, 0), P(20, 20, 0), P(10, 10, 600), P(600, 10), P(30, 30) }
	local kept = Grid.Thin(points, 512)
	T.eq(#kept, 3, "three cubes")
	T.eq(kept[1], points[1], "the first of the first cube")
	T.eq(kept[2], points[3], "a cube above")
	T.eq(kept[3], points[4], "a cube east; a missing z is 0")
end)

T.finish()
