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

local ACTIVE_KEY = "wetsand.aiwar" -- Global2: the Utilities menu reads it
local THINK_INTERVAL = 0.25
local RELATIONSHIP_INTERVAL = 1
local RELATIONSHIP_PRIORITY = 99

-- HL2's ground NPCs step 18 units and do not jump. A climb above the step
-- height up to jumpHeight is only penalised, since area edges measure a
-- little high on slopes; drops past deathDropHeight are refused, as the
-- engine NPCs will not walk off tall ledges. Both are estimates, not
-- measured in game.
local LIMITS = { stepHeight = 18, jumpHeight = 32, deathDropHeight = 120 }

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
function Soldier:RangeTo(p) return self.ent:GetPos():Distance(ToVector(p)) end

function Soldier:HasEnemy()
	return IsValid(self.ent:GetEnemy()) and self.ent:HasCondition(COND_SEE_ENEMY)
end

-- Pushers and blockers take the fastest route to the cart; everyone else
-- the bot's own (TF2's DEFAULT_ROUTE), which spreads soldiers over routes.
local RUSHING = { [AiWar.PUSH] = true, [AiWar.BLOCK] = true }

function Soldier:Bot()
	local member = self.controller.war:Member(self.ent)
	return {
		entIndex = self.ent:EntIndex(),
		now = CurTime(),
		team = self.team,
		route = member and RUSHING[member.role] and TFBot.FASTEST_ROUTE or TFBot.DEFAULT_ROUTE,
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
		strategy = TFBot,
		limits = LIMITS,
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
-- the last position).
function Soldier:MoveTo(p)
	local ent = self.ent
	if self.moveTarget == p and ent:IsCurrentSchedule(SCHED_FORCED_GO_RUN) then return end
	self.moveTarget = p
	ent:SetLastPosition(ToVector(p))
	ent:SetSchedule(SCHED_FORCED_GO_RUN)
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

-- Each team's first active cart: its path, how far along it is, and the
-- ground under it.
function Controller:Field(phase)
	local carts = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local team = watcher.team
		if watcher:IsActive() and IsValid(watcher:Train()) and #watcher:PathNodes() > 0 and not carts[team] then
			carts[team] = {
				track = self:TrackOf(watcher),
				distance = watcher:TrainDistanceAlongTrack(),
				pos = Point(GroundBelow(watcher:Train():GetPos())),
			}
		end
	end
	return { phase = phase, carts = carts }
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
	self.war:Assign(CartTeams(field.carts))
	self.war:SetField(field)
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
	SetGlobal2Bool(ACTIVE_KEY, true)
	self:OpenDoorsToSoldiers()
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
	self.war = nil
	SetGlobal2Bool(ACTIVE_KEY, false)
	return true
end

-- Hooks ------------------------------------------------------------------------------

hook.Add("Think", "wetsand_aiwar", function()
	if Controller.war then Controller:Think(CurTime()) end
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
	Controller.war:ResetWaves()
end)

-- The round keeps running with no human on a team while the war is on.
hook.Add("TF2HaveCombatants", "wetsand_aiwar", function()
	if Controller.war then return true end
end)

return Controller
