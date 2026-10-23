-- Lanes: the ways a team's offensive squads (escorts, raiders) take from
-- their spawn, so they come on by several paths instead of all by the
-- shortest. A team plans a direct lane to its objective first; then (Plans)
-- two flanks, siblings out of its way and each other's by walking
-- (Siblings), and two tours through the enemy's defenses farthest apart (or
-- the flanks, with a single defense) on to the enemy's spawn nearest each.
-- The aiwar controller routes them one after the other over the nav mesh,
-- each costing more
-- (LANE_PENALTY) through the band of the routes before it (Band: their
-- areas and those within LANE_SPREAD, so a later route leaves the corridor
-- instead of stepping one area aside; Strategy), and keeps each it can
-- route. Each squad holds a lane of a kind its job takes (Assign); its
-- leader walks the lane's waypoints (Next) until going on along it no
-- longer brings it nearer the lane's end.
--
-- A lane is { kind, ids (its nav areas), points (its waypoints, about
-- WAYPOINT_SPACING apart), length }; a team's lanes are { key, [1..n] =
-- lane }. Positions are { x, y, z } tables.
local ipairs, pairs = ipairs, pairs
local huge, min, sqrt = math.huge, math.min, math.sqrt
local sort = table.sort
local HL2Path = require("games.nextsoldier.path.hl2")
local Path = require("games.nextsoldier.path")
local Distance = require("foundation.math.geometry").Distance
local Graph = require("foundation.graph.search")
module(...)

LANE_PENALTY = 8
FLANK_RADIUS = 600 -- how far beside the objective a flank lane ends
LANE_SPREAD = 300 -- how far either side of a route its band reaches
WAYPOINT_SPACING, WAYPOINT_REACH, LOOKAHEAD = 300, 160, 2
POCKET_LIMIT = 128 -- fewer areas outside a spawn room leading into an area: a pocket the room encloses

-- The jobs whose squads take lanes (features.aiwar.model's ESCORT, RAID,
-- ASSAULT: the point scenarios' escort, and EXPLORE: arena's explorers).
JOBS = {
	escort = true,
	raid = true,
	assault = true,
	explore = true,
}

DIRECT, FLANK, TOUR = "direct", "flank", "tour"
-- The kinds of lane each job takes: escorts and assault squads come at the
-- objective, raiders go round through the enemy, explorers search the
-- ways to the objective.
JOB_KINDS = {
	escort = { [DIRECT] = true, [FLANK] = true },
	assault = { [DIRECT] = true, [FLANK] = true },
	explore = { [DIRECT] = true, [FLANK] = true },
	raid = { [TOUR] = true },
}

-- The route cost for planning a lane: HL2's, but each step into an area an
-- earlier lane took (bot.penalized: area id -> true) costs LANE_PENALTY
-- times as much.
Strategy = {
	Cost = function(step, limits, bot)
		local cost = HL2Path.Cost(step, limits, bot)
		if cost == Path.IMPASSABLE or not (bot.penalized and bot.penalized[step.areaId]) then return cost end
		local from = step.fromCostSoFar or 0
		return from + (cost - from) * LANE_PENALTY
	end,
}

-- A route's band: the ids of its areas and of every area within
-- LANE_SPREAD of one, an id -> true set. route: nav areas ({ id }, or the
-- controller's with GetID); near(area, radius): the areas within radius.
function Band(route, near)
	local band = {}
	for _, area in ipairs(route) do
		for _, other in ipairs(near(area, LANE_SPREAD)) do band[other.id] = true end
	end
	return band
end

local function Point(x, y, z) return { x = x, y = y, z = z } end

-- How long an area a team's lanes watch (their band, and the door walls they
-- went round) must stay blocked otherwise than when they were planned before
-- the lanes are planned again: a door that stays shut across a lane, a setup
-- gate that stays open. A door that opens and shuts again sooner, as spawn
-- doors do while soldiers come and go, changes nothing.
CHANGE_SETTLE = 5

-- Whether a watched area has differed from its planned blocking for
-- CHANGE_SETTLE: candidates (area id -> true: the watched areas whose
-- blocking changed since the last look), differs(id) whether it differs now
-- from when the lanes were planned, pending (id -> since when it has
-- differed), now. Only candidates and pending areas are looked at. Returns
-- that and the new pending.
function Settled(candidates, differs, pending, now)
	local after, stale = {}, false
	local function Look(id)
		if after[id] ~= nil or not differs(id) then return end
		after[id] = pending[id] or now
		if now - after[id] >= CHANGE_SETTLE then stale = true end
	end
	for id in pairs(candidates) do Look(id) end
	for id in pairs(pending) do Look(id) end
	return stale, after
