-- Skeleton horde (CTFProjectile_SpellSpawnHorde): a jar that bursts into
-- three skull grenades (tf_projectile_spellspawnzombie) of the caster's
-- team; each hatches a normal skeleton the caster owns.
local require = require
local Teams = require("foundation.teams")
local Spells = require("foundation.spells")
local SpellSet = require("foundation.spells.halloween")
local Zombie = require("foundation.npc.zombie")
module(...)

INDEX = SpellSet.SPELL_SKELETON_HORDE
PROJECTILE = "tf_projectile_spellspawnhorde"
FLIGHT = SpellSet.JAR_FLIGHT

RADIUS = 1
SKULLS = 3
SOUND = "Halloween.spell_skeleton_horde_rise"
GOOP = {
	[Teams.RED] = "spell_pumpkin_mirv_goop_red",
	[Teams.BLUE] = "spell_pumpkin_mirv_goop_blue",
}

USE = {
	kind = Spells.USE_SUMMON,
	range = SpellSet.THROW_RANGE,
	radius = 0,
	needsLineOfSight = true,
	selfOnly = false,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	return SpellSet.Toss(caster, _M)
end

local function Raise(caster, impact)
	for _ = 1, SKULLS do
		caster:SpawnNPC(Zombie.SKULL_CLASS, {
			thrower = caster:Owner(),
			team = impact.team,
			skeletonType = Zombie.SKELETON_NORMAL,
		}, impact.position)
	end
	return true
end

local JAR = {
	radius = RADIUS,
	Initial = Raise,
	particles = GOOP,
	sound = SOUND,
	blast = true,
}

function Impact(caster, impact)
	SpellSet.JarImpact(caster, impact, JAR)
end
