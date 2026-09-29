-- The Horseless Headless Horsemann (CHeadlessHatman, headless_hatman.cpp,
-- and halloween_behavior/headless_hatman_*.cpp): a boss variant of
-- foundation.npc.halloween_boss. It rises from the ground, makes the nearest
-- player IT (foundation.npc.tag, through the tag controller) and chases
-- them, cleaves whoever it targets with its axe, and every 20 s yells Boo,
-- stunning everyone nearby.
--
-- Its port adds METHODS to the boss port: ControlPoints() -> the control
-- points of the master, in its order, as { origin, inRound, owner,
-- blueMayCapture }. Its numbers come from the binding's convars, named and
-- defaulted as TF2's (CONVARS).
local require = require
local NpcSystem = require("foundation.npc")
local HalloweenBoss = require("foundation.npc.halloween_boss")
local Actor = require("foundation.npc.actor")
local Players = require("foundation.players")
local Teams = require("foundation.teams")
local atan2, cos, deg, floor, huge, rad, sin = math.atan2, math.cos, math.deg, math.floor, math.huge, math.rad, math.sin
local ipairs = ipairs
module(...)

BOSS_TYPE = HalloweenBoss.BOSS_HHH
PATH = "foundation.npc.path.ground"
LOCOMOTION = {
	runSpeed = 400, -- tf_halloween_bot_speed
	stepHeight = 18,
	jumpHeight = 18,
	deathDropHeight = 200, -- NextBotGroundLocomotion's
	maxYawRate = 200,
	acceleration = 500,
	deceleration = 500,
}

-- TF2's convars (headless_hatman.cpp), with their defaults.
-- tf_halloween_bot_chase_duration is left out: TF2 starts its timer and
-- never reads it.
CONVARS = {
	tf_halloween_bot_health_base = 3000,
	tf_halloween_bot_health_per_player = 200,
	tf_halloween_bot_min_player_count = 10,
	tf_halloween_bot_speed = 400,
	tf_halloween_bot_attack_range = 200,
	tf_halloween_bot_terrify_radius = 500,
	tf_halloween_bot_chase_range = 1500,
	tf_halloween_bot_quit_range = 2000,
}

METHODS = {
	"ControlPoints",
}

MODEL = "models/bots/headless_hatman.mdl"
AXE_MODEL = "models/weapons/c_models/c_bigaxe/c_bigaxe.mdl"
AXE_BONE = "weapon_bone"

-- Emerge
RISE_TIME = 3
EMERGE_OFFSET = 10
EMERGE_DEPTH = 200
RUMBLE_INTERVAL = 0.25
PUSH_RANGE = 250
PUSH_FORCE = 200
local FULL_TURN = 360

-- Attack
AXE_SWING_DELAY = 0.58
ATTACK_INTERVAL = 1
SCARE_INTERVAL = 20
HOME_RECALC = 3
WARN_IT_INTERVAL = 7
LOOKAHEAD = 100
AT_HOME_RANGE = 50
STAND_AND_SWING_RANGE = 100
HOME_REPATH_AGE = 3
CHASE_REPATH_AGE = 1
OFF_MESH_TOLERANCE = 50
CONTACT_FOCUS = 3
LAUGH_MIN, LAUGH_MAX = 3, 5
LAUGH_ROLL_MAX = 100 -- RandomInt( 0, 100 )
FIST_PUMP_BELOW, FINGER_POINT_BELOW = 25, 50
FOOTFALL_INTERVAL = 0.25
HALF_HEALTH_PERCENT = 50
local PERCENT = 100
AXE_DAMAGE_FRACTION = 0.8 -- of the target's max health
CLOSE_RANGE_FRACTION = 0.5 -- of the attack range: inside it any forward hit lands
HIT_ANGLE_SLOPE = 0.27
GHOST_PUSH_FORCE = 1300
GHOST_PUSH_LIFT = 0.7

-- UTIL_ScreenShake( origin, 15, 5, 1, 1000 )
SHAKE_AMPLITUDE, SHAKE_FREQUENCY, SHAKE_DURATION, SHAKE_RADIUS = 15, 5, 1, 1000

-- Terrify
BOO_DELAY = 0.25
SCARE_DELAY = 0.75
TERRIFY_TIME = 1.25
SCARE_DURATION = 2
SCARE_SPEED_REDUCTION = 0
SCARE_FLAGS = Players.STUN.LOSER_STATE + Players.STUN.BY_TRIGGER

