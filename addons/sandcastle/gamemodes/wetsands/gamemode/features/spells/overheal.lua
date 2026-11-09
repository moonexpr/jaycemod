-- Overheal (CTFSpellBook::CastSelfHeal): every teammate player in sight
-- within 250, the caster too (an NPC caster as well), gains 50 health, 1 s
-- of invulnerability and 3 s of quick healing; enemy players are pushed 300
-- away.
local require = require
local Teams = gameplay.teams
local Spells = require("features.spells.model")
local SpellSet = require("features.spells.halloween")
local ipairs = ipairs
module(...)

INDEX = SpellSet.SPELL_OVERHEAL

RADIUS = 250
HEAL = 50
INVULNERABLE_TIME = 1
QUICK_HEAL_TIME = 3
PUSH = 300
RING = {
	[Teams.RED] = "spell_overheal_red",
	[Teams.BLUE] = "spell_overheal_blue",
}

USE = {
	kind = Spells.USE_HEAL,
	range = 0,
	radius = RADIUS,
	needsLineOfSight = false,
	selfOnly = true,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	SpellSet.CastSound(caster, INDEX)
	local owner = caster:Owner()
	local origin, team = caster:Origin(owner), caster:TeamOf(owner)
	caster:AttachParticle(RING[team], owner)
	for _, target in ipairs(caster:EntitiesInSphere(origin, RADIUS)) do
		local reached = caster:IsPlayer(target) or target == owner
		if reached and caster:IsAlive(target) and caster:IsVisible(origin, caster:Origin(target)) then
			if caster:TeamOf(target) == team then
				caster:Heal(target, HEAL)
				caster:AddCond(target, SpellSet.COND.INVULNERABLE_USER_BUFF, INVULNERABLE_TIME)
				caster:AddCond(target, SpellSet.COND.HALLOWEEN_QUICK_HEAL, QUICK_HEAL_TIME)
			else
				caster:Push(target, (caster:Center(target) - origin):GetNormalized() * PUSH)
			end
		end
	end
	return true
end
