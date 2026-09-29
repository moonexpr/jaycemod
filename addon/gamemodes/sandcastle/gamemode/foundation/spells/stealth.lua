-- Stealth (CTFSpellBook::CastSelfStealth): 40 health and 8 s unseen. The
-- only spell CastSpell plays no cast wheel for.
local require = require
local Spells = require("foundation.spells")
local SpellSet = require("foundation.spells.halloween")
module(...)

INDEX = SpellSet.SPELL_STEALTH

HEAL = 40
DURATION = 8

USE = {
	kind = Spells.USE_ESCAPE,
	range = 0,
	radius = 0,
	needsLineOfSight = false,
	selfOnly = true,
}

function Cast(caster)
	SpellSet.CastSound(caster, INDEX)
	local owner = caster:Owner()
	caster:Heal(owner, HEAL)
	caster:AddCond(owner, SpellSet.COND.STEALTHED_USER_BUFF, DURATION)
	return true
end
