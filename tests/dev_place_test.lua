-- The dev workbench's placement of one body before another (sandcastle_dev_place), which
-- ENTITY:Teleport puts an entity at.
local T = dofile("tests/harness.lua")
local Place = T.require("sandcastle_dev_place")

T.defined(Place.GAP, "GAP")

local function P(x, y, z) return { x = x, y = y, z = z } end

T.test("a body is put before another, along its facing, the two clear of each other", function()
	local at = Place.Before(P(100, 50, 8), 0, 16, 10)
	T.near(at.x, 100 + 16 + 10 + Place.GAP, 1e-9, "ahead along +x")
	T.near(at.y, 50, 1e-9, "not across")
	T.eq(at.z, 8, "on its floor")
end)

T.test("facing another the other way, before it is the other way", function()
	local at = Place.Before(P(0, 0, 0), 90, 16, 16)
	T.near(at.x, 0, 1e-9, "not along x")
	T.near(at.y, 32 + Place.GAP, 1e-9, "ahead along +y")
end)

T.test("a body put before another faces it, or the way it faces", function()
	T.eq(Place.Yaw(30, true), 210, "turned to face it")
	T.eq(Place.Yaw(270, true), 90, "within a turn")
	T.eq(Place.Yaw(30, false), 30, "the way it faces")
end)

T.test("a body's reach across the ground is its widest from its middle", function()
	T.eq(Place.Reach(P(-16, -10, 0), P(12, 20, 72)), 20, "the widest side")
end)

T.finish()
