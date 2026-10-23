-- TF2's spell set (sdk/shared/tf/halloween/tf_weapon_spellbook.cpp):
-- g_NormalSpellList and g_RareSpellList as one index space,
-- g_generalSpellIndexList as COMMON_ROLL, and the mechanics its spells share:
-- the cast wheel, the toss (TossJarThink) and the thrown spells' impact
-- template (CTFProjectile_SpellBats::Explode). Kart and Doomsday lists are
-- left out: they hang on the map name.
local require = require
local Teams = require("games.gameplay.teams")
local Caster = require("features.spells.caster")
local Players = require("games.gameplay.players")
local ipairs, pairs = ipairs, pairs
module(...)

SPELL_FIREBALL = 0
SPELL_BATS = 1
SPELL_OVERHEAL = 2
SPELL_MIRV = 3
SPELL_BLASTJUMP = 4
SPELL_STEALTH = 5
SPELL_TELEPORT = 6
SPELL_LIGHTNING = 7
SPELL_ATHLETIC = 8
SPELL_METEOR = 9
SPELL_SPAWN_BOSS = 10
SPELL_SKELETON_HORDE = 11
COUNT = 12

-- SpellType_t
KIND_ROCKET, KIND_JAR, KIND_SELF = 0, 1, 2

-- CSpellPickup's m_nTier; foundation.npc.zombie's SPELL_TIER_RARE matches.
TIER_COMMON, TIER_RARE = 0, 1

ROLL_TIME = 2 -- RollNewSpell's flRollTime
CAST_COOLDOWN = 0.5 -- PrimaryAttack's default m_flTimeNextSpell

-- TossJarThink: the hand's offset from the shoot position, the hull that
-- must fit between the eyes and the hand, and CTFJar::GetVelocityVector.
TOSS_UP, TOSS_RIGHT, TOSS_FORWARD = -9, 7, 3
TOSS_HULL = 8
PROJECTILE_SPEED = 1000 -- TF_JAR_LAUNCH_SPEED
UP_SPEED = 200
SPREAD = 10

-- CastSpell's cast wheel, 100 above the caster.
CAST_WHEEL_HEIGHT = 100
CAST_WHEEL = {
	[Teams.RED] = "spell_cast_wheel_red",
	[Teams.BLUE] = "spell_cast_wheel_blue",
}

JAR_BLAST_DAMAGE = 10 -- ApplyBlastDamage
DENY_SOUND = "Player.DenyWeaponSelection"

ICON_PREFIX = "vgui/"
ICON_NONE = "vgui/spellbook_nospell"

local STRATEGY_PREFIX = "features.spells."

local function Spell(name, charges, kind, castSound, speedScale, icon)
	return {
		name = name,
		charges = charges,
		kind = kind,
		castSound = castSound,
		speedScale = speedScale,
		icon = ICON_PREFIX .. icon,
	}
end

local DEFINITIONS = {
	[SPELL_FIREBALL] = Spell("fireball", 2, KIND_ROCKET, "Halloween.spell_fireball_cast", 1, "spellbook_fireball"),
	[SPELL_BATS] = Spell("bats", 2, KIND_JAR, "Halloween.spell_bat_cast", 1, "spellbook_bats"),
	[SPELL_OVERHEAL] = Spell("overheal", 1, KIND_SELF, "Halloween.spell_overheal", 1, "spellbook_overheal"),
	[SPELL_MIRV] = Spell("mirv", 1, KIND_JAR, "Halloween.spell_mirv_cast", 1, "spellbook_mirv"),
	[SPELL_BLASTJUMP] = Spell("blastjump", 2, KIND_SELF, "Halloween.spell_blastjump", 1, "spellbook_blastjump"),
	[SPELL_STEALTH] = Spell("stealth", 1, KIND_SELF, "Halloween.spell_stealth", 1, "spellbook_stealth"),
	[SPELL_TELEPORT] = Spell("teleport", 2, KIND_JAR, "Halloween.spell_teleport", 1, "spellbook_teleport"),
	[SPELL_LIGHTNING] = Spell("lightning", 1, KIND_ROCKET, "Halloween.spell_lightning_cast", 0.4, "spellbook_lightning"),
	[SPELL_ATHLETIC] = Spell("athletic", 1, KIND_SELF, "Halloween.spell_athletic", 1, "spellbook_athletic"),
	[SPELL_METEOR] = Spell("meteor", 1, KIND_JAR, "Halloween.spell_meteor_cast", 1, "spellbook_meteor"),
	[SPELL_SPAWN_BOSS] = Spell("spawn_boss", 1, KIND_JAR, "Halloween.Merasmus_Spell", 1, "spellbook_boss"),
	[SPELL_SKELETON_HORDE] = Spell("skeleton_horde", 1, KIND_JAR, "Halloween.spell_skeleton_horde_cast", 1,
		"spellbook_skeleton"),
}

-- g_generalSpellIndexList: teleport and the summons are never common.
COMMON_ROLL = {
	SPELL_FIREBALL,
	SPELL_FIREBALL,
	SPELL_FIREBALL,
	SPELL_FIREBALL,
	SPELL_BATS,
	SPELL_BATS,
	SPELL_BATS,
	SPELL_BATS,
	SPELL_OVERHEAL,
	SPELL_OVERHEAL,
	SPELL_OVERHEAL,
	SPELL_OVERHEAL,
	SPELL_MIRV,
	SPELL_MIRV,
	SPELL_MIRV,
	SPELL_MIRV,
	SPELL_BLASTJUMP,
	SPELL_BLASTJUMP,
	SPELL_BLASTJUMP,
	SPELL_BLASTJUMP,
	SPELL_STEALTH,
	SPELL_STEALTH,
	SPELL_STEALTH,
	SPELL_STEALTH,
	SPELL_LIGHTNING,
	SPELL_ATHLETIC,
	SPELL_METEOR,
}

