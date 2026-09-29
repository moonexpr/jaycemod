-- Overheal (CTFSpellBook::CastSelfHeal): every teammate in sight within 250,
-- the caster too, gains 50 health, 1 s of invulnerability and 3 s of quick
-- healing; enemy players are pushed 300 away.
local require = require
local Teams = require("foundation.teams")
local Tf2 = require("foundation.spells.tf2")
local ipairs = ipairs
module(...)

INDEX = Tf2.SPELL_OVERHEAL

RADIUS = 250
HEAL = 50
INVULNERABLE_TIME = 1
QUICK_HEAL_TIME = 3
PUSH = 300
RING = {
	[Teams.RED] = "spell_overheal_red",
	[Teams.BLUE] = "spell_overheal_blue",
}

function Cast(caster)
	Tf2.CastWheel(caster)
	Tf2.CastSound(caster, INDEX)
	local owner = caster:Owner()
	local origin, team = caster:Origin(owner), caster:TeamOf(owner)
	caster:AttachParticle(RING[team], owner)
	for _, target in ipairs(caster:EntitiesInSphere(origin, RADIUS)) do
		if caster:IsPlayer(target) and caster:IsAlive(target) and caster:IsVisible(origin, caster:Origin(target)) then
			if caster:TeamOf(target) == team then
				caster:Heal(target, HEAL)
				caster:AddCond(target, Tf2.COND.INVULNERABLE_USER_BUFF, INVULNERABLE_TIME)
				caster:AddCond(target, Tf2.COND.HALLOWEEN_QUICK_HEAL, QUICK_HEAL_TIME)
			else
				caster:Push(target, (caster:Center(target) - origin):GetNormalized() * PUSH)
			end
		end
	end
	return true
end
