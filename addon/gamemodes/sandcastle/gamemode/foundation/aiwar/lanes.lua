-- Lanes: the different ways a team's offensive squads (escorts, raiders)
-- take from their spawn out to their front, so they come on by several
-- paths instead of all by the shortest. The aiwar controller plans a team's
-- lanes one after the other over the nav mesh, each route costing more
-- (LANE_PENALTY) through the band of the routes before it (Band: their
-- areas and those within LANE_SPREAD, so a later route leaves the corridor
-- instead of stepping one area aside; Strategy); it
-- keeps a route as a lane when it shares less than MAX_OVERLAP of its areas
-- with each lane kept and is at most MAX_DETOUR of the shortest. Each squad
-- holds a lane (Assign); its leader walks the lane's waypoints (Next) until
-- going on along it no longer brings it nearer its goal.
--
-- A lane is { ids (its nav areas), points (its waypoints, WAYPOINT_SPACING
-- apart), length }; a team's lanes are { key, [1..n] = lane }. Positions
-- are { x, y, z } tables.
local ipairs, pairs, sort = ipairs, pairs, table.sort
local sqrt = math.sqrt
local HL2Path = require("foundation.npc.path.hl2")
local Path = require("foundation.npc.path")
module(...)

LANES_MAX, LANE_TRIES = 3, 5
MAX_OVERLAP, MAX_DETOUR, LANE_PENALTY = 0.5, 1.6, 8
LANE_SPREAD = 300 -- how far either side of a route its band reaches
WAYPOINT_SPACING, WAYPOINT_REACH, LOOKAHEAD = 300, 160, 2

-- The jobs whose squads take lanes (foundation.aiwar's ESCORT, RAID and
-- ASSAULT: the point scenarios' escort).
JOBS = {
	escort = true,
	raid = true,
	assault = true,
}

local function Distance(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return sqrt(dx * dx + dy * dy + dz * dz)
end

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

-- The share of a's areas that b also takes.
function Overlap(a, b)
	if #a.ids == 0 then return 1 end
	local inB = {}
	for _, id in ipairs(b.ids) do inB[id] = true end
	local shared = 0
	for _, id in ipairs(a.ids) do
		if inB[id] then shared = shared + 1 end
	end
	return shared / #a.ids
end

-- Whether a route makes a lane beside the lanes kept, the shortest route's
-- length being `shortest`.
function Accept(lanes, route, shortest)
	if shortest and route.length > shortest * MAX_DETOUR then return false end
	for _, lane in ipairs(lanes) do
		if Overlap(route, lane) >= MAX_OVERLAP then return false end
	end
	return true
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

-- Gives each squad of a lane job a lane of its team, keeping the one it has
-- while its team's lanes are the same plan (lanes.key): the least taken
-- lane, raiders trying the longest first (the outer ways), escorts the
-- shortest. fireTeams: foundation.aiwar's; lanesByTeam: team -> lanes.
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
		local order = {}
		for i = 1, #lanes do order[i] = i end
		local longestFirst = fireTeam.role == "raid"
		sort(order, function(a, b)
			if longestFirst then return lanes[a].length > lanes[b].length end
			return lanes[a].length < lanes[b].length
		end)
		local best
		for _, i in ipairs(order) do
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

-- Where a walker at pos, with index its next waypoint, goes to reach goal:
-- the waypoint, or nil once the lane is done (walked to its end, or the
-- waypoint no nearer the goal than the walker is).
function Target(lane, pos, index, goal)
	local point = lane.points[index]
	if not point then return nil end
	if Distance(point, goal) >= Distance(pos, goal) then return nil end
	return point
end
