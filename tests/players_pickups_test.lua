local T = dofile("tests/harness.lua")
local P = T.require("foundation.players")

-- PackRatios (tf_powerup.cpp)

T.test("pack sizes are TF2's ratios", function()
	T.eq(P.PACK_RATIO.small, 0.2, "small")
	T.eq(P.PACK_RATIO.medium, 0.5, "medium")
	T.eq(P.PACK_RATIO.full, 1.0, "full")
	T.defined(P.ITEM_RESPAWN_TIME, "respawn")
end)

-- CHealthKit::MyTouch

T.test("a health kit heals ceil(max * ratio), capped at max", function()
	T.eq(P.HealthKitHeal(100, 125, 0.2), 25, "small on a soldier-ish max")
	T.eq(P.HealthKitHeal(50, 175, 0.5), 88, "medium rounds up")
	T.eq(P.HealthKitHeal(120, 125, 1.0), 5, "capped")
	T.eq(P.HealthKitHeal(125, 125, 1.0), 0, "full")
	T.eq(P.HealthKitHeal(200, 125, 1.0), 0, "overhealed")
end)

T.test("a health kit is taken when it heals or puts out fire", function()
	T.eq(P.HealthKitTaken(10, false), true, "healed")
	T.eq(P.HealthKitTaken(0, true), true, "burning")
	T.eq(P.HealthKitTaken(0, false), false, "nothing")
end)

-- CAmmoPack::MyTouch, GiveAmmo

T.test("an ammo pack gives ceil(max * ratio), capped", function()
	T.eq(P.AmmoAfterPack(0, 32, 0.2), 7, "small")
	T.eq(P.AmmoAfterPack(30, 32, 0.5), 32, "capped")
	T.eq(P.AmmoAfterPack(40, 32, 0.5), 40, "never takes away")
end)

-- CTFPlayer::Regenerate

T.test("resupply fills health but keeps overheal", function()
	T.eq(P.RegenerateHealth(40, 125), 125, "hurt")
	T.eq(P.RegenerateHealth(180, 125), 180, "overhealed")
end)

-- CTFAmmoPack

T.test("a dropped ammo pack is a medium pack that lasts 30 seconds", function()
	T.eq(P.DROPPED_PACK.ratio, 0.5, "ratio")
	T.eq(P.DROPPED_PACK.lifetime, 30, "lifetime")
	T.eq(P.DROPPED_PACK.ownerDelay, 0.75, "owner delay")
end)

-- Conditions (CTFPlayerShared::AddCond / RemoveCond)

T.test("a condition lasts its duration, PERMANENT forever", function()
	local conds = {}
	P.AddCond(conds, P.COND.SPEED_BOOST, 3, 100)
	P.AddCond(conds, P.COND.INVULNERABLE, P.PERMANENT, 100)
	T.eq(P.InCond(conds, P.COND.SPEED_BOOST, 102), true, "boost live")
	T.eq(P.InCond(conds, P.COND.SPEED_BOOST, 104), false, "boost over")
	T.eq(P.InCond(conds, P.COND.INVULNERABLE, 1e6), true, "permanent")
end)

