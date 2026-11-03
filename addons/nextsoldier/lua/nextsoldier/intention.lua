-- What a soldier with an enemy does about it: base_nextsoldier's intention
-- (TF2's IIntention), its decisions as plain values.
--
-- Ranges{ reach, avoid, range, melee } -> ranges, made once (a class's
--   ReachEnemyRange, AvoidEnemyRange, RangeAttackRange, MeleeAttackRange):
--   numbers, else refused
-- Stage(distance, ranges) -> CHASE (farther than reach), AVOID (nearer than
--   avoid), or HOLD: which hook the bot raises (OnChaseEnemy, OnAvoidEnemy,
--   OnIdleEnemy)
-- Attack(distance, ranges, visible, melee) -> MELEE (in melee reach with a
--   melee weapon), RANGED (a gun in range), or nil; only an enemy in sight
-- Better(a, b, ask, priorityOf, distanceOf) -> whether a is the more
--   dangerous threat (TF2's SelectMoreDangerousThreat): ask(a, b) first
--   (true or false, nil to leave it), then the higher priority, then the
--   nearer
local error, ipairs, type = error, ipairs, type
module(...)

CHASE, AVOID, HOLD = "chase", "avoid", "hold"
MELEE, RANGED = "melee", "ranged"

function Ranges(spec)
	for _, key in ipairs({ "reach", "avoid", "range", "melee" }) do
		if type(spec[key]) ~= "number" then error("ranges need a number " .. key, 2) end
	end
	return { reach = spec.reach, avoid = spec.avoid, range = spec.range, melee = spec.melee }
end

function Stage(distance, ranges)
	if distance > ranges.reach then return CHASE end
	if distance < ranges.avoid then return AVOID end
	return HOLD
end

function Attack(distance, ranges, visible, melee)
	if not visible then return nil end
	if melee then
		if distance <= ranges.melee then return MELEE end
		return nil
	end
	if distance <= ranges.range then return RANGED end
	return nil
end

function Better(a, b, ask, priorityOf, distanceOf)
	local answer = ask(a, b)
	if answer ~= nil then return answer end
	local pa, pb = priorityOf(a), priorityOf(b)
	if pa ~= pb then return pa > pb end
	return distanceOf(a) < distanceOf(b)
end
