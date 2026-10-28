-- nextsoldier.route_walk: a route walked waypoint by waypoint, by a
-- body that plans its own way (a bot player): reached waypoints are passed,
-- the farthest of the next few in a clear line is made for, and the last
-- is held until reached.
local T = dofile("tests/harness.lua")
local Walk = nextsoldier.route_walk

T.defined(Walk.RADIUS, "RADIUS")
T.defined(Walk.LOOKAHEAD, "LOOKAHEAD")
T.defined(Walk.ON, "ON")

local function P(x) return { x = x, y = 0, z = 0 } end
local STEP = Walk.RADIUS * 4
local ROUTE = { P(STEP), P(2 * STEP), P(3 * STEP), P(4 * STEP) }
local NEVER = function() return false end
local ALWAYS = function() return true end

T.test("it makes for the first waypoint, and passes each it has reached", function()
	local walk = Walk.New(ROUTE)
	T.eq(walk:Next(P(0), NEVER), ROUTE[1], "the first")
	T.eq(walk:Next(P(STEP - Walk.ON), NEVER), ROUTE[2], "standing on the first: the second")
	T.eq(walk:Next(P(STEP), NEVER), ROUTE[2], "it never goes back")
end)

T.test("a waypoint round a corner is passed only once it stands on it", function()
	local walk = Walk.New(ROUTE)
	local nearFirst = P(STEP - Walk.RADIUS)
	local onlySecond = function(q) return q == ROUTE[2] end
	T.eq(walk:Next(nearFirst, onlySecond), ROUTE[2], "near the first with the second in a clear line: on")
	local cornered = Walk.New(ROUTE)
	T.eq(cornered:Next(nearFirst, NEVER), ROUTE[1], "the second round a corner: still the first")
	T.eq(cornered:Next(P(STEP - Walk.ON + 1), NEVER), ROUTE[2], "standing on the first: on round the corner")
end)

T.test("it cuts ahead to the farthest of the next waypoints it can walk to in a straight line", function()
	local walk = Walk.New(ROUTE)
	T.eq(walk:Next(P(0), ALWAYS), ROUTE[1 + Walk.LOOKAHEAD], "as far as it looks ahead")
	local clearTo2 = function(q) return q.x <= 2 * STEP end
	T.eq(Walk.New(ROUTE):Next(P(0), clearTo2), ROUTE[2], "no farther than the line is clear")
end)

T.test("the last waypoint is held until reached, then the walk is over", function()
	local walk = Walk.New(ROUTE)
	T.eq(walk:Next(P(4 * STEP - Walk.RADIUS - 1), ALWAYS), ROUTE[4], "the last")
	T.eq(walk:Done(), false, "not over")
	T.eq(walk:Next(P(4 * STEP), ALWAYS), nil, "reached: nothing more")
	T.eq(walk:Done(), true, "over")
end)

T.test("an empty route is walked at once", function()
	local walk = Walk.New({})
	T.eq(walk:Next(P(0), ALWAYS), nil, "nothing to make for")
	T.eq(walk:Done(), true, "over")
end)

-- Where the floor under a straight walk is looked for: points along the
-- line, FOOTING_SPACING apart and at most FOOTING_MAX of them, the ends left
-- out (one stands on the start; the end is the waypoint's own floor), each
-- at the line's height there.
T.defined(Walk.FOOTING_SPACING, "FOOTING_SPACING")
T.defined(Walk.FOOTING_MAX, "FOOTING_MAX")

T.test("the floor is looked for along the line, evenly, the ends left out", function()
	local from, to = { x = 0, y = 0, z = 0 }, { x = Walk.FOOTING_SPACING * 4, y = 0, z = 40 }
	local points = Walk.Footing(from, to)
	T.eq(#points, 3, "between the ends")
	for i, p in ipairs(points) do
		T.near(p.x, Walk.FOOTING_SPACING * i, 1e-9, "spaced " .. i)
		T.near(p.z, 10 * i, 1e-9, "at the line's height " .. i)
	end
end)

T.test("a walk shorter than the spacing looks for no floor between", function()
	T.eq(#Walk.Footing({ x = 0, y = 0, z = 0 }, { x = Walk.FOOTING_SPACING / 2, y = 0, z = 0 }), 0, "none")
end)

T.test("a long walk is looked at no more than FOOTING_MAX times, still evenly", function()
	local far = { x = Walk.FOOTING_SPACING * Walk.FOOTING_MAX * 3, y = 0, z = 0 }
	local points = Walk.Footing({ x = 0, y = 0, z = 0 }, far)
	T.eq(#points, Walk.FOOTING_MAX, "capped")
	local step = far.x / (Walk.FOOTING_MAX + 1)
	T.near(points[1].x, step, 1e-9, "first")
	T.near(points[#points].x, far.x - step, 1e-9, "last")
end)

T.finish()
