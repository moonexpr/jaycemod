-- foundation.aiwar.lanes: keeping routes different enough to be lanes,
-- handing them to squads, and walking them.
local T = dofile("tests/harness.lua")
local Lanes = T.require("foundation.aiwar.lanes")
local Path = T.require("foundation.npc.path")

local function P(x, y) return { x = x, y = y, z = 0 } end
local function Lane(ids, length) return { ids = ids, points = {}, length = length } end

T.test("a route is a lane when it shares under half its areas with each lane and is no great detour", function()
	local first = Lane({ 1, 2, 3, 4 }, 1000)
	T.eq(Lanes.Overlap(Lane({ 1, 2, 5, 6 }, 1100), first), 0.5, "half shared")
	T.eq(Lanes.Accept({ first }, Lane({ 1, 2, 5, 6 }, 1100), 1000), false, "half is too much")
	T.eq(Lanes.Accept({ first }, Lane({ 1, 7, 8, 9 }, 1100), 1000), true, "a quarter will do")
	T.eq(Lanes.Accept({ first }, Lane({ 7, 8, 9, 10 }, 1700), 1000), false, "past MAX_DETOUR of the shortest")
end)

T.test("a route's points thin to about WAYPOINT_SPACING apart, keeping both ends", function()
	local points = {}
	for i = 0, 10 do points[#points + 1] = P(i * 100, 0) end
	local kept, length = Lanes.Thin(points)
	T.eq(length, 1000, "its length")
	T.eq(#kept, 5, "0, 300, 600, 900 and the end")
	T.eq(kept[#kept].x, 1000, "the end")
end)

T.test("lanes go to squads least taken first, raiders the longest, and stay while the plan does", function()
	local lanes = { key = "k", Lane({ 1 }, 1000), Lane({ 2 }, 1500), Lane({ 3 }, 1200) }
	local raiders = { team = 3, role = "raid" }
	local escortsA = { team = 3, role = "escort" }
	local escortsB = { team = 3, role = "escort" }
	local blockers = { team = 3, role = "block" }
	local teams = { raiders, escortsA, escortsB, blockers }
	Lanes.Assign(teams, { [3] = lanes })
	T.eq(raiders.laneIndex, 2, "raiders: the longest")
	T.eq(escortsA.laneIndex, 1, "escorts: the shortest")
	T.eq(escortsB.laneIndex, 3, "the next escorts: the one left")
	T.eq(blockers.lane, nil, "blockers take no lane")
	raiders.laneIndex = 2
	Lanes.Assign(teams, { [3] = lanes })
	T.eq(raiders.laneIndex, 2, "kept while the plan is the same")
	local replanned = { key = "k2", Lane({ 4 }, 900) }
	Lanes.Assign(teams, { [3] = replanned })
	T.eq(raiders.lane, replanned[1], "a new plan: a new lane")
end)

T.test("a walker makes for the next waypoint it has not reached, and leaves the lane once it no longer helps", function()
	local lane = { points = { P(0, 0), P(300, 0), P(600, 0) } }
	T.eq(Lanes.Next(lane, P(10, 0), 1), 2, "the first reached: the second")
	T.eq(Lanes.Next(lane, P(590, 10), 1), 4, "all reached")
	T.eq(Lanes.Target(lane, P(10, 0), 2, P(1000, 0)).x, 300, "on toward the goal")
	T.eq(Lanes.Target(lane, P(10, 0), 2, P(-500, 0)), nil, "the lane leads away from the goal")
	T.eq(Lanes.Target(lane, P(590, 0), 4, P(1000, 0)), nil, "walked")
end)

T.test("planning a lane costs more through areas an earlier lane took", function()
	local step = { hasFrom = true, traversable = true, length = 100, centerDistance = 100, heightChange = 0, fromCostSoFar = 50,
		areaId = 7, spawnRoomTeam = 0, attributes = 0 }
	local limits = { stepHeight = 18, jumpHeight = 18, deathDropHeight = 18 }
	local bot = { team = 2, route = 1, entIndex = 1, now = 0 }
	local plain = Lanes.Strategy.Cost(step, limits, bot)
	bot.penalized = { [7] = true }
	T.eq(Lanes.Strategy.Cost(step, limits, bot), 50 + (plain - 50) * Lanes.LANE_PENALTY, "LANE_PENALTY times the step")
	step.traversable = false
	T.eq(Lanes.Strategy.Cost(step, limits, bot), Path.IMPASSABLE, "impassable stays so")
end)
