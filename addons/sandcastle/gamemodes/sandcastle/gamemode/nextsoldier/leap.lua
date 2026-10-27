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

-- A vault: over an obstacle the walker cannot stand on (a railing, its top
-- at `top`), onto the floor beyond (`land`), which may lie far lower. Up
-- to VAULT_RISE of the way it rises straight up to CLEARANCE above the top;
-- by VAULT_CROSS it has crossed to OVER past the top, still that high; then
-- it moves on to the landing, falling ever faster, and ends on it.
VAULT_RISE, VAULT_CROSS = 0.3, 0.6
VAULT_DURATION = 0.7 -- seconds the vault takes

-- q = { from, top, land, maxHeight (the walker's climb), maxDrop (the fall
-- it survives) }: whether the vault is one it can make, the top no higher
-- than it climbs above it, the landing below the top and no farther below
-- it than it falls.
function VaultFits(q)
	return q.top.z - q.from.z <= q.maxHeight and q.land.z < q.top.z and q.from.z - q.land.z <= q.maxDrop
end

local function Lerp(a, b, s) return a + (b - a) * s end

function Vault(from, top, land, t)
	t = min(t, 1)
	local apex = top.z + CLEARANCE
	if t <= VAULT_RISE then
		local s = 1 - (1 - t / VAULT_RISE) ^ 2
		return { x = from.x, y = from.y, z = Lerp(from.z, apex, s) }
	end
	local dx, dy = top.x - from.x, top.y - from.y
	local reach = sqrt(dx * dx + dy * dy)
	local ux, uy = 0, 0
	if reach > 0 then ux, uy = dx / reach, dy / reach end
	local overX, overY = top.x + ux * OVER, top.y + uy * OVER
	if t <= VAULT_CROSS then
		local s = (t - VAULT_RISE) / (VAULT_CROSS - VAULT_RISE)
		return { x = Lerp(from.x, overX, s), y = Lerp(from.y, overY, s), z = apex }
	end
	local s = (t - VAULT_CROSS) / (1 - VAULT_CROSS)
	return { x = Lerp(overX, land.x, s), y = Lerp(overY, land.y, s), z = Lerp(apex, land.z, s * s) }
end