local function Shake(me)
	me:ScreenShake(me:GetAbsOrigin(), SHAKE_AMPLITUDE, SHAKE_FREQUENCY, SHAKE_DURATION, SHAKE_RADIUS)
end

-- The nearest of targets by range (INextBot::GetRangeTo), or nil.
local function Nearest(me, targets)
	local nearest, nearestRange = nil, huge
	for _, t in ipairs(targets) do
		local range = me:RangeTo(t)
		if range < nearestRange then nearest, nearestRange = t, range end
	end
	return nearest
end

local function Forward(me)
	local yaw = rad(me:GetYaw())
	return me:Vector(cos(yaw), sin(yaw), 0)
end

-------------------------------------------------------------------------------
-- Emerge (CHeadlessHatmanEmerge)

local Emerge = NpcSystem.Action:Extend("Emerge")
local Attack = NpcSystem.Action:Extend("Attack")
local Terrify = NpcSystem.Action:Extend("Terrify")
local Dying = NpcSystem.Action:Extend("Dying")

function Emerge:Init(state)
	self.state = state
end

function Emerge:OnStart(me, priorAction)
	me:StartActivity(me:Activity("ACT_TRANSITION"))
	me:DispatchParticleEffect("halloween_boss_summon", me:GetAbsOrigin())
	self.riseTimer = NpcSystem.CountdownTimer(me)
	self.riseTimer:Start(RISE_TIME)
	self.rumbleTimer = NpcSystem.CountdownTimer(me)
	self.emergePos = me:GetAbsOrigin() + me:Vector(0, 0, EMERGE_OFFSET)
	me:SetAbsOrigin(self.emergePos - me:Vector(0, 0, EMERGE_DEPTH))
	me:EmitSound("Halloween.HeadlessBossSpawnRumble")
	local close = Nearest(me, me:CollectPlayers(nil))
	if close then
		local to = me:TargetOrigin(close) - me:GetAbsOrigin()
		me:SetYaw(deg(atan2(to.y, to.x)))
	else
		me:SetYaw(me:RandomFloat(0, FULL_TURN))
	end
	return self:Continue()
end

-- Push players away from the emerge point, up and outwards.
local function PushAway(me, from)
	for _, ply in ipairs(me:CollectPlayers(nil)) do
		local to = me:TargetEyes(ply) - from
		if to:Length() < PUSH_RANGE then
			local flat = me:Vector(to.x, to.y, 0):GetNormalized()
			me:ApplyImpulse(ply, me:Vector(flat.x, flat.y, 1) * PUSH_FORCE)
		end
	end
end

function Emerge:Update(me, interval)
	local rise = self.riseTimer
	if not rise:IsElapsed() then
		local depth = EMERGE_DEPTH * rise:GetRemainingTime() / rise:GetCountdownDuration()
		me:SetAbsOrigin(self.emergePos - me:Vector(0, 0, depth))
		if self.rumbleTimer:IsElapsed() then
			self.rumbleTimer:Start(RUMBLE_INTERVAL)
			Shake(me)
		end
	end
	if me:IsActivityFinished() then return self:ChangeTo(Attack:New(self.state), "Here I come!") end
	PushAway(me, self.emergePos)
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Attack (CHeadlessHatmanAttack)

function Attack:Init(state)
	self.state = state
end

function Attack:OnStart(me, priorAction)
	local cv = self.state.convars
	self.path = me:NewPath()
	self.path:SetMinLookAheadDistance(LOOKAHEAD)
	me:StartActivity(me:Activity("ACT_MP_RUN_ITEM1"))
	me:SetDesiredSpeed(cv.tf_halloween_bot_speed)
	self.axeSwingTimer = NpcSystem.CountdownTimer(me)
	self.attackTimer = NpcSystem.CountdownTimer(me)
	self.laughTimer = NpcSystem.CountdownTimer(me)
	self.warnITTimer = NpcSystem.CountdownTimer(me)
	self.footfallTimer = NpcSystem.CountdownTimer(me)
	self.attackTargetFocusTimer = NpcSystem.CountdownTimer(me)
	self.scareTimer = NpcSystem.CountdownTimer(me)
	self.scareTimer:Start(SCARE_INTERVAL)
	self.homeRecalcTimer = NpcSystem.CountdownTimer(me)
	self.homeRecalcTimer:Start(HOME_RECALC)
	self.closestVisible = nil
	self.attackTarget = nil
	self.home = me:GetAbsOrigin()
	me:Tag():Set(nil)
	return self:Continue()
