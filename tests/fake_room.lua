-- A room for the squad's tests: 800 square about the origin, a doorway 128 wide in each wall (west,
-- north, south, east), walls 32 thick. What its inside sees out of each doorway is a wedge widening
-- four times as fast as it goes out (seen); what one walking up to a door sees in through it, a
-- wedge widening as fast as it goes in (watched); the map's word on a slot around a point is inside
-- the room or outside it beyond the wall, never across it (AdmitAt).
local R = {}

R.SPACING = 72
local DOOR_HALF, WALL, SLANT, WATCH_SLANT = 64, 32, 4, 1

R.DOORS = { { x = -400, y = 0, z = 0 }, { x = 0, y = 400, z = 0 }, { x = 0, y = -400, z = 0 }, { x = 400, y = 0, z = 0 } }
R.CENTER = { x = 0, y = 0, z = 0 }

function R.Distance2D(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

function R.Inside(p) return p.x > -400 and p.x < 400 and p.y > -400 and p.y < 400 end

function R.AdmitAt(around)
	local inside = R.Inside(around)
	return function(slot) if R.Inside(slot) == inside then return { x = slot.x, y = slot.y, z = slot.z } end return nil end
end

function R.Seen(p)
	if R.Inside(p) then return true end
	for _, door in ipairs(R.DOORS) do
		local nx, ny = door.x / 400, door.y / 400
		local out = (p.x * nx + p.y * ny) - 400 - WALL
		local across = math.abs(p.x * ny - p.y * nx)
		if out < 0 and (p.x * nx + p.y * ny) > 400 and across < DOOR_HALF then return true end
		if out >= 0 and across < DOOR_HALF + out * SLANT then return true end
	end
	return false
end

function R.Watched(p, door)
	local inward = { x = -door.x / 400, y = -door.y / 400 }
	local dx, dy = p.x - door.x, p.y - door.y
	local depth, across = dx * inward.x + dy * inward.y, math.abs(dx * inward.y - dy * inward.x)
	if depth < 0 then return true end
	return across < DOOR_HALF + depth * WATCH_SLANT
end

-- The door nearest p, by its number.
function R.DoorOf(p)
	local best
	for i, door in ipairs(R.DOORS) do
		if not best or R.Distance2D(p, door) < R.Distance2D(p, R.DOORS[best]) then best = i end
	end
	return best
end

-- The room, its entrances carrying the squad's team's flow (flows) and the enemy's (enemyFlows),
-- each by door in order; entered from the west.
function R.Room(flows, enemyFlows)
	local room = { center = R.CENTER, lo = { x = -400, y = -400, z = 0 }, hi = { x = 400, y = 400, z = 0 },
		entry = R.DOORS[1], exits = R.DOORS, seen = R.Seen, watched = R.Watched, entrances = {},
		score = function(p) return -math.sqrt((p.x - 400) ^ 2 + p.y ^ 2) end }
	for i, door in ipairs(R.DOORS) do
		room.entrances[i] = { pos = door, flow = flows and flows[i] or 0, enemyFlow = enemyFlows and enemyFlows[i] or 0 }
	end
	return room
end

-- count standing on the grass east of the room.
function R.East(count)
	local squad = {}
	for i = 1, count do squad[i] = { x = 700, y = -150 + i * 50, z = 0 } end
	return squad
end

return R
