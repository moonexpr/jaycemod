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

T.test("a zone needs spawns", function()
	T.eq(pcall(Zone.Of, {}, 50), false, "none")
end)

T.finish()
