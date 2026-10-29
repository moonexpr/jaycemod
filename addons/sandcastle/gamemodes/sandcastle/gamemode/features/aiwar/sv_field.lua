-- Part of the AI war controller (sv.lua): tracks, the field snapshot, the think and sight (lanes: sv_lanes.lua).
local Controller, Map, WATCH_INTERVAL = ...
local AiWar = WS.require("features.aiwar.model")
local Teams = gameplay.teams
local Track = math.polyline
local Explore = wartactics.explore
local Scenario = WS.require("features.aiwar.scenario")
local GROUND_PROBE, RED, BLUE = Map.GROUND_PROBE, Map.RED, Map.BLUE
local Point, Masks, SpawnSpots = Map.Point, Map.Masks, Map.SpawnSpots
local LoadedFeature, StalemateIsRound, GroundBelow = Map.LoadedFeature, Map.StalemateIsRound, Map.GroundBelow
local CartRadius, RoundsModeName = Map.CartRadius, Map.RoundsModeName

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

-- Each team's flag and where its carriers capture, as the flag feature
-- holds them (features.aiwar.scenario.ctf's field.flags and field.zones):
-- a flag where it is now (home, dropped on the ground, or with its
-- carrier), a zone's centre on the ground; and its tally, each team's
-- captures this round and the limit (field.captures, field.caplimit); all
-- nil while the map has no flags.
function Controller:FlagsSnapshot()
	local feature = LoadedFeature("flag")
	if not feature then return nil, nil, nil, nil end
	local Flag = WS.require("features.flag.model")
	local flags, zones = {}, {}
	for ent, flag in pairs(feature.flags) do
		local team, carrier = flag:Team(), flag:Carrier()
		if IsValid(ent) and flag:Enabled() and (team == RED or team == BLUE) and not flags[team] then
			flags[team] = {
				team = team,
				home = Point(GroundBelow(ent.wsHome)),
				state = flag:State(),
				pos = Point(IsValid(carrier) and carrier:GetPos() or GroundBelow(ent:GetPos())),
				carrier = carrier,
				carrierTeam = flag:CarrierTeam(),
			}
		end
	end
	for ent, zone in pairs(feature.zones) do
		for _, team in ipairs({ RED, BLUE }) do
			if IsValid(ent) and zone.enabled and not zones[team] and Flag.MayCapture(zone.team, team) then
				zones[team] = Point(GroundBelow(ent:WorldSpaceCenter()))
			end
		end
	end
	local captures = { [RED] = feature.tally:Captures(RED), [BLUE] = feature.tally:Captures(BLUE) }
	return flags, zones, captures, feature:CapLimit()
end

-- The hostages and the zone BLU leads them to, as the hostage feature holds
-- them (features.aiwar.scenario.hostage's field.hostages and field.zones):
-- each { id, home, pos, state, rescuer } with positions as points, and the
-- zone's centre on the ground; nil while the map has no hostages.
function Controller:HostagesSnapshot()
	local feature = LoadedFeature("hostage")
	if not feature then return nil, nil end
	local hostages, zone = feature:Snapshot()
	if #hostages == 0 or not zone then return nil, nil end
	local list = {}
	for i, h in ipairs(hostages) do
		list[i] = { id = h.id, home = Point(h.home), pos = Point(h.pos), state = h.state, rescuer = h.rescuer }
	end
	return list, { [BLUE] = Point(GroundBelow(zone)) }
end

-- Each team's first active cart: its path, how far along it is, where its
-- next checkpoint is, and the ground under it; the points, the clocks and
-- the bases (docs/aiwar-koth-cp.md §2.4); the flags and capture zones; the
-- round's winner.
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
	local flags, zones, captures, caplimit = self:FlagsSnapshot()
	local hostages, hostageZones = self:HostagesSnapshot()
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
		flags = flags,
		zones = zones or hostageZones,
		hostages = hostages,
		captures = captures,
		caplimit = caplimit,
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

-- Each side's living players in play (not watching), for the soldiers who
-- follow them (freeform):
-- { handle, pos }.
function Controller:Players()
	local players = { [RED] = {}, [BLUE] = {} }
	for _, ply in ipairs(player.GetAll()) do
		local list = players[WS.TeamOf(ply)]
		if list and WS.IsAliveInGame(ply) then list[#list + 1] = { handle = ply, pos = Point(ply:GetPos()) } end
	end
	return players
end

-- Each side's soldiers and players, for its medics: { handle, pos, health
-- (a share of their most), player, calling (a soldier that called for a
-- medic) }.
function Controller:Patients()
	local patients = { [RED] = {}, [BLUE] = {} }
	local function Add(team, ent, player, calling)
		local list = patients[team]
		if list and ent:Health() > 0 then
			list[#list + 1] = {
				handle = ent,
				pos = Point(ent:GetPos()),
				health = ent:Health() / math.max(ent:GetMaxHealth(), 1),
				player = player,
				calling = calling,
			}
		end
	end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then Add(entry.soldier.team, ent, false, entry.soldier:CallingMedic()) end
	end
	for _, ply in ipairs(player.GetAll()) do
		if WS.IsAliveInGame(ply) then Add(WS.TeamOf(ply), ply, true, false) end
	end
	return patients
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
	-- the rounds mode can change under the war (a tied match's deathmatch):
	-- the scenario follows it
	local entry, variant = Scenario.Entry(self.scenarios, { mode = RoundsModeName(), field = field })
	field.scenario = entry
	if getmetatable(self.scenario) ~= variant then self.scenario = variant:New() end
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
	self:HazardsThink()
	if field.phase.reinforce then self:Reinforce(now) end
	if field.phase.sightAll then self:SightAll(now) end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			self:NoteFooting(ent)
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
		if WS.IsAliveInGame(ply) and enemy ~= WS.TEAM_UNASSIGNED then board:Report(enemy, ply, ply:GetPos(), now) end
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
