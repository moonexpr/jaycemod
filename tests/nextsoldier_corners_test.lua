-- nextsoldier.corners: a route's turns rounded outward until the body
-- passes them. A point where the route turns more than TURN_DOT allows is
-- pushed out along the bisector of its two legs (away from the inside of the
-- turn), STEP at a time and at most PUSH_MAX, until both legs are clear for
-- the body; a turn sharper than a right angle becomes two points, each
-- turning half of it.
local T = dofile("tests/harness.lua")
local Corners = nextsoldier.corners

T.defined(Corners.TURN_DOT, "TURN_DOT")
T.defined(Corners.STEP, "STEP")
T.defined(Corners.PUSH_MAX, "PUSH_MAX")

local function P(x, y) return { x = x, y = y, z = 0 } end

-- A world of forbidden boxes for the body's centre (walls grown by the
-- body's half width): a straight walk is clear when no point along it,
-- looked at every unit, stands in one.
local function World(boxes)
	return function(a, b)
		local dx, dy = b.x - a.x, b.y - a.y
		local n = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy)))
		for i = 0, n do
			local x, y = a.x + dx * i / n, a.y + dy * i / n
			for _, box in ipairs(boxes) do
				if x > box[1] and x < box[3] and y > box[2] and y < box[4] then return false end
			end
		end
		return true
	end
end

-- A corridor 64 wide going north (+y) along x 0..64, turning east (+x) along
-- y 0..64; the inside of the turn is the wall's corner at (64, 0). A body 24
-- each way from its centre: the centre keeps 24 off every wall.
local HALF = 24
local CORRIDOR = World({
	{ -1000, -1000, HALF, 1000 }, -- the west wall
	{ -1000, 64 - HALF, 1000, 1000 }, -- the north wall
	{ 64 - HALF, -1000, 1000, HALF }, -- the block inside the turn
})
local START, NEXT = P(32, -200), P(300, 32)
-- where the engine crosses into the turn: by the inside wall, as it does
local HUGGING = P(56, 12)

T.test("a turn the body cannot pass is pushed outward until both legs are clear", function()
	T.eq(CORRIDOR(START, HUGGING), false, "as planned, the body catches the inside corner")
	local rounded = Corners.Round(START, HUGGING, NEXT, CORRIDOR)
	T.eq(#rounded, 1, "one point")
	local p = rounded[1]
	T.eq(CORRIDOR(START, p), true, "the leg in is clear")
	T.eq(CORRIDOR(p, NEXT), true, "the leg out is clear")
	T.eq(p.x < HUGGING.x and p.y > HUGGING.y, true, "out, away from the inside of the turn")
	T.eq(p.z, HUGGING.z, "at the point's height")
end)

T.test("it is pushed no farther than it needs, in STEPs", function()
	local p = Corners.Round(START, HUGGING, NEXT, CORRIDOR)[1]
	local moved = math.sqrt((p.x - HUGGING.x) ^ 2 + (p.y - HUGGING.y) ^ 2)
	local steps = moved / Corners.STEP
	T.near(steps, math.floor(steps + 0.5), 1e-9, "a whole number of steps")
	local back = { x = p.x + (HUGGING.x - p.x) / steps, y = p.y + (HUGGING.y - p.y) / steps, z = 0 }
	T.eq(CORRIDOR(START, back) and CORRIDOR(back, NEXT), false, "a step less is not clear")
end)

T.test("a turn already clear is left where it is", function()
	local middle = P(32, 32)
	T.eq(Corners.Round(START, middle, NEXT, CORRIDOR)[1], middle, "the corridor's middle")
end)

T.test("a point the route goes straight through is left where it is, clear or not", function()
	local nowhere = function() return false end
	local p = P(0, 100)
	T.eq(Corners.Round(P(0, 0), p, P(0, 200), nowhere)[1], p, "straight on")
	local slight = P(1, 100)
	T.eq(Corners.Round(P(0, 0), slight, P(0, 200), nowhere)[1], slight, "within TURN_DOT")
end)

T.test("a turn no push within PUSH_MAX clears is left as planned, and said so", function()
	local nowhere = function() return false end
	local rounded, cleared = Corners.Round(START, HUGGING, NEXT, nowhere)
	T.eq(rounded[1], HUGGING, "as planned")
	T.eq(cleared, false, "not cleared")
	local _, ok = Corners.Round(START, HUGGING, NEXT, CORRIDOR)
	T.eq(ok, true, "a cleared turn says so")
end)

-- A hairpin round the end of a thin wall (x <= 80, y 20..40, grown by a body
-- 8 each way): in along its south side, out along its north side.
local HAIRPIN = World({ { -1000, 12, 88, 48 } })

T.test("a turn sharper than a right angle becomes two points, each leg clear", function()
	local start, tip, finish = P(0, 0), P(90, 30), P(0, 60)
	local rounded, cleared = Corners.Round(start, tip, finish, HAIRPIN)
	T.eq(#rounded, 2, "two points")
	T.eq(cleared, true, "cleared")
	local a, b = rounded[1], rounded[2]
	T.eq(HAIRPIN(start, a), true, "in to the first")
	T.eq(HAIRPIN(a, b), true, "between them")
	T.eq(HAIRPIN(b, finish), true, "out of the second")
end)

T.test("a route's every turn is rounded, each from the point before it as rounded", function()
	local route = { START, HUGGING, NEXT, P(300, 400) }
	local rounded = Corners.Route(route, CORRIDOR)
	T.eq(rounded[1], START, "the start stays")
	T.eq(rounded[#rounded], route[4], "the end stays")
	T.eq(CORRIDOR(rounded[1], rounded[2]), true, "the first leg")
	T.eq(CORRIDOR(rounded[2], rounded[3]), true, "round the corner")
end)

T.test("a route of two points or fewer is as it was", function()
	local two = { P(0, 0), P(10, 0) }
	T.eq(#Corners.Route(two, CORRIDOR), 2, "two")
	T.eq(#Corners.Route({}, CORRIDOR), 0, "none")
end)

T.finish()