end

-- Whether the area start, outside the enemy's spawn room, is a pocket the
-- room encloses: fewer than POCKET_LIMIT areas outside the room lead into
-- it, so a route that may not enter the room cannot reach it. into(id): the
-- areas with a way into id; open(id): id is outside the room.
function Enclosed(start, into, open)
	local _, cut = Graph.Flood({ start }, into, open, POCKET_LIMIT - 1)
	return not cut
end

-- A tour's last stop: the enemy spawn's threshold, the centre of the area
-- nearest spawn that is not in the enemy's spawn room, which its team's
-- route cannot enter, nor enclosed by it (areas: { id, center, room }, room
-- the spawn room's team; enclosed(id), asked nearest first, as Enclosed
-- finds); the spawn itself when none is near.
function Threshold(spawn, areas, enemy, enclosed)
	local outside = {}
	for _, area in ipairs(areas) do
		if area.room ~= enemy then outside[#outside + 1] = { area = area, distance = Distance(area.center, spawn) } end
	end
	sort(outside, function(a, b) return a.distance < b.distance end)
	for _, candidate in ipairs(outside) do
		local area = candidate.area
		if not enclosed(area.id) then return Point(area.center.x, area.center.y, area.center.z) end
	end
	return spawn
end

-- Siblings: the flanks are a pair of equals, two ways that keep out of the
-- direct lane's way and out of each other's, judged by walking, not by
-- where they lie: the controller routes the direct lane first, then
-- measures each place's separation, the shortest walk to it from that
-- lane's band (foundation.graph.search's Distances), and the walk between two
-- places. Of the ground FLANK_MIN to FLANK_MAX from the objective (flat),
-- the flanks are the place farthest from the band and the place both far
-- from the band and far from it (Siblings): a hill path that climbs away
-- from the bottom corridor and stays apart from it counts for what it is,
-- however near it looks, and a cluster of such places gives one flank, not
-- two. With no such pair, the points FLANK_RADIUS either side of the
-- objective (FixedFlanks).
FLANK_MIN, FLANK_MAX = 400, 1200

function InFlankRange(objective, p)
	local dx, dy = p.x - objective.x, p.y - objective.y
	local flat = sqrt(dx * dx + dy * dy)
	return flat >= FLANK_MIN and flat <= FLANK_MAX
end

-- The flanks of candidates (keys): A, the farthest from the band
-- (separation(key): its walk from it); then B, the one whose least of its
-- separation and its walk from A (walkFrom(A)(key)) is greatest. Two walks
-- searched, whatever the candidates. Nil when no two are off the band and
-- apart.
function Siblings(candidates, separation, walkFrom)
	local a, farthest = nil, 0
	for _, key in ipairs(candidates) do
		if separation(key) > farthest then a, farthest = key, separation(key) end
	end
	if not a then return nil end
	local fromA = walkFrom(a)
	local b, best = nil, 0
	for _, key in ipairs(candidates) do
		if key ~= a then
			local score = min(separation(key), fromA(key))
			if score > best then b, best = key, score end
		end
	end
	if not b then return nil end
	return a, b
end

-- Of places (two or more), the two farthest apart by walk (between), in
-- the places' order; nil for fewer than two, or none apart.
function Farthest(places, between)
	local bestA, bestB, bestWalk = nil, nil, 0
	for i = 1, #places do
		for j = i + 1, #places do
			local walk = between(places[i], places[j])
			if walk > bestWalk then bestA, bestB, bestWalk = places[i], places[j], walk end
		end
	end
	return bestA, bestB
end

-- The flanks with no ground to choose from: FLANK_RADIUS left and right of
-- the objective, across the way in from spawn.
function FixedFlanks(spawn, objective)
	local dx, dy = objective.x - spawn.x, objective.y - spawn.y
	local length = sqrt(dx * dx + dy * dy)
	local lx, ly = -dy / length, dx / length -- the left of the way in
	return Point(objective.x + lx * FLANK_RADIUS, objective.y + ly * FLANK_RADIUS, objective.z),
		Point(objective.x - lx * FLANK_RADIUS, objective.y - ly * FLANK_RADIUS, objective.z)
end

