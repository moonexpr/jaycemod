-- The aiwar feature's controller: a payload round fought by DrGBase
-- NextBot soldiers (wetsand_drg_combine, wetsand_drg_rebel; the war needs
-- DrGBase). It owns the foundation.aiwar War, spawns each side's soldiers at
-- its team's spawns in TF2's respawn waves, enlists any soldier that
-- appears while the war runs (a player's included), gives each a
-- foundation.aiwar.orders Behavior over the soldier port below, and sets who
-- is friend or foe. The rules live in the models; this file only feeds them
-- the round and the carts and turns their answers into the soldiers' goals.
local AiWar = WETSAND.require("foundation.aiwar")
local Track = WETSAND.require("foundation.aiwar.track")
local Orders = WETSAND.require("foundation.aiwar.orders")
local NpcSystem = WETSAND.require("foundation.npc")
local TFBot = WETSAND.require("foundation.npc.path.tfbot")
local HL2Path = WETSAND.require("foundation.npc.path.hl2")
local Posts = WETSAND.require("foundation.aiwar.posts")
local Zone = WETSAND.require("foundation.aiwar.zone")

local ACTIVE_KEY = "wetsand.aiwar" -- Global2: the Utilities menu reads it
local THINK_INTERVAL = 0.25
local RELATIONSHIP_INTERVAL = 1
local RELATIONSHIP_PRIORITY = 99


-- CanWalkTo's sweep: a soldier's hull above its step height, so stairs and
-- slopes pass and walls do not.
local WALK_MINS, WALK_MAXS = Vector(-13, -13, 0), Vector(13, 13, 52)
local WALK_LIFT = Vector(0, 0, 20)
local WALK_MAX_RISE = 40

local SPAWN_MINS, SPAWN_MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)
local SPAWN_LIFT = Vector(0, 0, 4)
local SPAWN_SPREAD, SPAWN_TRIES = 48, 8

local GROUND_PROBE = 256
local SF_TRIGGER_ALLOW_NPCS = 2

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

local DOOR_CLASSES = { func_door = true, func_door_rotating = true, prop_door_rotating = true }

local function IsDoor(ent)
	return DOOR_CLASSES[ent:GetClass()] == true
end

-- Two entities that no longer collide, in physics or in an engine NPC's
-- movement checks (CTraceFilterNav skips pairs in the engine's collision
-- pair table, which logic_collision_pair fills, as Sandbox's No Collide
-- does). The pair goes with either entity.
local function PassThrough(a, b)
	local physA, physB = a:GetPhysicsObject(), b:GetPhysicsObject()
	if not (IsValid(physA) and IsValid(physB)) then return end
	local pair = ents.Create("logic_collision_pair")
	pair:SetKeyValue("startdisabled", "1")
	pair:SetPhysConstraintObjects(physA, physB)
	pair:Spawn()
	pair:Activate()
	pair:Input("DisableCollisions")
	a:DeleteOnRemove(pair)
	b:DeleteOnRemove(pair)
end

-------------------------------------------------------------------------------
-- The soldier port (foundation.aiwar.soldier) over a DrGBase soldier
-- (wetsand_drg_soldier): orders set its target and gait; it walks there on
-- the nav mesh as a NextBot, fighting on the way as DrGBase's human AI.

local Soldier = {}
Soldier.__index = Soldier

function Soldier.New(ent, controller, team)
	return setmetatable({
		ent = ent,
		controller = controller,
		team = team,
		ticket = 0,
		result = nil,
		moveTarget = nil,
		relations = {}, -- player -> disposition last set
	}, Soldier)
end

function Soldier:Now() return CurTime() end
function Soldier:IsAlive() return IsValid(self.ent) and self.ent:Health() > 0 end
function Soldier:Position() return Point(self.ent:GetPos()) end
function Soldier:RangeTo(p) return self.ent:GetPos():Distance(ToVector(p)) end

function Soldier:HasEnemy()
	local ent = self.ent
	local enemy = ent:HasEnemy() and ent:GetEnemy() or nil
	return IsValid(enemy) and ent:Visible(enemy)
end

-- Every soldier takes the fastest route. TF2's DEFAULT_ROUTE weighs each
-- area by up to 101 times its length to spread bots over routes, which
-- leaves the straight-line estimate almost no guidance: the search floods
-- most of the mesh, and on a large map (plr_hightower_event) soldiers
-- waited on searches that gave up and walked to where they had got to.
function Soldier:Bot()
	return {
		entIndex = self.ent:EntIndex(),
		now = CurTime(),
		team = self.team,
		route = TFBot.FASTEST_ROUTE,
		miniBoss = false,
		roundWon = WETSAND.State() == WETSAND.STATE.TEAM_WIN,
		winningTeam = GetGlobal2Int("tf2.winner", WETSAND.TEAM_UNASSIGNED),
	}
end

function Soldier:RequestRoute(goal)
	self.ticket = self.ticket + 1
	self.result = nil
	local ticket, goalPos, npcs = self.ticket, ToVector(goal), WETSAND.Feature("npc")
	local start = self.ent:GetPos()
	local controller = self.controller
	local team = self.team
	self.routeGeneration = self:Generation()
	npcs:RequestRoute({
		avoid = function(area) return controller:UnderCart(area) or controller:ShutDoorIn(area, team) end,
		from = start,
		to = goalPos,
		strategy = HL2Path,
		limits = HL2Path.LIMITS,
		bot = self:Bot(),
		onDone = function(areas, found)
			if self.ticket ~= ticket then return end
			if not areas then
				self.result = false
				return
			end
			local points = {}
			for i, v in ipairs(npcs:RouteWaypoints(areas, goalPos, found, start)) do points[i] = Point(v) end
			self.result = points
		end,
	})
end

function Soldier:RouteResult()
	return self.result
end

-- What the route was planned under: the blockers' changes and the doors
-- found shut.
function Soldier:Generation()
	return WETSAND.Feature("npc"):BlockerGeneration() .. ":" .. (self.controller.shutDoorGeneration or 0)
end

function Soldier:RouteStale()
	return type(self.result) == "table" and self.routeGeneration ~= self:Generation()
end

function Soldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = MASK_NPCSOLID,
		filter = self.ent,
	})
	return not tr.Hit
end

function Soldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = MASK_NPCSOLID,
		filter = self.ent,
	})
	return not tr.Hit
end

-- A nav area over stairs is a ramp, while the steps under it are not, so
-- a point taken from the mesh can lie inside a step. A point is dropped
-- onto the floor found by a trace down from above it, or kept when no
-- floor is found.
local FLOOR_ABOVE, FLOOR_BELOW, FLOOR_CLEARANCE = 32, 64, 2

local function OnFloor(pos)
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, FLOOR_ABOVE),
		endpos = pos - Vector(0, 0, FLOOR_BELOW),
		mask = MASK_NPCSOLID_BRUSHONLY,
	})
	if tr.StartSolid or not tr.Hit then return pos end
	return tr.HitPos + Vector(0, 0, FLOOR_CLEARANCE)
end

local HOP_MINS, HOP_MAXS = Vector(-13, -13, 0), Vector(13, 13, 72)
local HOP_LIFT = Vector(0, 0, 18)
local ARRIVED = 64

-- DrGBase paths on the nav mesh itself: every goal is its own to plan.
function Soldier:PlansRoutes() return true end
function Soldier:RouteStale() return false end

function Soldier:MoveTo(p, gait)
	self.moveTarget = p
	self.gait = gait or "run"
	self.ent.WetsandTarget = OnFloor(ToVector(p))
	self.ent.WetsandRun = self.gait ~= "walk"
end