end

-- Nobody is IT once the Horsemann stops attacking: it died (TF2's
-- CHeadlessHatmanBehavior clears IT on death) or it was removed.
function Attack:OnEnd(me, nextAction)
	me:Tag():Set(nil)
end

function Attack:IsSwingingAxe()
	return not self.axeSwingTimer:IsElapsed()
end

-- IsPotentiallyChaseable: alive, no ghost, reachable (not in a spawn room;
-- on the mesh while standing), not invulnerable, and not too far from home.
function Attack:IsPotentiallyChaseable(me, victim)
	if victim == nil or not me:IsTargetValid(victim) or not me:IsTargetAlive(victim) then return false end
	if me:InCond(victim, Players.COND.HALLOWEEN_GHOST_MODE) then return false end
	if me:InRespawnRoom(victim) then return false end
	local tolerance = me:IsTargetOnGround(victim) and OFF_MESH_TOLERANCE or huge
	if not me:IsOnNavMesh(victim, tolerance) then return false end
	if me:IsInvulnerable(victim) then return false end
	return (self.home - me:TargetOrigin(victim)):Length() <= self.state.convars.tf_halloween_bot_quit_range
end

-- SelectVictim, with ValidateChaseVictim.
function Attack:SelectVictim(me)
	local tag = me:Tag()
	local it = tag:Get()
	if it ~= nil and not self:IsPotentiallyChaseable(me, it) then tag:Set(nil) end

	self.closestVisible = tag:Get()
	if tag:Get() == nil then
		local chaseRange = self.state.convars.tf_halloween_bot_chase_range
		local newVictim, victimRange, visibleRange = nil, huge, huge
		for _, ply in ipairs(me:CollectPlayers(nil)) do
			if self:IsPotentiallyChaseable(me, ply) then
				local range = me:RangeTo(ply)
				if range < visibleRange and me:IsLineOfSightClear(ply) then
					self.closestVisible = ply
					visibleRange = range
				end
				local nearHome = (self.home - me:TargetOrigin(ply)):Length() <= chaseRange
				if nearHome and range < victimRange then
					newVictim = ply
					victimRange = range
				end
			end
		end
		if newVictim then tag:Set(newVictim) end
	end

	-- Sandcastle's own: with no player IT, the nearest chaseable AI war
	-- soldier near home is its victim. A soldier is never IT: IT is the tag
	-- feature's, a player's mark.
	self.soldierVictim = nil
	if tag:Get() == nil then
		local chaseRange = self.state.convars.tf_halloween_bot_chase_range
		local best = huge
		for _, team in ipairs({ Teams.RED, Teams.BLUE }) do
			for _, soldier in ipairs(me:CollectMembers(team)) do
				local range = me:RangeTo(soldier)
				if range < best and self:IsPotentiallyChaseable(me, soldier)
					and (self.home - me:TargetOrigin(soldier)):Length() <= chaseRange then
					self.soldierVictim, best = soldier, range
				end
			end
		end
		if self.soldierVictim and self.closestVisible == nil and me:IsLineOfSightClear(self.soldierVictim) then
			self.closestVisible = self.soldierVictim
		end
	end

	local target = self.attackTarget
	if target == nil or self.attackTargetFocusTimer:IsElapsed() or not me:IsTargetAlive(target) then
		self.attackTarget = tag:Get() or self.soldierVictim
	end
end

-- RecomputeHomePosition: the first point of the round that BLU does not own
-- and may capture; failing that, the last point the loop looked at.
function Attack:RecomputeHomePosition(me)
	if not self.homeRecalcTimer:IsElapsed() then return end
	self.homeRecalcTimer:Reset()
	local contested = nil
	for _, point in ipairs(me:ControlPoints()) do
		contested = point
		if point.inRound and point.owner ~= Teams.BLUE and point.blueMayCapture then break end
	end
	if contested then self.home = contested.origin end
end

