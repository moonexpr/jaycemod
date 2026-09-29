-- The aiwar feature's controller: a payload round fought by HL2's engine
-- NPCs. It owns the foundation.aiwar War, spawns each side's soldiers at its
-- team's spawns in TF2's respawn waves, enlists any Combine or Resistance
-- NPC that appears while the war runs (a player's included), gives each a
-- foundation.aiwar.orders Behavior over the soldier port below, and sets who
-- is friend or foe. The rules live in the models; this file only feeds them
-- the round and the carts and turns their answers into NPC schedules.
local AiWar = WETSAND.require("foundation.aiwar")
local Track = WETSAND.require("foundation.aiwar.track")
local Orders = WETSAND.require("foundation.aiwar.orders")
local NpcSystem = WETSAND.require("foundation.npc")
local TFBot = WETSAND.require("foundation.npc.path.tfbot")
local HL2Path = WETSAND.require("foundation.npc.path.hl2")

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
local SF_NPC_LONG_RANGE, SF_NPC_FADE_CORPSE = 256, 512

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

-------------------------------------------------------------------------------
-- The soldier port (foundation.aiwar.soldier) over an engine NPC

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

-- COND_SEE_ENEMY (ai_condition.h's SCOND_t); GMod defines no global for it.
local COND_SEE_ENEMY = 10

function Soldier:HasEnemy()
	return IsValid(self.ent:GetEnemy()) and self.ent:HasCondition(COND_SEE_ENEMY)
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
	npcs:RequestRoute({
		from = self.ent:GetPos(),
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
			for i, v in ipairs(npcs:RouteWaypoints(areas, goalPos, found)) do points[i] = Point(v) end
			self.result = points
		end,
	})
end

function Soldier:RouteResult()
	return self.result
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

-- A forced run ignores enemies until it arrives (SCHED_FORCED_GO_RUN to
-- the last position). A run already going to within MOVE_RETARGET of p
-- carries on: restarting the schedule every think for a target that moves
-- a little (the cart) would make the NPC stutter.
local MOVE_RETARGET = 24

-- A nav area over stairs is a ramp, while the steps under it are not, so
-- a point taken from the mesh can lie inside a step; the engine refuses a
-- run to a point in solid ground. The target is dropped onto the floor
-- found by a trace down from above it, or kept when no floor is found.
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

function Soldier:MoveTo(p)
	local ent = self.ent
	local current = self.moveTarget
	if current and Track.Distance(current, p) < MOVE_RETARGET and ent:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then return end
	self.moveTarget = p
	ent:SetLastPosition(OnFloor(ToVector(p)))
	ent:SetSchedule(SCHED_FORCED_GO_RUN)
end

-- For the report: whether the forced run is on, or ended away from its
-- target, which means the engine could not build a way there.
local RUN_ENDED_NEAR = 48

function Soldier:RunState()
	if self.moveTarget == nil then return nil end
	if self.ent:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then
		return string.format("running at %d u/s", math.floor(self.ent:GetVelocity():Length2D()))
	end
	if self:RangeTo(self.moveTarget) > RUN_ENDED_NEAR then return "run refused by the engine" end
	return "at its run target"
end

function Soldier:Release()
	if self.moveTarget == nil then return end
	self.moveTarget = nil
	if self.ent:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then self.ent:ClearSchedule() end
end

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

local function Disposition(team, otherTeam)
	if team == otherTeam then return D_LI end
	if AiWar.EnemyOf(team) == otherTeam then return D_HT end
	return D_NU
end

function Controller:RelateSoldiers(ent, team)
	for other, entry in pairs(self.soldiers) do
		if other ~= ent and IsValid(other) then
			local disposition = Disposition(team, entry.soldier.team)
			ent:AddEntityRelationship(other, disposition, RELATIONSHIP_PRIORITY)
			other:AddEntityRelationship(ent, disposition, RELATIONSHIP_PRIORITY)
		end
	end
end

-- RED players fight beside the Combine, BLU beside the Resistance, and the
-- rest (spectators, the unassigned) are left alone.
function Controller:RelatePlayers()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			for _, ply in ipairs(player.GetAll()) do
				local disposition = Disposition(entry.soldier.team, WETSAND.TeamOf(ply))
				if entry.soldier.relations[ply] ~= disposition then
					entry.soldier.relations[ply] = disposition
					ent:AddEntityRelationship(ply, disposition, RELATIONSHIP_PRIORITY)
				end
			end
		end
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
	self.nextRelations = 0
end

function Controller:Discharge(ent)
	local entry = self.soldiers[ent]
	if not entry then return end
	self.soldiers[ent] = nil
	self.war:Discharge(ent)
	entry.npc:Destroy()
	WETSAND.SetTeamMember(ent, nil)
end

-- A Combine or Resistance NPC that appeared on its own (a player spawned
-- it) joins its side, once its spawn has finished.
function Controller:Consider(ent)
	if not self.war or self.soldiers[ent] or not IsValid(ent) or not ent:IsNPC() then return end
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
	if recruit.model then ent:SetModel(recruit.model) end
	for key, value in pairs(recruit.keyvalues or {}) do ent:SetKeyValue(key, value) end
	ent:SetKeyValue("spawnflags", tostring(bit.bor(recruit.spawnflags or 0, SF_NPC_LONG_RANGE, SF_NPC_FADE_CORPSE)))
	ent:SetKeyValue("additionalequipment", recruit.weapon)
	ent:SetKeyValue("squadname", draft.squad)
	ent:Spawn()
	ent:Activate()
	if recruit.skin then ent:SetSkin(recruit.skin) end
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
-- come through (foundation.aiwar.orders). A gate is the first door on the
-- attackers' route from their spawn to their cart's next checkpoint that is
-- not one of their spawn-room doors, found once per round.

local DOOR_CLASSES = { func_door = true, func_door_rotating = true, prop_door_rotating = true }
local DOOR_TRACE_LIFT = Vector(0, 0, 36)
-- A door within this of a team's spawn room is that room's door.
local SPAWN_DOOR_REACH = 96
local REACH_OFFSETS = {
	Vector(0, 0, 0),
	Vector(SPAWN_DOOR_REACH, 0, 0), Vector(-SPAWN_DOOR_REACH, 0, 0),
	Vector(0, SPAWN_DOOR_REACH, 0), Vector(0, -SPAWN_DOOR_REACH, 0),
}

-- The team whose spawn room the door belongs to, or false; found once per
-- door entity (a cleanup makes new ones).
Controller.doorTeams = setmetatable({}, { __mode = "k" })

function Controller:SpawnDoorTeam(door)
	local team = self.doorTeams[door]
	if team ~= nil then return team end
	team = false
	local center = door:WorldSpaceCenter()
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		for _, offset in ipairs(REACH_OFFSETS) do
			if room.team ~= WETSAND.TEAM_UNASSIGNED and room:PointIsWithin(center + offset) then team = room.team end
		end
	end
	self.doorTeams[door] = team
	return team
end

local function IsDoor(ent)
	return DOOR_CLASSES[ent:GetClass()] == true
end

-- The first door along the waypoints that is not a spawn door of team.
function Controller:GateAlong(points, team)
	for i = 1, #points - 1 do
		local from, to = points[i] + DOOR_TRACE_LIFT, points[i + 1] + DOOR_TRACE_LIFT
		local tr = util.TraceLine({ start = from, endpos = to, mask = MASK_SOLID, filter = IsDoor })
		local door = tr.Entity
		if IsValid(door) and IsDoor(door) and self:SpawnDoorTeam(door) ~= team then
			local dir = to - from
			dir.z = 0
			dir:Normalize()
			return { pos = Point(tr.HitPos - DOOR_TRACE_LIFT), dir = { x = dir.x, y = dir.y }, door = door }
		end
	end
	return nil
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
					strategy = HL2Path,
					limits = HL2Path.LIMITS,
					bot = { entIndex = 0, now = CurTime(), team = team, route = TFBot.FASTEST_ROUTE, miniBoss = false, roundWon = false, winningTeam = WETSAND.TEAM_UNASSIGNED },
					onDone = function(areas, found)
						if not areas or self.gates ~= gates then return end
						local gate = self:GateAlong(npcs:RouteWaypoints(areas, target, found), team)
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

-- Spawn doors and forcefields -----------------------------------------------------------

-- A soldier near a door of its own team's spawn room opens it, whatever
-- the map's triggers make of NPCs; other doors (setup gates) stay as the
-- map has them.
local DOOR_OPEN_REACH = 128

function Controller:OpenSpawnDoors()
	for class in pairs(DOOR_CLASSES) do
		for _, door in ipairs(ents.FindByClass(class)) do
			local team = self:SpawnDoorTeam(door)
			if team then
				local center = door:WorldSpaceCenter()
				for ent, entry in pairs(self.soldiers) do
					if entry.soldier.team == team and IsValid(ent) and ent:GetPos():Distance(center) <= DOOR_OPEN_REACH then
						door:Fire("Open")
						break
					end
				end
			end
		end
	end
end

-- TF2's forcefields stop only players, but the engine NPCs' movement takes
-- a visualizer for a wall, so while the war runs they are not solid.
-- Soldiers still keep out of enemy spawn rooms: their routes refuse them.
function Controller:SetForcefieldsPassable(passable)
	for _, visualizer in ipairs(ents.FindByClass("func_respawnroomvisualizer")) do visualizer:SetNotSolid(passable) end
end

-- The field -----------------------------------------------------------------------------

-- Each team's first active cart: its path, how far along it is, where its
-- next checkpoint is, and the ground under it.
function Controller:Field(phase)
	local carts = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local team = watcher.team
		if watcher:IsActive() and IsValid(watcher:Train()) and #watcher:PathNodes() > 0 and not carts[team] then
			carts[team] = {
				track = self:TrackOf(watcher),
				distance = watcher:TrainDistanceAlongTrack(),
				nextCheckpoint = watcher:NextCheckpointDistance(),
				pos = Point(GroundBelow(watcher:Train():GetPos())),
			}
		end
	end
	return { phase = phase, setup = WETSAND.Active() and WETSAND.InSetup(), carts = carts, gates = self.gates or {} }
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
	if field.setup and self.gates == nil then self:FindGates(field) end
	self.war:Assign(CartTeams(field.carts))
	self.war:SetField(field)
	self:OpenSpawnDoors()
	if phase.reinforce then self:Reinforce(now) end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then entry.npc:Update(THINK_INTERVAL) end
	end
	if now >= self.nextRelations then
		self.nextRelations = now + RELATIONSHIP_INTERVAL
		self:RelatePlayers()
	end
end

-- Spawn doors ---------------------------------------------------------------------

-- A team's spawn doors open through trigger_multiples filtered by
-- filter_activator_tfteam, and NPCs only touch triggers flagged for them.
function Controller:OpenDoorsToSoldiers()
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		local filter = trigger:GetInternalVariable("m_hFilter")
		if IsValid(filter) and filter:GetClass() == "filter_activator_tfteam" and self.doorFlags[trigger] == nil then
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

-- One line on a soldier: who, what for, what it is doing, and where its
-- route stands.
function Controller:Describe(ent, entry)
	local member = self.war:Member(ent)
	local state = entry.npc:State()
	local role = member.role and (member.role .. member.slot) or "no role"
	local route = "no route"
	if entry.soldier.result == nil and entry.soldier.ticket > 0 then route = "searching" end
	if entry.soldier.result == false then route = "off the mesh" end
	if state.route then route = string.format("waypoint %d/%d", state.routeIndex, #state.route) end
	local goal = state.goal and Round(entry.soldier:RangeTo(state.goal)) .. "u to goal" or "no goal"
	return string.format("%s %s | %s | %s | %s | %s | last trip: %s%s%s",
		TEAM_LABEL[entry.soldier.team], ent:GetClass(), role, entry.npc:Describe(), route, goal,
		state.trip or "none",
		entry.soldier:RunState() and (" | " .. entry.soldier:RunState()) or "",
		entry.soldier:HasEnemy() and " | enemy in sight" or "")
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
		lines[#lines + 1] = string.format("  #%d %s", item.ent:EntIndex(), self:Describe(item.ent, item.entry))
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
		net.WriteString(self:Describe(item.ent, item.entry))
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

hook.Add("OnEntityCreated", "wetsand_aiwar", function(ent)
	if not Controller.war or not AiWar.FactionTeam(ent:GetClass()) then return end
	timer.Simple(0, function() Controller:Consider(ent) end)
end)

hook.Add("EntityRemoved", "wetsand_aiwar", function(ent)
	if Controller.war then Controller:Discharge(ent) end
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
	Controller.war:ResetWaves()
end)

-- A new mini-round (or round) may put the gates elsewhere.
hook.Add("TF2RoundActivate", "wetsand_aiwar", function()
	if Controller.war then Controller.gates = nil end
end)

-- The round keeps running with no human on a team while the war is on.
hook.Add("TF2HaveCombatants", "wetsand_aiwar", function()
	if Controller.war then return true end
end)

return Controller
