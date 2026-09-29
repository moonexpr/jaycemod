-- wetsand_nextbot: the base of every NPC, a thin binding from a GMod NextBot
-- to its foundation.npc model. It implements the actor port
-- (foundation.npc.actor) with GMod's NextBot machinery, forwards the engine's
-- events to the model, and ticks the model's Behavior from BehaveUpdate (no
-- coroutine). It knows no teams.
--
-- A subclass sets ENT.Variant = "foundation.npc.<variant>", sets its model
-- before calling this Initialize, and gives its config either through
-- Configure(config) before Spawn (the npc controller's Spawn does this) or
-- by overriding Config().
AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.Spawnable = false

-- Clients draw it with base_nextbot's defaults; the rest is the server's.
if CLIENT then return end

-- GMod looks up Entity and NextBot methods before the entity's own table,
-- so the port methods the engine already has (actor.ENGINE) are not defined
-- here, and a helper name must not be an engine method's.

local NAV_BENEATH_LIMIT = 100 -- navmesh.GetNavArea's search below a target
local HOVER_CEILING_PROBE = 1000 -- CEyeballBossLocomotion::MaintainAltitude
local HOVER_GROUND_PROBE = 2000
local HOVER_GROUND_HULL_SCALE = 1.25
local HOVER_MOVE_TRACES = 3 -- CEyeballBossLocomotion::Update's recursion limit
local HOVER_CLOSE_ENOUGH_SQR = 1
local STOPPED_SPEED = 0.01 -- CHeadlessHatmanBody::Update
local PLAYBACK_RATE_MIN, PLAYBACK_RATE_MAX = -4, 12

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Configure(config)
	self.configured = config
end

function ENT:Config()
	return self.configured
end

-------------------------------------------------------------------------------
-- Motion: the variant's LOCOMOTION drives GMod's ground locomotor; HOVER
-- drives a foundation.npc.hover model instead.

local GroundMotion = {}

function GroundMotion.Setup(self, limits)
	local loco = self.loco
	loco:SetDesiredSpeed(limits.runSpeed)
	loco:SetStepHeight(limits.stepHeight)
	loco:SetJumpHeight(limits.jumpHeight)
	loco:SetDeathDropHeight(limits.deathDropHeight)
	loco:SetMaxYawRate(limits.maxYawRate)
	loco:SetAcceleration(limits.acceleration)
	loco:SetDeceleration(limits.deceleration)
end

function GroundMotion.SetDesiredSpeed(self, u) self.loco:SetDesiredSpeed(u) end
function GroundMotion.FaceTowards(self, v) self.loco:FaceTowards(v) end
function GroundMotion.Approach(self, v) self.loco:Approach(v, 1) end
function GroundMotion.IsAttemptingToMove(self) return self.loco:IsAttemptingToMove() end
function GroundMotion.GetGroundSpeed(self) return self.loco:GetVelocity():Length2D() end
function GroundMotion.GroundMotionVector(self) return self.loco:GetGroundMotionVector() end
function GroundMotion.Update(self, interval) end

local HoverMotion = {}

function HoverMotion.Setup(self, cfg)
	self.hover = WETSAND.require("foundation.npc.hover").New(cfg, Vector)
	self.loco:SetGravity(0)
end

function HoverMotion.SetDesiredSpeed(self, u) end
function HoverMotion.Approach(self, v) self.hover:Approach(v, self:GetPos()) end
function HoverMotion.IsAttemptingToMove(self) return false end -- see foundation.npc.hover
function HoverMotion.GetGroundSpeed(self) return self.hover:GetGroundSpeed() end

function HoverMotion.GroundMotionVector(self)
	local v = self.hover:GetVelocity()
	v.z = 0
	return v:GetNormalized()
end

-- CEyeballBossLocomotion::FaceTowards: level, from my centre.
function HoverMotion.FaceTowards(self, v)
	local to = v - self:WorldSpaceCenter()
	to.z = 0
	self:SetAngles(to:Angle())
end

local function HullTrace(self, from, to, mins, maxs)
	return util.TraceHull({
		start = from,
		endpos = to,
		mins = mins,
		maxs = maxs,
		filter = self,
		mask = MASK_NPCSOLID,
	})
end

-- CEyeballBossLocomotion::MaintainAltitude's probes: up to the ceiling, then
-- down from there with a wider hull.
local function HoverGroundZ(self, origin)
	local mins, maxs = self:OBBMins(), self:OBBMaxs()
	local up = HullTrace(self, origin, origin + Vector(0, 0, HOVER_CEILING_PROBE), mins, maxs)
	local ceiling = up.HitPos.z - origin.z
	local s = HOVER_GROUND_HULL_SCALE
	local down = HullTrace(self, origin + Vector(0, 0, ceiling), origin - Vector(0, 0, HOVER_GROUND_PROBE),
		Vector(s * mins.x, s * mins.y, mins.z), Vector(s * maxs.x, s * maxs.y, maxs.z))
	return down.HitPos.z
end

-- CEyeballBossLocomotion::Update: slide along what the move hits, then bounce.
function HoverMotion.Update(self, interval)
	local from = self:GetPos()
	local _, move = self.hover:Step(interval, from, HoverGroundZ(self, from), self.alive)
	local mins, maxs = self:OBBMins(), self:OBBMaxs()
	local goal = from + move
	local normals = Vector(0, 0, 0)
	local hits = 0
	local tr
	for attempt = 1, HOVER_MOVE_TRACES do
		tr = HullTrace(self, from, goal, mins, maxs)
		if not tr.Hit then break end
		hits = hits + 1
		normals = normals + tr.HitNormal
		if tr.StartSolid or goal:DistToSqr(tr.HitPos) < HOVER_CLOSE_ENOUGH_SQR or attempt == HOVER_MOVE_TRACES then break end
		local full = goal - from
		local left = full * (1 - tr.Fraction)
		local unconstrained = full - tr.HitNormal * tr.HitNormal:Dot(left)
		local remaining = from + unconstrained
		if remaining:DistToSqr(tr.HitPos) < HOVER_CLOSE_ENOUGH_SQR then break end
		goal = remaining
	end
	if hits > 0 then self.hover:Bounce(normals:GetNormalized()) end
	self:SetPos(tr.HitPos)
end

-------------------------------------------------------------------------------
-- Binding

function ENT:Initialize()
	self.alive = true
	self.npcs = WETSAND.Feature("npc")
	local variant = WETSAND.require(self.Variant)
	self.npc = self.npcs:Bind(self, self.Variant, self:Config())
	if variant.HOVER then
		self.motion = HoverMotion
		HoverMotion.Setup(self, variant.HOVER)
	else
		self.motion = GroundMotion
		GroundMotion.Setup(self, variant.LOCOMOTION)
	end
	if variant.PATH then
		local bot = { entIndex = self:EntIndex(), now = 0 }
		self.pathCost = self.npcs:EnginePathCost(self, WETSAND.require(variant.PATH), variant.LOCOMOTION, bot)
	end
end

function ENT:OnRemove()
	self.npcs:Unbind(self)
end

function ENT:BehaveStart() end

function ENT:BehaveUpdate(interval)
	self.npc:Update(interval)
	self.motion.Update(self, interval)
end

-- CHeadlessHatmanBody::Update
function ENT:BodyUpdate()
	local speed = self:GetGroundSpeed()
	if speed < STOPPED_SPEED then
		self:SetPoseParameter("move_x", 0)
		self:SetPoseParameter("move_y", 0)
	else
		local motion = self.motion.GroundMotionVector(self)
		self:SetPoseParameter("move_x", motion:Dot(self:GetForward()))
		self:SetPoseParameter("move_y", motion:Dot(self:GetRight()))
	end
	local sequenceSpeed = self:GetSequenceGroundSpeed(self:GetSequence())
	if sequenceSpeed > 0 then
		self:SetPlaybackRate(math.Clamp(speed / sequenceSpeed, PLAYBACK_RATE_MIN, PLAYBACK_RATE_MAX))
	end
	self:FrameAdvance()
end

-- A damage event: plain values, built once. Source's DMG_CRITICAL shares
-- DMG_ACID's bit.
function ENT:DamageEvent(dmg)
	return {
		attacker = dmg:GetAttacker(),
		inflictor = dmg:GetInflictor(),
		amount = dmg:GetDamage(),
		dmgType = dmg:GetDamageType(),
		position = dmg:GetDamagePosition(),
		crit = dmg:IsDamageType(DMG_ACID),
	}
end

function ENT:OnInjured(dmg) self.npc:Event("OnInjured", self:DamageEvent(dmg)) end

-- No ragdoll: the model decides when the body goes.
function ENT:OnKilled(dmg)
	self.alive = false
	self.npc:Event("OnKilled", self:DamageEvent(dmg))
	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
end

function ENT:OnOtherKilled(victim, dmg) self.npc:Event("OnOtherKilled", victim, self:DamageEvent(dmg)) end
function ENT:OnContact(other) self.npc:Event("OnContact", other) end
function ENT:OnStuck() self.npc:Event("OnStuck") end
function ENT:OnUnStuck() self.npc:Event("OnUnStuck") end
function ENT:OnLandOnGround(ground) self.npc:Event("OnLandOnGround", ground) end
function ENT:OnLeaveGround(ground) self.npc:Event("OnLeaveGround", ground) end
function ENT:OnNavAreaChanged(old, new) self.npc:Event("OnNavAreaChanged", new, old) end
function ENT:OnIgnite() self.npc:Event("OnIgnite") end

-------------------------------------------------------------------------------
-- The actor port (foundation.npc.actor.METHODS)

-- time, chance
function ENT:Now() return CurTime() end
function ENT:RandomFloat(lo, hi) return math.Rand(lo, hi) end
function ENT:RandomInt(lo, hi) return math.random(lo, hi) end

-- self
function ENT:IsAlive() return self.alive end
function ENT:GetAbsOrigin() return self:GetPos() end
function ENT:SetAbsOrigin(v) self:SetPos(v) end
function ENT:EyePosition() return self:EyePos() end
function ENT:GetYaw() return self:GetAngles().y end
function ENT:SetYaw(deg) self:SetAngles(Angle(0, deg, 0)) end
function ENT:GetHealth() return self:Health() end
function ENT:GetOwnerEntity() return self:GetOwner() end
function ENT:GetEntIndex() return self:EntIndex() end
function ENT:Shared() return self.npcs:Shared(self.Variant) end
function ENT:Vector(x, y, z) return Vector(x, y, z) end

-- targets
function ENT:IsTargetValid(t) return IsValid(t) end

function ENT:IsTargetAlive(t)
	if t:IsPlayer() then return t:Alive() end
	if t.IsAlive then return t:IsAlive() end
	return t:Health() > 0
end

function ENT:TargetOrigin(t) return t:GetPos() end
function ENT:TargetCenter(t) return t:WorldSpaceCenter() end
function ENT:TargetEyes(t) return t:EyePos() end
function ENT:TargetVelocity(t) return t:GetVelocity() end
function ENT:TargetMaxHealth(t) return t:GetMaxHealth() end
function ENT:TargetIndex(t) return t:EntIndex() end
function ENT:IsTargetOnGround(t) return t:IsOnGround() end

-- relations. INextBot::GetRangeTo: an entity is measured hull to hull, a
-- position from my origin.
function ENT:RangeTo(t)
	if isvector(t) then return self:GetPos():Distance(t) end
	local mine = self:NearestPoint(t:WorldSpaceCenter())
	return t:NearestPoint(mine):Distance(mine)
end

function ENT:IsRangeLessThan(t, r) return self:RangeTo(t) < r end
function ENT:IsRangeGreaterThan(t, r) return self:RangeTo(t) > r end

local function IsActor(ent)
	return ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
end

-- CBaseCombatCharacter::IsLineOfSightClear(pos): with ignoreActors no
-- character blocks (CTraceFilterNoCombatCharacters); otherwise only I and
-- the target are skipped.
local function LineClear(self, to, ignore, ignoreActors)
	local trace = {
		start = self:EyePos(),
		endpos = to,
		filter = { self, ignore },
		mask = MASK_OPAQUE,
	}
	if ignoreActors then
		trace.mask = bit.bor(MASK_OPAQUE, CONTENTS_MONSTER)
		trace.filter = function(ent) return ent ~= ignore and not IsActor(ent) end
	end
	return util.TraceLine(trace).Fraction == 1
end

-- CBaseCombatCharacter::IsLineOfSightClear: its centre, eyes or origin.
function ENT:IsLineOfSightClear(t, ignoreActors)
	if isvector(t) then return LineClear(self, t, nil, ignoreActors) end
	return LineClear(self, t:WorldSpaceCenter(), t, ignoreActors)
		or LineClear(self, t:EyePos(), t, ignoreActors)
		or LineClear(self, t:GetPos(), t, ignoreActors)
end

function ENT:IsOnNavMesh(t, tolerance2D)
	local pos = t:GetPos()
	local area = navmesh.GetNavArea(pos, NAV_BENEATH_LIMIT)
	if not IsValid(area) then return false end
	return (pos - area:GetClosestPointOnArea(pos)):Length2D() <= tolerance2D
end

-- body
function ENT:Activity(name) return util.GetActivityIDByName(name) end
function ENT:IsActivity(act) return self:GetActivity() == act end
function ENT:IsActivityFinished() return self:IsSequenceFinished() end

function ENT:PlaySequence(seq)
	self:ResetSequence(self:LookupSequence(seq))
	self:SetCycle(0)
	self:SetPlaybackRate(1)
end

function ENT:SetBoneScale(bone, s)
	self:ManipulateBoneScale(self:LookupBone(bone), Vector(s, s, s))
end

function ENT:AttachProp(model, bone)
	local prop = ents.Create("prop_dynamic")
	prop:SetModel(model)
	prop:SetPos(self:GetPos())
	prop:Spawn()
	prop:FollowBone(self, self:LookupBone(bone))
	self:DeleteOnRemove(prop)
	return prop
end

-- motion
function ENT:SetDesiredSpeed(u) self.motion.SetDesiredSpeed(self, u) end
function ENT:FaceTowards(v) self.motion.FaceTowards(self, v) end
function ENT:Approach(v) self.motion.Approach(self, v) end
function ENT:IsAttemptingToMove() return self.motion.IsAttemptingToMove(self) end
function ENT:GetGroundSpeed() return self.motion.GetGroundSpeed(self) end

local FollowPath = {}
FollowPath.__index = FollowPath

-- A path profile measures the compute; the nbdebug feature, watching this
-- NPC, has it reported (the npc controller's ObserveCompute).
function FollowPath:Compute(goal)
	local bot, npcs = self.bot, self.bot.npcs
	local profile, watch = npcs:PathProfile(), npcs:PathWatch(bot)
	if not (profile or watch) then return self.path:Compute(bot, goal, bot.pathCost) end
	local function compute() return self.path:Compute(bot, goal, bot.pathCost) end
	if watch then return npcs:ObserveCompute(watch, bot, self.path, goal, compute) end
	return npcs:MeasureCompute(profile, bot.Variant, bot, compute)
end
function FollowPath:Update() self.path:Update(self.bot) end
function FollowPath:GetAge() return self.path:GetAge() end
function FollowPath:IsValid() return self.path:IsValid() end
function FollowPath:Invalidate() self.path:Invalidate() end
function FollowPath:SetMinLookAheadDistance(d) self.path:SetMinLookAheadDistance(d) end

function FollowPath:GetCurrentGoalPos()
	local goal = self.path:GetCurrentGoal()
	return goal and goal.pos
end

function ENT:NewPath()
	return setmetatable({
		path = Path("Follow"),
		bot = self,
	}, FollowPath)
end

-- effects
function ENT:DispatchParticleEffect(name, v) ParticleEffect(name, v, angle_zero) end
function ENT:ScreenShake(v, amp, freq, dur, radius) util.ScreenShake(v, amp, freq, dur, radius) end
function ENT:FireOutput(name, activator) self:TriggerOutput(name, activator) end
function ENT:SpawnEntity(class, config, pos) return self.npcs:Spawn(class, config, pos, angle_zero) end

-- ApplyAbsVelocityImpulse, by what the target moves with.
function ENT:ApplyImpulse(t, v)
	if t:IsPlayer() or t:IsNPC() then
		t:SetVelocity(v)
	elseif t:IsNextBot() then
		t.loco:SetVelocity(t.loco:GetVelocity() + v)
	else
		t:GetPhysicsObject():AddVelocity(v)
	end
end

function ENT:DealDamage(t, amount, dmgType, attacker)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(dmgType)
	dmg:SetAttacker(attacker or self)
	dmg:SetInflictor(self)
	dmg:SetDamagePosition(t:WorldSpaceCenter())
	t:TakeDamageInfo(dmg)
end
