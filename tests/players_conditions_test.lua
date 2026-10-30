local T = dofile("tests/harness.lua")
local P = gameplay.players
local C = P.COND

-- The conditions a hit inflicts (bleeding, marked for death): a hit while
-- one is held lasts the longer of the two, never cutting it short.
T.test("an inflicted condition lasts the longer of the one held and the new", function()
	local conds = {}
	P.Inflict(conds, C.BLEEDING, 5, 10)
	T.eq(P.InCond(conds, C.BLEEDING, 14.9), true, "held its seconds")
	P.Inflict(conds, C.BLEEDING, 2, 11)
	T.eq(P.InCond(conds, C.BLEEDING, 14.9), true, "a shorter one keeps the end held")
	P.Inflict(conds, C.BLEEDING, 10, 12)
	T.eq(P.InCond(conds, C.BLEEDING, 21.9), true, "a longer one lasts longer")
	T.eq(P.InCond(conds, C.BLEEDING, 22), false, "and ends")
end)

-- CTFPlayerShared::MakeBleed: TF_BLEEDING_DMG every TF_BLEEDING_FREQUENCY.
T.test("bleeding hurts as TF2's does", function()
	T.eq(C.BLEEDING, 25, "TF_COND_BLEEDING")
	T.eq(P.BLEED_INTERVAL, 0.5, "TF_BLEEDING_FREQUENCY")
	T.eq(P.BLEED_DAMAGE, 4, "TF_BLEEDING_DMG")
end)

-- CTFPlayerShared::MakeBleed and ConditionThink: a bleed first hurts a full
-- interval after it starts, then every interval, and not once it has ended.
T.test("a bleed hurts every interval from its start until it ends", function()
	local conds = {}
	P.Inflict(conds, C.BLEEDING, 4 * P.BLEED_INTERVAL, 0)
	local hurts, nextTick = P.BleedTick(conds, nil, 0.01)
	T.eq(hurts, false, "not as it starts")
	T.near(nextTick, 0.01 + P.BLEED_INTERVAL, 1e-9, "first a full interval on")
	local ticks, tick, now = 0, P.BLEED_INTERVAL, 0
	while now < 10 do
		now = now + 0.1
		local hurt
		hurt, tick = P.BleedTick(conds, tick, now)
		if hurt then ticks = ticks + 1 end
	end
	T.eq(ticks, 3, "every interval on its own clock, a coarse think not stretching it")
	T.eq(P.BleedTick({}, 1, 2), false, "no bleed held, no hurt")
end)

-- CTFWeaponBase::ApplyOnHitAttributes: a hit on a milked victim heals its
-- attacker 60 % of the damage, rounded down.
T.test("hurting a milked victim heals the attacker part of the damage", function()
	T.eq(C.MAD_MILK, 27, "TF_COND_MAD_MILK")
	T.eq(P.MILK_HEAL, 0.6, "TF2's share")
	local milked = {}
	P.AddCond(milked, C.MAD_MILK, 3, 0)
	T.eq(P.MilkHeal(milked, 25, 1), math.floor(25 * P.MILK_HEAL), "a share of the hit")
	T.eq(P.MilkHeal(milked, 25, 3), 0, "none once it is washed off")
	T.eq(P.MilkHeal({}, 25, 1), 0, "none on one never milked")
end)

-- TF_COND_MARKEDFORDEATH: the victim takes mini-crits, as a jarated one.
T.test("a victim marked for death takes mini-crits", function()
	T.eq(C.MARKED_FOR_DEATH, 30, "TF_COND_MARKEDFORDEATH")
	local marked = {}
	P.AddCond(marked, C.MARKED_FOR_DEATH, 3, 0)
	local scale, kind = P.Hit(marked, {}, 1, {})
	T.eq(kind, P.HIT_MINICRIT, "a mini-crit")
	T.eq(scale, P.MINICRIT_MULTIPLIER, "its damage")
	local _, own = P.Hit(marked, {}, 1, { selfHarm = true })
	T.eq(own, P.HIT_NORMAL, "not by its own hand")
	local _, after = P.Hit(marked, {}, 3, {})
	T.eq(after, P.HIT_NORMAL, "nor once the mark is gone")
end)

T.finish()