function Soldier:Release()
	self.moveTarget = nil
	self.walkSpeed = 0
	self.ent.WetsandTarget = nil
	self.ent.WetsandRun = nil
end

-- A soldier-sized box swept between two points above step height under
-- player movement's mask, teammates aside (the observer's recovery test).
function Soldier:Sweep(from, to)
	local controller, ent, team = self.controller, self.ent, self.team
	return util.TraceHull({
		start = from + HOP_LIFT,
		endpos = to + HOP_LIFT,
		mins = HOP_MINS,
		maxs = HOP_MAXS - HOP_LIFT,
		mask = MASK_PLAYERSOLID,
		filter = function(hit)
			if hit == ent then return false end
			local entry = controller.soldiers[hit]
			return not (entry and entry.soldier.team == team)
		end,
	})
end

-- Each tick of a move: the pace, from position (for the report), and the
-- door watchdog for a soldier held up by a door on its way.
local DOOR_HOLD_PROGRESS, DOOR_HOLD_TIME = 16, 1.5

function Soldier:Move(dt)
	local ent, now = self.ent, CurTime()
	local pos = ent:GetPos()
	self.walkSpeed = self.lastPos and pos:Distance(self.lastPos) / math.max(dt, 1e-3) or 0
	self.lastPos = pos
	local anchor = self.holdAnchor
	if not anchor or pos:Distance(anchor.pos) > DOOR_HOLD_PROGRESS then
		self.holdAnchor, self.heldBy = { pos = pos, since = now }, nil
	elseif now - anchor.since >= DOOR_HOLD_TIME then
		local door = self:DoorAhead(self.moveTarget)
		if door then self:HeldByDoor(door) end
	end
end

-- The door between me and p, if one stands in the way.
function Soldier:DoorAhead(p)
	local blocker = self:Blocker(p)
	return IsValid(blocker) and IsDoor(blocker) and blocker or nil
end

