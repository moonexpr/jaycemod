-- Part of the AI war controller (sv.lua): tracks, the field snapshot, lanes, the think and sight.
local Controller, Map, WATCH_INTERVAL = ...
local AiWar = WS.require("foundation.aiwar")
local Teams = WS.require("foundation.teams")
local Track = WS.require("foundation.core.polyline")
local Geometry = WS.require("foundation.core.geometry")
local TFBot = WS.require("foundation.npc.path.tfbot")
local HL2Path = WS.require("foundation.npc.path.hl2")
local Path = WS.require("foundation.npc.path")
local Lanes = WS.require("foundation.aiwar.lanes")
local Explore = WS.require("foundation.aiwar.explore")
local GROUND_PROBE, RED, BLUE = Map.GROUND_PROBE, Map.RED, Map.BLUE
local Point, ToVector, Masks, SpawnSpots = Map.Point, Map.ToVector, Map.Masks, Map.SpawnSpots
local WorldWalkClear, LoadedFeature, StalemateIsRound, GroundBelow = Map.WorldWalkClear, Map.LoadedFeature, Map.StalemateIsRound, Map.GroundBelow
local CartRadius = Map.CartRadius

local THINK_INTERVAL = 0.25
local RELATIONSHIP_INTERVAL = 1

-- The field ------------------------------------------------------------------------

function Controller:TrackOf(watcher)
	local nodes = watcher:PathNodes()
	local track = self.tracks[nodes]
	if not track then
		local points = {}
		for i, node in ipairs(nodes) do points[i] = Point(node:GetPos()) end
		track = Track.New(points)
		self.tracks[nodes] = track
	end
	return track
end

-- The field -----------------------------------------------------------------------------

-- A point's zone: the union of its capture areas' boxes, its center on the
-- ground and its radius ZONE_INSET of the smaller horizontal half extent,
-- so spots taken in it stay inside odd shapes; nil without an area.
local ZONE_INSET = 0.8

