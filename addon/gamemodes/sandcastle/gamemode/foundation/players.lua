-- Player rules of TF2 as pure functions: pickup amounts, resupply, the
-- player conditions map triggers apply, and stuns.
local bit, ipairs, math, pairs = bit, ipairs, math, pairs
module(...)

-- PackRatios (tf_powerup.cpp) and ITEM_RESPAWN_TIME (tf_gamerules.cpp).
PACK_RATIO = { small = 0.2, medium = 0.5, full = 1.0 }
ITEM_RESPAWN_TIME = 10

-- CTFAmmoPack: a medium pack, gone after 30s, which its dropper may not
-- pick up before FlyThink at 0.75s.
DROPPED_PACK = { ratio = 0.5, lifetime = 30, ownerDelay = 0.75 }

-- CHealthKit::MyTouch: TakeHealth(ceil(max * ratio)), which stops at max.
function HealthKitHeal(health, maxHealth, ratio)
	return math.max(0, math.min(math.ceil(maxHealth * ratio), maxHealth - health))
end

-- The kit is used up when it healed, or when it put out a fire.
function HealthKitTaken(given, burning)
	return given > 0 or burning
end

-- CAmmoPack::MyTouch through GiveAmmo: ceil(max * ratio), up to max.
function AmmoAfterPack(have, max, ratio)
	if have >= max then return have end
	return math.min(max, have + math.ceil(max * ratio))
end

-- CTFPlayer::Regenerate: InitClass refills health; a boost over max is kept.
function RegenerateHealth(health, maxHealth)
	return math.max(health, maxHealth)
end

-- ETFCond values (tf_shareddefs.h) of the conditions payload maps apply,
-- and those the Halloween NPCs read or give.
COND = {
	INVALID = -1,
	DISGUISED = 3,
	STEALTHED = 4,
	INVULNERABLE = 5,
	STEALTHED_BLINK = 9,
	CRITBOOSTED = 11,
	PHASE = 14,
	BURNING = 22,
	URINE = 24,
	BLEEDING = 25,
	MAD_MILK = 27,
	SPEED_BOOST = 32,
	CRITBOOSTED_PUMPKIN = 33,
	CRITBOOSTED_USER_BUFF = 34,
	CANNOT_SWITCH_FROM_MELEE = 41,
	INVULNERABLE_HIDE_UNLESS_DAMAGED = 51,
	INVULNERABLE_USER_BUFF = 52,
	HALLOWEEN_BOMB_HEAD = 53,
	HALLOWEEN_THRILLER = 54,
	INVULNERABLE_CARD_EFFECT = 57,
	STEALTHED_USER_BUFF = 64,
	STEALTHED_USER_BUFF_FADING = 66,
	BLAST_IMMUNE = 68,
	HALLOWEEN_SPEED_BOOST = 72,
	HALLOWEEN_QUICK_HEAL = 73,
	HALLOWEEN_TINY = 75,
	HALLOWEEN_GHOST_MODE = 77,
	MELEE_ONLY = 85,
	PURGATORY = 108,
	GAS = 123,
}
local C = COND

-- PERMANENT_CONDITION: a duration that never runs out.
PERMANENT = -1

-- conds maps a condition to the time it ends.
function AddCond(conds, cond, duration, now)
	conds[cond] = duration == PERMANENT and math.huge or now + duration
end

function RemoveCond(conds, cond)
	conds[cond] = nil
end

function InCond(conds, cond, now)
	local ends = conds[cond]
	return ends ~= nil and now < ends
end

-- Drops finished conditions; returns them.
function ExpireConds(conds, now)
	local gone = {}
	for cond, ends in pairs(conds) do
		if now >= ends then gone[#gone + 1] = cond end
	end
	for _, cond in ipairs(gone) do conds[cond] = nil end
	return gone
end

-- The conditions CTFPlayer::Regenerate removes that Sandcastle tracks.
local REGENERATE_CLEARS = { C.BURNING, C.URINE, C.MAD_MILK, C.GAS, C.BLEEDING, C.PHASE }

function ClearOnRegenerate(conds)
	for _, cond in ipairs(REGENERATE_CLEARS) do conds[cond] = nil end
end

-- TF_STUN_* (tf_shareddefs.h)
STUN = {
	MOVEMENT = 1,
	CONTROLS = 2,
	NO_EFFECTS = 32,
	LOSER_STATE = 64,
	BY_TRIGGER = 128,
}

-- trigger_stun's stun_type keyvalue.
STUN_TYPE = { MOVEMENT = 0, CONTROLS = 1, LOSER_STATE = 2 }

-- CTriggerStun::StunEntity: every stun slows; the stronger types take more.
function StunFlags(stunType)
	if stunType == STUN_TYPE.CONTROLS then return STUN.MOVEMENT + STUN.CONTROLS end
	if stunType == STUN_TYPE.LOSER_STATE then return STUN.MOVEMENT + STUN.LOSER_STATE end
	return STUN.MOVEMENT
end

-- CTFPlayerShared::StunPlayer keeps a list of stuns and applies the
-- strongest; Sandcastle folds them into one: the later end, the stronger
-- slow, and every flag.
function Stun(current, duration, reduction, flags, now)
	local ends = now + duration
	if not current or now >= current.ends then
		return { ends = ends, reduction = reduction, flags = flags }
	end
	return {
		ends = math.max(current.ends, ends),
		reduction = math.max(current.reduction, reduction),
		flags = bit.bor(current.flags, flags),
	}
end

function StunHas(stun, flag, now)
	return stun ~= nil and now < stun.ends and bit.band(stun.flags, flag) ~= 0
end

-- tf_whip_speed_increase: the cap on a speed boost's bonus.
local SPEED_BOOST_CAP = 105

-- TeamFortress_CalculateMaxSpeed scales by the move speed attributes
-- (attributeScale, default 1) and adds the boost; CTFGameMovement then
-- scales by the stun's slow.
function MaxSpeed(base, speedBoost, stunReduction, attributeScale)
	local speed = base * (attributeScale or 1)
	if speedBoost and speed > 0 then speed = speed + math.min(speed * 0.4, SPEED_BOOST_CAP) end
	return speed * (1 - stunReduction)
end

-- TF_DAMAGE_CRIT_MULTIPLIER, TF_DAMAGE_MINICRIT_MULTIPLIER
local CRIT_MULTIPLIER = 3
MINICRIT_MULTIPLIER = 1.35

-- The crit boosts CTFPlayerShared::IsCritBoosted counts that Sandcastle has.
local CRIT_BOOSTS = { C.CRITBOOSTED, C.CRITBOOSTED_PUMPKIN, C.CRITBOOSTED_USER_BUFF }

-- Damage scale from conditions: an invulnerable victim, or a blast-immune
-- one hit by a blast, takes nothing; a crit-boosted attacker deals triple;
-- a jarated victim takes mini-crits from anyone but themselves (selfHarm).
function DamageScale(victimConds, attackerConds, isBlast, now, selfHarm)
	if InCond(victimConds, C.INVULNERABLE, now) then return 0 end
	if isBlast and InCond(victimConds, C.BLAST_IMMUNE, now) then return 0 end
	for _, boost in ipairs(CRIT_BOOSTS) do
		if InCond(attackerConds, boost, now) then return CRIT_MULTIPLIER end
	end
	if not selfHarm and InCond(victimConds, C.URINE, now) then return MINICRIT_MULTIPLIER end
	return 1
end
