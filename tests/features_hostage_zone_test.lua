-- The rescue zone (features.hostage.zone): the area round BLU's spawns,
-- where a hostage led in is rescued.
local T = dofile("tests/harness.lua")
local Zone = T.require("features.hostage.zone")

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

T.test("the zone is centred on the spawns, reaching past the farthest by the margin", function()
	local zone = Zone.Of({ P(0, 0), P(200, 0), P(100, 100), P(100, -100) }, 50)
	T.near(zone.center.x, 100, 1e-6, "x")
	T.near(zone.center.y, 0, 1e-6, "y")
	T.near(zone.radius, 100 + 50, 1e-6, "radius")
end)

T.test("a hostage inside the radius and the zone's height is in; beyond either, out", function()
	local zone = Zone.Of({ P(0, 0, 10), P(200, 0, 10) }, 50)
	T.eq(Zone.Contains(zone, P(100, 140, 10)), true, "inside")
	T.eq(Zone.Contains(zone, P(100, 160, 10)), false, "past the radius")
	T.eq(Zone.Contains(zone, P(100, 0, 10 + Zone.HEIGHT + 1)), false, "a floor above")
	T.eq(Zone.Contains(zone, P(100, 0, 10 - Zone.HEIGHT - 1)), false, "a floor below")
end)

-- A map's func_hostage_rescue brushes are its zones, as CS:S has them: a
-- hostage inside any of their boxes is rescued.
T.test("a zone of the map's rescue boxes holds what is inside any of them", function()
	local zone = Zone.Boxes({
		{ mins = P(0, 0, 0), maxs = P(100, 100, 100) },
		{ mins = P(500, 500, 0), maxs = P(600, 600, 100) },
	})
	T.eq(Zone.Contains(zone, P(50, 50, 10)), true, "in the first")
	T.eq(Zone.Contains(zone, P(550, 550, 10)), true, "in the second")
	T.eq(Zone.Contains(zone, P(300, 300, 10)), false, "between them")
	T.eq(Zone.Contains(zone, P(50, 50, 200)), false, "above")
	T.near(zone.center.x, 50, 1e-6, "its centre is the first box's")
end)

T.test("a zone of boxes needs boxes", function()
	T.eq(pcall(Zone.Boxes, {}), false, "none")
end)

T.test("a zone needs spawns", function()
	T.eq(pcall(Zone.Of, {}, 50), false, "none")
end)

T.finish()
