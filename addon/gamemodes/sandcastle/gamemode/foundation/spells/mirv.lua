-- MIRV (CTFProjectile_SpellMirv and CTFProjectile_SpellPumpkin): a jar that
-- bursts into six pumpkin bomblets thrown at fixed offsets, each with a
-- fuse 0.05 s longer than the last and blind to touches for its first
-- second. A bomblet leaves a spell pumpkin bomb of its team.
local require = require
local Teams = require("foundation.teams")
local Spells = require("foundation.spells")
local SpellSet = require("foundation.spells.halloween")
local ipairs = ipairs
module(...)

INDEX = SpellSet.SPELL_MIRV
PROJECTILE = "tf_projectile_spellmirv"
FLIGHT = SpellSet.JAR_FLIGHT
BOMBLET = "tf_projectile_spellpumpkin"

RADIUS = 1 -- GetDamageRadius, for the blast of 10
BOMBLET_OFFSETS = {
	{ 75, 110, 400 },
	{ 75, -110, 400 },
	{ -75, 110, 400 },
	{ -75, -110, 400 },
	{ 135, 0, 400 },
	{ -135, 0, 400 },
}
BOMBLET_FUSE = 2
BOMBLET_FUSE_STEP = 0.05
BOMBLET_ARM_DELAY = 1 -- m_flImpactTime

-- SetInitParams( 0.60, 80.0f, 200.0f, team, 40.0f + RandomFloat( 0, 1.0f ) )
PUMPKIN = "tf_pumpkin_bomb"
PUMPKIN_SCALE = 0.6
PUMPKIN_DAMAGE = 80
PUMPKIN_RADIUS = 200
PUMPKIN_LIFETIME = 40
PUMPKIN_LIFETIME_SPREAD = 1

GOOP = {
	[Teams.RED] = "spell_pumpkin_mirv_goop_red",
	[Teams.BLUE] = "spell_pumpkin_mirv_goop_blue",
}

USE = {
	kind = Spells.USE_ATTACK,
	range = SpellSet.THROW_RANGE,
	radius = PUMPKIN_RADIUS,
	needsLineOfSight = true,
	selfOnly = false,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	return SpellSet.Toss(caster, _M)
end

local function Scatter(caster, impact)
	for i, offset in ipairs(BOMBLET_OFFSETS) do
		caster:LaunchProjectile(BOMBLET, {
			spell = INDEX,
			position = impact.position,
			velocity = caster:Vector(offset[1], offset[2], offset[3]),
			team = impact.team,
			fuse = BOMBLET_FUSE + BOMBLET_FUSE_STEP * (i - 1),
			armDelay = BOMBLET_ARM_DELAY,
		})
	end
	return true
end

local function Plant(caster, impact)
	caster:Spawn(PUMPKIN, {
		scale = PUMPKIN_SCALE,
		damage = PUMPKIN_DAMAGE,
		radius = PUMPKIN_RADIUS,
		team = impact.team,
		lifetime = PUMPKIN_LIFETIME + caster:RandomFloat(0, PUMPKIN_LIFETIME_SPREAD),
		isSpell = true,
	}, impact.position)
	return true
end

-- The pumpkin's ApplyBlastDamage does nothing.
local JARS = {
	[PROJECTILE] = {
		radius = RADIUS,
		Initial = Scatter,
		particles = GOOP,
		sound = "Halloween.spell_mirv_explode_primary",
		blast = true,
	},
	[BOMBLET] = {
		radius = RADIUS,
		Initial = Plant,
		particles = GOOP,
		sound = "Halloween.spell_mirv_explode_secondary",
		blast = false,
	},
}

function Impact(caster, impact)
	SpellSet.JarImpact(caster, impact, JARS[impact.class])
end
