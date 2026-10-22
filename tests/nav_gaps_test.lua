-- Nav gaps (foundation.nav_gaps): GMod's generator leaves seams between
-- areas at the same height (a crack a player walks over, often covered by a
-- clip brush), so routes cannot cross them: arena_well's point was one-way
-- out. Candidates are the pairs of areas a narrow seam apart, side by side
-- along enough of an edge, a step apart in height, not yet linked both ways;
-- each comes with where to cross, from just inside one to just inside the
-- other, for the server to sweep a walker across before it links them.
local T = dofile("tests/harness.lua")
local Gaps = T.require("foundation.nav_gaps")

-- An area from its extent, flat at z.
local function Area(id, x0, y0, x1, y1, z)
	return { id = id, lo = { x = x0, y = y0, z = z or 0 }, hi = { x = x1, y = y1, z = z or 0 } }
end

local function Flat(areas)
	local byId = {}
	for _, a in ipairs(areas) do byId[a.id] = a end
	return function(id, x, y) return byId[id].lo.z end
end
local function Never() return false end

T.test("two areas a seam apart, side by side, are a candidate crossed at the middle of their shared edge", function()
	local a, b = Area(1, 0, 0, 100, 100), Area(2, 125, 20, 225, 120)
	local list = Gaps.Candidates({ a, b }, Flat({ a, b }), Never)
	T.eq(#list, 1, "one")
	local c = list[1]
	T.eq(c.a == 1 and c.b == 2 or c.a == 2 and c.b == 1, true, "the pair")
	local from, to = c.from, c.to
	if c.a == 2 then from, to = to, from end
	T.eq(from.x, 100 - Gaps.INSIDE, "just inside the first")
	T.eq(to.x, 125 + Gaps.INSIDE, "just inside the second")
	T.eq(from.y, 60, "at the middle of the edges' overlap")
	T.eq(to.y, 60, "straight across")
end)

T.test("the seam may run along either axis", function()
	local a, b = Area(1, 0, 0, 100, 100), Area(2, 0, 125, 100, 225)
	local c = Gaps.Candidates({ a, b }, Flat({ a, b }), Never)[1]
	T.eq(c ~= nil, true, "a candidate")
	T.eq(c.from.x, 50, "across the middle")
end)

T.test("a gap wider than GAP_MAX, an edge overlap under OVERLAP_MIN, a corner, or a step too high is no candidate", function()
	local a = Area(1, 0, 0, 100, 100)
	local far = Area(2, 100 + Gaps.GAP_MAX + 1, 0, 300, 100)
	local sliver = Area(3, 125, 100 - Gaps.OVERLAP_MIN + 1, 225, 200)
	local corner = Area(4, 125, 125, 225, 225)
	local high = Area(5, 125, 0, 225, 100, Gaps.STEP_HEIGHT + 1)
	for _, other in ipairs({ far, sliver, corner, high }) do
		T.eq(#Gaps.Candidates({ a, other }, Flat({ a, other }), Never), 0, "area " .. other.id)
	end
end)

T.test("areas touching or overlapping are the generator's to link, not a seam", function()
	local a, b = Area(1, 0, 0, 100, 100), Area(2, 100, 0, 200, 100)
	T.eq(#Gaps.Candidates({ a, b }, Flat({ a, b }), Never), 0, "touching")
end)

T.test("a pair already linked both ways is no candidate; linked one way, it still is", function()
	local a, b = Area(1, 0, 0, 100, 100), Area(2, 125, 0, 225, 100)
	local both = function() return true end
	T.eq(#Gaps.Candidates({ a, b }, Flat({ a, b }), both), 0, "both ways")
	local oneWay = function(from, to) return from == 1 and to == 2 end
	T.eq(#Gaps.Candidates({ a, b }, Flat({ a, b }), oneWay), 1, "one way")
end)

T.test("each pair is found once, among many areas", function()
	local areas = {}
	for i = 0, 9 do areas[#areas + 1] = Area(i + 1, i * 125, 0, i * 125 + 100, 100) end
	T.eq(#Gaps.Candidates(areas, Flat(areas), Never), 9, "nine seams between ten areas in a row")
end)

-- A link a walker crosses (a lane over it): the line it walks along,
-- across the side of the area it leaves that the link is on, where the
-- other area borders that side (the middle of their overlap: a doorway,
-- not the wall beside it), from INSIDE within the edge to INSIDE past it,
-- at height z. Sides as GMod numbers them: 0 north (-y), 1 east (+x), 2
-- south (+y), 3 west (-x).
local function Pt(x, y, z) return { x = x, y = y, z = z or 0 } end

T.test("a crossing runs across the link's side, at the middle of where the other area borders it", function()
	-- a 200-wide room; a doorway area only 50 wide on its north side
	local start, finish = Gaps.CrossingLine(Pt(-750, -2125), Pt(-550, -1925), 2, Pt(-750, -1925), Pt(-700, -1800), -196)
	T.eq(start.x, -725, "the doorway's middle, not the room's")
	T.eq(finish.x, -725, "straight across")
	T.eq(start.y, -1925 - Gaps.DEEP, "DEEP inside the room, past a rail a lip in from its edge")
	T.eq(finish.y, -1925 + Gaps.INSIDE, "past its edge")
	T.eq(start.z, -196, "at the height given")
end)

T.test("each side crosses its own way", function()
	local lo, hi, other = Pt(0, 0), Pt(50, 50), { Pt(-100, -100), Pt(150, 150) }
	local s0, f0 = Gaps.CrossingLine(lo, hi, 0, other[1], other[2], 0)
	T.eq(s0.y, 25, "north: from inside, no farther in than the centre")
	T.eq(f0.y, -Gaps.INSIDE, "north: out the low y")
	local s1, f1 = Gaps.CrossingLine(lo, hi, 1, other[1], other[2], 0)
	T.eq(f1.x, 50 + Gaps.INSIDE, "east: out the high x")
	T.eq(s1.y, 25, "the middle of the overlap")
	local _, f3 = Gaps.CrossingLine(lo, hi, 3, other[1], other[2], 0)
	T.eq(f3.x, -Gaps.INSIDE, "west: out the low x")
end)

T.test("an area bordering the side nowhere is crossed nearest it", function()
	local start = Gaps.CrossingLine(Pt(0, 0), Pt(50, 50), 1, Pt(60, 80), Pt(100, 120), 0)
	T.eq(start.y, 50, "the side's end nearest the other area")
end)

-- A link down more than a step is a drop off the edge: it crosses only
-- where the floor past the edge falls away (else the floor goes on at the
-- upper level, and the way down is over a rail).
T.test("a drop crosses where the floor past the edge falls away", function()
	T.eq(Gaps.FallsAway(160, -32, -32), true, "the floor below")
	T.eq(Gaps.FallsAway(160, -32, 160), false, "walkway past the edge: no way down there")
	T.eq(Gaps.FallsAway(160, 160 - Gaps.STEP_HEIGHT, 150), true, "no drop at all: a step")
	T.eq(Gaps.FallsAway(160, -32, nil), true, "nothing under it: the walker falls")
end)

-- The side a link leaves by, from where the other area lies: GMod files
-- some links on no side.
T.test("the side toward an area is the way it mostly lies", function()
	T.eq(Gaps.SideToward(Pt(0, 0), Pt(100, 20)), 1, "east")
	T.eq(Gaps.SideToward(Pt(0, 0), Pt(-100, 20)), 3, "west")
	T.eq(Gaps.SideToward(Pt(0, 0), Pt(20, 100)), 2, "south (+y)")
	T.eq(Gaps.SideToward(Pt(0, 0), Pt(20, -100)), 0, "north (-y)")
end)

-- An area the generator laid over a rail (a player clip it did not see)
-- and the lip beyond: the line starts DEEP inside, so the rail between the
-- walkway and the edge is crossed.
T.test("a crossing starts DEEP inside a wide area, at most its centre", function()
	local start = Gaps.CrossingLine(Pt(0, 0), Pt(400, 400), 1, Pt(400, 0), Pt(800, 400), 0)
	T.eq(start.x, 400 - Gaps.DEEP, "DEEP in")
	local narrow = Gaps.CrossingLine(Pt(0, 0), Pt(20, 400), 1, Pt(20, 0), Pt(800, 400), 0)
	T.eq(narrow.x, 10, "a narrow area: its centre")
end)

T.test("a crossing is traced across the whole opening: CLEARANCE in from each end, SPAN_STEP apart", function()
	-- a doorway-wide strip of the wall: the engine's path may cross anywhere in the overlap
	local lines = Gaps.CrossingLines(Pt(0, 0), Pt(200, 200), 1, Pt(225, 40), Pt(400, 200), 0)
	T.eq(lines[1].start.y, 40 + Gaps.CLEARANCE, "first: off the overlap's low end")
	T.eq(lines[#lines].start.y, 200 - Gaps.CLEARANCE, "last: off its high end")
	for i = 2, #lines do
		T.eq(lines[i].start.y - lines[i - 1].start.y <= Gaps.SPAN_STEP, true, "no wider apart than SPAN_STEP")
		T.eq(lines[i].start.y > lines[i - 1].start.y, true, "in order along the opening")
	end
	local middle = Gaps.CrossingLine(Pt(0, 0), Pt(200, 200), 1, Pt(225, 40), Pt(400, 200), 0)
	for _, line in ipairs(lines) do
		T.eq(line.start.x, middle.x, "each starts as deep as the middle's")
	end
end)

T.test("an opening narrower than twice CLEARANCE is traced once, at its middle", function()
	local lines = Gaps.CrossingLines(Pt(0, 0), Pt(200, 200), 1, Pt(200, 100), Pt(400, 120), 0)
	T.eq(#lines, 1, "one line")
	T.eq(lines[1].start.y, 110, "the middle")
end)

T.test("across a strip between the areas, a crossing runs on INSIDE into the area entered", function()
	-- east: from ends at x 200, to starts at x 250
	local _, finish = Gaps.CrossingLine(Pt(0, 0), Pt(200, 200), 1, Pt(250, 0), Pt(400, 200), 0)
	T.eq(finish.x, 250 + Gaps.INSIDE, "into to, past the strip")
	-- west: from starts at x 0, to ends at x -50
	_, finish = Gaps.CrossingLine(Pt(0, 0), Pt(200, 200), 3, Pt(-200, 0), Pt(-50, 200), 0)
	T.eq(finish.x, -50 - Gaps.INSIDE, "into to, west")
	-- touching: as before, INSIDE past the shared edge
	_, finish = Gaps.CrossingLine(Pt(0, 0), Pt(200, 200), 1, Pt(200, 0), Pt(400, 200), 0)
	T.eq(finish.x, 200 + Gaps.INSIDE, "past the shared edge")
end)

T.finish()
