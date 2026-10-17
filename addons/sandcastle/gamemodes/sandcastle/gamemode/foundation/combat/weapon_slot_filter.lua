-- The damage filter filter_tf_damaged_by_weapon_in_slot
-- (FilterDamagedByWeaponInSlot, tf_filters.cpp): damage passes when the
-- weapon that dealt it sits in the filter's loadout slot. GMod's damage
-- names no TF2 weapon, so only the melee slot is judged, by what TF2's melee
-- weapons deal: a player's DMG_CLUB or DMG_SLASH. Other slots pass nothing,
-- and the binding says so once. The maps use only melee (pl_corruption).
--
-- damage = { byPlayer, dmgType }: whether a player dealt it, and its bits.
local require = require
local Actor = require("foundation.npc.actor")
local bor, band = bit.bor, bit.band
module(...)

-- CTFWeaponBase::GetSlot
SLOT_PRIMARY = 0
SLOT_SECONDARY = 1
SLOT_MELEE = 2

MELEE_DAMAGE = bor(Actor.DMG_CLUB, Actor.DMG_SLASH)

function Supported(slot)
	return slot == SLOT_MELEE
end

-- CBaseFilter::PassesDamageFilter over PassesDamageFilterImpl.
function PassesDamage(slot, negated, damage)
	local passes = Supported(slot) and damage.byPlayer and band(damage.dmgType, MELEE_DAMAGE) ~= 0
	return passes ~= negated
end

-- CBaseFilter::PassesFilter over PassesFilterImpl, which asserts (the filter
-- is for damage) and passes.
function PassesEntity(negated)
	return not negated
end