local function ZoneOf(areas)
	if #areas == 0 then return nil end
	local mins, maxs = areas[1]:WorldSpaceAABB()
	for i = 2, #areas do
		local low, high = areas[i]:WorldSpaceAABB()
		mins = Vector(math.min(mins.x, low.x), math.min(mins.y, low.y), math.min(mins.z, low.z))
		maxs = Vector(math.max(maxs.x, high.x), math.max(maxs.y, high.y), math.max(maxs.z, high.z))
	end
	local x, y = (mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2
	-- down from the middle of the box: areas often reach below the floor
	local tr = util.TraceLine({
		start = Vector(x, y, (mins.z + maxs.z) / 2),
		endpos = Vector(x, y, mins.z - GROUND_PROBE),
		mask = Masks().brushes,
	})
	local center = tr.Hit and tr.HitPos or Vector(x, y, mins.z)
	return {
		center = Point(center),
		radius = ZONE_INSET * math.min(maxs.x - mins.x, maxs.y - mins.y) / 2,
	}
end

-- The points as the capture HUD shows them, in rank order, with where each
-- is (docs/aiwar-koth-cp.md §2.4); nil while the map has no capture feature.
function Controller:PointsSnapshot()
	local capture = LoadedFeature("capture")
	if not capture then return nil end
	local points = {}
	for _, entry in ipairs(capture:HudPoints()) do
		local hud = entry.hud
		points[#points + 1] = {
			id = entry.point,
			rank = entry.rank,
			pos = Point(GroundBelow(entry.point:GetPos())),
			zone = ZoneOf(capture:AreaEntities(entry.point)),
			owner = hud.owner,
			locked = hud.locked,
			unlockAt = hud.unlockTime > 0 and hud.unlockTime or nil,
			capping = hud.capping,
			progress = hud.progress,
			blocked = hud.blocked,
			mayCapture = {
				[RED] = hud.redCanCap,
				[BLUE] = hud.blueCanCap,
			},
			inRound = hud.inRound,
			hidden = hud.hidden,
		}
	end
	return points
end

-- Each team's KOTH clock, as its HUD shows it: { left, running }; nil on a
-- map without team clocks.
local function Clocks(rounds, now)
	local clocks = nil
	for _, team in ipairs({ RED, BLUE }) do
		local clock = rounds:TeamClock(team)
		if clock then
			local timer = rounds:TimerOf(clock)
			clocks = clocks or {}
			clocks[team] = {
				left = timer:TimeRemaining(now),
				running = not timer:Paused(),
			}
		end
	end
	return clocks
end

-- The HUD timer's time left, or nil without one.
local function TimeLeft(rounds, now)
	local hud = rounds:HudTimer()
	return hud and rounds:TimerOf(hud):TimeRemaining(now)
end

-- Each team's spawns on the ground, and its base: their centroid, on the
-- ground (nil for a team without spawns). Kept until the next round.
function Controller:Bases()
	if self.baseCache then return self.baseCache end
	local bases, spawns = {}, {}
	for _, team in ipairs({ RED, BLUE }) do
		local list, sum = {}, Vector(0, 0, 0)
		for i, spot in ipairs(SpawnSpots(team)) do
			local pos = GroundBelow(spot:GetPos())
			list[i] = Point(pos)
			sum = sum + pos
		end
		spawns[team] = list
		if #list > 0 then bases[team] = Point(GroundBelow(sum / #list)) end
	end
	self.baseCache = {
		bases = bases,
		spawns = spawns,
	}
	return self.baseCache
end

-- Each team's first active cart: its path, how far along it is, where its
-- next checkpoint is, and the ground under it; the points, the clocks and
-- the bases (docs/aiwar-koth-cp.md §2.4); the round's winner.
function Controller:Field(phase, now)
	local carts = {}
	self.cartEntities = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local team = watcher.team
		if watcher:IsActive() and IsValid(watcher:Train()) and #watcher:PathNodes() > 0 and not carts[team] then
			self.cartEntities[team] = watcher:Train()
			carts[team] = {
				radius = CartRadius(watcher:Train()),
				track = self:TrackOf(watcher),
				distance = watcher:TrainDistanceAlongTrack(),
				nextCheckpoint = watcher:NextCheckpointDistance(),
				pos = Point(GroundBelow(watcher:Train():GetPos())),
			}
		end
	end
	local posts, forwardPosts = {}, {}
	for _, team in ipairs({ RED, BLUE }) do
		local enemyCart, ownCart = carts[Teams.EnemyOf(team)], carts[team]
		if enemyCart then posts[team] = self:DefendersPosts(team, enemyCart) end
		if ownCart then forwardPosts[team] = self:ForwardPosts(team, ownCart) end
	end
	local rounds = LoadedFeature("rounds")
	local bases = self:Bases()
	return {
		phase = phase,
		now = now,
		setup = WS.Active() and WS.InSetup(),
		carts = carts,
		gates = self.gates or {},
		posts = posts,
		forwardPosts = forwardPosts,
		patients = self:Patients(),
		players = self:Players(),
		points = self:PointsSnapshot(),
		clocks = rounds and Clocks(rounds, now),
		timeLeft = rounds and TimeLeft(rounds, now),
		overtime = WS.InOvertime(),
		bases = bases.bases,
		spawns = bases.spawns,
		winner = self.winner,
		-- arena's: when its point opens, and the waypoints its squads explore
		capEnableAt = rounds and rounds:CapEnableTime(),
		waypoints = self:Waypoints(),
	}
end

-- The nav mesh's area centres, one per Explore.SPACING cell, for arena's
-- squads to explore: sampled once a map, again while there are none (a
-- nav mesh generated after).
function Controller:Waypoints()
	if not self.waypointCache or #self.waypointCache == 0 then
		local centres = {}
		for _, area in ipairs(navmesh.GetAllNavAreas()) do centres[#centres + 1] = Point(area:GetCenter()) end
		self.waypointCache = Explore.Sample(centres, Explore.SPACING)
	end
	return self.waypointCache
end

-- Each side's living players, for the soldiers who follow them (freeform):
-- { handle, pos }.
function Controller:Players()
	local players = { [RED] = {}, [BLUE] = {} }
	for _, ply in ipairs(player.GetAll()) do
		local list = players[WS.TeamOf(ply)]
		if list and ply:Alive() then list[#list + 1] = { handle = ply, pos = Point(ply:GetPos()) } end
	end
	return players
end

-- Each side's soldiers and players, for its medics: { handle, pos, health
-- (a share of their most), player }.
function Controller:Patients()
	local patients = { [RED] = {}, [BLUE] = {} }
	local function Add(team, ent, player)
		local list = patients[team]
		if list and ent:Health() > 0 then
			list[#list + 1] = { handle = ent, pos = Point(ent:GetPos()), health = ent:Health() / math.max(ent:GetMaxHealth(), 1), player = player }
		end
	end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then Add(entry.soldier.team, ent, false) end
	end
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then Add(WS.TeamOf(ply), ply, true) end
	end
	return patients
end

-- Lanes (foundation.aiwar.lanes): each team's ways from its spawn: straight
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

local function Nearest(spots, p)
	local target = ToVector(p)
	local best, bestDistance
	for _, spot in ipairs(spots) do
		local d = spot:GetPos():DistToSqr(target)
		if not bestDistance or d < bestDistance then best, bestDistance = spot, d end
	end
	return best
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

function Controller:PlanLanes(team, to, field, now)
	local own = Nearest(SpawnSpots(team), to)
	if not own then return end
	local from = Point(own:GetPos())
	local enemy = Teams.EnemyOf(team)
	local enemySpawns = SpawnSpots(enemy)
	local function EnemySpawnNear(p) return Point(Nearest(enemySpawns, p):GetPos()) end
	local defenses = #enemySpawns > 0 and self:EnemyDefenses(field, team) or {}
	local npcs = WS.Feature("npc")
	local specs = Lanes.Plans(from, to, defenses, EnemySpawnNear)
	for _, spec in ipairs(specs) do
		for i, stop in ipairs(spec.stops) do spec.stops[i] = self:OutsideRoom(stop, enemy, npcs) end
	end
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
				for i, v in ipairs(npcs:RouteWaypoints(legAreas, stop, found, start)) do
					if i > 1 or #raw == 0 then raw[#raw + 1] = Point(v) end
				end
				if spec.stops[leg + 1] then return Leg(spec, leg + 1, stop, areas, raw, done) end
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
			Try()
		end)
	end
	Try()
end

-- The battlefield this think (docs/aiwar-koth-cp.md §2.2): the round's
-- phase and the field, which the scenario briefs (its doctrine and
-- objectives) and allocates each team's stance from; then the setup
-- gates, the guard posts and the lanes it leads to. Only a whole field is
-- briefed: nil while it lacks a part the scenario awaits (KOTH's clocks,
-- which a KOTH round makes: none in Sandbox mode or between rounds), with
-- the part in waitingFor.
function Controller:Survey(now)
	local phase = AiWar.PhaseOf(WS.Active(), WS.State(), self.winner, StalemateIsRound())
	local field = self:Field(phase, now)
	self:RefreshCartBounds()
	self.waitingFor = self.scenario:Lacks(field)
	if self.waitingFor then return nil end
	self.scenario:Command(self.war, field, now)
	if field.setup and self.gates == nil then self:FindGates(field) end
	self:GuardPosts(field)
	self:UpdateLanes(field, now)
	return field
end

function Controller:Think(now)
	if self.paused or now < self.nextThink then return end
	self.nextThink = now + THINK_INTERVAL
	local field = self:Survey(now)
	-- the war waits: its soldiers act only on a whole field
	if not field then return end
	self.war:SetField(field)
	if field.phase.reinforce then self:Reinforce(now) end
	if field.phase.sightAll then self:SightAll(now) end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			local member = self.war:Member(ent)
			self:JoinSquad(ent, member)
			self:Equip(ent, entry, member)
			entry.npc:Update(THINK_INTERVAL)
		end
	end
	if now >= self.nextRelations then
		self.nextRelations = now + RELATIONSHIP_INTERVAL
		self:RelatePlayers()
		self:SweepGadgets()
		self:RelateMonsters()
	end
	if now >= (self.nextWatch or 0) then
		self.nextWatch = now + WATCH_INTERVAL
		for ent, entry in pairs(self.soldiers) do
			if IsValid(ent) then self:Watch(ent, entry, now) end
		end
		self:CloseOpenedDoors()
	end
end

-- Sudden death: every live enemy, player or soldier, on each side's hunt
-- board, wherever it hides.
function Controller:SightAll(now)
	local board = self.war.hunt
	for _, ply in ipairs(player.GetAll()) do
		local team = WS.TeamOf(ply)
		local enemy = WS.EnemyOf(team)
		if ply:Alive() and enemy ~= WS.TEAM_UNASSIGNED then board:Report(enemy, ply, ply:GetPos(), now) end
	end
	for ent, entry in pairs(self.soldiers) do
		local enemy = WS.EnemyOf(entry.soldier.team)
		if IsValid(ent) and ent:Health() > 0 and enemy ~= WS.TEAM_UNASSIGNED then board:Report(enemy, ent, ent:GetPos(), now) end
	end
end

-- Hooks ------------------------------------------------------------------------------

hook.Add("Think", "ws_aiwar", function()
	if not Controller.war then return end
	Controller:Think(CurTime())
	Controller:SendDebug(CurTime())
	Controller:SyncSlots(false)
end)
