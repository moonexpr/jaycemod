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

T.finish()
