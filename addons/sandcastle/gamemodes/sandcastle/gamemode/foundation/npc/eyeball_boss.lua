-- MONOCULUS (CEyeballBoss, eyeball_boss/eyeball_boss.cpp and
-- eyeball_behavior/*.cpp): a flying boss variant of
-- foundation.npc.halloween_boss. It rises from its summoning portal, hunts
-- the nearest visible victim with rockets, teleports around the map's
-- spawn_boss_alt spots leaving vortexes behind, and escapes when its life
-- runs out. Killed, it falls, pops, jarates the players near it and leaves
-- a vortex to the loot island; the next one is a level tougher. A spell's
-- eyeball (any team but Halloween) is immune, always enraged, and leaves
-- after 8 s.
--
-- Its port adds METHODS to the boss port:
--   SetDesiredAltitude(h) (the hover locomotion's), AimHeadTowards(v),
--   GroundHeight(v) -> z | nil (the nav mesh's ground below v),
--   IsNearNavMesh(v, range), SetHidden(hidden), TraceWorld(from, to) ->
--   the hit position | nil (brushes only).
-- A map's eyeball (not a spell's) fires foundation.npc.boss_events' game
-- events where TF2 does: summoned as it rises, the escape warnings,
-- escaped and killed; the clients play and print what they mean.
--
-- The teleport vortex it leaves is a model here too (Vortex), bound by the
-- teleport_vortex entity through VORTEX_METHODS.
--
-- Left out (docs/pass3-halloween.md): the purgatory stun (no purgatory
-- buff), the per-weapon damage multipliers, the purgatory Z check, and the
-- leveled boss fizzling grenades at its portal.
local require = require
local NpcSystem = require("games.npc.nextbot")
local HalloweenBoss = require("foundation.npc.halloween_boss")
local BossEvents = require("foundation.npc.boss_events")
local Targeting = require("games.npc.targeting")
local Actor = require("games.npc.actor")
local Players = require("games.gameplay.players")
local Teams = require("games.gameplay.teams")
local cos, floor, huge, max, pi, rad, sin = math.cos, math.floor, math.huge, math.max, math.pi, math.rad, math.sin
local ipairs, setmetatable = ipairs, setmetatable
module(...)

BOSS_TYPE = HalloweenBoss.BOSS_MONOCULUS
HOVER = {
	hoverHeight = 200, -- tf_eyeball_boss_hover_height
	acceleration = 500, -- tf_eyeball_boss_acceleration
	horizontalDamping = 2, -- tf_eyeball_boss_horiz_damping
	verticalDamping = 1, -- tf_eyeball_boss_vert_damping
}

-- TF2's convars (eyeball_boss.cpp), with their defaults. The hover ones
-- live in HOVER, which the binding reads once.
CONVARS = {
	tf_eyeball_boss_lifetime = 120,
	tf_eyeball_boss_lifetime_spell = 8,
	tf_eyeball_boss_speed = 250,
	tf_eyeball_boss_attack_range = 750,
	tf_eyeball_boss_health_base = 8000,
	tf_eyeball_boss_health_per_player = 400,
	tf_eyeball_boss_health_at_level_2 = 17000,
	tf_eyeball_boss_health_per_level = 3000,
	tf_halloween_bot_min_player_count = 10,
}

METHODS = {
	"SetDesiredAltitude",
	"AimHeadTowards",
	"GroundHeight",
	"IsNearNavMesh",
	"SetHidden",
	"TraceWorld",
}

MODEL = "models/props_halloween/halloween_demoeye.mdl"
ROCKET_MODEL = "models/props_halloween/eyeball_projectile.mdl"
ROCKET_CLASS = "tf_projectile_rocket"
VORTEX_CLASS = "teleport_vortex"
SPAWN_SPOTS = "spawn_boss_alt"
HULL_HALF_WIDTH = 50 -- bounds ±50

-- Its particle systems, and the list the npc controller precaches (the
-- files: features/npc/sh.lua). The summon is the Horsemann's.
SUMMON_PARTICLE = "halloween_boss_summon" -- scary_ghost.pcf
TELEPORT_PARTICLE = "eyeboss_tp_normal" -- eyeboss.pcf, as are the rest
ESCAPE_PARTICLE = "eyeboss_tp_escape"
DEATH_PARTICLE = "eyeboss_death"
PARTICLES = {
	SUMMON_PARTICLE,
	TELEPORT_PARTICLE,
	ESCAPE_PARTICLE,
	DEATH_PARTICLE,
}

SKIN_NORMAL, SKIN_RED, SKIN_TEAM_RED, SKIN_TEAM_BLUE = 0, 1, 2, 3
ANGER_ENRAGED, ANGER_GRUMPY, ANGER_CALM = 1, 0.4, 0

FIRST_LEVEL = BossEvents.FIRST_LEVEL -- CEyeballBoss::m_level starts here
ZOMBIE_KIND = "zombie" -- foundation.npc.zombie's registry kind

-- Mood
ENRAGE_DURATION = 5 -- after a crit, or heavy DPS
ENRAGE_DPS = 300
local ENRAGED_BELOW, GRUMPY_BELOW = 1, 2 -- thirds of max health
local THIRDS = 3

-- Emerge
RISE_TIME = 3
EMERGE_OFFSET = 100
EMERGE_DEPTH = 150
RUMBLE_INTERVAL = 0.25
PUSH_RANGE = 250
PUSH_FORCE = 200
KILL_TIME = 2
DEATH_RANGE = 100
DEATH_RANGE_LEVELLED = 200
KILL_MAX_HEALTH_MULTIPLE = 2
SHAKE_AMPLITUDE, SHAKE_FREQUENCY, SHAKE_DURATION, SHAKE_RADIUS = 15, 5, 1, 1000

-- Idle
TALK_MIN, TALK_MAX = 3, 5
RAGE_TALK_MIN, RAGE_TALK_MAX = 1, 2
MOVE_MIN, MOVE_MAX = 10, 15
MAX_TELEPORT_HEIGHT = 300
TELEPORT_NAV_RANGE = 1.5 * MAX_TELEPORT_HEIGHT
LOOK_AT_ATTACKER_MIN, LOOK_AT_ATTACKER_MAX = 0.5, 2
LOOK_AROUND_MIN, LOOK_AROUND_MAX = 2, 4
LOOK_AROUND_DISTANCE = 100
-- The seconds left at which game_eyeball_boss_escape_imminent fires, checked
-- nearest first, as CEyeballBossIdle::Update does.
ESCAPE_WARNINGS = { 10, 30, 60 }

-- Notice and ApproachTarget
NOTICE_TIME = 0.25
GIVE_UP_TIME = 5
MIN_CHASE_TIME = 0.5
LINGER_TIME = 1
ENRAGED_RANGE_MULTIPLIER = 2

-- LaunchRockets
ROCKET_DAMAGE = 50
ROCKET_SPEED = 1100
CALM_SPEED_FACTOR = 0.3
CALM_ROCKETS, ANGRY_ROCKETS = 1, 3
CALM_DELAY, ANGRY_DELAY = 0.5, 0.25
ROCKET_INTERVAL = 0.3
CIRCLE_DISTANCE = 100
LEAD_MIN_RANGE = 150 -- veryCloseRange
LEAD_ERROR_TOLERANCE = 300

-- Teleport
TELEPORT_HEIGHT = 75

-- Dead
FALL_GIVE_UP = 10
POP_HEIGHT = 100
GOO_RANGE = 750
GOO_DURATION = 10
POP_SHAKE_AMPLITUDE, POP_SHAKE_FREQUENCY, POP_SHAKE_DURATION = 25, 5, 5

-------------------------------------------------------------------------------
-- The eyeball's own rules

function IsEnraged(state, me)
	if state.spell then return true end
	local maxHealth = me:GetMaxHealth()
	if me:GetHealth() < floor(ENRAGED_BELOW * maxHealth / THIRDS) then return true end
	return state.rageTimer:HasStarted() and not state.rageTimer:IsElapsed()
end

function IsGrumpy(state, me)
	if IsEnraged(state, me) then return false end
	return me:GetHealth() < floor(GRUMPY_BELOW * me:GetMaxHealth() / THIRDS)
end

function BecomeEnraged(state, me, duration)
	if not IsEnraged(state, me) then me:EmitSound("Halloween.EyeballBossBecomeEnraged") end
	state.rageTimer:Start(duration)
end

local function Play(state, me, sequence)
	me:PlaySequence(sequence)
	state.sequence = sequence
end

-- GetVictim: the victim, while it lives.
local function GetVictim(state, me)
	local victim = state.victim
	if victim == nil or not me:IsTargetValid(victim) or not me:IsTargetAlive(victim) then return nil end
	return victim
end

-- FindClosestVisibleVictim: the nearest visible living player who is not
-- hidden (a spell's: of the enemy team), other teams' skeletons, and for a
-- spell other teams' bosses.
function FindClosestVisibleVictim(state, me)
	local victim, victimRange = nil, huge
	local function Consider(t)
		local range = me:RangeTo(t)
		if range < victimRange and me:IsLineOfSightClear(t) then
			victim, victimRange = t, range
		end
	end
	local function OtherTeamsOf(kind)
		for _, npc in ipairs(me:CollectNPCs(kind)) do
			if npc ~= me and me:TeamOf(npc) ~= state.team and me:IsTargetAlive(npc) then Consider(npc) end
		end
	end
	local teams = { false }
	if state.spell then
		OtherTeamsOf(HalloweenBoss.KIND)
		teams = Targeting.EnemyTeamsOf(state.team)
	end
	for _, team in ipairs(teams) do
		for _, ply in ipairs(me:CollectPlayers(team or nil)) do
			if not Targeting.IsHiddenFromNPC(function(cond) return me:InCond(ply, cond) end) then Consider(ply) end
		end
		-- Sandcastle's own: the AI war's soldiers, as their team's players
		for _, memberTeam in ipairs(team and { team } or { Teams.RED, Teams.BLUE }) do
			for _, soldier in ipairs(me:CollectMembers(memberTeam)) do
				if me:IsTargetAlive(soldier) then Consider(soldier) end
			end
		end
	end
	OtherTeamsOf(ZOMBIE_KIND)
	return victim
end

local function Shake(me)
	me:ScreenShake(me:GetAbsOrigin(), SHAKE_AMPLITUDE, SHAKE_FREQUENCY, SHAKE_DURATION, SHAKE_RADIUS)
end

-- Low enough over reachable ground for players to reach the vortex it
-- leaves.
local function IsLowOverNavMesh(me)
	local center = me:WorldSpaceCenter()
	local groundZ = me:GroundHeight(center)
	if groundZ == nil then return false end
	if not me:IsNearNavMesh(me:Vector(center.x, center.y, groundZ), TELEPORT_NAV_RANGE) then return false end
	return center.z - groundZ < MAX_TELEPORT_HEIGHT
end

local Emerge = NpcSystem.Action:Extend("Emerge")
local Idle = NpcSystem.Action:Extend("Idle")
local Notice = NpcSystem.Action:Extend("Notice")
local ApproachTarget = NpcSystem.Action:Extend("ApproachTarget")
local LaunchRockets = NpcSystem.Action:Extend("LaunchRockets")
local Emote = NpcSystem.Action:Extend("Emote")
local Teleport = NpcSystem.Action:Extend("Teleport")
local Escape = NpcSystem.Action:Extend("Escape")
local Dead = NpcSystem.Action:Extend("Dead")

local function StateAction(class)
	function class:Init(state) self.state = state end
end

for _, class in ipairs({ Emerge, Idle, Notice, ApproachTarget, LaunchRockets, Teleport, Escape, Dead }) do
	StateAction(class)
end

-------------------------------------------------------------------------------
-- Emerge (CEyeballBossEmerge): a spell's teleports in; a map's rises from
-- its portal, pushing players away and killing those on it for 2 s.

function Emerge:OnStart(me, priorAction)
	local state = self.state
	self.riseTimer = NpcSystem.CountdownTimer(me)
	self.rumbleTimer = NpcSystem.CountdownTimer(me)
	self.killTimer = NpcSystem.CountdownTimer(me)
	if state.spell then
		me:DispatchParticleEffect(TELEPORT_PARTICLE, me:GetAbsOrigin())
		Play(state, me, "teleport_in")
		return self:Continue()
	end
	Play(state, me, "arrives")
	me:DispatchParticleEffect(SUMMON_PARTICLE, me:GetAbsOrigin())
	self.groundPos = me:GetAbsOrigin()
	self.riseTimer:Start(RISE_TIME)
	self.emergePos = me:GetAbsOrigin() + me:Vector(0, 0, EMERGE_OFFSET)
	me:SetAbsOrigin(self.emergePos - me:Vector(0, 0, EMERGE_DEPTH))
	me:EmitSound("Halloween.HeadlessBossSpawnRumble")
	me:FireGameEvent(BossEvents.EYEBALL_BOSS_SUMMONED, { level = Level(me) })
	self.killTimer:Start(KILL_TIME)
	return self:Continue()
end

function Emerge:Update(me, interval)
	local state = self.state
	local rise = self.riseTimer
	if not rise:IsElapsed() then
		local depth = EMERGE_DEPTH * rise:GetRemainingTime() / rise:GetCountdownDuration()
		me:SetAbsOrigin(self.emergePos - me:Vector(0, 0, depth))
		if self.rumbleTimer:IsElapsed() then
			self.rumbleTimer:Start(RUMBLE_INTERVAL)
			Shake(me)
		end
	end
	if me:IsSequenceFinished() then return self:ChangeTo(Idle:New(state), "Here I am!") end
	if state.spell then return self:Continue() end

	local deathRange = state.level > FIRST_LEVEL and DEATH_RANGE_LEVELLED or DEATH_RANGE
	for _, ply in ipairs(me:CollectPlayers(nil)) do
		local to = me:TargetEyes(ply) - self.groundPos
		local range = to:Length()
		if range < PUSH_RANGE then
			local flat = me:Vector(to.x, to.y, 0):GetNormalized()
			me:ApplyImpulse(ply, me:Vector(flat.x, flat.y, 1) * PUSH_FORCE)
		end
		if not self.killTimer:IsElapsed() and range < deathRange then
			me:DealDamage(ply, KILL_MAX_HEALTH_MULTIPLE * me:TargetMaxHealth(ply), Actor.DMG_BLAST)
		end
	end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Idle (CEyeballBossIdle)

function Idle:OnStart(me, priorAction)
	local state = self.state
	local cv = state.convars
	self.attacker = nil
	self.talkTimer = NpcSystem.CountdownTimer(me)
	self.talkTimer:Start(me:RandomFloat(TALK_MIN, TALK_MAX))
	self.lifeTimer = NpcSystem.CountdownTimer(me)
	self.lifeTimer:Start(state.spell and cv.tf_eyeball_boss_lifetime_spell or cv.tf_eyeball_boss_lifetime)
	self.moveTimer = NpcSystem.CountdownTimer(me)
	self.moveTimer:Start(me:RandomFloat(MOVE_MIN, MOVE_MAX))
	self.lookAroundTimer = NpcSystem.CountdownTimer(me)
	self.lastWarnTime = 0
	self.isLaughReady = false
	return self:Continue()
end

-- The escape warnings, each once as the time left falls past it.
function Idle:WarnOfEscape(me)
	local remaining = self.lifeTimer:GetRemainingTime()
	for _, seconds in ipairs(ESCAPE_WARNINGS) do
		if remaining < seconds and self.lastWarnTime > seconds then
			me:FireGameEvent(BossEvents.EYEBALL_BOSS_ESCAPE_IMMINENT, {
				level = Level(me),
				time_remaining = seconds,
			})
			break
		end
	end
	self.lastWarnTime = remaining
end

function Idle:LookAround(me)
	if self.attacker ~= nil then
		if me:IsTargetValid(self.attacker) then me:AimHeadTowards(me:TargetEyes(self.attacker)) end
		self.attacker = nil
		self.lookAroundTimer:Start(me:RandomFloat(LOOK_AT_ATTACKER_MIN, LOOK_AT_ATTACKER_MAX))
		return nil
	end
	if self.lookAroundTimer:IsElapsed() then
		self.lookAroundTimer:Start(me:RandomFloat(LOOK_AROUND_MIN, LOOK_AROUND_MAX))
		local angle = me:RandomFloat(-pi, pi)
		me:AimHeadTowards(me:GetAbsOrigin() + me:Vector(cos(angle), sin(angle), 0) * LOOK_AROUND_DISTANCE)
	end
	if self.isLaughReady then
		self.isLaughReady = false
		return self:SuspendFor(Emote:New(self.state, "laugh", "Halloween.EyeballBossLaugh"), "Taunt our victim")
	end
	return nil
end

function Idle:Update(me, interval)
	local state = self.state
	if not state.spell then self:WarnOfEscape(me) end
	if state.spell and self.lifeTimer:IsElapsed() then return self:ChangeTo(Escape:New(state), "Escaping...") end

	if self.moveTimer:IsElapsed() and not state.spell then
		me:SetDesiredAltitude(0)
		if IsLowOverNavMesh(me) then
			if self.lifeTimer:IsElapsed() then return self:ChangeTo(Escape:New(state), "Escaping...") end
			self.moveTimer:Start(me:RandomFloat(MOVE_MIN, MOVE_MAX))
			return self:SuspendFor(Teleport:New(state), "Moving...")
		end
	else
		me:SetDesiredAltitude(HOVER.hoverHeight)
	end

	local victim = FindClosestVisibleVictim(state, me)
	if victim then
		state.victim = victim
		return self:SuspendFor(Notice:New(state), "Target found...")
	end

	local laugh = self:LookAround(me)
	if laugh then return laugh end

	local sequence = "lookaround1"
	if IsEnraged(state, me) then
		sequence = "lookaround3"
	elseif IsGrumpy(state, me) then
		sequence = "lookaround2"
	end
	if state.sequence ~= sequence or me:IsSequenceFinished() then Play(state, me, sequence) end

	if self.talkTimer:IsElapsed() then
		if IsEnraged(state, me) then
			me:EmitSound("Halloween.EyeballBossRage")
			self.talkTimer:Start(me:RandomFloat(RAGE_TALK_MIN, RAGE_TALK_MAX))
		else
			me:EmitSound("Halloween.EyeballBossIdle")
			self.talkTimer:Start(me:RandomFloat(TALK_MIN, TALK_MAX))
		end
	end
	return self:Continue()
end

function Idle:OnResume(me, interruptingAction)
	self.talkTimer:Start(me:RandomFloat(TALK_MIN, TALK_MAX))
	return self:Continue()
end

function Idle:OnInjured(me, damageEvent)
	self.attacker = damageEvent.attacker
	return self:TryContinue()
end

function Idle:OnOtherKilled(me, victim, damageEvent)
	self.isLaughReady = true
	return self:TryContinue()
end

-------------------------------------------------------------------------------
-- Emote (CEyeballBossEmote): a sequence and a sound

function Emote:Init(state, sequence, sound)
	self.state = state
	self.sequence = sequence
	self.sound = sound
end

function Emote:OnStart(me, priorAction)
	Play(self.state, me, self.sequence)
	me:EmitSound(self.sound)
	return self:Continue()
end

function Emote:Update(me, interval)
	if me:IsSequenceFinished() then return self:Done() end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Notice (CEyeballBossNotice) and ApproachTarget (CEyeballBossApproachTarget)

function Notice:OnStart(me, priorAction)
	self.timer = NpcSystem.CountdownTimer(me)
	self.timer:Start(NOTICE_TIME)
	me:EmitSound("Halloween.EyeballBossBecomeAlert")
	return self:Continue()
end

function Notice:Update(me, interval)
	local victim = GetVictim(self.state, me)
	if victim == nil then return self:Done("Victim gone") end
	me:AimHeadTowards(me:TargetEyes(victim))
	if self.timer:IsElapsed() then return self:ChangeTo(ApproachTarget:New(self.state), "Chasing victim") end
	return self:Continue()
end

function ApproachTarget:OnStart(me, priorAction)
	self.giveUpTimer = NpcSystem.CountdownTimer(me)
	self.giveUpTimer:Start(GIVE_UP_TIME)
	self.minChaseTimer = NpcSystem.CountdownTimer(me)
	self.minChaseTimer:Start(MIN_CHASE_TIME)
	self.lingerTimer = NpcSystem.CountdownTimer(me)
	return self:Continue()
end

function ApproachTarget:Update(me, interval)
	local state = self.state
	local victim = GetVictim(state, me)
	if victim ~= FindClosestVisibleVictim(state, me) and self.minChaseTimer:IsElapsed() then
		return self:Done("Noticed better victim")
	end
	if victim == nil then return self:Done("Victim gone") end
	if self.giveUpTimer:IsElapsed() then return self:Done("Giving up") end
	if not me:IsLineOfSightClear(victim, true) then
		if self.lingerTimer:IsElapsed() then return self:Done("Lost victim") end
		return self:Continue()
	end
	self.lingerTimer:Start(LINGER_TIME)
	local attackRange = state.convars.tf_eyeball_boss_attack_range
	if IsEnraged(state, me) then attackRange = attackRange * ENRAGED_RANGE_MULTIPLIER end
	if me:IsRangeLessThan(victim, attackRange) then return self:ChangeTo(LaunchRockets:New(state), "Rocket attack!") end
	me:SetDesiredSpeed(state.convars.tf_eyeball_boss_speed)
	me:Approach(me:TargetCenter(victim))
	return self:Continue()
end

-------------------------------------------------------------------------------
-- LaunchRockets (CEyeballBossLaunchRockets)

function LaunchRockets:OnStart(me, priorAction)
	local state = self.state
	local victim = GetVictim(state, me)
	if victim == nil then return self:Done("No target") end
	self.lastTargetPosition = me:TargetOrigin(victim)
	self.initialDelayTimer = NpcSystem.CountdownTimer(me)
	self.launchTimer = NpcSystem.CountdownTimer(me)
	if IsEnraged(state, me) then
		self.rocketsLeft = ANGRY_ROCKETS
		self.initialDelayTimer:Start(ANGRY_DELAY)
		Play(state, me, "firing3")
		me:EmitSound("Halloween.EyeballBossRage")
	elseif IsGrumpy(state, me) then
		self.rocketsLeft = ANGRY_ROCKETS
		self.initialDelayTimer:Start(ANGRY_DELAY)
		Play(state, me, "firing2")
	else
		self.rocketsLeft = CALM_ROCKETS
		self.initialDelayTimer:Start(CALM_DELAY)
		Play(state, me, "firing1")
	end
	return self:Continue()
end

-- Circle the victim: to my right for an odd entity index, else my left.
local function Circle(me, victim)
	local yaw = rad(me:GetYaw())
	local right = me:Vector(sin(yaw), -cos(yaw), 0)
	local side = me:TargetIndex(victim) % 2 == 1 and CIRCLE_DISTANCE or -CIRCLE_DISTANCE
	me:Approach(me:WorldSpaceCenter() + right * side)
end

-- Where to aim: at the victim, or, enraged and not too close, where it will
-- be when a full-speed rocket arrives, unless that line hits a wall far
-- from the victim.
function LaunchRockets:TargetSpot(me, speed)
	local state = self.state
	local spot = self.lastTargetPosition
	local victim = GetVictim(state, me)
	if not IsEnraged(state, me) or victim == nil then return spot end
	local range = me:RangeTo(spot)
	if range <= LEAD_MIN_RANGE then return spot end
	local lead = me:TargetVelocity(victim) * (range / speed)
	local hit = me:TraceWorld(me:WorldSpaceCenter(), me:TargetOrigin(victim) + lead)
	if hit ~= nil and (hit - spot):Length() > LEAD_ERROR_TOLERANCE then lead = me:Vector(0, 0, 0) end
	return me:TargetOrigin(victim) + lead
end

function LaunchRockets:Launch(me)
	local state = self.state
	local speed = ROCKET_SPEED
	if not IsEnraged(state, me) then speed = ROCKET_SPEED * CALM_SPEED_FACTOR end
	local center = me:WorldSpaceCenter()
	local direction = (self:TargetSpot(me, speed) - center):GetNormalized()
	me:SpawnEntity(ROCKET_CLASS, {
		damage = ROCKET_DAMAGE,
		crit = not state.spell,
		team = state.team,
		attacker = me:GetOwnerEntity() or me,
		launcher = me,
		model = ROCKET_MODEL,
		velocity = direction * speed,
		sound = "Weapon_RPG.SingleCrit",
	}, center)
end

function LaunchRockets:Update(me, interval)
	local state = self.state
	local victim = GetVictim(state, me)
	if victim ~= nil then
		self.lastTargetPosition = me:TargetOrigin(victim)
		me:SetDesiredSpeed(state.convars.tf_eyeball_boss_speed)
		if not state.spell then Circle(me, victim) end
		me:AimHeadTowards(me:TargetEyes(victim))
	else
		me:AimHeadTowards(self.lastTargetPosition)
	end
	if self.initialDelayTimer:IsElapsed() and self.launchTimer:IsElapsed() then
		self.rocketsLeft = self.rocketsLeft - 1
		self.launchTimer:Start(ROCKET_INTERVAL)
		self:Launch(me)
		if self.rocketsLeft == 0 then return self:Done() end
	end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Teleport and Escape (CEyeballBossTeleport, CEyeballBossEscape)

local TELEPORTING_OUT, TELEPORTING_IN, TELEPORT_DONE = 0, 1, 2

-- PickNewSpawnSpot
local function PickNewSpawnSpot(me)
	local spots = me:SpawnPoints(SPAWN_SPOTS)
	if #spots == 0 then return me:GetAbsOrigin() end
	return spots[me:RandomInt(1, #spots)]
end

function Teleport:OnStart(me, priorAction)
	self.phase = TELEPORTING_OUT
	Play(self.state, me, "teleport_out")
	return self:Continue()
end

function Teleport:Update(me, interval)
	if not me:IsSequenceFinished() then return self:Continue() end
	if self.phase == TELEPORTING_OUT then
		me:SpawnEntity(VORTEX_CLASS, { death = false }, me:GetAbsOrigin())
		me:DispatchParticleEffect(TELEPORT_PARTICLE, me:GetAbsOrigin())
		me:EmitSound("Halloween.EyeballBossTeleport")
		me:SetHidden(true)
		me:SetAbsOrigin(PickNewSpawnSpot(me) + me:Vector(0, 0, TELEPORT_HEIGHT))
		self.phase = TELEPORTING_IN
	elseif self.phase == TELEPORTING_IN then
		me:SetHidden(false)
		me:DispatchParticleEffect(TELEPORT_PARTICLE, me:GetAbsOrigin())
		Play(self.state, me, "teleport_in")
		self.phase = TELEPORT_DONE
	else
		return self:Done()
	end
	return self:Continue()
end

function Escape:OnStart(me, priorAction)
	Play(self.state, me, "escape")
	me:EmitSound("Halloween.EyeballBossLaugh")
	return self:Continue()
end

-- Gone; the next eyeball starts over at the first level.
function Escape:Update(me, interval)
	if not me:IsSequenceFinished() then return self:Continue() end
	if self.state.spell then me:EmitSound("Halloween.spell_spawn_boss_disappear") end
	me:DispatchParticleEffect(ESCAPE_PARTICLE, me:GetAbsOrigin())
	me:SetBossHealth(0)
	me:Remove()
	if not self.state.spell then me:FireGameEvent(BossEvents.EYEBALL_BOSS_ESCAPED, { level = Level(me) }) end
	me:Shared().level = FIRST_LEVEL
	return self:Done()
end

-------------------------------------------------------------------------------
-- Dead (CEyeballBossDead): it falls (the hover locomotion drops a dead
-- eyeball), then pops near the ground or after 10 s.

function Dead:OnStart(me, priorAction)
	Play(self.state, me, "death")
	me:EmitSound("Halloween.EyeballBossStunned")
	self.giveUpTimer = NpcSystem.CountdownTimer(me)
	self.giveUpTimer:Start(FALL_GIVE_UP)
	return self:Continue()
end

local function IsNearGround(me)
	local center = me:WorldSpaceCenter()
	local groundZ = me:GroundHeight(center)
	return groundZ ~= nil and center.z - groundZ < POP_HEIGHT
end

-- JarateNearbyPlayers
local function JarateNearbyPlayers(me, range)
	for _, ply in ipairs(me:CollectPlayers(nil)) do
		if me:IsRangeLessThan(ply, range) and me:IsLineOfSightClear(ply, true) then
			me:AddCond(ply, Players.COND.URINE, GOO_DURATION)
		end
	end
end

function Dead:Update(me, interval)
	if not (self.giveUpTimer:IsElapsed() or IsNearGround(me)) then return self:Continue() end
	local origin = me:GetAbsOrigin()
	me:DispatchParticleEffect(DEATH_PARTICLE, origin)
	me:EmitSound("Cart.Explode")
	me:EmitSound("Halloween.EyeballBossDie")
	me:ScreenShake(origin, POP_SHAKE_AMPLITUDE, POP_SHAKE_FREQUENCY, POP_SHAKE_DURATION, SHAKE_RADIUS)
	me:Remove()
	if not self.state.spell then
		me:FireGameEvent(BossEvents.EYEBALL_BOSS_KILLED, { level = Level(me) })
		local shared = me:Shared()
		shared.level = shared.level + 1
	end
	JarateNearbyPlayers(me, GOO_RANGE)
	me:SpawnEntity(VORTEX_CLASS, { death = true }, origin)
	return self:Done()
end

-------------------------------------------------------------------------------
-- The boss hooks

-- The level every eyeball shares (CEyeballBoss::m_level).
function Level(me)
	local shared = me:Shared()
	if shared.level == nil then shared.level = FIRST_LEVEL end
	return shared.level
end

-- CEyeballBoss::Spawn: a beaten eyeball comes back tougher; otherwise
-- scaled by the players beyond the minimum.
function Health(players, level, convars)
	if level > FIRST_LEVEL then
		return convars.tf_eyeball_boss_health_at_level_2 + convars.tf_eyeball_boss_health_per_level * (level - 2)
	end
	local health = convars.tf_eyeball_boss_health_base
	local minimum = convars.tf_halloween_bot_min_player_count
	if players > minimum then
		health = health + (players - minimum) * convars.tf_eyeball_boss_health_per_player
	end
	return health
end

function Setup(state, config, me)
	state.rageTimer = NpcSystem.CountdownTimer(me)
	state.victim = nil
	state.sequence = nil
	if not state.spell then me:SetBossHealth(1) end
end

-- CEyeballBoss::OnTakeDamage_Alive: a spell is immune; otherwise the bar
-- shows what the hit leaves.
function ModifyDamage(state, damageEvent, me)
	if state.spell then return 0 end
	local left = max(0, me:GetHealth() - damageEvent.amount)
	me:SetBossHealth(left / me:GetMaxHealth())
	return damageEvent.amount
end

-- CEyeballBossBehavior::OnInjured: crits and heavy damage from players
-- anger it.
function OnInjured(state, damageEvent, me)
	if not HalloweenBoss.IsPlayer(me, damageEvent.attacker) then return end
	if damageEvent.crit then BecomeEnraged(state, me, ENRAGE_DURATION) end
	if state.dps > ENRAGE_DPS then BecomeEnraged(state, me, ENRAGE_DURATION) end
end

-- CEyeballBoss::Update: the skin and the anger pose follow the mood.
function OnUpdate(state, me)
	if IsEnraged(state, me) then
		if state.spell then
			me:SetSkin(state.team == Teams.RED and SKIN_TEAM_RED or SKIN_TEAM_BLUE)
		else
			me:SetSkin(SKIN_RED)
		end
		me:SetPoseParameter("anger", ANGER_ENRAGED)
	elseif IsGrumpy(state, me) then
		me:SetSkin(SKIN_NORMAL)
		me:SetPoseParameter("anger", ANGER_GRUMPY)
	else
		me:SetSkin(SKIN_NORMAL)
		me:SetPoseParameter("anger", ANGER_CALM)
	end
end

function EmergeAction(state) return Emerge:New(state) end
function DyingAction(state) return Dead:New(state) end

HalloweenBoss.Variant(_M)

-------------------------------------------------------------------------------
-- The teleport vortex (CTeleportVortex): a ±50 trigger living 5 s. It pulls
-- airborne players who look at it, and sends whoever touches it to a
-- random open info_target: spawn_loot from a death vortex (which shows the
-- book), spawn_purgatory otherwise.
--
-- Vortex.New(death, port, splitTeam); vortex:Think() each tick;
-- vortex:Touch(player). A split vortex (Merasmus's death vortex,
-- SetupVortex( true, true )) sends each team to its own spots, the name
-- with _red or _blue added.
-- The port (VORTEX_METHODS), implemented by teleport_vortex:
--   Now(), RandomInt(lo, hi), Vector(x, y, z), WorldSpaceCenter(), Remove(),
--   EmitSound(name), CollectPlayers(team) (living; nil means RED and BLU),
--   TeamOf(p), TargetOrigin(p), TargetCenter(p), IsTargetOnGround(p),
--   IsLookingTowards(p, v, cosTolerance), IsLineOfSightClear(p, v) (from
--   p's eyes, ignoring actors), SpawnPoints(name), ApplyImpulse(p, v),
--   Teleport(p, v), DealDamage(t, amount, dmgType, attacker).

VORTEX_METHODS = {
	"Now",
	"RandomInt",
	"Vector",
	"WorldSpaceCenter",
	"Remove",
	"EmitSound",
	"CollectPlayers",
	"TeamOf",
	"TargetOrigin",
	"TargetCenter",
	"IsTargetOnGround",
	"IsLookingTowards",
	"IsLineOfSightClear",
	"SpawnPoints",
	"ApplyImpulse",
	"Teleport",
	"DealDamage",
}

VORTEX_LIFETIME = 5
VORTEX_HALF_WIDTH = 50
VORTEX_SUCTION_RANGE = 500
VORTEX_SUCTION_FORCE = 30
VORTEX_LOOK_TOLERANCE = 0.9 -- BCC_DEFAULT_LOOK_TOWARDS_TOLERANCE
VORTEX_RAMP_FRACTION = 10 -- vortex_fade_fraction_denom
VORTEX_LOOT = "spawn_loot"
VORTEX_PURGATORY = "spawn_purgatory"
VORTEX_RED_SUFFIX, VORTEX_BLUE_SUFFIX = "_red", "_blue"
VORTEX_BOOK_MODEL = "models/props_halloween/bombonomicon.mdl"
SPAWN_OCCUPIED_RANGE = 25
TELEFRAG_DAMAGE = 1000

local BOOK_SILENT, BOOK_IN, BOOK_OUT = 0, 1, 2

local VortexModel = {}
VortexModel.__index = VortexModel
Vortex = {}

function Vortex.New(death, port, splitTeam)
	local lifeTimer = NpcSystem.CountdownTimer(port)
	lifeTimer:Start(VORTEX_LIFETIME)
	return setmetatable({
		port = port,
		death = death,
		splitTeam = splitTeam == true,
		where = death and VORTEX_LOOT or VORTEX_PURGATORY,
		lifeTimer = lifeTimer,
		book = BOOK_SILENT,
	}, VortexModel)
end

-- The book's sounds as it rises in and sinks out.
function VortexModel:RingBook()
	local port, life = self.port, self.lifeTimer
	local ramp = VORTEX_LIFETIME / VORTEX_RAMP_FRACTION
	local elapsed = life:GetElapsedTime()
	if self.book == BOOK_SILENT and elapsed <= ramp then
		port:EmitSound("Halloween.TeleportVortex.BookSpawn")
		self.book = BOOK_IN
	elseif self.book == BOOK_IN and elapsed >= VORTEX_LIFETIME - ramp then
		port:EmitSound("Halloween.TeleportVortex.BookExit")
		self.book = BOOK_OUT
	end
end

-- VortexThink
function VortexModel:Think()
	local port = self.port
	if self.lifeTimer:IsElapsed() then
		port:Remove()
		return
	end
	if self.death then self:RingBook() end
	local center = port:WorldSpaceCenter()
	for _, ply in ipairs(port:CollectPlayers(nil)) do
		if not port:IsTargetOnGround(ply) then
			local to = center - port:TargetCenter(ply)
			local lookingIn = port:IsLookingTowards(ply, center, VORTEX_LOOK_TOLERANCE)
			if to:Length() <= VORTEX_SUCTION_RANGE and lookingIn and port:IsLineOfSightClear(ply, center) then
				port:ApplyImpulse(ply, to:GetNormalized() * VORTEX_SUCTION_FORCE)
			end
		end
	end
end

-- SendPlayerToTheUnderworld: a random spot no enemy stands on; with none
-- free, a random spot, and the enemies on it are telefragged.
function VortexModel:Touch(ply)
	local port = self.port
	local where = self.where
	if self.splitTeam then
		where = where .. (port:TeamOf(ply) == Teams.RED and VORTEX_RED_SUFFIX or VORTEX_BLUE_SUFFIX)
	end
	local spots = port:SpawnPoints(where)
	if #spots == 0 then return end
	local enemies = {}
	for _, team in ipairs(Targeting.EnemyTeamsOf(port:TeamOf(ply))) do
		for _, enemy in ipairs(port:CollectPlayers(team)) do enemies[#enemies + 1] = enemy end
	end
	local function Occupants(spot)
		local found = {}
		for _, enemy in ipairs(enemies) do
			if (spot - port:TargetOrigin(enemy)):Length() < SPAWN_OCCUPIED_RANGE then found[#found + 1] = enemy end
		end
		return found
	end
	local open = {}
	for _, spot in ipairs(spots) do
		if #Occupants(spot) == 0 then open[#open + 1] = spot end
	end
	local destination
	if #open == 0 then
		destination = spots[port:RandomInt(1, #spots)]
		for _, enemy in ipairs(Occupants(destination)) do
			port:DealDamage(enemy, TELEFRAG_DAMAGE, Actor.DMG_CRUSH, ply)
		end
	else
		destination = open[port:RandomInt(1, #open)]
	end
	port:Teleport(ply, destination)
end
