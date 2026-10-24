-- games.nextsoldier.lanes: keeping routes different enough to be lanes,
-- handing them to squads, and walking them.
local T = dofile("tests/harness.lua")
local Lanes = nextsoldier.lanes
local Path = wetsands.path

local function P(x, y) return { x = x, y = y, z = 0 } end
local function Lane(ids, length) return { ids = ids, points = {}, length = length } end

-- Siblings: after the direct lane is routed, each place round the objective
-- has its separation, the shortest walk to it from that lane's band (at
-- least as far as the search reached, for one beyond it). The first flank
-- is the place farthest from the band; the second, the place whose least of
-- its separation and its walk from the first is greatest: both out of the
-- direct lane's way, and out of each other's. Places are keys here; the
-- numbers stand for walks on the nav mesh.

-- separation(key) and walkFrom(a) -> walk(b), from tables; Between(a, b) for
-- the tours, the same walks both ways.
local function Separation(t) return function(key) return t[key] end end
local function Between(walks)
	return function(a, b) return walks[a .. " " .. b] or walks[b .. " " .. a] end
end
local function WalksFrom(walks)
	return function(a)
		return function(b) return walks[a .. " " .. b] or walks[b .. " " .. a] end
	end
end

T.test("a hill path that climbs away from the corridor pairs with the far side, not with the field below it", function()
	-- the hill: a long climb off the corridor; the field below it, near the
	-- hill as the crow flies but a short walk from the corridor
	local separation = Separation({ hill = 1300, fieldLeft = 700, fieldRight = 690 })
	local walks = WalksFrom({ ["hill fieldLeft"] = 1800, ["hill fieldRight"] = 300 })
	local a, b = Lanes.Siblings({ "fieldRight", "hill", "fieldLeft" }, separation, walks)
	T.eq(a, "hill", "the hill, farthest off the corridor")
	T.eq(b, "fieldLeft", "with the far side")
end)

T.test("a cluster far off the corridor gives one flank; the other comes from elsewhere", function()
	local separation = Separation({ a = 1000, b = 990, c = 400 })
	local walks = WalksFrom({ ["a b"] = 100, ["a c"] = 1500 })
	local x, y = Lanes.Siblings({ "a", "b", "c" }, separation, walks)
	T.eq(x .. "," .. y, "a,c", "the one far off, and the one far from it")
end)

T.test("places on the band are no flanks", function()
	local separation = Separation({ a = 800, onBand = 0 })
	local walks = WalksFrom({ ["a onBand"] = 900 })
	T.eq(Lanes.Siblings({ "a", "onBand" }, separation, walks), nil, "a alone off the band: no pair")
end)

T.test("with fewer than two places there are no siblings", function()
	local walks = WalksFrom({})
	T.eq(Lanes.Siblings({ "a" }, Separation({ a = 500 }), walks), nil, "one place")
	T.eq(Lanes.Siblings({}, Separation({}), walks), nil, "none")
end)

T.test("flank range is FLANK_MIN to FLANK_MAX from the objective, flat", function()
	local objective = P(1000, 0)
	T.eq(Lanes.InFlankRange(objective, P(1000 + Lanes.FLANK_MIN - 1, 0)), false, "too near")
	T.eq(Lanes.InFlankRange(objective, { x = 1000, y = Lanes.FLANK_MIN + 1, z = 900 }), true, "high above counts flat")
	T.eq(Lanes.InFlankRange(objective, P(1000, Lanes.FLANK_MAX + 1)), false, "too far")
end)

T.test("with no ground to choose from the flanks are FLANK_RADIUS left and right of the objective", function()
	local left, right = Lanes.FixedFlanks(P(0, 0), P(1000, 0))
	T.near(left.x, 1000, 1e-9)
	T.near(left.y, Lanes.FLANK_RADIUS, 1e-9, "the left of the way in, +y")
	T.near(right.y, -Lanes.FLANK_RADIUS, 1e-9, "the right")
end)

