-- TF2's skeletons as a games.npc.nextbot variant: CZombie (halloween/zombie/
-- zombie.cpp) and its actions (zombie_behavior/*.cpp), run against the
-- combatant port (games.npc.combatant). The three skeleton types are
-- data plus per-type strategies in TYPES, so no rule switches on the type.
--
-- Also here, as the data and rules their bindings read:
--   - tf_zombie_spawner's keyvalues (SpawnerConfig) and its team rule
--     (SpawnerTeam), for features.npc.spawner;
--   - tf_zombie's config (BindingConfig);
--   - the skull grenade tf_projectile_spellspawnzombie: its throw
--     (SkullThrow, CreateSpellSpawnZombie) and what it hatches
--     (HatchConfig, CTFProjectile_SpellSpawnZombie::InitialExplodeEffects).
--
-- A damage event's `attackerIsCharacter` (a player, NPC or NextBot; TF2's
-- CBaseCombatCharacter) is added by the tf_zombie binding.
local ipairs, pairs, tonumber = ipairs, pairs, tonumber
local floor = math.floor
local require = require
local Npc = npc.nextbot
local Actor = npc.actor
local Targeting = npc.targeting
local Teams = gameplay.teams
module(...)

-- CZombie::SkeletonType_t
SKELETON_NORMAL, SKELETON_KING, SKELETON_MINI = 0, 1, 2

KIND = "zombie"
PATH = "foundation.wetsands.path.scatter"

MAX_ACTIVE_DEFAULT = 30 -- tf_max_active_zombie
CHASE_MIN_DURATION = 3 -- ZOMBIE_CHASE_MIN_DURATION
STAND_AND_SWING_RANGE = 50
SWING_RANGE = 150
REPATH_INTERVAL = 0.5
LOOKAHEAD = 100
OFF_MESH_TOLERANCE = 50 -- CZombieAttack::IsPotentiallyChaseable
ATTACK_INTERVAL_MIN, ATTACK_INTERVAL_MAX = 0.8, 1.2
SPECIAL_INTERVAL_MIN, SPECIAL_INTERVAL_MAX = 5, 10
STUCK_DAMAGE = 99999.9 -- CZombieAttack::OnStuck

STOMP_DELAY = 1
STOMP_RANGE = 200
STOMP_FORCE = 500
STOMP_PARTICLE = "bomibomicon_ring"

MINI_LIFETIME = 30
MINIS_ON_DEATH = 3
SPAWN_HEALTH = 50 -- CZombie::Spawn; a king sets its own
YAW_RANGE = 360

-- CTFSpellBook's rare tier (TFGameRules()->DropSpellPickup(pos, 1)); the
-- same number as the spellbook's TIER_RARE.
SPELL_TIER_RARE = 1

SKIN_RED, SKIN_BLUE, SKIN_HALLOWEEN = 0, 1, 2
local SKIN_BY_TEAM = {
	[Teams.RED] = SKIN_RED,
	[Teams.BLUE] = SKIN_BLUE,
	[Teams.HALLOWEEN] = SKIN_HALLOWEEN,
}

LOCOMOTION = {
	runSpeed = 300,
	stepHeight = 18,
	jumpHeight = 18,
	deathDropHeight = 200,
	maxYawRate = 200,
	acceleration = 500,
	deceleration = 500,
}

-- IBody's default hull, scaled by the model scale.
HULL_MINS = { -13, -13, 0 }
HULL_MAXS = { 13, 13, 68 }

SKELETON_MODEL = "models/bots/skeleton_sniper/skeleton_sniper.mdl"
KING_MODEL = "models/bots/skeleton_sniper_boss/skeleton_sniper_boss.mdl"
CROWN_MODEL = "models/player/items/demo/crown.mdl"
HEAD_BONE = "bip_head"
MINI_HEAD_SCALE = 3

BREAK_SOUND = "Halloween.skeleton_break"
DEATH_OUTPUT = "OnDeath"

GOOP_HALLOWEEN = "spell_skeleton_goop_green"
GOOP_RED = "spell_pumpkin_mirv_goop_red"
GOOP_BLUE = "spell_pumpkin_mirv_goop_blue"

-- Every particle system a skeleton or its skull dispatches, for the npc
-- controller to precache (the files: features/npc/sh.lua).
PARTICLES = {
	STOMP_PARTICLE, -- cinefx.pcf
	GOOP_HALLOWEEN, -- halloween.pcf
	GOOP_RED, -- halloween.pcf
	GOOP_BLUE, -- halloween.pcf
}

ZOMBIE_CLASS = "tf_zombie"
SPAWNER_MAX_DEFAULT = 1 -- CZombieSpawner::CZombieSpawner

-- The skull grenade (CreateSpellSpawnZombie).
SKULL_CLASS = "tf_projectile_spellspawnzombie"
SKULL_MODEL = "models/props_mvm/mvm_human_skull_collide.mdl"
SKULL_SOUND = "Cleaver.ImpactFlesh"
SKULL_SCATTER = 32
SKULL_START_HEIGHT = 16
SKULL_LIFT_MIN, SKULL_LIFT_MAX = 1, 1.6
SKULL_SPEED_MIN, SKULL_SPEED_MAX = 250, 300
SKULL_FUSE_MIN, SKULL_FUSE_MAX = 2, 2.5
SKULL_SPIN = { 300, 300, 100 }
local UNIT = 1 -- RandomVector(-1, 1)

local ACTIVITY_NAMES = {
	transition = "ACT_TRANSITION",
	run = "ACT_MP_RUN_MELEE",
	swing = "ACT_MP_ATTACK_STAND_MELEE",
	flinch = "ACT_MP_GESTURE_FLINCH_CHEST",
	stomp = "ACT_SPECIAL_ATTACK1",
}

local DMG_SLASH = Actor.DMG_SLASH
local CountdownTimer = Npc.CountdownTimer

-------------------------------------------------------------------------------
-- Rules every action shares

-- CZombieSpawner::Think and CZombie::Spawn: RED and BLU keep their team;
-- anything else is HALLOWEEN.
function SpawnerTeam(team)
	if team == Teams.RED or team == Teams.BLUE then return team end
	return Teams.HALLOWEEN
end

-- CZombie::OnTakeDamage_Alive and the skull's GetExplodeEffectParticle.
function GoopParticle(team)
	if team == Teams.HALLOWEEN then return GOOP_HALLOWEEN end
	if team == Teams.RED then return GOOP_RED end
	return GOOP_BLUE
end

-- Who a skeleton's blows come from: its owner, else itself (nil).
local function Attacker(me)
	local owner = me:GetOwnerEntity()
	if me:IsTargetValid(owner) then return owner end
	return nil
end

-- CZombie::ShouldSuicide
local function ShouldSuicide(state, me)
	if state.lifeTimer:HasStarted() and state.lifeTimer:IsElapsed() then return true end
	local owner = me:GetOwnerEntity()
	if me:IsTargetValid(owner) and me:TeamOf(owner) ~= state.team then return true end
	return state.culled
end

-- CZombie::FireDeathOutput. TF2 guards it to fire once; here the Behavior
-- does: a kill leaves a Done that runs before any suicide, and a suicide
-- ends the Behavior, so no kill reaches it after.
local function FireDeathOutput(me, culprit)
	me:FireOutput(DEATH_OUTPUT, culprit)
end

-- CZombieAttack::IsPotentiallyChaseable. TF2's spawn-room nav attribute is
-- the combatant port's InRespawnRoom.
local function IsChaseable(me, t)
	return me:IsTargetValid(t)
		and me:IsTargetAlive(t)
		and me:IsOnNavMesh(t, OFF_MESH_TOLERANCE)
		and not me:InRespawnRoom(t)
end

-- An enemy player, or an enemy team member that is not one (an AI war
-- soldier: Sandcastle's, not TF2's).
local function IsEnemyPlayer(me, team, other)
	for _, enemyTeam in ipairs(Targeting.EnemyTeamsOf(team)) do
		for _, ply in ipairs(me:CollectPlayers(enemyTeam)) do
			if ply == other then return true end
		end
		for _, member in ipairs(me:CollectMembers(enemyTeam)) do
			if member == other then return true end
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Actions

-- CZombieSpecialAttack: the king's stomp.
local SpecialAttack = Npc.Action:Extend("SpecialAttack")

function SpecialAttack:Init(state) self.state = state end

function SpecialAttack:OnStart(me)
	me:StartActivity(self.state.acts.stomp)
	self.stompTimer = CountdownTimer(me)
	self.stompTimer:Start(STOMP_DELAY)
	return self:Continue()
end

-- CZombieSpecialAttack::DoSpecialAttack and CTFGameRules::PushAllPlayersAway:
-- every living target-team player whose eyes are within range of my feet
-- is thrown up and away and takes my attack damage.
function SpecialAttack:Stomp(me)
	local state = self.state
	local origin = me:GetAbsOrigin()
	me:DispatchParticleEffect(STOMP_PARTICLE, origin)
	local attacker = Attacker(me)
	for _, team in ipairs(Targeting.EnemyTeamsOf(state.team)) do
		for _, ply in ipairs(me:CollectPlayers(team)) do
			local toPlayer = me:TargetEyes(ply) - origin
			if toPlayer:Length() < STOMP_RANGE then
				local away = me:Vector(toPlayer.x, toPlayer.y, 0):GetNormalized()
				me:ApplyImpulse(ply, me:Vector(away.x, away.y, UNIT) * STOMP_FORCE)
				me:DealDamage(ply, state.kind.attackDamage, DMG_SLASH, attacker)
			end
		end
		-- Sandcastle's own: the AI war's soldiers are stomped as players are
		for _, member in ipairs(me:CollectMembers(team)) do
			if (me:TargetOrigin(member) - origin):Length() < STOMP_RANGE then
				me:DealDamage(member, state.kind.attackDamage, DMG_SLASH, attacker)
			end
		end
	end
end

function SpecialAttack:Update(me, interval)
	if self.stompTimer:HasStarted() and self.stompTimer:IsElapsed() then
		self:Stomp(me)
		self.stompTimer:Invalidate()
	end
	if me:IsActivityFinished() then return self:Done() end
	return self:Continue()
end

-- CZombieAttack
local Attack = Npc.Action:Extend("Attack")

function Attack:Init(state) self.state = state end

function Attack:OnStart(me)
	self.path = me:NewPath()
	self.path:SetMinLookAheadDistance(LOOKAHEAD)
	self.attackTimer = CountdownTimer(me)
	self.specialTimer = CountdownTimer(me)
	self.focusTimer = CountdownTimer(me)
	self.target = nil
	me:StartActivity(self.state.acts.run)
	self.specialTimer:Start(me:RandomFloat(SPECIAL_INTERVAL_MIN, SPECIAL_INTERVAL_MAX))
	return self:Continue()
end

-- CZombieAttack::SelectVictim: keep a chaseable victim while its focus
-- lasts; otherwise the nearest visible enemy player or enemy skeleton (or,
-- Sandcastle's own, enemy AI war soldier).
function Attack:SelectVictim(me)
	if self.target ~= nil and IsChaseable(me, self.target) and not self.focusTimer:IsElapsed() then return end
	local team = self.state.team
	local victim, victimRange = nil, nil
	local function Consider(t)
		local range = me:RangeTo(t)
		if victimRange == nil or range < victimRange then victim, victimRange = t, range end
	end
	for _, enemyTeam in ipairs(Targeting.EnemyTeamsOf(team)) do
		for _, ply in ipairs(me:CollectPlayers(enemyTeam)) do
			local hidden = Targeting.IsHiddenFromNPC(function(cond) return me:InCond(ply, cond) end)
			if IsChaseable(me, ply) and not hidden then Consider(ply) end
		end
		for _, member in ipairs(me:CollectMembers(enemyTeam)) do
			if IsChaseable(me, member) then Consider(member) end
		end
	end
	for _, zombie in ipairs(me:CollectNPCs(KIND)) do
		if me:TeamOf(zombie) ~= team and IsChaseable(me, zombie) then Consider(zombie) end
	end
	if victim ~= nil then self.focusTimer:Start(CHASE_MIN_DURATION) end
	self.target = victim
end

function Attack:Update(me, interval)
	local state = self.state
	local kind = state.kind
	self:SelectVictim(me)
	local target = self.target
	if target == nil then return self:Continue() end

	if me:IsRangeGreaterThan(target, STAND_AND_SWING_RANGE) or not me:IsLineOfSightClear(target) then
		if self.path:GetAge() > REPATH_INTERVAL then self.path:Compute(me:TargetOrigin(target)) end
		self.path:Update()
	end

	if me:IsRangeLessThan(target, SWING_RANGE) then
		me:FaceTowards(me:TargetCenter(target))
		if not me:IsPlayingGesture(state.acts.swing) then me:AddGesture(state.acts.swing) end
		if me:IsRangeLessThan(target, kind.attackRange) then
			if kind.special ~= nil and self.specialTimer:IsElapsed() then
				self.specialTimer:Start(me:RandomFloat(SPECIAL_INTERVAL_MIN, SPECIAL_INTERVAL_MAX))
				return self:SuspendFor(kind.special:New(state), "Do Special Attack!")
			end
			if self.attackTimer:IsElapsed() then
				self.attackTimer:Start(me:RandomFloat(ATTACK_INTERVAL_MIN, ATTACK_INTERVAL_MAX))
				me:DealDamage(target, kind.attackDamage, DMG_SLASH, Attacker(me))
			end
		end
	end

	if not me:IsActivity(state.acts.run) then me:StartActivity(state.acts.run) end
	return self:Continue()
end

-- TF2's own damage filter refuses this blow, as it comes from my team.
function Attack:OnStuck(me)
	me:DealDamage(me, STUCK_DAMAGE, DMG_SLASH)
	return self:TryContinue()
end

-- A team skeleton locks onto an enemy player that touches it.
function Attack:OnContact(me, other)
	local team = self.state.team
	if team ~= Teams.HALLOWEEN and IsEnemyPlayer(me, team, other) then
		self.target = other
		self.focusTimer:Start(CHASE_MIN_DURATION)
	end
	return self:TryContinue()
end

-- CZombieSpawn
local Spawn = Npc.Action:Extend("Spawn")

function Spawn:Init(state) self.state = state end

function Spawn:OnStart(me)
	me:StartActivity(self.state.acts.transition)
	return self:Continue()
end

function Spawn:Update(me, interval)
	if me:IsActivityFinished() then return self:ChangeTo(Attack:New(self.state), "Start Attack!") end
	return self:Continue()
end

-- CZombieBehavior: suicide, death and laughter over whatever it is doing.
local ZombieBehavior = Npc.Action:Extend("ZombieBehavior")

function ZombieBehavior:Init(state) self.state = state end
function ZombieBehavior:InitialContainedAction(me) return Spawn:New(self.state) end

function ZombieBehavior:OnStart(me)
	self.laughTimer = CountdownTimer(me)
	return self:Continue()
end

function ZombieBehavior:ShouldLaugh(me)
	local kind = self.state.kind
	if not self.laughTimer:HasStarted() then
		self.laughTimer:Start(me:RandomFloat(kind.laughMin, kind.laughMax))
		return false
	end
	if self.laughTimer:IsElapsed() then
		self.laughTimer:Invalidate()
		return true
	end
	return false
end

function ZombieBehavior:Update(me, interval)
	local state = self.state
	local dead = not me:IsAlive()
	if not dead and ShouldSuicide(state, me) then
		FireDeathOutput(me, me)
		dead = true
	end
	if dead then
		me:Remove()
		return self:Done("dead")
	end
	if self:ShouldLaugh(me) then me:EmitSound(state.kind.laughSound) end
	return self:Continue()
end

-- CZombie::Event_Killed, then CZombieBehavior::OnKilled: the type's death
-- only when a player or NPC did it.
function ZombieBehavior:OnKilled(me, damageEvent)
	local state = self.state
	me:EmitSound(BREAK_SOUND)
	FireDeathOutput(me, damageEvent.inflictor)
	if damageEvent.attackerIsCharacter then state.kind.onDeath(state, me) end
	me:Remove()
	return self:TryDone()
end

-------------------------------------------------------------------------------
-- The types (CZombie::SetSkeletonType, CZombieBehavior)

-- A normal skeleton throws three skulls that hatch minis
-- (CreateSpellSpawnZombie), thrown by its owner or itself.
local function ThrowSkulls(state, me)
	local thrower = Attacker(me) or me
	local origin = me:GetAbsOrigin()
	for _ = 1, MINIS_ON_DEATH do
		me:SpawnEntity(SKULL_CLASS, {
			thrower = thrower,
			team = state.team,
			skeletonType = SKELETON_MINI,
		}, origin)
	end
end

local function DropRareSpell(state, me)
	me:DropSpellPickup(me:GetAbsOrigin(), SPELL_TIER_RARE)
end

local function Nothing() end

local function Crown(me) me:AttachProp(CROWN_MODEL, HEAD_BONE) end
local function BigHead(me) me:SetBoneScale(HEAD_BONE, MINI_HEAD_SCALE) end

TYPES = {
	[SKELETON_NORMAL] = {
		model = SKELETON_MODEL,
		scale = nil, -- keeps the map's modelscale
		health = SPAWN_HEALTH,
		attackRange = 50,
		attackDamage = 30,
		laughMin = 4,
		laughMax = 5,
		laughSound = "Halloween.skeleton_laugh_medium",
		cullable = true,
		special = nil,
		dress = Nothing,
		onDeath = ThrowSkulls,
	},
	[SKELETON_KING] = {
		model = KING_MODEL,
		scale = 2,
		health = 1000,
		attackRange = 100,
		attackDamage = 100,
		laughMin = 6,
		laughMax = 7,
		laughSound = "Halloween.skeleton_laugh_giant",
		cullable = false,
		special = SpecialAttack,
		dress = Crown,
		onDeath = DropRareSpell,
	},
	[SKELETON_MINI] = {
		model = SKELETON_MODEL,
		scale = 0.5,
		health = SPAWN_HEALTH,
		attackRange = 40,
		attackDamage = 20,
		laughMin = 2,
		laughMax = 3,
		laughSound = "Halloween.skeleton_laugh_small",
		cullable = true,
		special = nil,
		dress = BigHead,
		onDeath = Nothing,
	},
}

function Model(skeletonType)
	return TYPES[skeletonType].model
end

-------------------------------------------------------------------------------
-- The NPC variant

-- CZombie::SpawnAtPos and Spawn, in their order: the map's scale, the team
-- and its skin, a random yaw and the rise; then the lifetime; then the type.
-- config = { lifetime, owner, skeletonType, modelScale, maxActive }; the
-- team is the one the binding gave me.
function NewState(config, me)
	if config.modelScale then me:SetModelScale(config.modelScale) end
	local acts = {}
	for key, name in pairs(ACTIVITY_NAMES) do acts[key] = me:Activity(name) end
	local team = SpawnerTeam(me:GetTeamNumber())
	me:SetYaw(me:RandomFloat(0, YAW_RANGE))
	me:StartActivity(acts.transition)
	me:SetSkin(SKIN_BY_TEAM[team])

	local lifeTimer = CountdownTimer(me)
	if config.lifetime > 0 then lifeTimer:Start(config.lifetime) end

	local kind = TYPES[config.skeletonType]
	if kind.scale then me:SetModelScale(kind.scale) end
	me:SetHealth(kind.health)
	me:SetMaxHealth(kind.health)
	kind.dress(me)

	return {
		team = team,
		skeletonType = config.skeletonType,
		kind = kind,
		acts = acts,
		lifeTimer = lifeTimer,
		maxActive = config.maxActive,
		culled = false,
	}
end

function InitialAction(state)
	return ZombieBehavior:New(state)
end

-- CZombie::OnTakeDamage_Alive: my team cannot hurt me; anyone else makes
-- me flinch and splash.
function FilterDamage(state, damageEvent, me)
	local attacker = damageEvent.attacker
	if me:IsTargetValid(attacker) and me:TeamOf(attacker) == state.team then return false end
	if not me:IsPlayingGesture(state.acts.flinch) then me:AddGesture(state.acts.flinch) end
	me:DispatchParticleEffect(GoopParticle(state.team), damageEvent.position)
	return true
end

-- CZombie::Spawn's cull: over tf_max_active_zombie (as the newest
-- skeleton saw it), the oldest skeletons that are not kings must suicide.
function Cull(liveStates)
	local excess = #liveStates - liveStates[#liveStates].maxActive
	local culled = {}
	for _, state in ipairs(liveStates) do
		if excess <= 0 then break end
		if state.kind.cullable then
			culled[#culled + 1] = state
			excess = excess - 1
		end
	end
	return culled
end

-------------------------------------------------------------------------------
-- The bindings' configs

-- Keyvalues read as TF2's keyfields read them (atoi, atof): a non-number is 0.
local ATOI_FALLBACK = 0

local function Keyfield(kv, key, default)
	if kv[key] == nil then return default end
	return tonumber(kv[key]) or ATOI_FALLBACK
end

local function IntKeyfield(kv, key, default)
	return floor(Keyfield(kv, key, default))
end

-- tf_zombie_spawner's keyvalues (lower-case keys) as a features.npc.spawner
-- config, with CZombieSpawner's defaults. zombie_scale, set by some maps,
-- is in neither the FGD nor the C++, and is ignored.
function SpawnerConfig(kv)
	return {
		class = ZOMBIE_CLASS,
		team = IntKeyfield(kv, "teamnum", Teams.UNASSIGNED),
		maxActive = IntKeyfield(kv, "max_zombies", SPAWNER_MAX_DEFAULT),
		infinite = IntKeyfield(kv, "infinite_zombies", ATOI_FALLBACK) ~= 0,
		npcConfig = {
			lifetime = Keyfield(kv, "zombie_lifetime", 0),
			skeletonType = IntKeyfield(kv, "zombie_type", SKELETON_NORMAL),
		},
		teamOf = SpawnerTeam,
	}
end

-- A skeleton the map places has no lifetime, no owner, and is normal.
local PLACED = {
	lifetime = 0,
	skeletonType = SKELETON_NORMAL,
}

local function OrPlaced(given, key)
	if given[key] == nil then return PLACED[key] end
	return given[key]
end

-- tf_zombie's config: what its spawner or skull gave (nil for one the map
-- placed; its TeamNum keyvalue then gives the team), its keyvalues, and
-- tf_max_active_zombie. A field the caller leaves out is the placed one's.
function BindingConfig(given, kv, maxActive)
	local from = given or PLACED
	return {
		team = from.team,
		lifetime = OrPlaced(from, "lifetime"),
		owner = from.owner,
		skeletonType = OrPlaced(from, "skeletonType"),
		modelScale = kv.modelscale and tonumber(kv.modelscale),
		maxActive = maxActive,
	}
end

-- CreateSpellSpawnZombie: the skull starts beside and above where it is
-- thrown from, and flies up and out on a fuse. `random(lo, hi)` draws a
-- float; `vector(x, y, z)` makes a vector. The result is a
-- games.gameplay.projectile.grenade config plus the start offset and spin.
function SkullThrow(random, vector)
	local offset = vector(random(-SKULL_SCATTER, SKULL_SCATTER), random(-SKULL_SCATTER, SKULL_SCATTER), SKULL_START_HEIGHT)
	local direction = vector(random(-UNIT, UNIT), random(-UNIT, UNIT), random(-UNIT, UNIT)):GetNormalized()
	local lifted = vector(direction.x, direction.y, random(SKULL_LIFT_MIN, SKULL_LIFT_MAX))
	return {
		model = SKULL_MODEL,
		offset = offset,
		velocity = lifted * random(SKULL_SPEED_MIN, SKULL_SPEED_MAX),
		spin = vector(SKULL_SPIN[1], SKULL_SPIN[2], SKULL_SPIN[3]),
		fuse = random(SKULL_FUSE_MIN, SKULL_FUSE_MAX),
		explodeOnTouch = false,
	}
end

-- CTFProjectile_SpellSpawnZombie::InitialExplodeEffects: the skull hatches
-- a skeleton of its team and type that lives 30 s, owned by its thrower
-- only when that is a player. skull = { thrower, team, skeletonType }.
function HatchConfig(skull, throwerIsPlayer)
	local owner = nil
	if throwerIsPlayer then owner = skull.thrower end
	return {
		team = skull.team,
		lifetime = MINI_LIFETIME,
		owner = owner,
		skeletonType = skull.skeletonType,
	}
end
