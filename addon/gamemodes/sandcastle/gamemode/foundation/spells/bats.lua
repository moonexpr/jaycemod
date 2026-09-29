-- Bats (CTFProjectile_SpellBats): a jar that bursts into bats. Each enemy
-- within 250 is stunned 0.5 s at half speed, flung 200 away and 800 up,
-- bleeds for 3 s and takes 40 burn damage (an NPC is flung 1000 instead);
-- then a blast of 10.
local require = require
local Teams = require("foundation.teams")
local Tf2 = require("foundation.spells.tf2")
module(...)

INDEX = Tf2.SPELL_BATS
PROJECTILE = "tf_projectile_spellbats"
FLIGHT = Tf2.JAR_FLIGHT

RADIUS = 250
STUN_TIME, STUN_SLOW = 0.5, 0.5
PUSH, LIFT = 200, 800
NPC_PUSH = 1000
BLEED_TIME = 3
DAMAGE = 40
EXPLOSION = "ExplosionCore_MidAir" -- TE_TFExplosion's pipebomb blast
SOUND = "Halloween.spell_bat_impact"
IMPACT_PARTICLES = {
	[Teams.RED] = "spell_batball_impact_red",
	[Teams.BLUE] = "spell_batball_impact_blue",
}
SWARM = {
	[Teams.RED] = "spell_batball_red",
	[Teams.BLUE] = "spell_batball_blue",
}

function Cast(caster)
	Tf2.CastWheel(caster)
	return Tf2.Toss(caster, _M)
end

-- ExplodeEffectOnTarget
local function OnTarget(caster, impact, target)
	if caster:TeamOf(target) == impact.team or Tf2.Spared(caster, target) then return end
	local away = (caster:Center(target) - impact.position):GetNormalized()
	if caster:IsPlayer(target) then
		caster:Stun(target, STUN_TIME, STUN_SLOW)
		caster:Push(target, away * PUSH + caster:Vector(0, 0, LIFT))
		caster:AttachParticle(SWARM[impact.team], target)
		caster:AddCond(target, Tf2.COND.BLEEDING, BLEED_TIME)
	else
		caster:Push(target, away * NPC_PUSH)
	end
	caster:Damage(target, DAMAGE, Tf2.DMG_BURN, impact.projectile)
end

local function Initial(caster, impact)
	caster:Particle(EXPLOSION, impact.position)
	return true
end

local JAR = {
	radius = RADIUS,
	Initial = Initial,
	OnTarget = OnTarget,
	particles = IMPACT_PARTICLES,
	sound = SOUND,
	blast = true,
}

function Impact(caster, impact)
	Tf2.JarImpact(caster, impact, JAR)
end