-- Stopped by a door: open it if my team may, and after DOOR_STUCK_TIME
-- held by it, label it blocked for my team (the door watchdog, with the
-- controller's shut doors).
local DOOR_STUCK_TIME = 3

function Soldier:HeldByDoor(door)
	local now, held = CurTime(), self.heldBy
	if not held or held.door ~= door then
		held = { door = door, since = now }
		self.heldBy = held
	end
	self.controller:OpenDoorFor(door, self.team)
	if now - held.since >= DOOR_STUCK_TIME then
		self.controller:NoteShutDoor(door, self.team)
		self.heldBy = nil
	end
end

-- For the report: the gait and pace, or why the soldier is not moving.
function Soldier:RunState()
	if self.moveTarget == nil then return nil end
	if self:RangeTo(self.moveTarget) <= ARRIVED then return "at its target" end
	if self.ent.WetsandMoveResult == "unreachable" then return "no nav mesh path to its target" end
	return string.format("%s at %d u/s", self.gait or "run", math.floor(self.walkSpeed or 0))
end

-- What stands between me and p for an NPC's movement (a soldier-sized box
-- above step height, under the NPC's mask, teammates and the enemy aside),
-- and whether a player would pass it (the same sweep under player
-- movement's mask does not hit it).
function Soldier:Blocker(p)
	local controller = self.controller
	local from, to = self.ent:GetPos() + HOP_LIFT, ToVector(p) + HOP_LIFT
	local function NotSoldier(hit) return controller.soldiers[hit] == nil end
	local hit = util.TraceHull({ start = from, endpos = to, mins = HOP_MINS, maxs = HOP_MAXS - HOP_LIFT, mask = MASK_NPCSOLID, filter = NotSoldier })
	if not hit.Hit then return nil, false end
	-- map geometry (func_detail is compiled into it) is the world
	local blocker = hit.HitWorld and game.GetWorld() or hit.Entity
	local function OnlyBlocker(other) return other == blocker end
	local asPlayer = util.TraceHull({ start = from, endpos = to, mins = HOP_MINS, maxs = HOP_MAXS - HOP_LIFT, mask = MASK_PLAYERSOLID, filter = OnlyBlocker })
	if hit.HitWorld then return blocker, not asPlayer.HitWorld end
	return blocker, asPlayer.Entity ~= blocker
end

-- NextBot movement steers round what it can; nothing is passed or hopped.
function Soldier:PassBlocker() return false end
function Soldier:Detour() return nil end
function Soldier:Hop() return false end

-- A random spot on the nav mesh within radius of center, on floor a
-- soldier can walk (no crouch or jump areas).
local PATROL_TRIES = 6

function Soldier:PatrolSpot(center, radius)
	local step = HL2Path.LIMITS.stepHeight
	local areas = navmesh.Find(ToVector(center), radius, step * 4, step * 4)
	if #areas == 0 then return nil end
	for _ = 1, PATROL_TRIES do
		local area = areas[math.random(#areas)]
		if bit.band(area:GetAttributes(), HL2Path.NAV_MESH_CROUCH + HL2Path.NAV_MESH_JUMP) == 0 and not self.controller:UnderCart(area) then
			return Point(area:GetRandomPoint())
		end
	end
	return nil
end

function Soldier:WanderSpot()
	local zone = self.controller:SetupZone(self.team)
	if zone then
		for _ = 1, WANDER_TRIES do
			local area = Zone.PickWeighted(zone, AreaSize, math.random())
			if not self.controller:UnderCart(area) then return Point(area:GetRandomPoint()) end
		end
	end
	local step = HL2Path.LIMITS.stepHeight
	local areas = navmesh.Find(self.ent:GetPos(), WANDER_RADIUS, step, step)
	if #areas == 0 then return nil end
	for _ = 1, WANDER_TRIES do
		local spot = Point(areas[math.random(#areas)]:GetRandomPoint())
		if self:CanWalkTo(spot) then return spot end
	end
	return nil
end

function Soldier:EnemyPosition()
	local enemy = self.ent:GetEnemy()
	return IsValid(enemy) and Point(enemy:GetPos()) or nil
end

function Soldier:HurtSince(t)
	return self.hurtAt ~= nil and self.hurtAt > (t or 0)
end

function Soldier:Hold()
	self:MoveTo(self:Position(), self.gait)
end

-- Cover: the nav mesh's hiding spots in cover (CNavArea::GetHidingSpots)
-- within radius of center, that the threat cannot see from eye height to
-- a crouching soldier's chest, nearest center first, COVER_EXCLUDE clear of
-- the spot to leave.
local HIDING_IN_COVER_SPOT = 1
local THREAT_EYE, COVER_CHEST = Vector(0, 0, 64), Vector(0, 0, 36)
local COVER_EXCLUDE = 96

function Soldier:CoverSpot(center, radius, threat, exclude)
	local c, t = ToVector(center), ToVector(threat)
	local best, bestDistance
	for _, area in ipairs(navmesh.Find(c, radius, 96, 96)) do
		for _, spot in ipairs(area:GetHidingSpots(HIDING_IN_COVER_SPOT) or {}) do
			local d = spot:Distance(c)
			if d <= radius and (not bestDistance or d < bestDistance)
				and not (exclude and spot:Distance(ToVector(exclude)) < COVER_EXCLUDE) then
				local tr = util.TraceLine({ start = t + THREAT_EYE, endpos = spot + COVER_CHEST, mask = MASK_SOLID_BRUSHONLY })
				if tr.Hit then best, bestDistance = spot, d end
			end
		end
	end
	return best and Point(best) or nil
end

-- Poses and following the cart are not yet made for DrGBase soldiers.
function Soldier:Pose() return nil end
function Soldier:Unpose() end
function Soldier:FollowCart() return false end
function Soldier:Unfollow() end
function Soldier:RemoveScript() end

-------------------------------------------------------------------------------
-- Controller

local Controller = {
	war = nil, -- a foundation.aiwar War while the war runs
	soldiers = {}, -- NPC entity -> { soldier = port, npc = foundation.npc Npc }
	doorFlags = {}, -- trigger_multiple -> its spawnflags before the war
	tracks = setmetatable({}, { __mode = "k" }), -- a watcher's path node list -> Track
	nextThink = 0,
	nextRelations = 0,
}

local function TeamSize()
	return GetConVar("wetsand_aiwar_team_size"):GetInt()
end

function Controller:Active()
	return self.war ~= nil
end

-- Relationships ---------------------------------------------------------------

local DISPOSITION = { [AiWar.ALLY] = D_LI, [AiWar.ENEMY_OF] = D_HT, [AiWar.FEAR] = D_FR, [AiWar.NEUTRAL] = D_NU }

function Controller:Disposition(team, otherTeam)
	return DISPOSITION[AiWar.Relation(team, otherTeam, self.losers)]
end

function Controller:RelateSoldiers(ent, team)
	for other, entry in pairs(self.soldiers) do
		if other ~= ent and IsValid(other) then
			ent:AddEntityRelationship(other, self:Disposition(team, entry.soldier.team), RELATIONSHIP_PRIORITY)
			other:AddEntityRelationship(ent, self:Disposition(entry.soldier.team, team), RELATIONSHIP_PRIORITY)
		end
	end
end

-- RED players fight beside the Combine, BLU beside the Resistance, and the
-- rest (spectators, the unassigned) are left alone.
function Controller:RelatePlayers()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			for _, ply in ipairs(player.GetAll()) do
				local disposition = self:Disposition(entry.soldier.team, WETSAND.TeamOf(ply))
				if entry.soldier.relations[ply] ~= disposition then
					entry.soldier.relations[ply] = disposition
					ent:AddEntityRelationship(ply, disposition, RELATIONSHIP_PRIORITY)
				end
			end
		end
	end
end

-- Every soldier toward every other and every player, again (the losers changed).
function Controller:RelateEveryone()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			self:RelateSoldiers(ent, entry.soldier.team)
			entry.soldier.relations = {}
		end
	end
	self.nextRelations = 0
end

-- Humiliation ------------------------------------------------------------------------
-- TF2's losers cannot attack while the winners celebrate (for players,
-- WETSAND.RestrictCommand). A losing soldier stops firing
-- (wetsand_drg_soldier's WetsandDisarmed) and fears its enemies: DrGBase
-- keeps away from what it fears. The winners hunt them.
function Controller:Disarm(ent, entry)
	if entry.disarmed then return end
	entry.disarmed = true
	ent.WetsandDisarmed = true
end

function Controller:Rearm(ent, entry)
	if not entry.disarmed then return end
	entry.disarmed = nil
	ent.WetsandDisarmed = nil
end

-- losers: the team humiliated, or nil for none.
function Controller:Humiliate(losers)
	self.losers = losers
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			if entry.soldier.team == losers then self:Disarm(ent, entry) else self:Rearm(ent, entry) end
		end
	end
	self:RelateEveryone()
end

-- Teammates pass through each other ---------------------------------------------------
-- An engine NPC's movement checks (CTraceFilterNav, ai_utils.cpp) skip any
-- entity it is paired with in the engine's collision pair table, which
-- logic_collision_pair fills (as Sandbox's No Collide does), so a teammate
-- in a doorway no longer blocks a soldier's run. Enemies still collide.
-- Each pair goes with either of its soldiers.

function Controller:PassTeammates(ent, team)
	for other, entry in pairs(self.soldiers) do
		if other ~= ent and IsValid(other) and entry.soldier.team == team then PassThrough(ent, other) end
	end
end

-- Enlisting ---------------------------------------------------------------------

function Controller:Enlist(ent, team, drafted)
	local member = self.war:Enlist(ent, team, drafted)
	local soldier = Soldier.New(ent, self, team)
	self.soldiers[ent] = {
		soldier = soldier,
		npc = NpcSystem.Npc.New(Orders, { war = self.war, member = member }, soldier),
	}
	WETSAND.SetTeamMember(ent, team)
	self:RelateSoldiers(ent, team)
	self:PassTeammates(ent, team)
	self:JoinSquad(ent, member)
	if team == self.losers then self:Disarm(ent, self.soldiers[ent]) end
	self.nextRelations = 0
end

-- The member's fire team, for the report; DrGBase has no squads of its
-- own, so fire teams are the orders' alone.
function Controller:JoinSquad(ent, member)
	ent.wetsandSquad = member and member.fireTeam and member.fireTeam.squad or nil
end

function Controller:Discharge(ent)
	local entry = self.soldiers[ent]
	if not entry then return end
	self.soldiers[ent] = nil
	entry.soldier:Unpose()
	entry.soldier:RemoveScript()
	if IsValid(ent) then self:Rearm(ent, entry) end
	self.war:Discharge(ent)
	entry.npc:Destroy()
	WETSAND.SetTeamMember(ent, nil)
end

-- A Combine or Resistance NPC that appeared on its own (a player spawned
-- it) joins its side, once its spawn has finished.
function Controller:Consider(ent)
	if not self.war or self.soldiers[ent] or not IsValid(ent) or not (ent:IsNPC() or ent:IsNextBot()) then return end
	local team = AiWar.FactionTeam(ent:GetClass())
	if team and ent:Health() > 0 then self:Enlist(ent, team, false) end
end

-- Spawning ------------------------------------------------------------------------

local function Clear(pos)
	local tr = util.TraceHull({
		start = pos + SPAWN_LIFT,
		endpos = pos + SPAWN_LIFT,
		mins = SPAWN_MINS,
		maxs = SPAWN_MAXS,
		mask = MASK_NPCSOLID,
	})
	return not tr.Hit
end

-- The spot itself, else the first clear point on a ring around it.
local function ClearSpotNear(pos)
	if Clear(pos) then return pos end
	for i = 1, SPAWN_TRIES do
		local angle = (i / SPAWN_TRIES) * math.pi * 2
		local candidate = pos + Vector(math.cos(angle), math.sin(angle), 0) * SPAWN_SPREAD
		if Clear(candidate) then return candidate end
	end
	return nil
end

function Controller:Draft(team, pos, ang)
	local draft = self.war:Draft(team)
	local recruit = draft.recruit
	local ent = ents.Create(recruit.class)
	if not IsValid(ent) then return end
	ent:SetPos(pos + SPAWN_LIFT)
	ent:SetAngles(ang)
	ent:Spawn()
	ent:Activate()
	self:Enlist(ent, team, true)
end

-- TF2's respawn wave for the team (0 during setup, when TF2 respawns at
-- once), or none without gamerules. With respawns stopped by an admin, the
-- first wave of a round is the last.
local function WaveLength(team)
	if not IsValid(WETSAND.Rules) then return 0 end
	if WETSAND.Rules:RespawnsDisabled() then return math.huge end
	if WETSAND.InSetup() then return 0 end
	return WETSAND.Rules:GetRespawnWaveMaxLength(team, true)
end

function Controller:Reinforce(now)
	for team, count in pairs(self.war:Reinforcements(now, TeamSize(), WaveLength)) do
		local spots = WETSAND.SpawnPoints(team)
		for i = 1, #spots > 0 and count or 0 do
			local spot = spots[(i - 1) % #spots + 1]
			local pos = ClearSpotNear(spot:GetPos())
			if pos then self:Draft(team, pos, spot:GetAngles()) end
		end
	end
end

-- A new round or stage: every soldier starts again from its side's spawn,
-- as TF2 respawns every player (RoundRespawn). The war's own soldiers are
-- replaced by a fresh wave; the ones players spawned are healed, rearmed
-- and moved to a spawn point (on a stage of a multi-stage map, the new
-- stage's), and their orders start over.
function Controller:RespawnAll()
	self.gates = nil
	self.shutDoors = nil
	self.zones = nil
	self.postCache = nil
	self.losers = nil
	local entries = {}
	for ent, entry in pairs(self.soldiers) do entries[#entries + 1] = { ent = ent, entry = entry } end
	local spots, used = {}, {}
	for _, e in ipairs(entries) do
		local ent, team = e.ent, e.entry.soldier.team
		if IsValid(ent) then
			local drafted = self.war:Member(ent).drafted
			e.entry.soldier:Release()
			self:Discharge(ent)
			if drafted then
				ent:Remove()
			else
				spots[team] = spots[team] or WETSAND.SpawnPoints(team)
				used[team] = (used[team] or 0) + 1
				local spot = spots[team][(used[team] - 1) % math.max(#spots[team], 1) + 1]
				local pos = spot and ClearSpotNear(spot:GetPos())
				if pos then
					ent:SetPos(pos + SPAWN_LIFT)
					ent:SetAngles(spot:GetAngles())
				end
				ent:SetHealth(ent:GetMaxHealth())
				self:Enlist(ent, team, false)
			end
		end
	end
	self:RelateEveryone()
	self.war:ResetWaves()
end

-- The field ------------------------------------------------------------------------

local function GroundBelow(pos)
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, 16),
		endpos = pos - Vector(0, 0, GROUND_PROBE),
		mask = MASK_NPCSOLID_BRUSHONLY,
	})
	return tr.Hit and tr.HitPos or pos
end

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

-- Setup gates -------------------------------------------------------------------------
-- In setup the defending side lines up past the gates the attackers must
-- come through (foundation.aiwar.orders). A gate is the last door on the
-- attackers' route from their spawn to their cart's next checkpoint: the
-- setup gate beyond a spawn door, or the spawn exit on maps whose exits
-- are the gates. Found once per round.

local DOOR_TRACE_LIFT = Vector(0, 0, 36)

-- The last door along the waypoints, where the route passes it.
function Controller:GateAlong(points)
	local gate = nil
	for i = 1, #points - 1 do
		local from, to = points[i] + DOOR_TRACE_LIFT, points[i + 1] + DOOR_TRACE_LIFT
		local tr = util.TraceLine({ start = from, endpos = to, mask = MASK_SOLID, filter = IsDoor })
		local door = tr.Entity
		if IsValid(door) and IsDoor(door) then
			local dir = to - from
			dir.z = 0
			dir:Normalize()
			gate = { pos = Point(tr.HitPos - DOOR_TRACE_LIFT), dir = { x = dir.x, y = dir.y }, door = door }
		end
	end
	return gate
end

-- A team's spawn points far apart: the first and the one farthest from it.
local function SpreadSpawns(team)
	local spawns = WETSAND.SpawnPoints(team)
	local first, far, farthest = spawns[1], nil, -1
	for _, spawn in ipairs(spawns) do
		local d = spawn:GetPos():DistToSqr(first:GetPos())
		if d > farthest then far, farthest = spawn, d end
	end
	return first and { first:GetPos(), far:GetPos() } or {}
end

function Controller:FindGates(field)
	local gates = {}
	self.gates = gates
	local npcs = WETSAND.Feature("npc")
	for team, cart in pairs(field.carts) do
		-- an attacking team: the other side has no cart to push
		if not field.carts[AiWar.EnemyOf(team)] then
			local target = ToVector(cart.track:PointAt(cart.nextCheckpoint or cart.track:Length()))
			for _, from in ipairs(SpreadSpawns(team)) do
				npcs:RequestRoute({
					from = from,
					to = target,
					ignoreBlockers = true, -- the route is looked for through the shut gates
					strategy = HL2Path,
					limits = HL2Path.LIMITS,
					bot = { entIndex = 0, now = CurTime(), team = team, route = TFBot.FASTEST_ROUTE, miniBoss = false, roundWon = false, winningTeam = WETSAND.TEAM_UNASSIGNED },
					onDone = function(areas, found)
						if not areas or self.gates ~= gates then return end
						local gate = self:GateAlong(npcs:RouteWaypoints(areas, target, found))
						if not gate then return end
						gates[team] = gates[team] or {}
						for _, known in ipairs(gates[team]) do
							if known.door == gate.door then return end
						end
						table.insert(gates[team], gate)
					end,
				})
			end
		end
	end
end

-- Forcefields -----------------------------------------------------------------------------

-- TF2's forcefields stop only players, but the engine NPCs' movement takes
-- a visualizer for a wall, so while the war runs they are not solid.
-- Soldiers still keep out of enemy spawn rooms: their routes refuse them.
function Controller:SetForcefieldsPassable(passable)
	for _, visualizer in ipairs(ents.FindByClass("func_respawnroomvisualizer")) do visualizer:SetNotSolid(passable) end
end

-- Carts in the way of routes -------------------------------------------------------------
-- The nav mesh does not know where the carts are, so routes led through
-- them. An area whose centre is under a cart (its bounds widened by
-- CART_MARGIN) counts as blocked for routes, the goal's area aside
-- (a pusher's spot is beside its cart). Refreshed every think.
local CART_MARGIN = Vector(24, 24, 64)

function Controller:RefreshCartBounds()
	local bounds = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local train = watcher:IsActive() and watcher:Train()
		if IsValid(train) then
			local mins, maxs = train:WorldSpaceAABB()
			bounds[#bounds + 1] = { mins = mins - CART_MARGIN, maxs = maxs + CART_MARGIN }
		end
	end
	self.cartBounds = bounds
end

function Controller:UnderCart(area)
	local center = area:GetCenter()
	for _, box in ipairs(self.cartBounds or {}) do
		if center:WithinAABox(box.mins, box.maxs) then return true end
	end
	return false
end

-- The setup zone -------------------------------------------------------------------------
-- The ground behind the setup gates, where the attackers wander in setup
-- (foundation.aiwar.zone): flooded over the nav mesh from the team's spawn
-- points, held back by the shut doors no trigger opens (the setup gates),
-- by what closes areas to routes (locked doors, solid brushes: the npc
-- feature's NavBlocks) and by rises
-- no soldier walks. A flood that reaches the checkpoint the team's cart
-- heads for, or the enemy's spawn, got past a gate standing open, and
-- gives no zone. Taken again every ZONE_REFRESH seconds.
local ZONE_LIMIT, ZONE_REFRESH = 4000, 10
local ZONE_SNAP = 256

local function AreaAt(pos)
	local area = navmesh.GetNearestNavArea(pos, false, ZONE_SNAP, false, true)
	return IsValid(area) and area or nil
end

function Controller:FloodZone(team)
	local npcs = WETSAND.Feature("npc")
	local starts, outside = {}, {}
	for _, spot in ipairs(WETSAND.SpawnPoints(team)) do
		local area = AreaAt(spot:GetPos())
		if area then starts[#starts + 1] = area:GetID() end
	end
	if #starts == 0 then return nil end
	for _, spot in ipairs(WETSAND.SpawnPoints(AiWar.EnemyOf(team))) do
		local area = AreaAt(spot:GetPos())
		if area then outside[area:GetID()] = true end
	end
	local field = self.war:Field()
	local cart = field and field.carts[team]
	if cart then
		local area = AreaAt(ToVector(cart.track:PointAt(cart.nextCheckpoint or cart.track:Length())))
		if area then outside[area:GetID()] = true end
	end
	local function Neighbors(id)
		local area, ids = navmesh.GetNavAreaByID(id), {}
		for _, next in ipairs(area:GetAdjacentAreas()) do
			if area:ComputeAdjacentConnectionHeightChange(next) <= WALK_MAX_RISE then ids[#ids + 1] = next:GetID() end
		end
		return ids
	end
	local function Blocked(id)
		local area = navmesh.GetNavAreaByID(id)
		return npcs:EngineBlocks(area, team) or npcs:NavBlocks(area, team) or npcs:DoorWallIn(area)
	end
	local ids, leaked = Zone.Flood(starts, Neighbors, Blocked, function(id) return outside[id] == true end, ZONE_LIMIT)
	if leaked then return nil end
	local areas = {}
	for i, id in ipairs(ids) do areas[i] = navmesh.GetNavAreaByID(id) end
	return areas
end

-- The team's setup zone, a list of nav areas, or nil.
function Controller:SetupZone(team)
	self.zones = self.zones or {}
	local cached, now = self.zones[team], CurTime()
	if not cached or now >= cached.expires then
		cached = { zone = self:FloodZone(team), expires = now + ZONE_REFRESH }
		self.zones[team] = cached
	end
	return cached.zone
end

-- Opening doors -------------------------------------------------------------------------------
-- The soldiers' own movement sets the ground under them, which touches no
-- trigger, so the trigger that opens a door for a player never sees them.
-- A soldier that walks into a door opens it as that trigger would: only a
-- door a trigger opens (not a setup gate, which map logic opens), not
-- locked, and whose trigger's filter admits the soldier's team (not the
-- enemy's spawn door). Many spawn doors close only when their trigger
-- sees everyone leave, which it never sees of a soldier, so a door a
-- soldier opened is closed again once no soldier or player is within
-- DOOR_CLOSE_RANGE of it.
local DOOR_OPEN_INTERVAL = 1
local DOOR_CLOSE_RANGE = 192

function Controller:OpenDoorFor(door, team)
	local state = WETSAND.Feature("npc"):DoorState(door)
	if not state or state.locked or not state.controlled then return end
	if state.owner and state.owner ~= team then return end
	self.doorOpened = self.doorOpened or setmetatable({}, { __mode = "k" })
	local now = CurTime()
	if now < (self.doorOpened[door] or 0) then return end
	self.doorOpened[door] = now + DOOR_OPEN_INTERVAL
	self.openedDoors = self.openedDoors or setmetatable({}, { __mode = "k" })
	self.openedDoors[door] = true
	door:Fire("Open")
end

function Controller:CloseOpenedDoors()
	for door in pairs(self.openedDoors or {}) do
		if not IsValid(door) then
			self.openedDoors[door] = nil
		else
			local center, near = door:WorldSpaceCenter(), false
			for _, ent in ipairs(ents.FindInSphere(center, DOOR_CLOSE_RANGE)) do
				if self.soldiers[ent] or (ent:IsPlayer() and ent:Alive()) then
					near = true
					break
				end
			end
			if not near then
				self.openedDoors[door] = nil
				door:Fire("Close")
			end
		end
	end
end

-- Doors that stayed shut --------------------------------------------------------------------
-- The door watchdog: a soldier held up by the same door for DOOR_STUCK_TIME
-- (its own try at opening it included, Controller:OpenDoorFor) found it
-- impassable, whatever the blockers made of it (a door map logic shut, a
-- door the soldier's team may not open). The door is labelled blocked for
-- that team: its routes keep off the areas under it, and every route the
-- team planned before is planned again (Soldier:RouteStale). The labels
-- last the round: a new round or stage (RespawnAll, a cleanup) erases them.
local SHUT_DOOR_FLOOR = Vector(0, 0, 32)

function Controller:NoteShutDoor(door, team)
	self.shutDoors = self.shutDoors or {}
	local noted = self.shutDoors[door]
	if not noted then
		local mins, maxs = door:WorldSpaceAABB()
		local areas = {}
		for _, area in ipairs(navmesh.FindInBox(mins - SHUT_DOOR_FLOOR, maxs)) do areas[area:GetID()] = true end
		noted = { areas = areas, teams = {} }
		self.shutDoors[door] = noted
	end
	if noted.teams[team] then return end
	noted.teams[team] = true
	self.shutDoorGeneration = (self.shutDoorGeneration or 0) + 1
end

function Controller:ShutDoorIn(area, team)
	if not self.shutDoors then return false end
	local id = area:GetID()
	for door, noted in pairs(self.shutDoors) do
		if not IsValid(door) then
			self.shutDoors[door] = nil
		elseif noted.areas[id] and noted.teams[team] then
			return true
		end
	end
	return false
end

-- The observer ---------------------------------------------------------------------------------
-- A soldier that fell out of the map, or is wedged where nothing gets it
-- out, is put back: one outside the world, or off the nav mesh for
-- OFF_MESH_TIME, where it last stood on the mesh (on its own side of any
-- wall; the nearest nav area may be beyond one), else at its spawn; one
-- that has tried to move for STRANDED_TIME without getting
-- STRANDED_PROGRESS from where it was, onto the next waypoint of its route
-- when a player could walk there. A soldier recovered again within
-- RELAPSE_TIME goes back to spawn. The mesh leaves gaps along walls and
-- round corners, which a soldier sliding along a wall walks into: it is
-- off the mesh only with no nav area it can see within OFF_MESH_REACH.
local WATCH_INTERVAL = 2
local STRANDED_TIME, STRANDED_PROGRESS = 15, 48
local OFF_MESH_BELOW, OFF_MESH_LIFT = 96, Vector(0, 0, 16)
local OFF_MESH_REACH, OFF_MESH_TIME = 48, 5
local RELAPSE_TIME = 60

local function OnMesh(pos)
	if IsValid(navmesh.GetNavArea(pos + OFF_MESH_LIFT, OFF_MESH_BELOW)) then return true end
	return IsValid(navmesh.GetNearestNavArea(pos + OFF_MESH_LIFT, false, OFF_MESH_REACH, true, true))
end

function Controller:SpawnSpot(team)
	local spots = WETSAND.SpawnPoints(team)
	if #spots == 0 then return nil end
	local spot = spots[math.random(#spots)]
	return ClearSpotNear(spot:GetPos())
end

function Controller:Recover(ent, entry, reason, pos)
	local soldier, now = entry.soldier, CurTime()
	local relapse = soldier.recoveredAt and now - soldier.recoveredAt < RELAPSE_TIME
	if relapse or not pos then
		pos = self:SpawnSpot(soldier.team)
		reason = reason .. (relapse and ", again: back to spawn" or ": back to spawn")
	end
	soldier.recoveredAt = now
	soldier.recoveries = (soldier.recoveries or 0) + 1
	soldier.recoveredWhy = reason
	soldier.watch = nil
	if not pos then
		-- nowhere to put it: the next wave replaces it
		ent:TakeDamage(ent:Health() + 1, game.GetWorld(), game.GetWorld())
		return
	end
	soldier:Release()
	ent:SetPos(pos + SPAWN_LIFT)
	if ent.loco then ent.loco:SetVelocity(vector_origin) end
end

function Controller:Watch(ent, entry, now)
	local soldier = entry.soldier
	local pos = ent:GetPos()
	local inWorld = util.IsInWorld(pos + OFF_MESH_LIFT)
	if inWorld and OnMesh(pos) then
		soldier.lastOnMesh = pos
		soldier.offMeshSince = nil
	else
		soldier.offMeshSince = soldier.offMeshSince or now
		if not inWorld or now - soldier.offMeshSince >= OFF_MESH_TIME then
			soldier.offMeshSince = nil
			local spot = soldier.lastOnMesh and ClearSpotNear(soldier.lastOnMesh)
			return self:Recover(ent, entry, inWorld and "off the nav mesh" or "out of the world", spot)
		end
	end
	local watch = soldier.watch
	if not soldier.moveTarget or not watch or pos:Distance(watch.pos) > STRANDED_PROGRESS then
		soldier.watch = { pos = pos, since = now }
		return
	end
	if now - watch.since < STRANDED_TIME then return end
	local state = entry.npc:State()
	local waypoint = state.route and state.route[math.min((state.routeIndex or 1) + 1, #state.route)]
	local spot = waypoint and ClearSpotNear(OnFloor(ToVector(waypoint)))
	-- never through what would stop a player: a shut door, a wall
	if spot and soldier:Sweep(pos, spot).Hit then spot = nil end
	self:Recover(ent, entry, "stranded", spot)
end

-- Posts: where soldiers establish their line ----------------------------------------------
-- foundation.aiwar.posts picks among the nav mesh's hiding spots (with
-- their cover and sniper flags) and the centres of areas well above or
-- below the place in question (high ground, pits), each tested for a
-- clear line from eye height:
-- - a team's defenders: near the checkpoint the enemy cart heads for,
--   seeing it; found once per checkpoint;
-- - a team's escorts: ahead of its own cart along the track, seeing the
--   cart; found again every FORWARD_STEP the cart moves, so the line is
--   pushed forward with it.
local HIDING_IN_COVER, HIDING_GOOD_SNIPER, HIDING_IDEAL_SNIPER = 1, 2, 4 -- CNavArea hiding spot flags
local POST_EYE, TARGET_EYE = Vector(0, 0, 64), Vector(0, 0, 48)
local HIGH_OR_LOW = 48 -- an area this far above or below the place is high or low ground
local SEARCH_HEIGHT = 1000
local FORWARD_STEP = 200

local function Sees(pos, target)
	local tr = util.TraceLine({ start = pos + POST_EYE, endpos = target + TARGET_EYE, mask = MASK_SOLID_BRUSHONLY })
	return not tr.Hit
end

-- Every candidate spot within radius of center, once each, with its flags.
local function CandidateSpots(center, radius)
	local spots, order = {}, {}
	local function Add(pos, cover, sniper)
		local key = string.format("%d %d %d", pos.x, pos.y, pos.z)
		local spot = spots[key]
		if not spot then
			spot = { pos = pos, cover = false, sniper = 0 }
			spots[key] = spot
			order[#order + 1] = spot
		end
		spot.cover = spot.cover or cover
		spot.sniper = math.max(spot.sniper, sniper)
	end
	for _, area in ipairs(navmesh.Find(center, radius, SEARCH_HEIGHT, SEARCH_HEIGHT)) do
		for _, pos in ipairs(area:GetHidingSpots(HIDING_IN_COVER) or {}) do Add(pos, true, 0) end
		for _, pos in ipairs(area:GetHidingSpots(HIDING_GOOD_SNIPER) or {}) do Add(pos, false, Posts.GOOD_SNIPER) end
		for _, pos in ipairs(area:GetHidingSpots(HIDING_IDEAL_SNIPER) or {}) do Add(pos, false, Posts.IDEAL_SNIPER) end
		local areaCenter = area:GetCenter()
		if math.abs(areaCenter.z - center.z) >= HIGH_OR_LOW then Add(areaCenter, false, 0) end
	end
	return order
end

function Controller:CachedPosts(kind, team, key, find)
	self.postCache = self.postCache or {}
	local cacheKey = kind .. team
	local cached = self.postCache[cacheKey]
	if cached and cached.key == key then return cached.posts end
	local posts = find()
	self.postCache[cacheKey] = { key = key, posts = posts }
	return posts
end

-- Where a team's defenders wait for the enemy cart.
function Controller:DefendersPosts(team, cart)
	if not cart.nextCheckpoint then return nil end
	return self:CachedPosts("defend", team, tostring(cart.track) .. "@" .. cart.nextCheckpoint, function()
		local objective = GroundBelow(ToVector(cart.track:PointAt(cart.nextCheckpoint)))
		local cartPos = ToVector(cart.pos)
		local candidates = {}
		for _, spot in ipairs(CandidateSpots(objective, Posts.MAX_RANGE)) do
			candidates[#candidates + 1] = {
				pos = Point(spot.pos),
				sees = Sees(spot.pos, objective),
				toObjective = spot.pos:Distance(objective),
				toCart = spot.pos:Distance(cartPos),
				elevation = spot.pos.z - objective.z,
				cover = spot.cover,
				sniper = spot.sniper,
			}
		end
		return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX)
	end)
end

-- Where a team's escorts push their line ahead of their own cart.
function Controller:ForwardPosts(team, cart)
	local step = math.floor(cart.distance / FORWARD_STEP)
	return self:CachedPosts("forward", team, tostring(cart.track) .. "@" .. step, function()
		local cartPos = ToVector(cart.pos)
		local ahead = GroundBelow(ToVector(cart.track:PointAt(cart.distance + Posts.MAX_LEAD / 2)))
		local candidates = {}
		for _, spot in ipairs(CandidateSpots(ahead, Posts.MAX_LEAD)) do
			local point = Point(spot.pos)
			candidates[#candidates + 1] = {
				pos = point,
				sees = Sees(spot.pos, cartPos),
				ahead = cart.track:DistanceOf(point) - cart.distance,
				toCart = spot.pos:Distance(cartPos),
				elevation = spot.pos.z - cartPos.z,
				cover = spot.cover,
				sniper = spot.sniper,
			}
		end
		return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX, Posts.ScoreForward)
	end)
end

-- The field -----------------------------------------------------------------------------

-- Each team's first active cart: its path, how far along it is, where its
-- next checkpoint is, and the ground under it.
function Controller:Field(phase)
	local carts = {}
	self.cartEntities = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local team = watcher.team
		if watcher:IsActive() and IsValid(watcher:Train()) and #watcher:PathNodes() > 0 and not carts[team] then
			self.cartEntities[team] = watcher:Train()
			carts[team] = {
				track = self:TrackOf(watcher),
				distance = watcher:TrainDistanceAlongTrack(),
				nextCheckpoint = watcher:NextCheckpointDistance(),
				pos = Point(GroundBelow(watcher:Train():GetPos())),
			}
		end
	end
	local posts, forwardPosts = {}, {}
	for _, team in ipairs({ RED, BLUE }) do
		local enemyCart, ownCart = carts[AiWar.EnemyOf(team)], carts[team]
		if enemyCart then posts[team] = self:DefendersPosts(team, enemyCart) end
		if ownCart then forwardPosts[team] = self:ForwardPosts(team, ownCart) end
	end
	return {
		phase = phase,
		setup = WETSAND.Active() and WETSAND.InSetup(),
		carts = carts,
		gates = self.gates or {},
		posts = posts,
		forwardPosts = forwardPosts,
	}
end

local function CartTeams(carts)
	local teams = {}
	for team in pairs(carts) do teams[team] = true end
	return teams
end

function Controller:Think(now)
	if now < self.nextThink then return end
	self.nextThink = now + THINK_INTERVAL
	local phase = AiWar.PhaseOf(WETSAND.Active(), WETSAND.State())
	local field = self:Field(phase)
	self:RefreshCartBounds()
	if field.setup and self.gates == nil then self:FindGates(field) end
	self.war:Assign(CartTeams(field.carts))
	self.war:SetField(field)
	if phase.reinforce then self:Reinforce(now) end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			self:JoinSquad(ent, self.war:Member(ent))
			entry.npc:Update(THINK_INTERVAL)
		end
	end
	if now >= self.nextRelations then
		self.nextRelations = now + RELATIONSHIP_INTERVAL
		self:RelatePlayers()
	end
	if now >= (self.nextWatch or 0) then
		self.nextWatch = now + WATCH_INTERVAL
		for ent, entry in pairs(self.soldiers) do
			if IsValid(ent) then self:Watch(ent, entry, now) end
		end
		self:CloseOpenedDoors()
	end
end

-- Spawn doors ---------------------------------------------------------------------

-- A team's spawn doors open through trigger_multiples filtered by
-- filter_activator_tfteam, other doors through a trigger_multiple around
-- them (TF2's nav mesh counts a door so overlapped as one anyone opens,
-- foundation.npc.doors), and NPCs only touch triggers flagged for them.
local function AroundADoor(trigger, doors)
	local mins, maxs = trigger:WorldSpaceAABB()
	for _, door in ipairs(doors) do
		local doorMins, doorMaxs = door:WorldSpaceAABB()
		if mins.x <= doorMaxs.x and doorMins.x <= maxs.x and mins.y <= doorMaxs.y and doorMins.y <= maxs.y
			and mins.z <= doorMaxs.z and doorMins.z <= maxs.z then
			return true
		end
	end
	return false
end

function Controller:OpenDoorsToSoldiers()
	local doors = ents.FindByClass("func_door*")
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		local filter = trigger:GetInternalVariable("m_hFilter")
		local teamDoor = IsValid(filter) and filter:GetClass() == "filter_activator_tfteam"
		if self.doorFlags[trigger] == nil and (teamDoor or AroundADoor(trigger, doors)) then
			local flags = trigger:GetSpawnFlags()
			self.doorFlags[trigger] = flags
			trigger:SetKeyValue("spawnflags", tostring(bit.bor(flags, SF_TRIGGER_ALLOW_NPCS)))
		end
	end
end

function Controller:CloseDoorsToSoldiers()
	for trigger, flags in pairs(self.doorFlags) do
		if IsValid(trigger) then trigger:SetKeyValue("spawnflags", tostring(flags)) end
	end
	self.doorFlags = {}
end

-- Starting and ending ------------------------------------------------------------------

-- Returns true, or false and why not.
function Controller:Start()
	if self.war then return false, "the war is already on" end
	if not DrGBase then return false, "the AI war needs DrGBase (Steam Workshop) for its soldiers" end
	if #ents.FindByClass("team_train_watcher") == 0 then return false, "this map has no payload cart" end
	WETSAND.Feature("npc"):CheckNavMesh()
	self.war = AiWar.War.New()
	self.gates = nil
	SetGlobal2Bool(ACTIVE_KEY, true)
	self:OpenDoorsToSoldiers()
	self:SetForcefieldsPassable(true)
	for _, ent in ipairs(ents.GetAll()) do self:Consider(ent) end
	if IsValid(WETSAND.Rules) then WETSAND.Rules:RestartRound() end
	return true
end

-- The war's own soldiers leave; the ones players spawned stay, back under
-- the engine's AI alone.
function Controller:End()
	if not self.war then return false, "no war is on" end
	local entries = {}
	for ent, entry in pairs(self.soldiers) do entries[#entries + 1] = { ent = ent, entry = entry } end
	for _, e in ipairs(entries) do
		if IsValid(e.ent) then
			local drafted = self.war:Member(e.ent).drafted
			e.entry.soldier:Release()
			self:Discharge(e.ent)
			if drafted then e.ent:Remove() end
		end
	end
	self.soldiers = {}
	self.losers = nil
	self:CloseDoorsToSoldiers()
	self:SetForcefieldsPassable(false)
	self.war = nil
	SetGlobal2Bool(ACTIVE_KEY, false)
	return true
end

-- Debugging: wetsand_aiwar_report and wetsand_aiwar_debug ------------------------------

local DEBUG_NET = "wetsand_aiwar_debug"
local DEBUG_INTERVAL = 0.5
local DEBUG_MAX_POINTS = 24
util.AddNetworkString(DEBUG_NET)

local TEAM_LABEL = { [RED] = "RED", [BLUE] = "BLU" }

local function Round(n) return math.floor(n + 0.5) end

-- A soldier described: a heading that says who it is ("BLU npc_citizen
-- #45"), and labelled lines on what it is for, what it is doing, and where
-- its route stands.
function Controller:Describe(ent, entry)
	local member = self.war:Member(ent)
	local state, soldier = entry.npc:State(), entry.soldier
	local route = "none"
	if soldier.result == nil and soldier.ticket > 0 then route = "searching" end
	if soldier.result == false then route = "off the nav mesh" end
	if state.route then route = string.format("waypoint %d of %d", state.routeIndex, #state.route) end
	local heading = string.format("%s %s #%d", TEAM_LABEL[soldier.team], ent:GetClass(), ent:EntIndex())
	local lines = {
		"Role: " .. (member.role and (member.role .. " " .. member.slot) or "none"),
		"Action: " .. entry.npc:Describe(),
		"Route: " .. route,
		"Goal: " .. (state.goal and (Round(soldier:RangeTo(state.goal)) .. " units away") or "none"),
		"Last trip: " .. (state.trip or "none"),
		"Movement: " .. (soldier:RunState() or "left to the engine's AI"),
		"Enemy: " .. (soldier:HasEnemy() and "in sight" or "none in sight"),
	}
	if state.wandering then lines[#lines + 1] = "Setup: wandering until it ends" end
	if state.following then lines[#lines + 1] = "Following: its cart" end
	if state.fighting then
		local fireTeam = member.fireTeam
		lines[#lines + 1] = string.format("Fighting: %s (fire team %s %d)", state.tactic or "?", fireTeam and fireTeam.role or "-", fireTeam and fireTeam.index or 0)
	end
	if state.patrolling then lines[#lines + 1] = "Patrol: walking its rounds near its post until the cart moves" end
	if entry.disarmed then lines[#lines + 1] = "Humiliated: cannot attack, fears the winners" end
	if soldier.failures then
		lines[#lines + 1] = string.format("Engine runs failed: %d refused, %d stalled; last target %s over the node graph",
			soldier.failures.refused or 0, soldier.failures.stalled or 0,
			soldier.graphPath == nil and "untested" or (soldier.graphPath and "had a path" or "had NO path"))
	end
	if soldier.recoveries then lines[#lines + 1] = string.format("Recovered: %d time(s), last %s", soldier.recoveries, soldier.recoveredWhy) end
	if state.hops then lines[#lines + 1] = "Hops: " .. state.hops end
	if state.passed then lines[#lines + 1] = "Let through: " .. state.passed .. " NPC-only blocker(s)" end
	local blocked = self:BlockedBy(soldier)
	if blocked then lines[#lines + 1] = "Blocked by: " .. blocked end
	return heading, lines
end

-- What holds a soldier that is running but barely moving, in words, or nil.
local SLOW_RUN = 20

local function DescribeBlocker(blocker)
	if blocker:IsWorld() then return "map geometry (world brushes, func_detail among them)" end
	local text = blocker:GetClass()
	if blocker:GetName() ~= "" then text = text .. " '" .. blocker:GetName() .. "'" end
	if blocker:GetClass() == "func_brush" then
		text = text .. string.format(" (solidity %s, excluded NPC '%s', inverted %s)",
			tostring(blocker:GetInternalVariable("m_iSolidity")), tostring(blocker:GetInternalVariable("m_iszExcludedClass")),
			tostring(blocker:GetInternalVariable("m_bInvertExclusion")))
	end
	local door = IsDoor(blocker) and WETSAND.Feature("npc"):DoorState(blocker)
	if door then
		local opener = door.controlled and ("a trigger" .. (door.owner and (" for " .. (TEAM_LABEL[door.owner] or door.owner)) or "")) or "none"
		local routes = door.blocks == nil and "open" or door.blocks == "any" and "closed to everyone" or ("closed to " .. (TEAM_LABEL[door.blocks] or door.blocks))
		text = text .. string.format(" (%s%s, opened by %s, routes: %s)", door.closed and "shut" or "open", door.locked and ", locked" or "", opener, routes)
		local noted = Controller.shutDoors and Controller.shutDoors[blocker]
		if noted then
			local teams = {}
			for team in pairs(noted.teams) do teams[#teams + 1] = TEAM_LABEL[team] or tostring(team) end
			text = text .. "; labelled blocked for " .. table.concat(teams, " and ") .. " this round"
		end
	end
	return text
end

function Controller:BlockedBy(soldier)
	local target = soldier.moveTarget
	if not target or soldier:RangeTo(target) <= ARRIVED then return nil end
	if (soldier.walkSpeed or 0) > SLOW_RUN then return nil end
	local blocker, playersPass = soldier:Blocker(target)
	if not blocker then return "nothing in the way (the floor ahead is too steep, too high a step or missing)" end
	return DescribeBlocker(blocker) .. (playersPass and "; a player would pass" or "; blocks players too")
end

function Controller:Report()
	local lines = {}
	local field = self.war:Field()
	lines[1] = string.format("AI war on %s: phase %s, %d nav areas, %d spawn-door triggers open to NPCs, %d route searches running",
		game.GetMap(), field and field.phase.name or "none", navmesh.GetNavAreaCount(), table.Count(self.doorFlags),
		WETSAND.Feature("npc"):SearchesRunning())
	for team, cart in pairs(field and field.carts or {}) do
		lines[#lines + 1] = string.format("  %s cart: %d of %d units along its track", TEAM_LABEL[team], Round(cart.distance), Round(cart.track:Length()))
	end
	for team, gates in pairs(self.gates or {}) do
		for _, gate in ipairs(gates) do
			lines[#lines + 1] = string.format("  %s must pass gate %s at (%d, %d, %d)", TEAM_LABEL[team], tostring(gate.door), Round(gate.pos.x), Round(gate.pos.y), Round(gate.pos.z))
		end
	end
	local list = {}
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then list[#list + 1] = { ent = ent, entry = entry } end
	end
	table.sort(list, function(a, b) return a.ent:EntIndex() < b.ent:EntIndex() end)
	for _, item in ipairs(list) do
		local heading, details = self:Describe(item.ent, item.entry)
		lines[#lines + 1] = "  " .. heading
		for _, detail in ipairs(details) do lines[#lines + 1] = "    " .. detail end
	end
	if #list == 0 then lines[#lines + 1] = "  no soldiers" end
	return lines
end

-- The overlay: each soldier's line, goal and remaining route, to the
-- admins who asked for it.
function Controller:SendDebug(now)
	if now < (self.nextDebug or 0) then return end
	self.nextDebug = now + DEBUG_INTERVAL
	local viewers = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply.wetsandAiwarDebug then viewers[#viewers + 1] = ply end
	end
	if #viewers == 0 then return end
	local list = {}
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then list[#list + 1] = { ent = ent, entry = entry } end
	end
	net.Start(DEBUG_NET)
	net.WriteUInt(#list, 8)
	for _, item in ipairs(list) do
		local state = item.entry.npc:State()
		net.WriteEntity(item.ent)
		net.WriteUInt(item.entry.soldier.team, 3)
		local heading, details = self:Describe(item.ent, item.entry)
		net.WriteString(heading)
		net.WriteUInt(#details, 4)
		for _, detail in ipairs(details) do net.WriteString(detail) end
		net.WriteBool(state.goal ~= nil)
		if state.goal then net.WriteVector(ToVector(state.goal)) end
		local route, first = state.route or {}, state.routeIndex or 1
		local last = math.min(#route, first + DEBUG_MAX_POINTS - 1)
		net.WriteUInt(math.max(0, last - first + 1), 8)
		for i = first, last do net.WriteVector(ToVector(route[i])) end
	end
	net.Send(viewers)
end

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

concommand.Add("wetsand_aiwar_report", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	if not Controller.war then
		Tell(ply, { "AI war: not running" })
		return
	end
	Tell(ply, Controller:Report())
	if IsValid(ply) then ply:ChatPrint("AI war: report printed to your console") end
end, nil, "Print every AI war soldier's role, action, route and last trip to the console")

concommand.Add("wetsand_aiwar_debug", function(ply)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	ply.wetsandAiwarDebug = not ply.wetsandAiwarDebug
	ply:ChatPrint("AI war overlay " .. (ply.wetsandAiwarDebug and "on" or "off"))
end, nil, "Toggle drawing each AI war soldier's route, goal and state")

-- Hooks ------------------------------------------------------------------------------

hook.Add("Think", "wetsand_aiwar", function()
	if not Controller.war then return end
	Controller:Think(CurTime())
	Controller:SendDebug(CurTime())
end)

-- Each tick, a moving soldier's pace and the door watchdog.
hook.Add("Tick", "wetsand_aiwar_move", function()
	if not Controller.war then return end
	local dt = engine.TickInterval()
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) and entry.soldier.moveTarget then entry.soldier:Move(dt) end
	end
end)

hook.Add("OnEntityCreated", "wetsand_aiwar", function(ent)
	if not Controller.war or not AiWar.FactionTeam(ent:GetClass()) then return end
	timer.Simple(0, function() Controller:Consider(ent) end)
end)

hook.Add("EntityRemoved", "wetsand_aiwar", function(ent)
	if Controller.war then Controller:Discharge(ent) end
end)

hook.Add("EntityTakeDamage", "wetsand_aiwar", function(target, dmg)
	local entry = Controller.war and Controller.soldiers[target]
	if entry and dmg:GetDamage() > 0 then entry.soldier.hurtAt = CurTime() end
end)

hook.Add("OnNPCKilled", "wetsand_aiwar", function(ent)
	if Controller.war then Controller:Discharge(ent) end
end)

-- A cleanup (every full round reset) removes the soldiers and remakes the
-- map's triggers: the doors are opened again and the first wave comes at once.
hook.Add("PostCleanupMap", "wetsand_aiwar", function()
	if not Controller.war then return end
	Controller.doorFlags = {}
	Controller:OpenDoorsToSoldiers()
	Controller:SetForcefieldsPassable(true)
	Controller.gates = nil
	Controller.zones = nil
	Controller.shutDoors = nil
	Controller.postCache = nil
	Controller.war:ResetWaves()
end)

-- Every round and every stage of a multi-stage map (pl_dustbowl,
-- pl_goldrush) starts with everyone back at spawn: a stage keeps the map
-- as it is, so without this the soldiers would stay where the last stage
-- left them.
hook.Add("TF2RoundActivate", "wetsand_aiwar", function()
	if Controller.war then Controller:RespawnAll() end
end)

hook.Add("TF2RoundWin", "wetsand_aiwar", function(winner)
	if Controller.war then Controller:Humiliate(AiWar.LosersOf(winner)) end
end)

-- The round keeps running with no human on a team while the war is on.
hook.Add("TF2HaveCombatants", "wetsand_aiwar", function()
	if Controller.war then return true end
end)

return Controller