T.test("the tours go through the two defenses farthest apart by walk", function()
	local walks = Between({ ["d1 d2"] = 300, ["d1 d3"] = 1200, ["d2 d3"] = 900 })
	local a, b = Lanes.Farthest({ "d1", "d2", "d3" }, walks)
	T.eq(a .. "," .. b, "d1,d3")
	T.eq(Lanes.Farthest({ "d1" }, walks), nil, "a defense alone has no pair")
end)

-- After the direct lane: the flanks, then the tours, each on to the enemy
-- spawn nearest its place.
T.test("the lanes after the direct one: two flanks, then two tours on to the enemy spawn", function()
	local flanks, tours = { P(1000, 600), P(1000, -600) }, { P(1500, 400), P(1500, -300) }
	local function EnemySpawnNear(p) return P(3000, p.y) end
	local specs = Lanes.Plans(flanks, tours, EnemySpawnNear)
	local kinds = {}
	for i, spec in ipairs(specs) do kinds[i] = spec.kind end
	T.eq(table.concat(kinds, ","), "flank,flank,tour,tour")
	T.eq(specs[1].stops[1], flanks[1])
	T.eq(specs[2].stops[1], flanks[2])
	T.eq(specs[3].stops[1], tours[1], "through the first place")
	T.eq(specs[3].stops[2].x .. "," .. specs[3].stops[2].y, "3000,400", "on to the enemy spawn nearest it")
	T.eq(specs[4].stops[2].x .. "," .. specs[4].stops[2].y, "3000,-300", "and its own")
end)

