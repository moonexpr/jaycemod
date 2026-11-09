-- Athletic (CTFSpellBook::CastSelfSpeedBoost): 100 health, and 20 s tiny and
-- fast. OnAddHalloweenSpeedBoost adds TF_COND_SPEED_BOOST, the speed bonus
-- TeamFortress_CalculateMaxSpeed gives, so the spell adds it for as long.
local require = require
local Spells = require("features.spells.model")
local SpellSet = require("features.spells.halloween")
module(...)

INDEX = SpellSet.SPELL_ATHLETIC

HEAL = 100
DURATION = 20

USE = {
	kind = Spells.USE_MOBILITY,
	range = 0,
	radius = 0,
	needsLineOfSight = false,
	selfOnly = true,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	SpellSet.CastSound(caster, INDEX)
	local owner = caster:Owner()
	caster:Heal(owner, HEAL)
	caster:AddCond(owner, SpellSet.COND.HALLOWEEN_TINY, DURATION)
	caster:AddCond(owner, SpellSet.COND.HALLOWEEN_SPEED_BOOST, DURATION)
	caster:AddCond(owner, SpellSet.COND.SPEED_BOOST, DURATION)
	return true
end