-- The lanes after the direct one, in order: { kind, stops }, routed from
-- spawn through each stop. flanks: the two flank stops; tours: the two
-- places the tours go through (the defenses farthest apart, else the
-- flanks), or nil for no tours (no enemy defenses known); each tour goes on
-- to the enemy spawn nearest it (enemySpawnNear).
function Plans(flanks, tours, enemySpawnNear)
	local plans = {
		{ kind = FLANK, stops = { flanks[1] } },
		{ kind = FLANK, stops = { flanks[2] } },
	}
	if not tours then return plans end
	plans[3] = { kind = TOUR, stops = { tours[1], enemySpawnNear(tours[1]) } }
	plans[4] = { kind = TOUR, stops = { tours[2], enemySpawnNear(tours[2]) } }
	return plans
end

-- A route's points thinned to about WAYPOINT_SPACING apart (the last kept),
-- and its length. clear(a, b): whether a soldier can walk straight from a
-- to b (the controller's hull trace); a point is kept too where skipping it
-- would make the line from the last kept point cut through the world.
function Thin(points, clear)
	local kept, length, since = {}, 0, 0
	for i, p in ipairs(points) do
		if i > 1 then
			local d = Distance(points[i - 1], p)
			length = length + d
			since = since + d
		end
		local nextPoint = points[i + 1]
		if i == 1 or not nextPoint or since >= WAYPOINT_SPACING or not clear(kept[#kept], nextPoint) then
			kept[#kept + 1] = p
			since = 0
		end
	end
	return kept, length
end

-- The lanes a squad of job `role` may take: those of its kinds
-- (JOB_KINDS), or every lane when none of those could be planned.
local function Choices(lanes, role)
	local choices = {}
	for i, lane in ipairs(lanes) do
		if JOB_KINDS[role][lane.kind] then choices[#choices + 1] = i end
	end
	if #choices > 0 then return choices end
	for i = 1, #lanes do choices[i] = i end
	return choices
end

-- Gives each squad of a lane job a lane of its team, keeping the one it has
-- while its team's lanes are the same plan (lanes.key): of the kinds its
-- job takes, the least taken, the first planned on a tie. fireTeams:
-- features.aiwar.model's; lanesByTeam: team -> lanes.
function Assign(fireTeams, lanesByTeam)
	local taken = {}
	local waiting = {}
	for _, fireTeam in ipairs(fireTeams) do
		local lanes = lanesByTeam[fireTeam.team]
		if JOBS[fireTeam.role] and lanes and #lanes > 0 then
			if fireTeam.laneKey == lanes.key and lanes[fireTeam.laneIndex] then
				taken[lanes] = taken[lanes] or {}
				taken[lanes][fireTeam.laneIndex] = (taken[lanes][fireTeam.laneIndex] or 0) + 1
			else
				waiting[#waiting + 1] = fireTeam
			end
		else
			fireTeam.laneKey, fireTeam.laneIndex, fireTeam.lane = nil, nil, nil
		end
	end
	for _, fireTeam in ipairs(waiting) do
		local lanes = lanesByTeam[fireTeam.team]
		taken[lanes] = taken[lanes] or {}
		local best
		for _, i in ipairs(Choices(lanes, fireTeam.role)) do
			if best == nil or (taken[lanes][i] or 0) < (taken[lanes][best] or 0) then best = i end
		end
		taken[lanes][best] = (taken[lanes][best] or 0) + 1
		fireTeam.laneKey, fireTeam.laneIndex = lanes.key, best
	end
	for _, fireTeam in ipairs(fireTeams) do
		local lanes = lanesByTeam[fireTeam.team]
		fireTeam.lane = fireTeam.laneIndex and lanes and lanes[fireTeam.laneIndex] or nil
	end
end

-- The waypoint a walker at pos makes for next, from index: past the ones it
-- has reached, or a nearer one up to LOOKAHEAD further along.
function Next(lane, pos, index)
	local points = lane.points
	index = index or 1
	while points[index] and Distance(pos, points[index]) <= WAYPOINT_REACH do index = index + 1 end
	local best, bestDistance = index, points[index] and Distance(pos, points[index])
	for i = index + 1, index + LOOKAHEAD do
		if points[i] then
			local d = Distance(pos, points[i])
			if d < bestDistance then best, bestDistance = i, d end
		end
	end
	while points[best] and Distance(pos, points[best]) <= WAYPOINT_REACH do best = best + 1 end
	return best
end

-- Where a walker at pos, with index its next waypoint, goes along the
-- lane: the waypoint, or nil once the lane is done (walked to its end, or
-- the waypoint no nearer the lane's end than the walker is). A lane is
-- walked to its own end, so a tour runs on past the objective.
function Target(lane, pos, index)
	local point = lane.points[index]
	if not point then return nil end
	local goal = lane.points[#lane.points]
	if Distance(point, goal) >= Distance(pos, goal) then return nil end
	return point
end