-- AttackTarget: a ghost is batted away; anyone else in front and in sight
-- is cleaved, the cone widening as they come closer.
function Attack:AttackTarget(me, target, attackRange)
	if not me:IsRangeLessThan(target, attackRange) then return end
	local toVictim = (me:TargetCenter(target) - me:WorldSpaceCenter()):GetNormalized()
	if me:InCond(target, Players.COND.HALLOWEEN_GHOST_MODE) then
		me:ApplyImpulse(target, (toVictim + me:Vector(0, 0, GHOST_PUSH_LIFT)) * GHOST_PUSH_FORCE)
		return
	end
	local closeRange = CLOSE_RANGE_FRACTION * attackRange
	local range = me:RangeTo(target)
	local closeness = 0
	if range >= closeRange then closeness = (range - closeRange) / (attackRange - closeRange) end
	if Forward(me):Dot(toVictim) > closeness * HIT_ANGLE_SLOPE and me:IsLineOfSightClear(target) then
		me:DealDamage(target, me:TargetMaxHealth(target) * AXE_DAMAGE_FRACTION, Actor.DMG_CLUB)
		me:EmitSound("Halloween.HeadlessBossAxeHitFlesh")
	end
end

function Attack:UpdateAxeSwing(me)
	local swing = self.axeSwingTimer
	if not (swing:HasStarted() and swing:IsElapsed()) then return end
	swing:Invalidate()
	if self.attackTarget ~= nil then
		self:AttackTarget(me, self.attackTarget, self.state.convars.tf_halloween_bot_attack_range)
	end
	me:EmitSound("Halloween.HeadlessBossAxeHitWorld")
	Shake(me)
	me:DispatchParticleEffect("halloween_boss_axe_hit_world", me:WorldSpaceCenter())
end

function Attack:Laugh(me, it)
	if self:IsSwingingAxe() or not self.laughTimer:IsElapsed() then return end
	me:EmitSound("Halloween.HeadlessBossLaugh")
	self.laughTimer:Start(me:RandomFloat(LAUGH_MIN, LAUGH_MAX))
	if it ~= nil then return end
	local roll = me:RandomInt(0, LAUGH_ROLL_MAX)
	if roll < FIST_PUMP_BELOW then
		me:AddGesture(me:Activity("ACT_MP_GESTURE_VC_FISTPUMP_MELEE"))
	elseif roll < FINGER_POINT_BELOW then
		me:AddGesture(me:Activity("ACT_MP_GESTURE_VC_FINGERPOINT_MELEE"))
	end
end

-- With nobody IT, go home; with IT, warn them and chase. (Sandcastle's
-- own: with no IT, a soldier victim is chased as IT would be, unwarned.)
function Attack:Move(me, it)
	local path = self.path
	local quarry = it or self.soldierVictim
	if quarry == nil then
		if me:IsRangeGreaterThan(self.home, AT_HOME_RANGE) then
			if path:GetAge() > HOME_REPATH_AGE then path:Compute(self.home) end
			path:Update()
		elseif self.closestVisible ~= nil then
			me:FaceTowards(me:TargetCenter(self.closestVisible))
		end
		return
	end
	if it ~= nil and self.warnITTimer:IsElapsed() then
		self.warnITTimer:Start(WARN_IT_INTERVAL)
		me:Tag():Warn(it)
	end
	if me:IsRangeGreaterThan(quarry, STAND_AND_SWING_RANGE) or not me:IsLineOfSightClear(quarry) then
		if path:GetAge() > CHASE_REPATH_AGE then path:Compute(me:TargetOrigin(quarry)) end
		path:Update()
	end
end

function Attack:Animate(me)
	if not me:IsAttemptingToMove() then
		local stand = me:Activity("ACT_MP_STAND_ITEM1")
		if not me:IsActivity(stand) then me:StartActivity(stand) end
		return
	end
	local healthPercent = floor(PERCENT * me:GetHealth() / me:GetMaxHealth())
	local run = me:Activity(healthPercent > HALF_HEALTH_PERCENT and "ACT_MP_RUN_ITEM1" or "ACT_MP_RUN_MELEE")
	if not me:IsActivity(run) then me:StartActivity(run) end
	if self.footfallTimer:IsElapsed() then
		self.footfallTimer:Start(FOOTFALL_INTERVAL)
		Shake(me)
	end
end

function Attack:Update(me, interval)
	if not me:IsAlive() then return self:Done() end
	self:SelectVictim(me)
	self:RecomputeHomePosition(me)
	local it = me:Tag():Get()
	self:Laugh(me, it)
	self:Move(me, it)

	local target = self.attackTarget
	if target ~= nil and me:IsTargetAlive(target) then
		if me:IsRangeLessThan(target, self.state.convars.tf_halloween_bot_attack_range) then
			if self.scareTimer:IsElapsed() and HalloweenBoss.IsPlayer(me, target) then
				self.scareTimer:Reset()
				return self:SuspendFor(Terrify:New(self.state), "Boo!")
			end
			if self.attackTimer:IsElapsed() and not self:IsSwingingAxe() then
				me:AddGesture(me:Activity("ACT_MP_ATTACK_STAND_ITEM1"))
				self.axeSwingTimer:Start(AXE_SWING_DELAY)
				me:EmitSound("Halloween.HeadlessBossAttack")
				self.attackTimer:Start(ATTACK_INTERVAL)
			end
			me:FaceTowards(me:TargetCenter(target))
		end
	end

	self:UpdateAxeSwing(me)
	self:Animate(me)
	return self:Continue()
