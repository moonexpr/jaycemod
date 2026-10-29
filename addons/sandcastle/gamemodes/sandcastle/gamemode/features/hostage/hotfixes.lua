-- Curated hotfixes for the stock CS:S maps' navigation, so the hostage mode
-- plays on them. A fix is a nav link that runs through a wall, which soldiers
-- walk into and are stranded at, named by the centres of its two areas (area
-- ids change when a mesh is generated again) and cut both ways as the map
-- loads (features/hostage/sv.lua). The mesh files are left as they are.
-- Positions are { x, y, z }.
local ipairs, pairs, sort = ipairs, pairs, table.sort
module(...)

-- An area is found at a fix's position within this many units.
TOLERANCE = 24

local function P(x, y, z) return { x = x, y = y, z = z } end

-- map -> { { a, b, why } }
MAPS = {
	cs_office = {
		{
			a = P(1212.5, 375, -160),
			b = P(1262, 337, -160),
			why = "the 25-wide strip at the Terrorist spawn's exit is linked east through the wall to the room: soldiers push at it and are stranded",
		},
	},
	cs_assault = {},
	cs_compound = {},
	cs_havana = {},
	cs_italy = {},
	cs_militia = {},
}

-- The links to cut on the map, or none.
function For(map)
	return MAPS[map] or {}
end

-- The maps with fixes listed, in order.
function Maps()
	local list = {}
	for map in pairs(MAPS) do list[#list + 1] = map end
	sort(list)
	return list
end

-- Whether two positions are the same place for finding an area.
function Near(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return dx * dx + dy * dy + dz * dz <= TOLERANCE * TOLERANCE
end
