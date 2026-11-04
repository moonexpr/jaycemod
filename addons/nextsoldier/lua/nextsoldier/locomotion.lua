-- How a soldier gets there: its parts ladder, leap, probe, reach_memo,
-- route_record and route_walk; here, the way round a blocker, a drop rappelled,
-- a route's corners rounded and a goal arrived at.
local Geometry = math.geometry
local Noise = nextsoldier.body.noise
local ipairs, sqrt = ipairs, math.sqrt
module("nextsoldier.locomotion")

DETOUR_MARGIN = 8 -- room past the blocker and the walker's own width

local UP = { x = 0, y = 0, z = 1 }

-- The way round a solid entity standing in a walker's way (a crate across a
-- lane, which the nav mesh does not know of): the points beside it, square to
-- the way, far enough out for the walker to pass. The AI war's soldiers walk
-- to one when stuck against it (features.aiwar.orders' Unstick, through the
-- soldier port's Detour).
-- from, to: the walker and where it is going; center, extent: the blocker's
-- centre and how far it reaches from it across the ground; radius: the
-- walker's. Returns the two points beside the blocker at from's height, the
-- one nearer to first; none for a way with no length across the ground.
function DetourBeside(from, to, center, extent, radius)
	local way = Geometry.Normalize({ x = to.x - from.x, y = to.y - from.y, z = 0 })
	if not way then return {} end
	local out = Geometry.Scale(Geometry.Cross(UP, way), extent + radius + DETOUR_MARGIN)
	local a = Geometry.Add({ x = center.x, y = center.y, z = from.z }, out)
	local b = Geometry.Sub({ x = center.x, y = center.y, z = from.z }, out)
	if Geometry.Distance2D(b, to) < Geometry.Distance2D(a, to) then a, b = b, a end
	return { a, b }
end

-- Rappelling: a soldier going down a drop deeper than a safe fall (one it
-- would land from faster than nextsoldier.body.noise's MAX_SAFE_FALL_SPEED,
-- HL2's) comes down it no faster than RAPPEL_SPEED, landing softly. Its
-- paths may take drops as deep as foundation.wetsands.path.hl2's
-- SOLDIER_DROP_HEIGHT: mvm_decoy's ledge below BLU's spawn, cp_steel's.
-- Speeds are downward, in units a second; gravity is sv_gravity's.
RAPPEL_SPEED = 160

-- The deepest drop fallen without rappelling, under gravity.
local function SafeDrop(gravity)
	return Noise.MAX_SAFE_FALL_SPEED ^ 2 / (2 * gravity)
end

-- Whether a drop this deep is rappelled.
function Rappels(depth, gravity)
	return depth > SafeDrop(gravity)
end

-- How fast to come down now, falling at downSpeed with height to the floor,
-- and whether it rappels: as it falls, unless it would land faster than a
-- safe fall or rappels already; then no faster than RAPPEL_SPEED, to the
-- floor. Returns the speed, rappelling.
function RappelDescent(downSpeed, height, gravity, rappelling)
	local landing = sqrt(downSpeed * downSpeed + 2 * gravity * height)
	if not rappelling and landing <= Noise.MAX_SAFE_FALL_SPEED then return downSpeed, false end
	return downSpeed < RAPPEL_SPEED and downSpeed or RAPPEL_SPEED, true
end

-- A route's turns rounded outward until the body passes them. The engine's
-- route points sit on the openings between nav areas, nearest where the
-- route comes from: round a corner, by its inside wall, where a body as wide
-- as a TF2 player's catches its shoulders on the corner (gm_bigmaze's 64-wide
-- corridors leave it 8 a side). Where the route turns (its two legs' unit
-- directions u, v meet with u . v under CORNER_TURN_DOT), the point is pushed
-- out along the bisector of the turn, u - v (away from the inside),
-- CORNER_STEP at a time and at most CORNER_PUSH_MAX, until both legs are clear
-- for the body. A turn sharper than a right angle (u . v < 0), which no single
-- point rounds, is two points, each turning half of it: through m, the
-- direction between u and v, pushed out along u - m and m - v.
--
-- clear(a, b): whether a straight walk from a to b is clear for the body
-- (the caller's hull sweep). Points are { x, y, z }; a pushed point keeps the
-- height of the point it replaces.
CORNER_TURN_DOT = 0.985 -- cos 10 degrees: a bend gentler than this is no turn
CORNER_STEP = 8
CORNER_PUSH_MAX = 96

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
-- whether they are clear (false: no push within CORNER_PUSH_MAX clears the
-- turn, and p is left as planned).
function RoundCorner(prev, p, nxt, clear)
	local u, v = Unit(prev, p), Unit(p, nxt)
	if not u or not v then return { p }, true end
	local dot = u.x * v.x + u.y * v.y
	if dot >= CORNER_TURN_DOT then return { p }, true end
	if dot >= 0 then
		if clear(prev, p) and clear(p, nxt) then return { p }, true end
		local w = Direction(u.x - v.x, u.y - v.y)
		for distance = CORNER_STEP, CORNER_PUSH_MAX, CORNER_STEP do
			local q = Pushed(p, w, distance)
			if clear(prev, q) and clear(q, nxt) then return { q }, true end
		end
		return { p }, false
	end
	local mx, my = u.x + v.x, u.y + v.y
	local m = (mx * mx + my * my) > 1e-12 and Direction(mx, my) or { x = -u.y, y = u.x }
	local wa, wb = Direction(u.x - m.x, u.y - m.y), Direction(m.x - v.x, m.y - v.y)
	for distance = CORNER_STEP, CORNER_PUSH_MAX, CORNER_STEP do
		local a, b = Pushed(p, wa, distance), Pushed(p, wb, distance)
		if clear(prev, a) and clear(a, b) and clear(b, nxt) then return { a, b }, true end
	end
	return { p }, false
end

-- Whether a body at pos has come to its goal: within `within` across the ground,
-- and the goal no further below its feet than its height (a wide body rides a
-- slope well above the floor under it; a deck overhead is another place) nor
-- further above them than `within`.
function Arrived(pos, goal, within, height)
	local dx, dy, rise = pos.x - goal.x, pos.y - goal.y, pos.z - goal.z
	return dx * dx + dy * dy <= within * within and rise <= height and rise >= -within
end

-- The route with each of its turns rounded, each from the point before it as
-- rounded; its first and last points stay.
function RoundCorners(points, clear)
	if #points <= 2 then return points end
	local out = { points[1] }
	for i = 2, #points - 1 do
		for _, q in ipairs((RoundCorner(out[#out], points[i], points[i + 1], clear))) do out[#out + 1] = q end
	end
	out[#out + 1] = points[#points]
	return out
end
