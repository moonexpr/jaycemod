-- Curated hotfixes for the stock CS:S maps' navigation, so the hostage mode
-- plays on them, applied as a map loads (features/hostage/sv.lua); the mesh
-- files are left as they are. Each is named by positions, as area ids change
-- when a mesh is generated again:
--   links  a link that runs through a wall, which soldiers walk into and are
--          stranded at, named by the centres of its two areas, cut both ways
--   areas  an area no body should stand on (a dumpster's lid, which soldiers
--          climbed and hostages followed them onto), named by its centre,
--          removed
-- Positions are { x, y, z }.
local pairs, sort = pairs, table.sort
module(...)

-- An area is found at a fix's position within this many units.
TOLERANCE = 24

local function P(x, y, z) return { x = x, y = y, z = z } end

-- map -> { links = { { a, b, why } }, areas = { { at, why } } }
MAPS = {
	cs_office = {
		links = {
			{
				a = P(1212.5, 375, -160),
				b = P(1262, 337, -160),
				why = "the 25-wide strip at the Terrorist spawn's exit is linked east through the wall to the room: soldiers push at it and are stranded",
			},
		},
		-- the lids of its dumpsters (TrashDumpster01a and 02), one by one: a
		-- radius round each also took ledges and the floor above
		areas = {
			{ at = P(-837.5, 137.5, -317.8), why = "a dumpster lid by the garage" },
			{ at = P(-637.5, -475.0, -207.5), why = "a dumpster lid" },
			{ at = P(912.5, -1125.0, -206.9), why = "a dumpster lid under a window" },
			{ at = P(-275.0, -1875.0, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(-337.5, -1912.5, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(-300.0, -1812.5, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(-237.5, -1812.5, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(175.0, -2025.0, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(175.0, -1925.0, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(162.5, -2062.5, -210.0), why = "a dumpster lid at the CT spawn" },
			{ at = P(125.0, -1937.5, -210.0), why = "a dumpster lid at the CT spawn" },
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
	return (MAPS[map] or {}).links or {}
end

-- The areas to remove on the map, or none.
function Areas(map)
	return (MAPS[map] or {}).areas or {}
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
