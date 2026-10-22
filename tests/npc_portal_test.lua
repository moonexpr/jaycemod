-- foundation.npc.portal: where a path crosses from one nav area into the
-- next (CNavArea::ComputeClosestPointInPortal), so waypoints keep off the
-- corners and door jambs at an opening's ends.
local T = dofile("tests/harness.lua")
local Portal = T.require("foundation.npc.portal")

local N, E, S, W = Portal.NORTH, Portal.EAST, Portal.SOUTH, Portal.WEST

local function Rect(x1, y1, x2, y2, edges)
	return { lo = { x = x1, y = y1 }, hi = { x = x2, y = y2 }, edges = edges or {} }
end

-- `from` is 0..200 x 0..200; `to` lies north of it (smaller y), 50..150 x -200..0.
local FROM = Rect(0, 0, 200, 200)

T.test("the crossing is on the shared edge, at the point nearest where the path comes from", function()
	local to = Rect(50, -200, 150, 0)
	local x, y = Portal.ClosestPointInPortal(FROM, to, N, { x = 100, y = 150 })
	T.eq(x, 100, "straight across")
	T.eq(y, 0, "on the north edge")
	x = Portal.ClosestPointInPortal(FROM, to, N, { x = 190, y = 150 })
	T.eq(x, 150, "clamped to the opening")
end)

T.test("an end of the opening with a wall beyond it is kept a margin away", function()
	local to = Rect(50, -200, 150, 0, { [W] = true, [E] = true })
	T.eq((Portal.ClosestPointInPortal(FROM, to, N, { x = 0, y = 150 })), 50 + Portal.MARGIN, "off the west jamb")
	T.eq((Portal.ClosestPointInPortal(FROM, to, N, { x = 200, y = 150 })), 150 - Portal.MARGIN, "off the east jamb")
end)

T.test("an opening too narrow for its margins is crossed in the middle", function()
	local to = Rect(90, -200, 120, 0, { [W] = true, [E] = true })
	T.eq((Portal.ClosestPointInPortal(FROM, to, N, { x = 0, y = 150 })), 105, "midline")
end)

T.test("east, south and west crossings use the matching edge and axis", function()
	local east = Rect(200, 50, 400, 150, { [N] = true })
	local x, y = Portal.ClosestPointInPortal(FROM, east, E, { x = 100, y = 0 })
	T.eq(x, 200, "east edge")
	T.eq(y, 50 + Portal.MARGIN, "off the north jamb")
	x, y = Portal.ClosestPointInPortal(FROM, Rect(0, 200, 200, 400), S, { x = 30, y = 100 })
	T.eq(x .. "," .. y, "30,200", "south edge")
	x, y = Portal.ClosestPointInPortal(FROM, Rect(-200, 0, 0, 200), W, { x = 100, y = 70 })
	T.eq(x .. "," .. y, "0,70", "west edge")
end)

-- A lane's waypoints stand in the middle of each opening (a doorway's
-- centre), wherever the path came from: lanes are walked by many, and a
-- point at a jamb puts them between walls.
T.test("the middle of an opening is its usable span's centre on the shared edge", function()
	local to = Rect(50, -200, 150, 0)
	local x, y = Portal.MiddleOfPortal(FROM, to, N)
	T.eq(x, 100, "the doorway's centre")
	T.eq(y, 0, "on the north edge")
	local east = Rect(200, 120, 400, 180)
	x, y = Portal.MiddleOfPortal(FROM, east, E)
	T.eq(x, 200, "on the east edge")
	T.eq(y, 150, "the opening's centre")
end)

T.test("the middle keeps off a jamb with a wall beyond it", function()
	local to = Rect(50, -200, 150, 0, { [W] = true })
	T.eq((Portal.MiddleOfPortal(FROM, to, N)), (50 + Portal.MARGIN + 150) / 2, "between the margin and the open end")
end)

-- Off a drop the walker steps past the edge and falls: its landing is `out`
-- past the crossing, the way the opening faces.
T.test("a drop lands out past the crossing, the way the opening faces", function()
	local x, y = Portal.Past(100, 0, N, 24)
	T.eq(x, 100, "north: straight out")
	T.eq(y, -24, "north is -y")
	x, y = Portal.Past(200, 150, E, 24)
	T.eq(x, 224, "east is +x")
	T.eq(y, 150, "straight out")
	x = Portal.Past(0, 150, W, 24)
	T.eq(x, -24, "west is -x")
	local _, ys = Portal.Past(100, 200, S, 24)
	T.eq(ys, 224, "south is +y")
end)

T.finish()
