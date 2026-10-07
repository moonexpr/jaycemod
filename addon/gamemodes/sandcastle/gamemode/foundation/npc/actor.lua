-- The actor port: what an NPC model may ask of the entity it drives. The
-- entity wetsand_nextbot implements it and tests/fake_actor.lua fakes it.
-- Method names are NextBot's (INextBot, IBody, ILocomotion,
-- CBaseCombatCharacter) wherever NextBot has one.
--
-- Values: targets are opaque handles; vectors are the engine's (`+ - *`,
-- :Length(), :Length2D(), :GetNormalized(), :Dot(v), .x .y .z), made with
-- Vector(x, y, z). Activities are ids from Activity(name), where name is the
-- engine's, e.g. "ACT_MP_RUN_MELEE". NewPath() returns a path with
-- :Compute(goal), :Update(), :GetAge(), :IsValid(), :Invalidate(),
-- :SetMinLookAheadDistance(d) and :GetCurrentGoalPos().
-- DealDamage(t, amount, dmgType, attacker): attacker nil means me.
-- SpawnEntity(class, config, pos) goes to the npc controller's Spawn.
--
-- Event payloads, built once at the entity: damageEvent = { attacker,
-- inflictor, amount, dmgType, position, crit }; OnOtherKilled gets
-- (victim, damageEvent); OnContact gets (other).
module(...)

METHODS = {
	-- time, chance
	"Now",
	"RandomFloat",
	"RandomInt",
	-- self
	"IsAlive",
	"GetAbsOrigin",
	"SetAbsOrigin",
	"WorldSpaceCenter",
	"EyePosition",
	"GetYaw",
	"SetYaw",
	"GetHealth",
	"SetHealth",
	"GetMaxHealth",
	"SetMaxHealth",
	"GetOwnerEntity",
	"GetEntIndex",
	"Remove",
	"Shared",
	"Vector",
	-- targets
	"IsTargetValid",
	"IsTargetAlive",
	"TargetOrigin",
	"TargetCenter",
	"TargetEyes",
	"TargetVelocity",
	"TargetMaxHealth",
	"TargetIndex",
	"IsTargetOnGround",
	-- relations
	"RangeTo",
	"IsRangeLessThan",
	"IsRangeGreaterThan",
	"IsLineOfSightClear",
	"IsOnNavMesh",
	-- body
	"Activity",
	"StartActivity",
	"IsActivity",
	"IsActivityFinished",
	"PlaySequence",
	"IsSequenceFinished",
	"AddGesture",
	"IsPlayingGesture",
	"SetPoseParameter",
	"SetSkin",
	"SetModelScale",
	"SetBoneScale",
	"AttachProp",
	-- motion
	"SetDesiredSpeed",
	"FaceTowards",
	"Approach",
	"IsAttemptingToMove",
	"GetGroundSpeed",
	"NewPath",
	-- effects
	"EmitSound",
	"DispatchParticleEffect",
	"ScreenShake",
	"ApplyImpulse",
	"DealDamage",
	"FireOutput",
	"SpawnEntity",
}

-- Methods GMod's Entity or NextBot metatable already provides with the
-- port's meaning. GMod's entity __index searches the metatable before the
-- entity's own table, so the entity must not define these: its version
-- would never run.
ENGINE = {
	WorldSpaceCenter = true,
	SetHealth = true,
	GetMaxHealth = true,
	SetMaxHealth = true,
	Remove = true,
	StartActivity = true,
	IsSequenceFinished = true,
	AddGesture = true,
	IsPlayingGesture = true,
	SetPoseParameter = true,
	SetSkin = true,
	SetModelScale = true,
	EmitSound = true,
}

-- Source's damage type bits (shared/shareddefs.h).
DMG_GENERIC = 0
DMG_CRUSH = 1
DMG_BULLET = 2
DMG_SLASH = 4
DMG_BURN = 8
DMG_BLAST = 64
DMG_CLUB = 128
DMG_NEVERGIB = 4096
DMG_BUCKSHOT = 536870912
DMG_SNIPER = 1073741824
