-- TF2's victim rules for its NPCs, as data: whom an NPC may not see, who
-- cannot be hurt, and which teams an NPC of a team fights.
--
-- A player's conditions come in as a predicate, inCond(cond) -> bool, so a
-- model asks through its combatant port:
--   Targeting.IsHiddenFromNPC(function(cond) return me:InCond(t, cond) end)
local require = require
local Players = gameplay.players
local Teams = gameplay.teams
local ipairs = ipairs
module(...)

local C = Players.COND

-- CTFPlayerShared::IsStealthed
local STEALTH = { C.STEALTHED, C.STEALTHED_USER_BUFF, C.STEALTHED_USER_BUFF_FADING }
-- What gives a stealthed player away (CZombieAttack::SelectVictim).
local REVEALED_BY = { C.BURNING, C.URINE, C.STEALTHED_BLINK, C.BLEEDING }
-- CTFPlayerShared::IsInvulnerable
local INVULNERABLE = {
	C.INVULNERABLE,
	C.INVULNERABLE_USER_BUFF,
	C.INVULNERABLE_HIDE_UNLESS_DAMAGED,
	C.INVULNERABLE_CARD_EFFECT,
}

local function Any(inCond, conds)
	for _, cond in ipairs(conds) do
		if inCond(cond) then return true end
	end
	return false
end

-- CZombieAttack::SelectVictim and CEyeballBoss::FindClosestVisibleVictim:
-- a cloaked player is invisible unless something gives it away, and a ghost
-- always is. (Their disguise rule needs a disguise team, which Sandcastle
-- players do not have.)
function IsHiddenFromNPC(inCond)
	if inCond(C.HALLOWEEN_GHOST_MODE) then return true end
	return Any(inCond, STEALTH) and not Any(inCond, REVEALED_BY)
end

function IsInvulnerable(inCond)
	return Any(inCond, INVULNERABLE)
end

-- The teams an NPC of `team` attacks: RED and BLU each other, any other team
-- (HALLOWEEN, or none) both. A fresh list each call.
function EnemyTeamsOf(team)
	if team == Teams.RED then return { Teams.BLUE } end
	if team == Teams.BLUE then return { Teams.RED } end
	return { Teams.RED, Teams.BLUE }
end
