-- NextSoldier's base: the interface our code keeps of DrGBase's NextBot
-- (issue #8), its names and hook contracts only. NextSoldier's own NextBot
-- base implements it from scratch over GMod's NextBot, nothing taken from
-- DrGBase's source, each component on its own model and native where that
-- pays: the senses on nextsoldier.vision and .hearing, the relations as a
-- table by entity and faction, locomotion on wetsands' path costs, the
-- intention on generator.hfsm's chart.
--
-- The components are NextBot's own (TF2's INextBotComponent: IIntention,
-- IVision, ILocomotion, IBody), with the relations and the soldier's life
-- apart. Each declares:
--   methods  a core.port: what the base does when asked
--   hooks    what the base raises on a soldier class, which it may define
--   fields   a class's settings, read by the base
-- hooks and fields are named sets, or nil for a component with none;
-- Hooks(component) and Fields(component) list them either way.
--
-- COMPONENTS, in order; INTENTION, SENSES, RELATIONS, LOCOMOTION, BODY, LIFE
-- METHODS     the port of every component's methods, in order
-- HOOKS       the named set of every hook; FIELDS, of every field
-- ComponentOf(name) -> the component declaring a method, hook or field, or nil
-- REPLACED    names our code uses of DrGBase that the base does not keep,
--             each with what takes its place
--
-- .devtools/bin/drg_interface.py inventories the DrGBase names our code
-- uses, and its check refuses one this file does not declare.
local Port, Sets = core.port, world.sets
local ipairs = ipairs
module(...)

local function Named(name, members)
	if members == nil then return nil end
	return Sets.Named(name, members)
end

local function Component(name, spec)
	return {
		name = name,
		methods = Port.New("NextSoldier " .. name, spec.methods),
		hooks = Named("NextSoldier " .. name .. " hooks", spec.hooks),
		fields = Named("NextSoldier " .. name .. " fields", spec.fields),
	}
end

local NONE = {}

function Hooks(component)
	return component.hooks and component.hooks:Members() or NONE
end

function Fields(component)
	return component.fields and component.fields:Members() or NONE
end

-- What the soldier wants and does: its enemy, its AI on or off, and the
-- behaviour coroutine (BehaveStart, yielded and paused); its hooks are the
-- stages of fighting an enemy.
INTENTION = Component("intention", {
	methods = { "GetEnemy", "HasEnemy", "SetAIDisabled", "IsAIDisabled", "BehaveStart", "YieldCoroutine",
		"PauseCoroutine" },
	hooks = { "OnIdle", "OnNewEnemy", "OnLastEnemy", "OnFetchEnemy", "OnChaseEnemy", "OnAvoidEnemy",
		"OnIdleEnemy", "OnRangeAttack", "OnMeleeAttack", "ShouldRun" },
	fields = { "ReachEnemyRange", "AvoidEnemyRange", "RangeAttackRange", "MeleeAttackRange" },
})

-- What it senses: sight (spotted, lost), hearing, and the range to another.
SENSES = Component("senses", {
	methods = { "IsDeaf", "GetHearingCoefficient", "GetRangeTo", "SetNoTarget" },
	hooks = { "OnSpotted", "OnLost" },
})

-- Whom it fights: dispositions by entity and by faction.
RELATIONS = Component("relations", {
	methods = { "AddEntityRelationship", "SetFactionRelationship", "Disposition", "JoinFaction", "LeaveFaction" },
	fields = { "Factions", "DefaultRelationship", "IsDrGNextbot" },
})

-- How it moves: its path, priced by the class (GetPathGenerator), facing,
-- jumping, crouching, climbing ledges and dropping down.
LOCOMOTION = Component("locomotion", {
	methods = { "FollowPath", "GetPath", "FaceTowards", "IsMoving", "Jump", "IsCrouching", "SetCrouching",
		"GetStepHeight", "GetDeathDropHeight" },
	hooks = { "GetPathGenerator", "OnComputePath", "CustomClimbing", "OnStartClimbing", "OnLandOnGround",
		"OnNavAreaChanged" },
	fields = { "WalkSpeed", "RunSpeed", "ClimbLedges", "ClimbLedgesMaxHeight", "DeathDropHeight" },
})

-- What it looks like and holds: its weapons, scale, models, animations and
-- sounds.
BODY = Component("body", {
	methods = { "GetActiveWeapon", "GetWeapons", "GiveWeapon", "RemoveWeapon", "SelectWeapon", "SetScale" },
	hooks = { "OnWeaponChange", "OnUpdateAnimation", "OnAnimEvent" },
	fields = { "Models", "Weapons", "BloodColor", "CollisionBounds", "IdleAnimation", "WalkAnimation",
		"RunAnimation", "OnDamageSounds", "OnDeathSounds" },
})

-- Its life: alive, down or dead, hurt and dying, and its own setup and think.
LIFE = Component("life", {
	methods = { "IsAlive", "IsDead", "IsDown" },
	hooks = { "CustomInitialize", "CustomThink", "OnTakeDamage", "OnTraceAttack", "OnDealtDamage", "OnDeath" },
	fields = { "SpawnHealth", "RagdollOnDeath" },
})

COMPONENTS = { INTENTION, SENSES, RELATIONS, LOCOMOTION, BODY, LIFE }

local methods, hooks, fields, owner = {}, {}, {}, {}
for _, component in ipairs(COMPONENTS) do
	for _, name in ipairs(component.methods:Methods()) do
		methods[#methods + 1], owner[name] = name, component
	end
	for _, name in ipairs(Hooks(component)) do
		hooks[#hooks + 1], owner[name] = name, component
	end
	for _, name in ipairs(Fields(component)) do
		fields[#fields + 1], owner[name] = name, component
	end
end

METHODS = Port.New("NextSoldier base", methods)
HOOKS = Sets.Named("NextSoldier hooks", hooks)
FIELDS = Sets.Named("NextSoldier fields", fields)

function ComponentOf(name)
	return owner[name]
end

REPLACED = {
	-- DrGBase's own landing handling, which the soldier's OnLandOnGround
	-- calls first: the base runs its own before raising the hook.
	_HandleLandOnGround = "the base's landing, run before OnLandOnGround",
}
