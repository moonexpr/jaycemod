-- Part of the AI war controller (sv.lua): lanes, each team's ways from its spawn (wartactics.lanes).
local Controller, Map = ...
local Teams = gameplay.teams
local Geometry = math.geometry
local Select = list.select
local TFBot = WS.require("foundation.wetsands.path.tfbot")
local HL2Path = WS.require("foundation.wetsands.path.hl2")
local Path = wetsands.path
local Lanes = wartactics.lanes
local Graph = graph.search
local NavSearch = wetsands.navsearch
local RED, BLUE = Map.RED, Map.BLUE
local Point, ToVector, SpawnSpots, WorldWalkClear = Map.Point, Map.ToVector, Map.SpawnSpots, Map.WorldWalkClear

-- Lanes (wartactics.lanes): each team's ways from its spawn: straight
-- to its front (the scenario's Front: on payload its own cart, else the
-- enemy's), to either side of it, and through the enemy's defenses (its
-- posts, else its front) on to the enemy's spawn, planned one after the
-- other, each costing more through the bands of the ones before. A team's lanes
-- are planned again once its front has moved LANE_REPLAN from where they
-- led, or an area they watch (their band, and the door walls they went
-- round: plan.snapshot, each area's blocking when they were planned) has
-- been blocked otherwise for Lanes.CHANGE_SETTLE (Lanes.Settled over the npc
-- feature's BlockerChangesSince: a door that stays shut across a lane, a
-- setup gate that stays open, not a spawn door opening and shutting), and
-- tried again after LANE_RETRY when no route was found; the last lanes found
-- stand until new ones are ready. A change elsewhere only moves their
-- generation on.
local LANE_REPLAN, LANE_RETRY = 1024, 5

local function BlockersStale(plan, npcs, now)
	local snapshot, candidates = plan.snapshot, {}
	local generation = npcs:BlockerGeneration()
	if plan.blockers ~= generation then
		local changes = npcs:BlockerChangesSince(plan.blockers)
		plan.blockers = generation
		for id in pairs(changes or snapshot) do
			if snapshot[id] ~= nil then candidates[id] = true end
		end
	end
	local stale
	stale, plan.pending = Lanes.Settled(candidates, function(id) return npcs:AreaBlocked(id) ~= snapshot[id] end,
		plan.pending or {}, now)
	return stale
end

function Controller:UpdateLanes(field, now)
	self.lanePlans = self.lanePlans or {}
	self.laneSets = self.laneSets or {}
	field.lanes = {}
	local npcs = WS.Feature("npc")
	for _, team in ipairs({ RED, BLUE }) do
		local front = self.scenario:Front(field, team)
		local plan = self.lanePlans[team]
		local stale = plan and not plan.planning and BlockersStale(plan, npcs, now)
		if front and not (plan and plan.planning)
			and (stale or (now >= (plan and plan.retryAt or 0) and (not plan or Geometry.Distance(front, plan.to) > LANE_REPLAN))) then
			self:PlanLanes(team, front, field, now)
		end
		if not front then self.laneSets[team] = nil end
		field.lanes[team] = self.laneSets[team]
	end
end

-- A route's band is found on its own floor: areas a step above or below.
local BAND_STEP = 64

-- Nav areas as Lanes.Band takes them.
local function BandAreas(areas)
	local list = {}
	for i, area in ipairs(areas) do list[i] = { id = area:GetID(), center = area:GetCenter() } end
	return list
end

local function NearAreas(area, radius)
	local list = {}
	for i, other in ipairs(navmesh.Find(area.center, radius, BAND_STEP, BAND_STEP)) do list[i] = { id = other:GetID() } end
	return list
end

-- The enemy's defense points for a team's tours: its posts, else its front.
function Controller:EnemyDefenses(field, team)
	local enemy = Teams.EnemyOf(team)
	local posts = field.posts and field.posts[enemy]
	if posts and #posts > 0 then return posts end
	local front = self.scenario:Front(field, enemy)
	return front and { front } or {}
end

-- Where spawn spots stand, read when a plan begins: its searches run on
-- after, and a spot the map removes meanwhile (a round restart's cleanup)
-- is no entity to read by then.
local function Positions(spots)
	local list = {}
	for i, spot in ipairs(spots) do list[i] = spot:GetPos() end
	return list
end

-- Of positions, the nearest to p, or nil for none.
local function Nearest(positions, p)
	return (Select.Nearest(positions, ToVector(p)))
end

-- A lane stop inside the enemy's spawn room moves to its threshold
-- (Lanes.Threshold): the nearest area outside the room, and not a pocket
-- that only the room, or a climb too high, leads into (Lanes.Enclosed),
-- among those the nav
-- mesh reaches from the stop (navmesh.Find floods out from it) within each of
-- THRESHOLD_RADII in turn, a step or two above or below. The team's route
-- cannot enter the room, so a stop inside it sent the search through every
-- area it could reach first. Tours end at the enemy spawn, and on payload a
-- defender's front is the enemy cart, which starts deep in the room. Each
-- stop's area keeps its threshold for the round (roomExits).
local THRESHOLD_RADII, THRESHOLD_STEP = { 1500, 3000, 6000 }, 256

-- The areas a soldier can walk into the area id from: its two-way
-- neighbours and its one-way incoming connections, but for a climb or a drop
-- past the soldier's limits (Path.Walkable).
local function AreasInto(id)
	local area, list = navmesh.GetNavAreaByID(id), {}
	local function Add(other)
		if Path.Walkable(other:ComputeAdjacentConnectionHeightChange(area), HL2Path.SOLDIER_LIMITS) then
			list[#list + 1] = other:GetID()
		end
	end
	for _, other in ipairs(area:GetAdjacentAreas()) do
		if other:IsConnected(area) then Add(other) end
	end
	for _, other in ipairs(area:GetIncomingConnections()) do Add(other) end
	return list
end

function Controller:OutsideRoom(stop, enemy, npcs)
	local here = navmesh.GetNearestNavArea(ToVector(stop), false, THRESHOLD_STEP, false, true)
	if not (IsValid(here) and npcs:SpawnRoomTeam(here) == enemy) then return stop end
	self.roomExits = self.roomExits or {}
	local known = self.roomExits[here:GetID()]
	if known then return known end
	local threshold = stop
	local function Open(id) return npcs:SpawnRoomTeam(navmesh.GetNavAreaByID(id)) ~= enemy end
	local function Enclosed(id) return Lanes.Enclosed(id, AreasInto, Open) end
	for _, radius in ipairs(THRESHOLD_RADII) do
		local areas = {}
		for i, area in ipairs(navmesh.Find(ToVector(stop), radius, THRESHOLD_STEP, THRESHOLD_STEP)) do
			areas[i] = { id = area:GetID(), center = Point(area:GetCenter()), room = npcs:SpawnRoomTeam(area) }
		end
		threshold = Lanes.Threshold(stop, areas, enemy, Enclosed)
		if threshold ~= stop then break end
	end
	self.roomExits[here:GetID()] = threshold
	return threshold
end

-- The ground round the objective for the flanks: the areas a soldier can
-- walk to it from (flooded back along AreasInto), out of either spawn room,
-- in flank range (Lanes.InFlankRange). The flood may wander GROUND_REACH from
-- it, so a way that winds out and back (up onto a hill) is found. At most
-- GROUND_LIMIT areas are flooded.
local GROUND_REACH, GROUND_LIMIT = Lanes.FLANK_MAX * 2, 2000

function Controller:FlankGround(to, npcs)
	local here = navmesh.GetNearestNavArea(ToVector(to), false, THRESHOLD_STEP, false, true)
	if not IsValid(here) then return {} end
	local function Admit(id)
		local area = navmesh.GetNavAreaByID(id)
		local center = area:GetCenter()
		return Geometry.Distance2D(center, to) <= GROUND_REACH and npcs:SpawnRoomTeam(area) == WS.TEAM_UNASSIGNED
	end
	local ground = {}
	for _, id in ipairs(Graph.Flood({ here:GetID() }, AreasInto, Admit, GROUND_LIMIT)) do
		if Lanes.InFlankRange(to, Point(navmesh.GetNavAreaByID(id):GetCenter())) then ground[#ground + 1] = id end
	end
	return ground
end

-- Walking between areas, for Graph.Distances: each neighbour a soldier can
-- step to, at the distance between the areas' centres. A walk beyond
-- SEPARATION_LIMIT is not followed (Lanes.Siblings reads it as that far).
local SEPARATION_LIMIT = GROUND_REACH * 2

local function WalkEdges(id)
	local area, list = navmesh.GetNavAreaByID(id), {}
	local center = area:GetCenter()
	for _, other in ipairs(area:GetAdjacentAreas()) do
		if Path.Walkable(area:ComputeAdjacentConnectionHeightChange(other), HL2Path.SOLDIER_LIMITS) and WS.NavLinkCrossable(area, other) then
			list[#list + 1] = { node = other:GetID(), cost = center:Distance(other:GetCenter()) }
		end
	end
	return list
end

-- The walks from starts (area ids): on the npc controller's mesh snapshot,
-- which holds the same links, rises and centre distances and the links
-- WS.NavLinkCrossable refuses (navsearch's Distances, native on a server
-- with native/wetsands: on cp_ambush_event 4 ms for walks WalkEdges took
-- 350 ms over, each one call a tick could not break); by WalkEdges only
-- while the snapshot is being built again (seams linked).
local function Walks(npcs, starts)
	if npcs.navMesh then
		return NavSearch.Distances(npcs.navMesh, starts, SEPARATION_LIMIT, HL2Path.SOLDIER_LIMITS, { uncrossable = npcs.navUncrossable })
	end
	return Graph.Distances(starts, WalkEdges, SEPARATION_LIMIT)
end

-- The lanes after the direct one (Lanes.Plans), once it is routed: the flank
-- siblings among the ground, by their walks from the direct lane's band
-- (band: area id -> true; empty when it found no route) and between them;
-- else the fixed flanks. The tours go through the enemy's defenses farthest
-- apart by walk, else the flanks.
function Controller:PlansAfterDirect(from, to, band, defenses, enemySpawnNear, npcs)
	local starts = {}
	for id in pairs(band) do starts[#starts + 1] = id end
	-- a walk beyond the search is at least SEPARATION_LIMIT
	local walks = {}
	local function WalkFrom(a)
		walks[a] = walks[a] or Walks(npcs, { a })
		return function(b) return walks[a][b] or SEPARATION_LIMIT end
	end
	local function Between(a, b) return WalkFrom(a)(b) end
	local function Center(id) return Point(navmesh.GetNavAreaByID(id):GetCenter()) end
	local a, b
	-- no band (the direct lane found no route): nothing to keep out of the way of
	if #starts > 0 then
		local fromBand = Walks(npcs, starts)
		local function Separation(id) return fromBand[id] or SEPARATION_LIMIT end
		a, b = Lanes.Siblings(self:FlankGround(to, npcs), Separation, WalkFrom)
	end
	local flanks
	if a then flanks = { Center(a), Center(b) } else flanks = { Lanes.FixedFlanks(from, to) } end
	if #defenses == 0 then return Lanes.Plans(flanks, nil, enemySpawnNear) end
	local defenseAreas, defenseAt = {}, {}
	for _, p in ipairs(defenses) do
		local area = navmesh.GetNearestNavArea(ToVector(p), false, THRESHOLD_STEP, false, true)
		if IsValid(area) and not defenseAt[area:GetID()] then
			defenseAt[area:GetID()] = p
			defenseAreas[#defenseAreas + 1] = area:GetID()
		end
	end
	local da, db = Lanes.Farthest(defenseAreas, Between)
	return Lanes.Plans(flanks, da and { defenseAt[da], defenseAt[db] } or flanks, enemySpawnNear)
end

function Controller:PlanLanes(team, to, field, now)
	local own = Nearest(Positions(SpawnSpots(team)), to)
	if not own then return end
	local from = Point(own)
	local enemy = Teams.EnemyOf(team)
	local enemySpawns = Positions(SpawnSpots(enemy))
	local function EnemySpawnNear(p) return Point(Nearest(enemySpawns, p)) end
	local defenses = #enemySpawns > 0 and self:EnemyDefenses(field, team) or {}
	local npcs = WS.Feature("npc")
	-- the direct lane first; the rest once it is routed (PlansAfterDirect)
	local function OutOfRooms(specs)
		for _, spec in ipairs(specs) do
			for i, stop in ipairs(spec.stops) do spec.stops[i] = self:OutsideRoom(stop, enemy, npcs) end
		end
		return specs
	end
	local specs = OutOfRooms({ { kind = Lanes.DIRECT, stops = { to } } })
	local plan = { to = to, planning = true, tries = 0, penalized = {}, lanes = { key = team .. ":" .. now },
		blockers = npcs:BlockerGeneration(), snapshot = npcs:DoorWalls(), specs = specs }
	self.lanePlans[team] = plan
	local npcs = WS.Feature("npc")
	local function Finish()
		plan.planning = false
		if #plan.lanes > 0 then
			self.laneSets[team] = plan.lanes
		else
			plan.retryAt = CurTime() + LANE_RETRY
			plan.to = { x = math.huge, y = 0, z = 0 } -- stale: plan again after the retry
		end
	end
	-- Routes leg `leg` of the spec, from `start`, adding to the route so far;
	-- done(route) with the whole route, or with nil when a leg has none.
	local function Leg(spec, leg, start, areas, raw, done)
		local stop = ToVector(spec.stops[leg])
		npcs:RequestRoute({
			-- nor through a shut door nothing opens: a lane is kept for long
			avoid = function(area) return self:UnderCart(area) or npcs:DoorWallIn(area) end,
			-- nor over a link a soldier cannot cross: a players' map's clip along a rail
			crossable = WS.NavLinkCrossable,
			from = start,
			to = stop,
			strategy = Lanes.Strategy,
			limits = HL2Path.SOLDIER_LIMITS,
			bot = { entIndex = 0, now = CurTime(), team = team, route = TFBot.FASTEST_ROUTE, miniBoss = false,
				roundWon = false, winningTeam = WS.TEAM_UNASSIGNED, penalized = plan.penalized },
			onDone = function(legAreas, found)
				-- a new round may have dropped every plan while the search ran
				if not self.lanePlans or self.lanePlans[team] ~= plan then return end
				if not legAreas then return done(nil) end
				for _, area in ipairs(legAreas) do areas[#areas + 1] = area end
				-- each crossing in the middle of its opening (a doorway's centre)
				for i, v in ipairs(npcs:RouteWaypoints(legAreas, stop, found, start, true)) do
					if i > 1 or #raw == 0 then raw[#raw + 1] = Point(v) end
				end
				-- a stop out of reach (past a rail): on from as near as the leg came
				if spec.stops[leg + 1] then return Leg(spec, leg + 1, found and stop or ToVector(raw[#raw]), areas, raw, done) end
				done(areas, raw)
			end,
		})
	end
	local function Try()
		plan.tries = plan.tries + 1
		local spec = plan.specs[plan.tries]
		if not spec then return Finish() end
		Leg(spec, 1, ToVector(from), {}, {}, function(areas, raw)
			if areas then
				local ids = {}
				for i, area in ipairs(areas) do ids[i] = area:GetID() end
				local points, length = Lanes.Thin(raw, WorldWalkClear)
				plan.lanes[#plan.lanes + 1] = { kind = spec.kind, ids = ids, points = points, length = length }
				for id in pairs(Lanes.Band(BandAreas(areas), NearAreas)) do
					plan.penalized[id] = true
					if plan.snapshot[id] == nil then plan.snapshot[id] = npcs:AreaBlocked(id) end
				end
			end
			if plan.tries == 1 then
				-- the direct lane's band is all of penalized yet
				for _, spec in ipairs(OutOfRooms(self:PlansAfterDirect(from, to, plan.penalized, defenses, EnemySpawnNear, npcs))) do
					plan.specs[#plan.specs + 1] = spec
				end
			end
			Try()
		end)
	end
	Try()
end