end

-- Stuck: warp to where the path was heading.
function Attack:OnStuck(me)
	local goal = self.path:GetCurrentGoalPos()
	if goal then me:SetAbsOrigin(goal + me:Vector(0, 0, EMERGE_OFFSET)) end
	return self:TryContinue()
end

-- Bumping a living combatant makes it the target for a while, so the
-- Horsemann does not stay stuck on it.
function Attack:OnContact(me, other)
	if me:IsTargetValid(other) and me:TeamOf(other) ~= Teams.UNASSIGNED and me:IsTargetAlive(other) then
		self.attackTarget = other
		self.attackTargetFocusTimer:Start(CONTACT_FOCUS)
	end
	return self:TryContinue()
end

-------------------------------------------------------------------------------
-- Terrify (CHeadlessHatmanTerrify): Boo! Everyone near and in sight is
-- stunned in the Halloween "yikes" state. (The pumpkin head and Saxton
-- mask that protect in TF2 are econ items, left out.)

function Terrify:Init(state)
	self.state = state
end

function Terrify:OnStart(me, priorAction)
	me:AddGesture(me:Activity("ACT_MP_GESTURE_VC_HANDMOUTH_ITEM1"))
	self.booTimer = NpcSystem.CountdownTimer(me)
	self.booTimer:Start(BOO_DELAY)
	self.scareTimer = NpcSystem.CountdownTimer(me)
	self.scareTimer:Start(SCARE_DELAY)
	self.timer = NpcSystem.CountdownTimer(me)
	self.timer:Start(TERRIFY_TIME)
	return self:Continue()
end

function Terrify:Update(me, interval)
	if self.timer:IsElapsed() then return self:Done() end
	if self.booTimer:HasStarted() and self.booTimer:IsElapsed() then
		self.booTimer:Invalidate()
		me:EmitSound("Halloween.HeadlessBossBoo")
	end
	if self.scareTimer:IsElapsed() then
		local radius = self.state.convars.tf_halloween_bot_terrify_radius
		for _, victim in ipairs(me:CollectPlayers(nil)) do
			if me:IsRangeLessThan(victim, radius) and me:IsLineOfSightClear(victim) then
				me:StunPlayer(victim, SCARE_DURATION, SCARE_SPEED_REDUCTION, SCARE_FLAGS)
			end
		end
	end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Dying (CHeadlessHatmanDying)

function Dying:OnStart(me, priorAction)
	me:StartActivity(me:Activity("ACT_DIESIMPLE"))
	me:EmitSound("Halloween.HeadlessBossDying")
	return self:Continue()
end

function Dying:Update(me, interval)
	if not me:IsActivityFinished() then return self:Continue() end
	me:Break()
	me:DispatchParticleEffect("halloween_boss_death", me:GetAbsOrigin())
	me:Remove()
	return self:Done()
end

-------------------------------------------------------------------------------
-- The boss hooks

-- CHeadlessHatman::Spawn: scaled by the players beyond the minimum.
function Health(players, level, convars)
	local health = convars.tf_halloween_bot_health_base
	local minimum = convars.tf_halloween_bot_min_player_count
	if players > minimum then
		health = health + (players - minimum) * convars.tf_halloween_bot_health_per_player
	end
	return health
end

function Setup(state, config, me)
	me:AttachProp(AXE_MODEL, AXE_BONE)
end

-- CHeadlessHatman::OnTakeDamage_Alive
function ModifyDamage(state, damageEvent, me)
	me:DispatchParticleEffect("halloween_boss_injured", damageEvent.position)
	return damageEvent.amount
end

-- CHeadlessHatman::Update: the wounds show as health falls.
function OnUpdate(state, me)
	me:SetPoseParameter("damage", 1 - me:GetHealth() / me:GetMaxHealth())
end

function EmergeAction(state) return Emerge:New(state) end
function DyingAction(state) return Dying:New(state) end

HalloweenBoss.Variant(_M)