function Definition(index)
	return DEFINITIONS[index]
end

function Strategy(index)
	return STRATEGY_PREFIX .. DEFINITIONS[index].name
end

-- RollNewSpell: a common roll draws from COMMON_ROLL; any other tier is
-- uniform over the rare list (the nav-mesh reduction TF2 computes is never
-- applied). random(lo, hi) draws an integer.
function Roll(tier, random)
	if tier == TIER_COMMON then return COMMON_ROLL[random(1, #COMMON_ROLL)] end
	return random(SPELL_LIGHTNING, COUNT - 1)
end

-------------------------------------------------------------------------------
-- What the spells share

-- CastSpell's one-off effect, played for every spell but stealth.
function CastWheel(caster)
	local owner = caster:Owner()
	caster:Particle(CAST_WHEEL[caster:TeamOf(owner)], caster:Origin(owner) + caster:Vector(0, 0, CAST_WHEEL_HEIGHT))
end

-- The sound TossJarThink plays as a spell goes off.
function CastSound(caster, index)
	caster:EmitSound(Definition(index).castSound)
end

-- CreateSpellRocket flies along the eye angles at the toss's speed;
-- CreateSpellJar throws with the toss's velocity.
local LAUNCH_VELOCITY = {
	[KIND_ROCKET] = function(forward, velocity) return forward * velocity:Length() end,
	[KIND_JAR] = function(forward, velocity) return velocity end,
}

-- The flight a thrown spell adds to its launch config (its FLIGHT). A jar is
-- a pipebomb-mode grenade: it breaks on the world or an enemy, or when its
-- TF_WEAPON_GRENADE_DETONATE_TIME fuse runs out, and ignores nothing.
JAR_FUSE = 2
JAR_FLIGHT = {
	fuse = JAR_FUSE,
	armDelay = 0,
}
ROCKET_FLIGHT = {}

-- A thrown spell's rough reach for its USE: a jar's flight before its fuse.
THROW_RANGE = PROJECTILE_SPEED * JAR_FUSE

-- TossJarThink for a spell that throws its PROJECTILE: from the hand, if an
-- 8-unit hull fits between the eyes and the hand; otherwise nothing is
-- thrown (and the charge is gone). Returns whether it threw.
function Toss(caster, spell)
	local definition = Definition(spell.INDEX)
	local owner = caster:Owner()
	local forward, right, up = caster:EyeVectors()
	local hand = caster:ShootPosition() + up * TOSS_UP + right * TOSS_RIGHT + forward * TOSS_FORWARD
	local spreadRight = caster:RandomFloat(-SPREAD, SPREAD)
	local spreadUp = caster:RandomFloat(-SPREAD, SPREAD)
	local velocity = (forward * PROJECTILE_SPEED + up * UP_SPEED + right * spreadRight + up * spreadUp)
		* definition.speedScale
	local hull = caster:Vector(TOSS_HULL, TOSS_HULL, TOSS_HULL)
	local trace = caster:TraceHull(caster:EyePosition(owner), hand, hull * -1, hull)
	if trace.startSolid then return false end
	caster:EmitSound(definition.castSound)
	local config = {
		spell = spell.INDEX,
		position = trace.endPos,
		velocity = LAUNCH_VELOCITY[definition.kind](forward, velocity),
		team = caster:TeamOf(owner),
	}
	for key, value in pairs(spell.FLIGHT) do config[key] = value end
	caster:LaunchProjectile(spell.PROJECTILE, config)
	return true
end

-- A spell's blast: CTFRadiusDamageInfo with the thrower as the entity it
-- ignores, so the thrower is both attacker and inflictor.
function Blast(caster, origin, radius, damage)
	local owner = caster:Owner()
	return {
		origin = origin,
		radius = radius,
		damage = damage,
		attackerTeam = caster:TeamOf(owner),
		attacker = owner,
		inflictor = owner,
		halfFalloff = false,
		forceFriendlyFire = false,
		crit = false,
	}
end

-- CTFProjectile_SpellBats::Explode, the template of every thrown (jar)
-- spell. jar = { radius, Initial(caster, impact) -> bool, particles (by
-- team), sound, blast (bool), OnTarget(caster, impact, target) (optional) }.
-- When Initial fails the thrower hears the deny sound and nothing else
-- happens. Otherwise the effects play, each living player or NPC within the
-- radius with no world between is a target, and a blast of 10 follows.
-- Returns whether Initial succeeded.
function JarImpact(caster, impact, jar)
	if not jar.Initial(caster, impact) then
		caster:EmitSound(DENY_SOUND)
		return false
	end
	local origin = impact.position
	caster:Particle(jar.particles[impact.team], origin)
	caster:EmitSound(jar.sound, impact.projectile)
	if jar.OnTarget then
		for _, target in ipairs(caster:EntitiesInSphere(origin, jar.radius)) do
			if caster:IsAlive(target) and caster:IsVisible(origin, caster:Origin(target)) then
				jar.OnTarget(caster, impact, target)
			end
		end
	end
	if jar.blast then caster:Explode(Blast(caster, origin, jar.radius, JAR_BLAST_DAMAGE)) end
	return true
end

-- ExplodeEffectOnTarget's guard: an enemy player who is invulnerable or
-- phased is spared.
function Spared(caster, target)
	return caster:IsPlayer(target) and (caster:IsInvulnerable(target) or caster:InCond(target, COND.PHASE))
end

DMG_BURN, DMG_BLAST = Caster.DMG_BURN, Caster.DMG_BLAST
COND = Players.COND
