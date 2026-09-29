-- Athletic (CTFSpellBook::CastSelfSpeedBoost): 100 health, and 20 s tiny and
-- fast. OnAddHalloweenSpeedBoost adds TF_COND_SPEED_BOOST, the speed bonus
-- TeamFortress_CalculateMaxSpeed gives, so the spell adds it for as long.
local require = require
local Tf2 = require("foundation.spells.tf2")
module(...)

INDEX = Tf2.SPELL_ATHLETIC

HEAL = 100
DURATION = 20

function Cast(caster)
	Tf2.CastWheel(caster)
	Tf2.CastSound(caster, INDEX)
	local owner = caster:Owner()
	caster:Heal(owner, HEAL)
	caster:AddCond(owner, Tf2.COND.HALLOWEEN_TINY, DURATION)
	caster:AddCond(owner, Tf2.COND.HALLOWEEN_SPEED_BOOST, DURATION)
	caster:AddCond(owner, Tf2.COND.SPEED_BOOST, DURATION)
	return true
end
