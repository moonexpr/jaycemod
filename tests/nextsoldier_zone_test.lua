-- nextsoldier.zone: the ground behind the setup gates, flooded over
-- the nav mesh from the attackers' spawn and held back at the gates.
local T = dofile("tests/harness.lua")
local Zone = nextsoldier.zone

-- A spawn room (1), a yard (2, 3) and a corridor (4) up to a gate (5),
-- the map beyond (6, 7).
local GRAPH = { [1] = { 2 }, [2] = { 1, 3 }, [3] = { 2, 4 }, [4] = { 3, 5 }, [5] = { 4, 6 }, [6] = { 5, 7 }, [7] = { 6 } }
local function Neighbors(id) return GRAPH[id] or {} end
local function Set(list)
	local set = {}
	for _, id in ipairs(list) do set[id] = true end
	return set
end
local function Sorted(list)
	local copy = { unpack(list) }
	table.sort(copy)
	return table.concat(copy, ",")
end

T.test("the zone is everything from the spawn up to the gate", function()
	local gate, outside = Set({ 5 }), Set({ 7 })
	local zone, leaked = Zone.Flood({ 1 }, Neighbors, function(id) return gate[id] end, function(id) return outside[id] end, 100)
	T.eq(Sorted(zone), "1,2,3,4", "spawn, yard and corridor")
	T.eq(leaked, false, "held at the gate")
end)

T.test("a gate not known lets the flood out, and says so", function()
	local zone, leaked = Zone.Flood({ 1 }, Neighbors, function() return false end, function(id) return id == 7 end, 100)
	T.eq(leaked, true, "reached the far side")
	T.eq(#zone > 4, true, "took more than the zone")
end)

T.test("a flood past its limit counts as leaked", function()
	local _, leaked = Zone.Flood({ 1 }, Neighbors, function() return false end, function() return false end, 3)
	T.eq(leaked, true, "too many areas")
end)

T.test("several spawns flood together, each area once", function()
	local zone = Zone.Flood({ 1, 3, 1 }, Neighbors, function(id) return id == 5 end, function() return false end, 100)
	T.eq(Sorted(zone), "1,2,3,4", "no repeats")
end)

T.finish()
