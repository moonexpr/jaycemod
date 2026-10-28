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
-- A path segment's type (GMod's PathFollower goals, NextBot's SegmentType).
local CLIMB_UP = 2
-- A climb begins this near the ledge's foot.
local CLIMB_REACH = 48
local STEP_HEIGHT, JUMP_HEIGHT = 18, 58

if CLIENT then return end

local Relations = nextsoldier.relations
local Vision = nextsoldier.vision
local Intention = nextsoldier.intention
local Factions = WS.require("ws.factions")

-- Its sight: how far, how wide, and how often it looks (TF2's IVision
-- update), how soon it recognizes what it sees and how long it remembers.
local SIGHT_RANGE, FOV_COS = 4000, math.cos(math.rad(60))
local NOTICE_NEAR = 200
-- Its eyes where its model has none (TF2's VEC_VIEW and VEC_DUCK_VIEW, near enough).
local EYE_HEIGHT, CROUCH_EYE_HEIGHT = 64, 28
local LOOK_INTERVAL = 0.2
local VISION = { reaction = 0.1, memory = 8 }
-- A melee weapon's hold types.
local MELEE_HOLDS = { melee = true, melee2 = true, knife = true, fist = true }

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
	self.nsVision = Vision.New(VISION)
	self.nsNextLook = 0
	self.nsWeapons = {}
	self:NSReadRanges()
	if #self.Weapons > 0 then self:SelectWeapon(self:GiveWeapon(self.Weapons[math.random(#self.Weapons)])) end
	self:CustomInitialize()
end

function ENT:IsAlive() return self.nsAlive == true end

-- Hurt: whoever did it is noticed at the next look, wherever it stands.
function ENT:OnInjured(dmg)
	local attacker = dmg:GetAttacker()
	if IsValid(attacker) and attacker ~= self then self.nsAttacker = attacker end
end
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
	if self:NSScrambleUpdate() then return end
	if self:IsAIDisabled() then return end
	self.loco:SetDesiredSpeed(self:ShouldRun() and self.RunSpeed or self.WalkSpeed)
	self:IntentionUpdate(interval)
end

-------------------------------------------------------------------------------
-- Locomotion (ILocomotion): the path followed, priced by the class

function ENT:GetPath() return self.nsPath end

-- A scramble (TF2's ClimbUpToLedge, JumpAcrossGap: a locomotion process
-- carried out over ticks, no coroutine): { duration, at(t) -> position,
-- done() }, its momentum stopped each step; nothing else moves it, and its
-- intention waits, until it ends.
function ENT:Scramble(motion)
	self.nsScramble = { duration = motion.duration, at = motion.at, done = motion.done, began = CurTime() }
end

function ENT:IsScrambling() return self.nsScramble ~= nil end

-- One step of the scramble under way; whether one was.
function ENT:NSScrambleUpdate()
	local scramble = self.nsScramble
	if not scramble then return false end
	local t = math.min(1, (CurTime() - scramble.began) / scramble.duration)
	self.loco:SetVelocity(vector_origin)
	self:SetPos(scramble.at(t))
	if t >= 1 then
		self.nsScramble = nil
		if scramble.done then scramble.done() end
	end
	return true
end

-- A climb up its path's next goal, when the class climbs ledges, asks to
-- (OnStartClimbing) and begins one (CustomClimbing): whether it did.
function ENT:NSClimb(path)
	if not self.ClimbLedges then return false end
	local goal = path:GetCurrentGoal()
	if not goal or goal.type ~= CLIMB_UP then return false end
	local pos = self:GetPos()
	if (pos - goal.pos):Length2D() > CLIMB_REACH then return false end
	local height = goal.pos.z - pos.z
	if height > self.ClimbLedgesMaxHeight or not self:OnStartClimbing(goal.pos, height, false) then return false end
	self:CustomClimbing(goal.pos)
	return self:IsScrambling()
end

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
	if self:NSClimb(path) then return "moving" end
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
	self:NSReadRanges()
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

-- The class's ranges (which OnWeaponChange may set), read again as its
-- weapon changes.
function ENT:NSReadRanges()
	self.nsRanges = Intention.Ranges({
		reach = self.ReachEnemyRange, avoid = self.AvoidEnemyRange, range = self.RangeAttackRange, melee = self.MeleeAttackRange,
	})
end

-- A look around: the hostile entities (its relations' D_HT and D_FR) in its
-- field of view, near it, or that just hurt it, in a clear line, to its
-- vision; vision's events raise the class's hooks.
-- Where it looks from: its model's eyes, else a player's eye height (a
-- NextBot's EyePos is its hips).
function ENT:NSEye()
	local attachment = self:LookupAttachment("eyes")
	if attachment and attachment > 0 then return self:GetAttachment(attachment).Pos end
	return self:GetPos() + Vector(0, 0, self:IsCrouching() and CROUCH_EYE_HEIGHT or EYE_HEIGHT)
end

-- Whether the line from eye to point reaches other (or nothing).
local function Clear(eye, point, self, other)
	local tr = util.TraceLine({ start = eye, endpos = point, mask = MASK_SHOT, filter = self })
	return not tr.Hit or tr.Entity == other
end

-- Another's eyes: a soldier's own, else its EyePos.
local function EyesOf(other)
	if other.NSEye then return other:NSEye() end
	return other:EyePos()
end

-- A look around: its centre or its eyes in a clear line, as TF2's vision
-- tries more than one point of what it looks at.
function ENT:NSLook(now)
	local eye, facing = self:NSEye(), self:GetForward()
	local seen = {}
	for _, other in ipairs(ents.FindInSphere(eye, SIGHT_RANGE)) do
		if other ~= self and (other:IsPlayer() or other:IsNPC() or other:IsNextBot()) and other:Health() > 0
			and not other:IsFlagSet(FL_NOTARGET) then
			local disposition = self:Disposition(other)
			if disposition == D_HT or disposition == D_FR then
				local center = other:WorldSpaceCenter()
				local to = center - eye
				local distance = to:Length()
				if (distance <= NOTICE_NEAR or other == self.nsAttacker or to:Dot(facing) >= FOV_COS * distance)
					and (Clear(eye, center, self, other) or Clear(eye, EyesOf(other), self, other)) then
					seen[other] = other:GetPos()
				end
			end
		end
	end
	self:NSTell(self.nsVision:Update(now, seen, self.nsBetter))
end

-- Vision's events as the class's hooks: sight, and the contact as its enemy.
function ENT:NSTell(events)
	for _, event in ipairs(events) do
		if event.kind == Vision.SIGHT then
			self:OnSpotted(event.handle)
		elseif event.kind == Vision.LOST_SIGHT then
			self:OnLost(event.handle)
		elseif event.kind == Vision.CONTACT then
			self.nsEnemy = event.handle
			self:OnNewEnemy(event.handle)
		elseif event.kind == Vision.CONTACT_LOST then
			self.nsEnemy = nil
			self:OnLastEnemy(event.handle)
		end
	end
end

-- Which of two threats is the more dangerous: the class's OnFetchEnemy,
-- then the higher priority, then the nearer (nextsoldier.intention).
function ENT:NSBetter(a, b)
	return Intention.Better(a, b,
		function(x, y) return self:OnFetchEnemy(x, y) end,
		function(x) local _, priority = self:Disposition(x) return priority end,
		function(x) return self:GetRangeTo(x) end)
end

function ENT:IsMeleeWeapon(weapon)
	return IsValid(weapon) and MELEE_HOLDS[weapon:GetHoldType()] == true
end

-- Each tick with the AI on: a look every LOOK_INTERVAL; with no enemy, the
-- idle hook; with one, the stage of fighting it by its distance (the
-- class's hook, else the base's own: chase it, back away, or face it), then
-- an attack if it is in sight and in range (the class's hook, else the
-- body's).
function ENT:IntentionUpdate(interval)
	local now = CurTime()
	self.nsBetter = self.nsBetter or function(a, b) return self:NSBetter(a, b) end
	if now >= self.nsNextLook then
		self.nsNextLook = now + LOOK_INTERVAL
		local enemy = self.nsEnemy
		if enemy ~= nil and not (IsValid(enemy) and enemy:Health() > 0) then self:NSTell(self.nsVision:Forget(enemy)) end
		self:NSLook(now)
	end
	local enemy = self:GetEnemy()
	if not enemy then
		self:OnIdle()
		return
	end
	local ranges = self.nsRanges
	local distance = self:GetRangeTo(enemy)
	local stage = Intention.Stage(distance, ranges)
	if stage == Intention.CHASE then
		if not self:OnChaseEnemy(enemy) then self:FollowPath(enemy) end
	elseif stage == Intention.AVOID then
		if not self:OnAvoidEnemy(enemy) then
			local away = self:GetPos() + (self:GetPos() - enemy:GetPos()):GetNormalized() * ranges.avoid
			self:FollowPath(away)
		end
	elseif not self:OnIdleEnemy(enemy) then
		self:FaceTowards(enemy)
	end
	local weapon = self:GetActiveWeapon()
	local visible = self.nsVision:Visible(enemy) and self.nsVision:Recognized(enemy, now)
	local attack = Intention.Attack(distance, ranges, visible, self:IsMeleeWeapon(weapon))
	if attack == Intention.MELEE then
		if not self:OnMeleeAttack(enemy, weapon) then self:MeleeAttack(enemy, weapon) end
	elseif attack == Intention.RANGED then
		if not self:OnRangeAttack(enemy) then self:RangeAttack(enemy, weapon) end
	end
end

-- The body's own attacks, which the body slice (L3, our soldier weapons)
-- fills: until then a soldier whose class does not attack does not.
function ENT:RangeAttack(enemy, weapon) end
function ENT:MeleeAttack(enemy, weapon) end

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
-- The path's cost by default: the length of each link, with the class's
-- OnComputePath added (-1 refuses the link, as DrGBase's contract has it).
function ENT:GetPathGenerator()
	return function(area, fromArea, ladder, elevator, length)
		if not IsValid(fromArea) then return 0 end
		local extra = self:OnComputePath(fromArea, area)
		if extra ~= nil and extra < 0 then return -1 end
		local link = length and length > 0 and length or area:GetCenter():Distance(fromArea:GetCenter())
		return fromArea:GetCostSoFar() + link + (extra or 0)
	end
end
function ENT:OnComputePath(from, to) return nil end
function ENT:OnStartClimbing(ledge, height, down) return false end
function ENT:CustomClimbing(ledge) return false end
function ENT:OnWeaponChange(old, new) end
function ENT:OnUpdateAnimation() return nil end
function ENT:OnAnimEvent(event, ...) end
function ENT:OnTakeDamage(dmg, hitgroup) return nil end
function ENT:OnTraceAttack(dmg, dir, trace) self.nsHitGroup = trace.HitGroup end
function ENT:OnDealtDamage(victim, dmg) end
function ENT:OnDeath(dmg) end
