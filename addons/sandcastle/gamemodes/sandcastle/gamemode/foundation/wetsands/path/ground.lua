-- A walker's path cost: the body CZombiePathCost and CHeadlessHatmanPathCost
-- share. Weighted(step, limits, preference) is that body with the distance
-- weighed by a preference; Cost uses none.
local Path = wetsands.path
module(...)

local IMPASSABLE, JUMP_PENALTY = Path.IMPASSABLE, Path.JUMP_PENALTY
local NO_PREFERENCE = 1

local function Distance(step)
	if step.ladderLength then return step.ladderLength end
	if step.length > 0 then return step.length end
	return step.centerDistance
end

function Weighted(step, limits, preference)
	if not step.hasFrom then return 0 end
	if not step.traversable then return IMPASSABLE end
	local dist = Distance(step)
	local deltaZ = step.heightChange
	if not Path.Walkable(deltaZ, limits) then return IMPASSABLE end
	if deltaZ >= limits.stepHeight then dist = dist + JUMP_PENALTY * dist end
	return dist * preference + step.fromCostSoFar
end

function Cost(step, limits, bot)
	return Weighted(step, limits, NO_PREFERENCE)
end
