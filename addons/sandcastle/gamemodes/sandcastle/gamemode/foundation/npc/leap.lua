-- A walker's jump onto a ledge as an arc it is moved along (the AI war's
-- soldiers: ws/sh_drg_soldier.lua's CustomClimbing), not left to physics:
-- a jump pushed at a wall hits its face and falls back, where an arc set
-- each tick lands. The walker rises first and only then moves across, so
-- its feet are above the lip wherever the wall stands between it and the
-- ledge: by halfway it has risen 7/8 of the way to CLEARANCE above the lip
-- (above the lip for any ledge up to 7 * CLEARANCE), and it crosses in the
-- second half, ending OVER past the lip.
local sqrt = math.sqrt
local min = math.min
module(...)

CLEARANCE = 10 -- how far above the lip the arc ends
OVER = 16 -- how far past the lip, across, the arc ends
DURATION = 0.45 -- seconds the arc takes

-- The point of the arc from `from` onto the ledge (its lip, the point the
-- walker stands on at the top) at t, the share of DURATION gone (past 1:
-- the end).
function Arc(from, ledge, t)
	t = min(t, 1)
	local dx, dy = ledge.x - from.x, ledge.y - from.y
	local reach = sqrt(dx * dx + dy * dy)
	local ux, uy = 0, 0
	if reach > 0 then ux, uy = dx / reach, dy / reach end
	local across = 0
	if t > 0.5 then across = ((t - 0.5) / 0.5) ^ 2 end
	local up = 1 - (1 - t) ^ 3
	local distance = (reach + OVER) * across
	if reach == 0 then distance = 0 end
	return {
		x = from.x + ux * distance,
		y = from.y + uy * distance,
		z = from.z + (ledge.z + CLEARANCE - from.z) * up,
	}
end
