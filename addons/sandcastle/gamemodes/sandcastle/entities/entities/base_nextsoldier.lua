-- base_nextsoldier: NextSoldier's own NextBot base (issue #8 L1,
-- docs/base-nextsoldier-plan.md), implementing the interface our code keeps
-- of DrGBase's (nextsoldier.base) from scratch, organised as TF2's NextBot
-- in source-sdk-2013: the bot (life and relations) and its locomotion,
-- body, vision and intention, each a model or a thin binding to GMod's
-- NextBot, updated every tick from BehaveUpdate. No coroutine runs: TF2
-- runs none per bot.
--
-- A soldier class sets ENT.Base = "base_nextsoldier", its fields (the
-- profile: Models, Weapons, Factions, SpawnHealth, speeds and ranges) and
-- defines the hooks it wants (nextsoldier.base's HOOKS); the base raises
-- them and keeps its own defaults for the ones a class calls through.
AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "NextSoldier"
ENT.Spawnable = false
ENT.IsNextSoldier = true

-- The profile's defaults (nextsoldier.base's FIELDS).
ENT.Models = { "models/player/kleiner.mdl" }
ENT.Weapons = {}
ENT.SpawnHealth = 100
ENT.WalkSpeed = 90
ENT.RunSpeed = 220
ENT.ClimbLedges = false
ENT.ClimbLedgesMaxHeight = 64
ENT.DeathDropHeight = 200
ENT.ReachEnemyRange = 600
ENT.AvoidEnemyRange = 0
ENT.RangeAttackRange = 1500
ENT.MeleeAttackRange = 60
ENT.RagdollOnDeath = true
ENT.Factions = {}

-- The hull of a standing and a crouching player (TF2's VEC_HULL, VEC_DUCK_HULL).
local HULL_MINS, HULL_MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)
local CROUCH_HEIGHT = 36
-- A path is computed again for a goal moved this far, or this old.
local REPATH_DISTANCE, REPATH_AGE = 64, 2
local PATH_LOOKAHEAD = 300
local STEP_HEIGHT, JUMP_HEIGHT = 18, 58

if CLIENT then return end

local Relations = nextsoldier.relations
local Factions = WS.require("ws.factions")

-- Each team's faction, for a player's (a player's faction is its team's).
local function TeamFaction(team)
	for _, entry in ipairs(Factions.ALL) do
		if entry.team == team then return entry.faction end
	end
end

-- The factions another entity is in, for a disposition toward it.
local function FactionsOf(other)
	if other.nsRelations then return other.nsRelations:Factions() end
	if other:IsPlayer() then
		local faction = TeamFaction(WS.TeamOf(other))
		return faction and { faction } or {}
	end
	if other.GetFactions then return other:GetFactions() end
	return {}
end

-------------------------------------------------------------------------------
-- The bot: setup, life, relations

