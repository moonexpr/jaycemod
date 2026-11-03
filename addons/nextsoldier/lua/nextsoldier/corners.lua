-- A route's turns rounded outward until the body passes them. The engine's
-- route points sit on the openings between nav areas, nearest where the
-- route comes from: round a corner, by its inside wall, where a body as wide
-- as a TF2 player's catches its shoulders on the corner (gm_bigmaze's 64-wide
-- corridors leave it 8 a side). Where the route turns (its two legs' unit
-- directions u, v meet with u . v under TURN_DOT), the point is pushed out
-- along the bisector of the turn, u - v (away from the inside), STEP at a
-- time and at most PUSH_MAX, until both legs are clear for the body. A turn
-- sharper than a right angle (u . v < 0), which no single point rounds, is
-- two points, each turning half of it: through m, the direction between u
-- and v, pushed out along u - m and m - v.
--
-- clear(a, b): whether a straight walk from a to b is clear for the body
-- (the caller's hull sweep). Points are { x, y, z }; a pushed point keeps the
-- height of the point it replaces.
local ipairs, sqrt = ipairs, math.sqrt
module(...)

TURN_DOT = 0.985 -- cos 10 degrees: a bend gentler than this is no turn
STEP = 8
PUSH_MAX = 96

local function Unit(a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return nil end
	return { x = dx / length, y = dy / length }
end

local function Direction(x, y)
	local length = sqrt(x * x + y * y)
	return { x = x / length, y = y / length }
end

local function Pushed(p, w, distance)
	return { x = p.x + w.x * distance, y = p.y + w.y * distance, z = p.z }
end

-- The point(s) to walk in place of p, met from prev and left for nxt, and
-- whether they are clear (false: no push within PUSH_MAX clears the turn,
-- and p is left as planned).
function Round(prev, p, nxt, clear)
	local u, v = Unit(prev, p), Unit(p, nxt)
	if not u or not v then return { p }, true end
	local dot = u.x * v.x + u.y * v.y
	if dot >= TURN_DOT then return { p }, true end
	if dot >= 0 then
		if clear(prev, p) and clear(p, nxt) then return { p }, true end
		local w = Direction(u.x - v.x, u.y - v.y)
		for distance = STEP, PUSH_MAX, STEP do
			local q = Pushed(p, w, distance)
			if clear(prev, q) and clear(q, nxt) then return { q }, true end
		end
		return { p }, false
	end
	local mx, my = u.x + v.x, u.y + v.y
	local m = (mx * mx + my * my) > 1e-12 and Direction(mx, my) or { x = -u.y, y = u.x }
	local wa, wb = Direction(u.x - m.x, u.y - m.y), Direction(m.x - v.x, m.y - v.y)
	for distance = STEP, PUSH_MAX, STEP do
		local a, b = Pushed(p, wa, distance), Pushed(p, wb, distance)
		if clear(prev, a) and clear(a, b) and clear(b, nxt) then return { a, b }, true end
	end
	return { p }, false
end

-- The route with each of its turns rounded, each from the point before it as
-- rounded; its first and last points stay.
function Route(points, clear)
	if #points <= 2 then return points end
	local out = { points[1] }
	for i = 2, #points - 1 do
		for _, q in ipairs((Round(out[#out], points[i], points[i + 1], clear))) do out[#out + 1] = q end
	end
	out[#out + 1] = points[#points]
	return out
end
