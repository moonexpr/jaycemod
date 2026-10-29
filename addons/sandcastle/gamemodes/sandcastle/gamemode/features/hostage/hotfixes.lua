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

-- Static props whose tops the mesh calls walkable, though only a player's
-- crouch-jump gets on them: a soldier climbs one to take a route and a
-- hostage cannot follow it off. The nav areas on top of each are removed.
-- An area is on top within PROP_RADIUS of the prop and PROP_LIFT above its
-- foot (the prop's origin).
PROP_RADIUS, PROP_LIFT = 110, 30

-- map -> { links = { { a, b, why } }, props = { { x, y, z } } }
MAPS = {
	cs_office = {
		links = {
			{
				a = P(1212.5, 375, -160),
				b = P(1262, 337, -160),
				why = "the 25-wide strip at the Terrorist spawn's exit is linked east through the wall to the room: soldiers push at it and are stranded",
			},
		},
		-- TrashDumpster01a and 02, read from the map's static props
		props = {
			P(-836, 121, -341), P(-826, 202, -341), P(-636, -464, -272), P(916, -1123, -272),
			P(1729, 1458, -272), P(-273, -1852, -272), P(170, -1987, -272),
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

-- The props whose tops to clear of nav areas on the map, or none.
function Props(map)
	return (MAPS[map] or {}).props or {}
end

-- Whether a nav area's centre is on top of the prop.
function OnTop(prop, center)
	local dx, dy = center.x - prop.x, center.y - prop.y
	return dx * dx + dy * dy <= PROP_RADIUS * PROP_RADIUS and (center.z or 0) >= prop.z + PROP_LIFT
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
