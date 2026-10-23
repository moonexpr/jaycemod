-- The Halloween ghost (CGhost, halloween/ghost/ghost.cpp): an NPC variant
-- that appears in a puff, moans every 5-7 s, drifts ahead turning from what
-- its feelers touch, and every second stuns (scares) the living RED and BLU
-- players within 192 it can see. When its lifetime is up, or it has been
-- stuck a second, it vanishes with a cry. It collides with nothing.
--
-- Haunt is CTFGameRules::BeginHaunting's rule (the Wheel of Fate's
-- Ghosts): the ghosts
-- about get new lifetimes, and more come up to the count, on nav areas away
-- from the players.
--
-- Its port adds METHODS to the combatant port (the ghost binding):
--   FeelerHit(from, to) -> the fraction of the line to the first solid
--     (MASK_PLAYERSOLID, through NPCs and players), or nil when clear.
-- config = { lifetime }.
local require = require
local NpcSystem = npc.nextbot
local Players = gameplay.players
local ipairs = ipairs
local cos, rad, sin = math.cos, math.rad, math.sin
module(...)

KIND = "ghost"
MODEL = "models/props_halloween/ghost_no_hat.mdl"
-- CGhostLocomotion
LOCOMOTION = {
	runSpeed = 90, -- GHOST_SPEED
	stepHeight = 18,
	jumpHeight = 18,
	deathDropHeight = 200,
	maxYawRate = 200,
	acceleration = 500,
	deceleration = 500,
}

METHODS = {
	"FeelerHit",
}

APPEAR_PARTICLE = "ghost_appearation"
PARTICLES = { APPEAR_PARTICLE }
MOAN_SOUND = "Halloween.GhostMoan"
VANISH_SOUND = "Halloween.Haunted"

SCARE_RADIUS = 192 -- GHOST_SCARE_RADIUS
SCARE_TIME = 2
SCARE_SLOW = 0
SCARE_INTERVAL = 1
SCARE_FLAGS = Players.STUN.LOSER_STATE + Players.STUN.BY_TRIGGER -- the Halloween "yikes"
MOAN_MIN, MOAN_MAX = 5, 7
FEELER_RANGE = 150
TURN_RATE = 0.2
GOAL_AHEAD = 100
STUCK_RANGE = 50
STUCK_TIME = 1

-- BeginHaunting: new ghosts keep this far from every living player.
SPAWN_CLEARANCE = 1.25 * SCARE_RADIUS

local GhostBehavior = NpcSystem.Action:Extend("Behavior")

function GhostBehavior:Init(state) self.state = state end

function GhostBehavior:OnStart(me, priorAction)
	self.born = me:Now()
	self.stuckAnchor = me:GetAbsOrigin()
	self.stuckTimer = NpcSystem.CountdownTimer(me)
	self.stuckTimer:Start(STUCK_TIME)
	self.moanTimer = NpcSystem.CountdownTimer(me)
	self.scareTimer = NpcSystem.CountdownTimer(me)
	local yaw = rad(me:GetYaw())
	self.forward = me:Vector(cos(yaw), sin(yaw), 0)
	me:SetDesiredSpeed(LOCOMOTION.runSpeed)
	me:DispatchParticleEffect(APPEAR_PARTICLE, me:WorldSpaceCenter())
	return self:Continue()
end

-- DriftAroundAndAvoidObstacles
function GhostBehavior:Drift(me)
	local f = self.forward
	local left, right = me:Vector(-f.y, f.x, 0), me:Vector(f.y, -f.x, 0)
	local center = me:WorldSpaceCenter()
	local hitLeft = me:FeelerHit(center, center + (f + left) * FEELER_RANGE)
	local hitRight = me:FeelerHit(center, center + (f + right) * FEELER_RANGE)
	if hitLeft then
		if hitRight and hitRight <= hitLeft then
			f = f + left * TURN_RATE
		else
			f = f + right * TURN_RATE
		end
	elseif hitRight then
		f = f + left * TURN_RATE
	end
	f = f:GetNormalized()
	self.forward = f
	local goal = me:GetAbsOrigin() + f * GOAL_AHEAD
	me:Approach(goal)
	me:FaceTowards(goal)
	if me:IsRangeGreaterThan(self.stuckAnchor, STUCK_RANGE) then
		self.stuckAnchor = me:GetAbsOrigin()
		self.stuckTimer:Reset()
	end
end

-- ScareNearbyPlayers
function GhostBehavior:Scare(me)
	if not self.scareTimer:IsElapsed() then return end
	self.scareTimer:Start(SCARE_INTERVAL)
	for _, victim in ipairs(me:CollectPlayers(nil)) do
		if not me:InCond(victim, Players.COND.PURGATORY) and me:IsRangeLessThan(victim, SCARE_RADIUS)
			and me:IsLineOfSightClear(victim) then
			me:StunPlayer(victim, SCARE_TIME, SCARE_SLOW, SCARE_FLAGS)
		end
	end
end

function GhostBehavior:Update(me, interval)
	if me:Now() - self.born > self.state.lifetime or self.stuckTimer:IsElapsed() then
		me:DispatchParticleEffect(APPEAR_PARTICLE, me:WorldSpaceCenter())
		me:EmitSound(VANISH_SOUND)
		me:Remove()
		return self:Done()
	end
	if self.moanTimer:IsElapsed() then
		me:EmitSound(MOAN_SOUND)
		self.moanTimer:Start(me:RandomFloat(MOAN_MIN, MOAN_MAX))
	end
	self:Drift(me)
	self:Scare(me)
	return self:Continue()
end

function NewState(config, me)
	return { lifetime = config.lifetime }
end

function InitialAction(state) return GhostBehavior:New(state) end

-- Ghosts are not hurt.
function FilterDamage(state, damageEvent, me) return false end

-- CGhost::SetLifetime: its whole life, from when it appeared.
function SetLifetime(state, seconds) state.lifetime = seconds end

-------------------------------------------------------------------------------
-- Haunting (CTFGameRules::BeginHaunting)

function HauntingAllowed(halloween, bossScenario, holidayAllowsHaunting)
	return halloween and (bossScenario or holidayAllowsHaunting)
end

-- world: RandomInt(lo, hi), RandomFloat(lo, hi), LivingPlayerOrigins()
-- (RED and BLU), SpawnAreaCenters() (the nav areas outside the spawn
-- rooms). existing: the ghosts about. Returns { extend = { ghost,
-- lifetime }..., spawn = { pos, lifetime }... }.
function Haunt(world, existing, desired, minDuration, maxDuration)
	local plan = {
		extend = {},
		spawn = {},
	}
	for i, ghost in ipairs(existing) do
		plan.extend[i] = {
			ghost = ghost,
			lifetime = world:RandomFloat(minDuration, maxDuration),
		}
	end
	if #existing >= desired then return plan end
	local players, spots = world:LivingPlayerOrigins(), {}
	for _, spot in ipairs(world:SpawnAreaCenters()) do
		local clear = true
		for _, origin in ipairs(players) do
			if (origin - spot):Length() < SPAWN_CLEARANCE then clear = false end
		end
		if clear then spots[#spots + 1] = spot end
	end
	if #spots == 0 then return plan end
	for i = 1, desired - #existing do
		plan.spawn[i] = {
			pos = spots[world:RandomInt(1, #spots)],
			lifetime = world:RandomFloat(minDuration, maxDuration),
		}
	end
	return plan
end
