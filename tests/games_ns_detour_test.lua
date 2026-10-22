-- games.ns.detour: the way round a solid entity in a walker's way (a
-- crate across a lane): the points beside it, square to the way, far
-- enough out for the walker to pass.
local T = dofile("tests/harness.lua")
local Detour = T.require("games.ns.detour")

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

local function Distance2D(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

T.test("the tuning is defined", function()
	T.defined(Detour.MARGIN, "MARGIN")
end)

T.test("two points, either side of the blocker, square to the way", function()
	local from, to, center = P(0, 0), P(400, 0), P(100, 0)
	local points = Detour.Beside(from, to, center, 20, 16)
	T.eq(#points, 2, "both sides")
	local out = 20 + 16 + Detour.MARGIN
	for i, p in ipairs(points) do
		T.near(p.x, center.x, 1e-9, i .. ": level with the blocker along the way")
		T.near(math.abs(p.y), out, 1e-9, i .. ": its extent, the walker's and the margin out")
		T.eq(p.z, from.z, i .. ": at the walker's height")
	end
	T.eq(points[1].y * points[2].y < 0, true, "opposite sides")
end)

T.test("the side nearer the way's end comes first", function()
	local from, to, center = P(0, 0), P(400, 60), P(100, 0)
	local points = Detour.Beside(from, to, center, 20, 16)
	T.eq(Distance2D(points[1], to) <= Distance2D(points[2], to), true, "nearer first")
end)

T.test("a way with no length has no side to step to", function()
	T.eq(#Detour.Beside(P(5, 5), P(5, 5, 40), P(6, 5), 20, 16), 0)
end)

T.finish()