T.test("with no enemy defenses known there are no tours", function()
	local specs = Lanes.Plans({ P(1000, 600), P(1000, -600) }, nil, function() error("no spawn asked for") end)
	T.eq(#specs, 2, "two flanks")
end)

T.test("a route's points thin to about WAYPOINT_SPACING apart, keeping both ends", function()
	local points = {}
	for i = 0, 10 do points[#points + 1] = P(i * 100, 0) end
	local kept, length = Lanes.Thin(points, function() return true end)
	T.eq(length, 1000, "its length")
	T.eq(#kept, 5, "0, 300, 600, 900 and the end")
	T.eq(kept[#kept].x, 1000, "the end")
end)

-- A route round a wall's corner: skipping the corner would cut through the
-- wall, so it is kept though the spacing is not reached, and every kept
-- segment is one a soldier can walk straight.
T.test("thinning keeps a waypoint where skipping it would cut through the world", function()
	local route = { P(0, 0), P(100, 0), P(200, 0), P(200, 100), P(200, 200) }
	-- the wall fills the inside of the corner: a segment from the first leg
	-- (x < 200) into the second (y > 0) crosses it
	local function Clear(a, b)
		return not ((a.x < 200 and b.y > 0) or (b.x < 200 and a.y > 0))
	end
	local kept, length = Lanes.Thin(route, Clear)
	T.eq(length, 400, "its length")
	T.eq(#kept, 3, "the start, the corner and the end")
	T.eq(kept[2].x .. "," .. kept[2].y, "200,0", "the corner")
	for i = 2, #kept do T.eq(Clear(kept[i - 1], kept[i]), true, "segment " .. i - 1 .. " is clear") end
end)

-- A lane's band: its areas and every area within LANE_SPREAD of them, the
-- areas the next tries pay LANE_PENALTY for, so a later lane leaves the
-- corridor instead of stepping one area aside.
T.test("a lane's band holds its areas and the areas near them, so later lanes leave its corridor", function()
	local route = { { id = 1 }, { id = 2 } }
	local near = { [1] = { { id = 1 }, { id = 10 }, { id = 11 } }, [2] = { { id = 2 }, { id = 11 }, { id = 12 } } }
	local asked
	local band = Lanes.Band(route, function(area, radius)
		asked = radius
		return near[area.id]
	end)
	local ids = {}
	for id in pairs(band) do ids[#ids + 1] = id end
	table.sort(ids)
	T.eq(table.concat(ids, ","), "1,2,10,11,12")
	T.eq(asked, Lanes.LANE_SPREAD, "areas within LANE_SPREAD")
end)

local function Kind(kind, length) return { kind = kind, ids = {}, points = {}, length = length } end

T.test("escorts take the direct lane and the flanks, least taken first, and stay while the plan does", function()
	local lanes = { key = "k", Kind("direct", 1000), Kind("flank", 1200), Kind("flank", 1300), Kind("tour", 2000), Kind("tour", 2100) }
	local a, b, c, d = { team = 3, role = "escort" }, { team = 3, role = "escort" }, { team = 3, role = "escort" }, { team = 3, role = "escort" }
	local blockers = { team = 3, role = "block" }
	local teams = { a, b, c, d, blockers }
	Lanes.Assign(teams, { [3] = lanes })
	T.eq(a.laneIndex .. b.laneIndex .. c.laneIndex .. d.laneIndex, "1231", "direct, flank, flank, then the direct again")
	T.eq(blockers.lane, nil, "blockers take no lane")
	Lanes.Assign(teams, { [3] = lanes })
	T.eq(b.laneIndex, 2, "kept while the plan is the same")
	local replanned = { key = "k2", Kind("direct", 900) }
	Lanes.Assign(teams, { [3] = replanned })
	T.eq(b.lane, replanned[1], "a new plan: a new lane")
end)

T.test("raiders take the tours, and assault squads take lanes as escorts do", function()
	local lanes = { key = "k", Kind("direct", 1000), Kind("flank", 1200), Kind("tour", 2000), Kind("tour", 2100) }
	local r1, r2, r3 = { team = 3, role = "raid" }, { team = 3, role = "raid" }, { team = 3, role = "raid" }
	local assault = { team = 3, role = "assault" }
	Lanes.Assign({ r1, r2, r3, assault }, { [3] = lanes })
	T.eq(r1.laneIndex .. r2.laneIndex .. r3.laneIndex, "343", "the tours, least taken first")
	T.eq(assault.laneIndex, 1, "the direct lane")
	T.eq(Lanes.JOBS.assault, true, "a lane job")
end)

T.test("a squad whose kind of lane could not be planned takes any lane", function()
	local lanes = { key = "k", Kind("direct", 1000), Kind("flank", 1200) }
	local raiders = { team = 3, role = "raid" }
	Lanes.Assign({ raiders }, { [3] = lanes })
	T.eq(raiders.laneIndex, 1, "no tours: the least taken lane")
end)

-- A lane is walked to its own end (the objective, a flank point, the enemy
-- spawn), whatever the walker's goal, so a tour runs on past the objective.
T.test("a walker makes for the next waypoint it has not reached, and leaves the lane once it no longer brings it nearer the lane's end", function()
	local lane = { points = { P(0, 0), P(300, 0), P(600, 0) } }
	T.eq(Lanes.Next(lane, P(10, 0), 1), 2, "the first reached: the second")
	T.eq(Lanes.Next(lane, P(590, 10), 1), 4, "all reached")
	T.eq(Lanes.Target(lane, P(10, 0), 2).x, 300, "on toward the lane's end")
	T.eq(Lanes.Target(lane, P(450, 0), 2), nil, "past that waypoint: it no longer helps")
	T.eq(Lanes.Target(lane, P(590, 0), 4), nil, "walked")
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

-- Staleness: a team's lanes are planned again when an area they watch (their
-- band, and the door walls they went round) has been blocked otherwise than
-- when they were planned for CHANGE_SETTLE: a door that stays shut across a
-- lane, a setup gate that stays open. A door that opens and shuts again
-- before then, as spawn doors do, changes nothing.
T.test("a change that lasts CHANGE_SETTLE makes the lanes stale", function()
	T.defined(Lanes.CHANGE_SETTLE, "CHANGE_SETTLE")
	local function Differs(id) return id == 40 end
	local stale, pending = Lanes.Settled({ [40] = true }, Differs, {}, 100)
	T.eq(stale, false, "just changed")
	T.eq(pending[40], 100, "changed at 100")
	stale = Lanes.Settled({}, Differs, pending, 100 + Lanes.CHANGE_SETTLE)
	T.eq(stale, true, "still changed after the settle")
end)

T.test("a change undone before CHANGE_SETTLE changes nothing", function()
	local _, pending = Lanes.Settled({ [40] = true }, function() return true end, {}, 100)
	local stale, after = Lanes.Settled({ [40] = true }, function() return false end, pending, 101)
	T.eq(stale, false, "undone")
	T.eq(after[40], nil, "forgotten")
	stale = Lanes.Settled({ [40] = true }, function() return true end, after, 100 + Lanes.CHANGE_SETTLE)
	T.eq(stale, false, "changed again: the settle starts over")
end)

T.test("an area not changed and not pending is not looked at", function()
	local looked = {}
	local stale, pending = Lanes.Settled({}, function(id) looked[#looked + 1] = id return true end, {}, 100)
	T.eq(stale, false, "nothing to look at")
	T.eq(#looked, 0, "none looked at")
	T.eq(next(pending), nil, "nothing pending")
end)

-- A tour's last stop: the enemy spawn's threshold, the nearest area to it
-- outside the enemy's spawn room.
local function Area(id, x, y, room) return { id = id, center = P(x, y), room = room } end
local function Open() return false end

T.test("a tour ends at the nearest area outside the enemy's spawn room", function()
	local spawn = P(0, 0)
	local areas = {
		Area(1, 10, 0, 3), -- inside the spawn room
		Area(2, 50, 0, 3),
		Area(3, 300, 0, 0), -- the doorway
		Area(4, 900, 0, 0),
	}
	local stop = Lanes.Threshold(spawn, areas, 3, Open)
	T.eq(stop.x, 300, "the doorway's x")
	T.eq(stop.y, 0, "the doorway's y")
end)

T.test("a tour skips an area outside the room that is enclosed by it", function()
	local spawn = P(0, 0)
	local function Enclosed(id) return id == 2 end
	local stop = Lanes.Threshold(spawn, { Area(1, 10, 0, 3), Area(2, 100, 0, 0), Area(3, 300, 0, 0) }, 3, Enclosed)
	T.eq(stop.x, 300, "the open doorway, not the pocket")
end)

-- Whether an area outside the enemy's spawn room is reached only through
-- the room: few areas outside it lead into it. into(id): the areas with a
-- way into id; open(id): outside the room.
T.defined(Lanes.POCKET_LIMIT, "POCKET_LIMIT")

T.test("an area reached only through the enemy's room is enclosed", function()
	-- 1 <- 2 (outside), and both are entered otherwise only from room areas 10, 11,
	-- which the open field (20, 21, ...) leads into
	local into = { [1] = { 2, 10 }, [2] = { 1, 11 }, [10] = { 11, 20 }, [11] = { 10, 21 } }
	local open = function(id) return id < 10 or id >= 20 end
	T.eq(Lanes.Enclosed(1, function(id) return into[id] or {} end, open), true, "a two-area pocket")
end)

T.test("an area the open field leads into is not enclosed", function()
	-- a chain of open areas longer than the limit leads into 1
	local into = {}
	for id = 1, Lanes.POCKET_LIMIT + 1 do into[id] = { id + 1 } end
	local open = function() return true end
	T.eq(Lanes.Enclosed(1, function(id) return into[id] or {} end, open), false, "the field reaches it")
end)

T.test("a way in from the area itself or one already seen is counted once", function()
	-- 1 and 2 lead into each other and nothing else does
	local into = { [1] = { 1, 2 }, [2] = { 1, 2 } }
	T.eq(Lanes.Enclosed(1, function(id) return into[id] or {} end, function() return true end), true, "two areas")
end)

T.test("with no area outside the room near, a tour still heads for the spawn", function()
	local spawn = P(5, 5)
	local stop = Lanes.Threshold(spawn, { Area(1, 10, 0, 3) }, 3, Open)
	T.eq(stop, spawn, "the spawn itself")
end)

T.finish()
