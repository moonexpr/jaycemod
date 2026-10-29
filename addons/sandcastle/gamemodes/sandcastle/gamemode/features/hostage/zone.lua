-- The rescue zone: the area round BLU's spawns, where a hostage led in is
-- rescued. A zone is { center, radius, floor }, positions { x, y, z }.
local error, ipairs, max, sqrt = error, ipairs, math.max, math.sqrt
module(...)

-- A hostage on another floor than the spawns is not in the zone.
HEIGHT = 200

-- The zone round the spawns: their middle, reaching margin past the farthest.
function Of(spawns, margin)
	if #spawns == 0 then error("a rescue zone needs spawns", 2) end
	local x, y, z = 0, 0, 0
	for _, p in ipairs(spawns) do x, y, z = x + p.x, y + p.y, z + (p.z or 0) end
	local n = #spawns
	local center = { x = x / n, y = y / n, z = z / n }
	local farthest = 0
	for _, p in ipairs(spawns) do
		farthest = max(farthest, sqrt((p.x - center.x) ^ 2 + (p.y - center.y) ^ 2))
	end
	return { center = center, radius = farthest + margin }
end

function Contains(zone, pos)
	local dx, dy = pos.x - zone.center.x, pos.y - zone.center.y
	if (pos.z or 0) - zone.center.z > HEIGHT or zone.center.z - (pos.z or 0) > HEIGHT then return false end
	return dx * dx + dy * dy <= zone.radius * zone.radius
end