function ENT:Initialize()
	self:SetModel(self.Models[math.random(#self.Models)])
	self:SetHealth(self.SpawnHealth)
	self:SetMaxHealth(self.SpawnHealth)
	self:SetCollisionBounds(HULL_MINS, HULL_MAXS)
	self.loco:SetStepHeight(STEP_HEIGHT)
	self.loco:SetJumpHeight(JUMP_HEIGHT)
	self.loco:SetDeathDropHeight(self.DeathDropHeight)
	self.loco:SetDesiredSpeed(self.WalkSpeed)
	self.nsAlive = true
	self.nsRelations = Relations.New({ default = self.DefaultRelationship or D_NU, ally = D_LI })
	for _, faction in ipairs(self.Factions) do self.nsRelations:Join(faction) end
	self.nsWeapons = {}
	if #self.Weapons > 0 then self:SelectWeapon(self:GiveWeapon(self.Weapons[math.random(#self.Weapons)])) end
	self:CustomInitialize()
end

function ENT:IsAlive() return self.nsAlive == true end
function ENT:IsDead() return not self:IsAlive() end
function ENT:IsDown() return false end

function ENT:AddEntityRelationship(other, disposition, priority) self.nsRelations:SetEntity(other, disposition, priority) end
function ENT:SetFactionRelationship(faction, disposition, priority) self.nsRelations:SetFaction(faction, disposition, priority) end
function ENT:Disposition(other) return self.nsRelations:Disposition(other, FactionsOf) end
function ENT:JoinFaction(faction) self.nsRelations:Join(faction) end
function ENT:LeaveFaction(faction) self.nsRelations:Leave(faction) end
function ENT:GetFactions() return self.nsRelations:Factions() end

-- No coroutine: BehaveStart starts nothing, and BehaveUpdate updates the
-- bot each tick, as TF2's INextBot::Update does its components.
function ENT:BehaveStart() end

function ENT:BehaveUpdate(interval)
	if not self:IsAlive() then return end
	self:CustomThink()
	if self:IsAIDisabled() then return end
	self.loco:SetDesiredSpeed(self:ShouldRun() and self.RunSpeed or self.WalkSpeed)
	self:IntentionUpdate(interval)
end

-------------------------------------------------------------------------------
-- Locomotion (ILocomotion): the path followed, priced by the class

function ENT:GetPath() return self.nsPath end

-- Follows a path to goal, computed again when the goal has moved or the path
-- has aged: "unreachable" (no path), "reached", "obstacle" (stuck against
-- something on its way) or "moving".
function ENT:FollowPath(goal, tolerance)
	if isentity(goal) then goal = goal:GetPos() end
	local path = self.nsPath
	if not (path and path:IsValid()) or path:GetAge() > REPATH_AGE
		or (self.nsPathGoal and self.nsPathGoal:DistToSqr(goal) > REPATH_DISTANCE * REPATH_DISTANCE) then
		path = Path("Follow")
		path:SetMinLookAheadDistance(PATH_LOOKAHEAD)
		path:SetGoalTolerance(tolerance or 20)
		path:Compute(self, goal, self:GetPathGenerator())
		self.nsPath, self.nsPathGoal = path, goal
		if not path:IsValid() then return "unreachable" end
	end
	path:Update(self)
	if not path:IsValid() then return "reached" end
	if self.loco:IsStuck() then return "obstacle" end
	return "moving"
end

function ENT:FaceTowards(target)
	if isentity(target) then target = target:GetPos() end
	self.loco:FaceTowards(target)
end

function ENT:IsMoving() return self.loco:GetVelocity():Length2DSqr() > 1 end
function ENT:Jump() self.loco:Jump() end
function ENT:GetStepHeight() return self.loco:GetStepHeight() end
function ENT:GetDeathDropHeight() return self.loco:GetDeathDropHeight() end
function ENT:IsOnGround() return self.loco:IsOnGround() end

-------------------------------------------------------------------------------
-- Body (IBody): weapons held, scale, posture

function ENT:GiveWeapon(class)
	local weapon = ents.Create(class)
	if not IsValid(weapon) then return nil end
	weapon:SetOwner(self)
	weapon:SetPos(self:GetPos())
	weapon:SetParent(self)
	weapon:AddEffects(EF_BONEMERGE)
	weapon:Spawn()
	weapon:SetNoDraw(true)
	self.nsWeapons[class] = weapon
	return weapon
end

function ENT:GetWeapons()
	local list = {}
	for _, weapon in pairs(self.nsWeapons) do
		if IsValid(weapon) then list[#list + 1] = weapon end
	end
	return list
end

function ENT:GetActiveWeapon() return self.nsActive end

function ENT:SelectWeapon(weapon)
	if isstring(weapon) then weapon = self.nsWeapons[weapon] end
	if not IsValid(weapon) or weapon == self.nsActive then return end
	local old = self.nsActive
	if IsValid(old) then old:SetNoDraw(true) end
	weapon:SetNoDraw(false)
	self.nsActive = weapon
	self:OnWeaponChange(old, weapon)
end

function ENT:RemoveWeapon(class)
	local weapon = self.nsWeapons[class]
	self.nsWeapons[class] = nil
	if weapon == self.nsActive then self.nsActive = nil end
	if IsValid(weapon) then weapon:Remove() end
end

function ENT:SetScale(scale) self:SetModelScale(scale) end

-- Posture (IBody's): crouched, the hull a crouching player's.
function ENT:IsCrouching() return self.nsCrouching == true end

function ENT:SetCrouching(crouching)
	crouching = crouching == true
	if crouching == self:IsCrouching() then return end
	self.nsCrouching = crouching
	local maxs = Vector(HULL_MAXS.x, HULL_MAXS.y, crouching and CROUCH_HEIGHT or HULL_MAXS.z)
	self:SetCollisionBounds(HULL_MINS, maxs)
end

-------------------------------------------------------------------------------
-- Vision (IVision): hearing, range, being no one's target

function ENT:IsDeaf() return self.nsDeaf == true end
function ENT:GetHearingCoefficient() return self:IsDeaf() and 0 or 1 end

function ENT:GetRangeTo(target)
	if isentity(target) then target = target:GetPos() end
	return self:GetPos():Distance(target)
end

function ENT:SetNoTarget(none)
	if none then self:AddFlags(FL_NOTARGET) else self:RemoveFlags(FL_NOTARGET) end
end

-------------------------------------------------------------------------------
-- Intention (IIntention): the enemy, AI on or off

function ENT:GetEnemy() return IsValid(self.nsEnemy) and self.nsEnemy or nil end
function ENT:HasEnemy() return self:GetEnemy() ~= nil end
function ENT:SetAIDisabled(disabled) self.nsAIDisabled = disabled == true end
function ENT:IsAIDisabled() return self.nsAIDisabled == true end

-- Each tick with the AI on: with no enemy, the idle hook.
function ENT:IntentionUpdate(interval)
	if not self:HasEnemy() then self:OnIdle() end
end

-------------------------------------------------------------------------------
-- The hooks' defaults (nextsoldier.base's HOOKS), for a class that does not
-- define one or calls this one through.

function ENT:CustomInitialize() end
function ENT:CustomThink() end
function ENT:OnIdle() end
function ENT:OnNewEnemy(enemy) end
function ENT:OnLastEnemy(enemy) end
function ENT:OnFetchEnemy(a, b) return nil end
function ENT:OnChaseEnemy(enemy) return false end
function ENT:OnAvoidEnemy(enemy) return false end
function ENT:OnIdleEnemy(enemy) return false end
function ENT:OnRangeAttack(enemy) return false end
function ENT:OnMeleeAttack(enemy, weapon) return false end
function ENT:ShouldRun() return false end
function ENT:OnSpotted(ent) end
function ENT:OnLost(ent) end
function ENT:GetPathGenerator() return nil end
function ENT:OnComputePath(from, to) return nil end
function ENT:OnStartClimbing(ledge, height, down) return false end
function ENT:CustomClimbing(ledge) return false end
function ENT:OnWeaponChange(old, new) end
function ENT:OnUpdateAnimation() return nil end
function ENT:OnAnimEvent(event, ...) end
function ENT:OnTakeDamage(dmg, hitgroup) return nil end
function ENT:OnTraceAttack(dmg, dir, trace) return nil end
function ENT:OnDealtDamage(victim, dmg) end
function ENT:OnDeath(dmg) end
