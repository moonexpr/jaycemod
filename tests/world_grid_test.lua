-- foundation.world.grid: a spatial hash of items by square cells on the
-- ground plane, and thinning points to one per cube.
local T = dofile("tests/harness.lua")
local Grid = world.grid

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

-- GMod's Vector: a userdata answering x, y and z through its metatable
-- (newproxy stands in for one under plain LuaJIT).
local function Vector(x, y, z)
	local v = newproxy(true)
	getmetatable(v).__index = { x = x, y = y, z = z }
	return v
end

T.test("positions may be any value answering x and y, as GMod's Vector does", function()
	local grid = Grid.New(100)
	grid:Put(Vector(10, 10, 0), "a")
	local found = grid:Near(Vector(50, 50, 0), function(item) return item == "a" end)
	T.eq(found, true, "found near a Vector")
	T.eq(#Grid.Thin({ Vector(1, 1, 1), Vector(2, 2, 2), Vector(500, 1, 1) }, 100), 2, "thinned Vectors")
end)

local function Xs(points)
	local xs = {}
	for i, p in ipairs(points) do xs[i] = p.x end
	return table.concat(xs, " ")
end

T.test("Spread keeps each point, in order, that is not within spacing of one kept", function()
	local kept = Grid.Spread({ { x = 0, y = 0 }, { x = 5, y = 0 }, { x = 10, y = 0 }, { x = 12, y = 0 }, { x = 20, y = 0 } }, 10)
	T.eq(Xs(kept), "0 10 20", "0, then 10 (exactly spacing away is apart), then 20")
end)

T.test("Spread measures in 3D, across cell borders, and with negative coordinates", function()
	T.eq(#Grid.Spread({ { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 9 } }, 10), 1, "9 above is too close")
	T.eq(#Grid.Spread({ { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 10 } }, 10), 2, "10 above is apart")
	T.eq(#Grid.Spread({ { x = -1, y = 0 }, { x = 1, y = 0 } }, 5), 1, "across the origin's cell border")
	T.eq(#Grid.Spread({ { x = 4.9, y = 4.9 }, { x = 5.1, y = 5.1 } }, 5), 1, "across a corner")
end)

T.test("Spread stops at limit, and reads each item's point through position", function()
	local items = {}
	for i = 1, 10 do items[i] = { name = i, at = { x = i * 100, y = 0 } } end
	local kept = Grid.Spread(items, 10, 3, function(item) return item.at end)
	T.eq(#kept, 3, "limit")
	T.eq(kept[1] == items[1] and kept[3] == items[3], true, "the first ones, as the items given")
	T.eq(#Grid.Spread(items, 10, 0, function(item) return item.at end), 0, "a limit of 0")
	T.eq(#Grid.Spread(items, 10, nil, function(item) return item.at end), 10, "no limit")
	T.eq(#Grid.Spread(items, 10, math.huge, function(item) return item.at end), 10, "an infinite limit is none")
end)

T.test("Spread refuses a spacing that is not positive", function()
	T.eq(pcall(Grid.Spread, {}, 0), false, "zero")
	T.eq(pcall(Grid.Spread, {}, -3), false, "negative")
end)

T.test("Spread is what comparing every point with every one kept gives", function()
	local seed = 12345
	local function Next(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	for trial = 1, 20 do
		local points = {}
		for i = 1, 200 do points[i] = { x = Next(600) - 300, y = Next(600) - 300, z = Next(100) } end
		local spacing = 20 + Next(60)
		local expected = {}
		for _, p in ipairs(points) do
			local apart = true
			for _, q in ipairs(expected) do
				if math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 + (p.z - q.z) ^ 2) < spacing then apart = false break end
			end
			if apart then expected[#expected + 1] = p end
		end
		local kept = Grid.Spread(points, spacing)
		T.eq(#kept, #expected, "trial " .. trial .. ": as many")
		for i = 1, #expected do
			if kept[i] ~= expected[i] then T.eq(false, true, "trial " .. trial .. ": the same point at " .. i) break end
		end
	end
end)

T.test("Spread compares a point only with those kept, not with those it skipped", function()
	local kept = Grid.Spread({ { x = 0, y = 0 }, { x = 8, y = 0 }, { x = 16, y = 0 } }, 10)
	T.eq(Xs(kept), "0 16", "8 is skipped for 0; 16 is near the skipped 8 but not near 0")
end)

T.finish()