T.test("removing a condition ends it; expiring drops only the finished ones", function()
	local conds = {}
	P.AddCond(conds, P.COND.SPEED_BOOST, 3, 100)
	P.AddCond(conds, P.COND.CRITBOOSTED, 10, 100)
	P.RemoveCond(conds, P.COND.CRITBOOSTED)
	T.eq(P.InCond(conds, P.COND.CRITBOOSTED, 101), false, "removed")
	P.AddCond(conds, P.COND.BLAST_IMMUNE, 10, 100)
	local gone = P.ExpireConds(conds, 105)
	T.eq(#gone, 1, "one expired")
	T.eq(gone[1], P.COND.SPEED_BOOST, "the boost")
	T.eq(P.InCond(conds, P.COND.BLAST_IMMUNE, 105), true, "still immune")
end)

T.test("resupply clears burning, jarate, milk and gas but not a speed boost", function()
	local conds = {}
	P.AddCond(conds, P.COND.BURNING, 5, 0)
	P.AddCond(conds, P.COND.URINE, 5, 0)
	P.AddCond(conds, P.COND.SPEED_BOOST, 5, 0)
	P.ClearOnRegenerate(conds)
	T.eq(P.InCond(conds, P.COND.BURNING, 1), false, "burning")
	T.eq(P.InCond(conds, P.COND.URINE, 1), false, "urine")
	T.eq(P.InCond(conds, P.COND.SPEED_BOOST, 1), true, "boost")
end)

-- Stuns (CTriggerStun::StunEntity, CTFPlayerShared::StunPlayer)

T.test("trigger stun types map to TF2's stun flags", function()
	T.eq(P.StunFlags(P.STUN_TYPE.MOVEMENT), P.STUN.MOVEMENT, "movement")
	T.eq(P.StunFlags(P.STUN_TYPE.CONTROLS), P.STUN.MOVEMENT + P.STUN.CONTROLS, "controls")
	T.eq(P.StunFlags(P.STUN_TYPE.LOSER_STATE), P.STUN.MOVEMENT + P.STUN.LOSER_STATE, "loser")
end)

T.test("a stronger or longer stun wins", function()
	local s = P.Stun(nil, 3, 0.5, P.STUN.MOVEMENT, 10)
	T.eq(s.ends, 13, "ends")
	T.eq(s.reduction, 0.5, "reduction")
	s = P.Stun(s, 1, 0.2, P.STUN.LOSER_STATE, 11)
	T.eq(s.ends, 13, "keeps the later end")
	T.eq(s.reduction, 0.5, "keeps the stronger slow")
	T.eq(P.StunHas(s, P.STUN.LOSER_STATE, 12), true, "adds the loser state")
	T.eq(P.StunHas(s, P.STUN.LOSER_STATE, 14), false, "over")
end)

-- CTFPlayer::TeamFortress_CalculateMaxSpeed and CTFGameMovement's stun slow

T.test("speed boost adds 40 percent, at most 105 units", function()
	T.near(P.MaxSpeed(200, false, 0), 200, 1e-6, "plain")
	T.near(P.MaxSpeed(200, true, 0), 280, 1e-6, "boost")
	T.near(P.MaxSpeed(400, true, 0), 505, 1e-6, "boost capped")
end)

T.test("a stun slows by its reduction after the boost", function()
	T.near(P.MaxSpeed(200, false, 0.5), 100, 1e-6, "half")
	T.near(P.MaxSpeed(200, true, 0.5), 140, 1e-6, "boosted half")
end)

-- "major move speed bonus" scales the class speed before the boost.
T.test("a move speed attribute scales the speed before the boost and the stun", function()
	T.near(P.MaxSpeed(200, false, 0, 2), 400, 1e-6, "doubled")
	T.near(P.MaxSpeed(200, true, 0, 2), 505, 1e-6, "then boosted, capped")
	T.near(P.MaxSpeed(200, false, 0.5, 2), 200, 1e-6, "then slowed")
end)

-- Damage conditions: invulnerable, blast immune, crit boosted

-- What a hit is, and what it multiplies the damage by (CTFGameRules::
-- ApplyOnDamageModifyRules): facts says whether it was a blast, the
-- attacker's own harm, a headshot, or a crit already (DMG_CRITICAL, its
-- damage already tripled).
local function Hit(victim, attacker, now, facts) return P.Hit(victim, attacker, now, facts or {}) end

local function Is(scale, kind, what, gotScale, gotKind)
	T.eq(gotScale, scale, what .. " (scale)")
	T.eq(gotKind, kind, what .. " (kind)")
end

T.test("a hit's scale follows the victim's and attacker's conditions", function()
	local victim, attacker = {}, {}
	Is(1, P.HIT_NORMAL, "plain", Hit(victim, attacker, 0))
	P.AddCond(attacker, P.COND.CRITBOOSTED, P.PERMANENT, 0)
	Is(3, P.HIT_CRIT, "crit boosted", Hit(victim, attacker, 0))
	P.AddCond(victim, P.COND.BLAST_IMMUNE, P.PERMANENT, 0)
	Is(0, P.HIT_NORMAL, "blast immune", Hit(victim, attacker, 0, { blast = true }))
	Is(3, P.HIT_CRIT, "not blast", Hit(victim, attacker, 0))
	P.AddCond(victim, P.COND.INVULNERABLE, P.PERMANENT, 0)
	Is(0, P.HIT_NORMAL, "invulnerable", Hit(victim, attacker, 0))
end)

