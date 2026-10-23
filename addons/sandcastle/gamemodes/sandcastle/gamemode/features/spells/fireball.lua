-- Fireball (CTFProjectile_SpellFireball): a rocket that bursts on the first
-- thing it hits. Each enemy player within 200, in sight of the burst's
-- centre, burns for 5 s and takes 100 burn damage; then a blast of 10.
-- Meteors burst the same way (Burst).
local require = require
local Spells = require("features.spells.model")
local SpellSet = require("features.spells.halloween")
local ipairs = ipairs
module(...)

INDEX = SpellSet.SPELL_FIREBALL
PROJECTILE = "tf_projectile_spellfireball"
FLIGHT = SpellSet.ROCKET_FLIGHT

RADIUS = 200 -- GetDamageRadius
BURN_TIME = 5 -- SelfBurn
BURN_DAMAGE = 100
BLAST_DAMAGE = 10
NUDGE = 5 -- ApplyGenericPushbackImpulse( vecDir * 5 ), with vecDir.z = 0.1
NUDGE_LIFT = 0.1
PARTICLE = "bombinomicon_burningdebris"
SOUND = "Halloween.spell_fireball_impact"

USE = {
	kind = Spells.USE_ATTACK,
	range = SpellSet.THROW_RANGE,
	radius = RADIUS,
	needsLineOfSight = true,
	selfOnly = false,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	return SpellSet.Toss(caster, _M)
end

-- ExplodeEffectOnTarget
local function Burn(caster, impact, target)
	if caster:TeamOf(target) == impact.team or SpellSet.Spared(caster, target) then return end
	caster:AddCond(target, SpellSet.COND.BURNING, BURN_TIME)
	caster:Damage(target, BURN_DAMAGE, SpellSet.DMG_BURN, impact.projectile)
	local away = (caster:Center(target) - impact.position):GetNormalized()
	caster:Push(target, caster:Vector(away.x, away.y, NUDGE_LIFT) * NUDGE)
end

-- CTFProjectile_SpellFireball::Explode, with its burst particle.
function Burst(caster, impact, particle)
	local origin = impact.position
	caster:Particle(particle, origin)
	caster:EmitSound(SOUND, impact.projectile)
	for _, target in ipairs(caster:EntitiesInSphere(origin, RADIUS)) do
		if caster:IsPlayer(target) and caster:IsAlive(target) and caster:IsVisible(origin, caster:Center(target)) then
			Burn(caster, impact, target)
		end
	end
	caster:Explode(SpellSet.Blast(caster, origin, RADIUS, BLAST_DAMAGE))
end

function Impact(caster, impact)
	Burst(caster, impact, PARTICLE)
end
