-- Blast jump (CTFSpellBook::CastRocketJump): the caster stops falling, is
-- thrown 800 up and gains 25 health; enemy players within 100 in sight are
-- flung 800 away, then a blast of 20 over 100 that spares the caster.
local require = require
local Tf2 = require("foundation.spells.tf2")
local ipairs = ipairs
module(...)

INDEX = Tf2.SPELL_BLASTJUMP

RADIUS = 100
LIFT = 800
HEAL = 25 -- "to compensate for fall damage"
FLING = 800
DAMAGE = 20
DEBRIS = "bombinomicon_burningdebris"
RING = "heavy_ring_of_fire"
SMOKE = "rocketjump_smoke"

function Cast(caster)
	Tf2.CastWheel(caster)
	Tf2.CastSound(caster, INDEX)
	local owner = caster:Owner()
	local velocity = caster:GetVelocity(owner)
	if velocity.z < 0 then velocity = caster:Vector(velocity.x, velocity.y, 0) end
	caster:SetVelocity(owner, velocity)
	caster:Push(owner, caster:Vector(0, 0, LIFT))
	local origin, team = caster:Origin(owner), caster:TeamOf(owner)
	caster:Particle(DEBRIS, origin)
	caster:Particle(RING, origin)
	caster:AttachParticle(SMOKE, owner)
	caster:Heal(owner, HEAL)
	for _, target in ipairs(caster:EntitiesInSphere(origin, RADIUS)) do
		if caster:IsPlayer(target) and caster:IsAlive(target) and caster:TeamOf(target) ~= team
			and caster:IsVisible(origin, caster:Origin(target)) then
			caster:Push(target, (caster:Center(target) - origin):GetNormalized() * FLING)
		end
	end
	caster:Explode(Tf2.Blast(caster, origin, RADIUS, DAMAGE))
	return true
end
