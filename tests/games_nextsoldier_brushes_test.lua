-- games.nextsoldier.brushes: the sweep TF2 makes across a nav area to find a
-- solid func_brush standing in it (TestAndBlockOverlappingAreas).
local T = dofile("tests/harness.lua")
local Brushes = nextsoldier.brushes

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end
local function Key(p) return p.x .. "," .. p.y .. "," .. p.z end

-- A 100 x 50 area from (0, 0); corners given heights nw, ne, se, sw.
local function Area(hnw, hne, hse, hsw)
	return P(0, 0, hnw), P(100, 0, hne), P(100, 50, hse), P(0, 50, hsw)
end

T.test("a level area is swept south by a hull as wide as it, from step height to crouch height", function()
	local nw, ne, se, sw = Area(0, 0, 0, 0)
	local from, to, mins, maxs = Brushes.Sweep(nw, ne, se, sw, 100, 50)
	T.eq(Key(from) .. " to " .. Key(to), "0,0,0 to 0,50,0", "north-west to south-west")
	T.eq(Key(mins), "0,0," .. Brushes.STEP_HEIGHT, "above a step")
	T.eq(Key(maxs), "100,0," .. Brushes.CROUCH_HEIGHT, "the area's width, crouch high")
end)

T.test("a slope along y is swept down it, from the high end", function()
	local nw, ne, se, sw = Area(0, 0, 40, 40)
	local from, to, _, maxs = Brushes.Sweep(nw, ne, se, sw, 100, 50)
	T.eq(Key(from) .. " to " .. Key(to), "0,50,40 to 0,0,0", "high to low")
	T.eq(maxs.x, 100, "still as wide as the area")
end)

T.test("a slope along x is swept east (or west, from its high end) by a hull as deep as the area", function()
	local nw, ne, se, sw = Area(0, 30, 30, 0)
	local from, to, _, maxs = Brushes.Sweep(nw, ne, se, sw, 100, 50)
	T.eq(Key(from) .. " to " .. Key(to), "100,0,30 to 0,0,0", "high to low")
	T.eq(maxs.y .. "," .. maxs.x, "50,0", "the area's depth")
end)

T.test("an area sloping both ways is swept along its diagonal", function()
	local nw, ne, se, sw = Area(0, 10, 30, 20)
	local from, to, _, maxs = Brushes.Sweep(nw, ne, se, sw, 100, 50)
	T.eq(Key(from) .. " to " .. Key(to), "100,50,30 to 0,0,0", "south-east (higher) to north-west")
	T.eq(maxs.x .. "," .. maxs.y, "1,1", "a thin hull")
end)

T.finish()