-- CTFPlayerShared::IsCritBoosted counts the pumpkin's crits, which
-- Merasmus gives whoever finds or stuns him, and the winners' bonus time.
T.test("the pumpkin and bonus-time crit boosts triple damage too", function()
	local victim, attacker = {}, {}
	P.AddCond(attacker, P.COND.CRITBOOSTED_PUMPKIN, P.PERMANENT, 0)
	Is(3, P.HIT_CRIT, "pumpkin crit", Hit(victim, attacker, 0))
	local winner = {}
	P.AddCond(winner, P.COND.CRITBOOSTED_BONUS_TIME, P.PERMANENT, 0)
	Is(3, P.HIT_CRIT, "bonus time", Hit(victim, winner, 0))
	T.eq(P.COND.CRITBOOSTED_PUMPKIN, 33, "TF2's number")
	T.eq(P.COND.CRITBOOSTED_BONUS_TIME, 38, "TF2's number")
	T.eq(P.COND.HALLOWEEN_BOMB_HEAD, 53, "TF2's number")
end)

-- ApplyOnDamageModifyRules: Jarate makes every hit but your own a mini-crit.
T.test("a jarated player takes mini-crits from anyone else; a crit stays a crit", function()
	local victim, attacker = {}, {}
	P.AddCond(victim, P.COND.URINE, 10, 0)
	local scale, kind = Hit(victim, attacker, 1)
	T.near(scale, 1.35, 1e-9, "mini-crit")
	T.eq(kind, P.HIT_MINICRIT, "a mini-crit")
	Is(1, P.HIT_NORMAL, "not their own", Hit(victim, attacker, 1, { selfHarm = true }))
	Is(1, P.HIT_NORMAL, "dry again", Hit(victim, attacker, 11))
	P.AddCond(attacker, P.COND.CRITBOOSTED_PUMPKIN, P.PERMANENT, 0)
	Is(3, P.HIT_CRIT, "a crit", Hit(victim, attacker, 1))
end)

-- Sandcastle crits every weapon's headshot, not only the Sniper's.
T.test("a headshot is a crit, from any weapon", function()
	Is(3, P.HIT_CRIT, "a headshot", Hit({}, {}, 0, { headshot = true }))
	local boosted = {}
	P.AddCond(boosted, P.COND.CRITBOOSTED, P.PERMANENT, 0)
	Is(3, P.HIT_CRIT, "a boosted headshot is one crit", Hit({}, boosted, 0, { headshot = true }))
end)

-- The shotgun's crit by distance (foundation.combat.weapon_balance).
T.test("a crit the weapon rolled is tripled, as a headshot", function()
	Is(3, P.HIT_CRIT, "a rolled crit", Hit({}, {}, 0, { rolled = true }))
	local boosted = {}
	P.AddCond(boosted, P.COND.CRITBOOSTED, P.PERMANENT, 0)
	Is(3, P.HIT_CRIT, "a boosted rolled crit is one crit", Hit({}, boosted, 0, { rolled = true }))
	Is(1, P.HIT_NORMAL, "never on itself", Hit({}, {}, 0, { selfHarm = true, rolled = true }))
end)

T.test("a hit already a crit keeps its damage, tripled where it was dealt", function()
	local boosted = {}
	P.AddCond(boosted, P.COND.CRITBOOSTED, P.PERMANENT, 0)
	Is(1, P.HIT_CRIT, "a crit rocket", Hit({}, {}, 0, { critical = true }))
	Is(1, P.HIT_CRIT, "not tripled twice", Hit({}, boosted, 0, { critical = true }))
	local invulnerable = {}
	P.AddCond(invulnerable, P.COND.INVULNERABLE, P.PERMANENT, 0)
	Is(0, P.HIT_NORMAL, "nothing through an uber", Hit(invulnerable, {}, 0, { critical = true }))
end)

-- ApplyOnDamageModifyRules: a player's own damage is never a crit.
T.test("an attacker's harm to itself is never crit boosted", function()
	local boosted = {}
	P.AddCond(boosted, P.COND.CRITBOOSTED, P.PERMANENT, 0)
	Is(1, P.HIT_NORMAL, "a rocket jump", Hit(boosted, boosted, 0, { selfHarm = true }))
	Is(1, P.HIT_NORMAL, "nor a headshot", Hit({}, {}, 0, { selfHarm = true, headshot = true }))
end)

T.finish()
