-- Stealth (CTFSpellBook::CastSelfStealth): 40 health and 8 s unseen. The
-- only spell CastSpell plays no cast wheel for.
local require = require
local Tf2 = require("foundation.spells.tf2")
module(...)

INDEX = Tf2.SPELL_STEALTH

HEAL = 40
DURATION = 8

function Cast(caster)
	Tf2.CastSound(caster, INDEX)
	local owner = caster:Owner()
	caster:Heal(owner, HEAL)
	caster:AddCond(owner, Tf2.COND.STEALTHED_USER_BUFF, DURATION)
	return true
end
