-- The rescue zone, where a hostage led in is rescued: the map's own
-- func_hostage_rescue brushes (Boxes), as CS:S has them, else on a map
-- without any the area round BLU's spawns (Of). A zone is { center, boxes }
-- or { center, radius }; center is where the war leads hostages. Positions
-- are { x, y, z }.
local error, ipairs, max, sqrt = error, ipairs, math.max, math.sqrt
module(...)

-- A hostage on another floor than the spawns is not in a spawn zone.
HEIGHT = 200

-- The zone of the map's rescue brushes, each { mins, maxs } in the world;
-- its centre is the first box's.
function Boxes(boxes)
	if #boxes == 0 then error("a rescue zone needs boxes", 2) end
	local first = boxes[1]
	local center = {
		x = (first.mins.x + first.maxs.x) / 2,
		y = (first.mins.y + first.maxs.y) / 2,
		z = first.mins.z,
	}
	return { center = center, boxes = boxes }
end

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

local function InBox(box, pos)
	local z = pos.z or 0
	return pos.x >= box.mins.x and pos.x <= box.maxs.x and pos.y >= box.mins.y and pos.y <= box.maxs.y
		and z >= box.mins.z and z <= box.maxs.z
end

function Contains(zone, pos)
	if zone.boxes then
		for _, box in ipairs(zone.boxes) do
			if InBox(box, pos) then return true end
		end
		return false
	end
	local dx, dy = pos.x - zone.center.x, pos.y - zone.center.y
	if (pos.z or 0) - zone.center.z > HEIGHT or zone.center.z - (pos.z or 0) > HEIGHT then return false end
	return dx * dx + dy * dy <= zone.radius * zone.radius
end
