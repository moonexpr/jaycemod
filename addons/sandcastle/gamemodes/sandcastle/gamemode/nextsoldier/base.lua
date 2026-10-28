-- NextSoldier's base: the interface our code keeps of DrGBase's NextBot
-- (issue #8), its names and hook contracts only, organised as TF2's NextBot
-- is in source-sdk-2013 (server/NextBot/), not as DrGBase is. NextSoldier's
-- own base (base_nextsoldier) implements it from scratch over GMod's
-- NextBot, nothing taken from DrGBase's source, each component on its own
-- model and native where that pays.
--
-- The components are TF2's: the bot itself (INextBot: its life, and whom it
-- fights, IsEnemy and IsFriend being INextBot's) and its INextBotComponents,
-- each updated every tick:
--   ILocomotion  moving; climbs and jumps are its own processes, started by
--                ClimbUpToLedge, JumpAcrossGap, Jump and carried out over
--                ticks in its Update (IsClimbingOrJumping): no coroutine
--   IBody        what it holds and how it stands: weapons, aim, posture
--   IVision      what it senses
--   IIntention   what it wants: its enemy, and the behaviours (nextsoldier
--                .chart's states) run from its Update
-- Each declares:
--   methods  a core.port: what the base does when asked
--   hooks    what the base raises on a soldier class, which it may define
--   fields   a class's settings, read by the base
-- hooks and fields are named sets, or nil for a component with none;
-- Hooks(component) and Fields(component) list them either way.
--
-- Posture is the body's (IBody::SetDesiredPosture), apart as an optional
-- component only while DrGBase's classes stand in, its non-human NextBots
-- lacking crouching: a soldier has it whole or not at all, and its callers
-- ask Has first.
--
-- COMPONENTS, in order; NEXTBOT, LOCOMOTION, BODY, POSTURE (optional),
--             VISION, INTENTION
-- METHODS     the port of every required component's methods, in order
-- Has(soldier, component) -> whether soldier has an optional component;
--             one with only some of its methods is refused, naming them
-- HOOKS       the named set of every hook; FIELDS, of every field
-- ComponentOf(name) -> the component declaring a method, hook or field, or nil
-- REPLACED    names our code uses of DrGBase that the base does not keep,
--             each with what takes its place
--
-- .devtools/bin/drg_interface.py inventories the DrGBase names our code
-- uses, and its check refuses one this file does not declare.
local Port, Sets = core.port, world.sets
local concat, error, ipairs = table.concat, error, ipairs
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
		optional = spec.optional == true,
	}
end

local NONE = {}

function Hooks(component)
	return component.hooks and component.hooks:Members() or NONE
end

function Fields(component)
	return component.fields and component.fields:Members() or NONE
end

-- The bot itself (INextBot, its combat character): alive, down or dead,
-- hurt and dying, its own setup and think, and whom it fights (dispositions
-- by entity and by faction; INextBot's IsEnemy and IsFriend read them).
NEXTBOT = Component("nextbot", {
	methods = { "IsAlive", "IsDead", "IsDown", "AddEntityRelationship", "SetFactionRelationship", "Disposition",
		"JoinFaction", "LeaveFaction" },
	hooks = { "CustomInitialize", "CustomThink", "OnTakeDamage", "OnTraceAttack", "OnDealtDamage", "OnDeath" },
	fields = { "SpawnHealth", "RagdollOnDeath", "Factions", "DefaultRelationship" },
})

-- Moving (ILocomotion): its path, priced by the class (GetPathGenerator),
-- facing, jumping, climbing ledges and dropping down, its speeds.
LOCOMOTION = Component("locomotion", {
	methods = { "FollowPath", "GetPath", "FaceTowards", "IsMoving", "Jump", "GetStepHeight", "GetDeathDropHeight" },
	hooks = { "GetPathGenerator", "OnComputePath", "CustomClimbing", "OnStartClimbing", "OnLandOnGround",
		"OnNavAreaChanged" },
	fields = { "WalkSpeed", "RunSpeed", "ClimbLedges", "ClimbLedgesMaxHeight", "DeathDropHeight" },
})

-- What it holds and looks like (IBody): its weapons (the bot equips the best
-- for its threat, as CTFBot::EquipBestWeaponForThreat; the intention fires),
-- its scale, models, animations and sounds.
BODY = Component("body", {
	methods = { "GetActiveWeapon", "GetWeapons", "GiveWeapon", "RemoveWeapon", "SelectWeapon", "SetScale" },
	hooks = { "OnWeaponChange", "OnUpdateAnimation", "OnAnimEvent" },
	fields = { "Models", "Weapons", "BloodColor", "CollisionBounds", "IdleAnimation", "WalkAnimation",
		"RunAnimation", "OnDamageSounds", "OnDeathSounds" },
})

-- The body's posture: crouching, which a human soldier has and a
-- vortigaunt does not.
POSTURE = Component("posture", {
	methods = { "IsCrouching", "SetCrouching" },
	optional = true,
})

-- What it senses (IVision, with hearing): sight (spotted, lost), hearing,
-- the range to another, and being no one's target.
VISION = Component("vision", {
	methods = { "IsDeaf", "GetHearingCoefficient", "GetRangeTo", "SetNoTarget" },
	hooks = { "OnSpotted", "OnLost" },
})

-- What it wants (IIntention): its enemy, its AI on or off, and the stages
-- of fighting an enemy; the behaviours themselves are nextsoldier.chart's
-- states, run from its Update.
INTENTION = Component("intention", {
	methods = { "GetEnemy", "HasEnemy", "SetAIDisabled", "IsAIDisabled" },
	hooks = { "OnIdle", "OnNewEnemy", "OnLastEnemy", "OnFetchEnemy", "OnChaseEnemy", "OnAvoidEnemy",
		"OnIdleEnemy", "OnRangeAttack", "OnMeleeAttack", "ShouldRun" },
	fields = { "ReachEnemyRange", "AvoidEnemyRange", "RangeAttackRange", "MeleeAttackRange" },
})

COMPONENTS = { NEXTBOT, LOCOMOTION, BODY, POSTURE, VISION, INTENTION }

local methods, hooks, fields, owner = {}, {}, {}, {}
for _, component in ipairs(COMPONENTS) do
	for _, name in ipairs(component.methods:Methods()) do
		owner[name] = component
		if not component.optional then methods[#methods + 1] = name end
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

function Has(soldier, component)
	local present, missing = 0, {}
	for _, name in ipairs(component.methods:Methods()) do
		if soldier[name] ~= nil then present = present + 1 else missing[#missing + 1] = name end
	end
	if present > 0 and #missing > 0 then
		error("a soldier has part of NextSoldier " .. component.name .. ": no " .. concat(missing, ", "), 2)
	end
	return present > 0
end

REPLACED = {
	-- DrGBase's own landing handling, which the soldier's OnLandOnGround
	-- calls first: the base runs its own before raising the hook.
	_HandleLandOnGround = "the base's landing, run before OnLandOnGround",
	-- DrGBase's behaviour coroutine: TF2 runs none. The bot's Reset begins
	-- its components and behaviour again; a leap, vault or rappel is a
	-- locomotion process carried out over ticks in ILocomotion's Update.
	BehaveStart = "Reset (INextBot::Reset): the components and the behaviour begin again",
	YieldCoroutine = "a locomotion process, ticked in ILocomotion's Update (as ClimbUpToLedge)",
	PauseCoroutine = "a behaviour that waits, ticked in IIntention's Update",
}
