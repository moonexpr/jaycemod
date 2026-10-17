-- Lanes: the ways a team's offensive squads (escorts, raiders) take from
-- their spawn, so they come on by several paths instead of all by the
-- shortest. A team plans (Plans) a direct lane to its objective, a flank
-- to either side of it (FLANK_RADIUS beside the objective, left and right
-- of the way in), and two tours through the enemy's defenses (its leftmost
-- and rightmost) on to the enemy's spawn nearest each. The aiwar controller
-- routes them one after the other over the nav mesh, each costing more
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
local huge, sqrt = math.huge, math.sqrt
local sort = table.sort
local HL2Path = require("foundation.npc.path.hl2")
local Path = require("foundation.npc.path")
local Distance = require("foundation.core.geometry").Distance
module(...)

LANE_PENALTY = 8
FLANK_RADIUS = 600 -- how far beside the objective a flank lane ends
LANE_SPREAD = 300 -- how far either side of a route its band reaches
WAYPOINT_SPACING, WAYPOINT_REACH, LOOKAHEAD = 300, 160, 2
POCKET_LIMIT = 128 -- fewer areas outside a spawn room leading into an area: a pocket the room encloses

-- The jobs whose squads take lanes (foundation.aiwar's ESCORT, RAID,
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
	local seen, queue, i = { [start] = true }, { start }, 1
	while queue[i] do
		for _, id in ipairs(into(queue[i])) do
			if not seen[id] and open(id) then
				seen[id] = true
				queue[#queue + 1] = id
				if #queue >= POCKET_LIMIT then return false end
			end
		end
		i = i + 1
	end
	return true
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

-- The lanes a team plans, in order: { kind, stops }, routed from spawn
-- through each stop. objective: where the team is going (its front);
-- defenses: the enemy's defense points (its posts, else its front), may be
-- empty; enemySpawnNear(p): the enemy spawn nearest p.
function Plans(spawn, objective, defenses, enemySpawnNear)
	local dx, dy = objective.x - spawn.x, objective.y - spawn.y
	local length = sqrt(dx * dx + dy * dy)
	local lx, ly = -dy / length, dx / length -- the left of the way in
	local plans = {
		{ kind = DIRECT, stops = { objective } },
		{ kind = FLANK, stops = { Point(objective.x + lx * FLANK_RADIUS, objective.y + ly * FLANK_RADIUS, objective.z) } },
		{ kind = FLANK, stops = { Point(objective.x - lx * FLANK_RADIUS, objective.y - ly * FLANK_RADIUS, objective.z) } },
	}
	if #defenses == 0 then return plans end
	local left, right, most, least = nil, nil, -huge, huge
	for _, p in ipairs(defenses) do
		local side = (p.x - spawn.x) * lx + (p.y - spawn.y) * ly
		if side > most then left, most = p, side end
		if side < least then right, least = p, side end
	end
	plans[4] = { kind = TOUR, stops = { left, enemySpawnNear(left) } }
	plans[5] = { kind = TOUR, stops = { right, enemySpawnNear(right) } }
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
-- foundation.aiwar's; lanesByTeam: team -> lanes.
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
