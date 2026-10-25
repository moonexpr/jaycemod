-- Path costs: the IPathCost functor a NextBot hands its path search, as
-- strategies. A strategy is a part (foundation.wetsands.path.<name>) providing
-- Cost(step, limits, bot) -> cost or IMPASSABLE, where
--   step   = { hasFrom, traversable, ladderLength, length, centerDistance,
--              heightChange, fromCostSoFar, areaId } for the move into an area,
--   limits = the variant's LOCOMOTION (stepHeight, jumpHeight, deathDropHeight),
--   bot    = { entIndex, now }.
-- The binding builds `step` from the engine's navigation areas; a variant
-- names its strategy in PATH. A strategy the native search can run also
-- provides Model(limits, bot) -> the walker model native/wetsands prices a
-- step with (its walker.rs): the same cost as parameters, built on
-- Model(limits, fields) here.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local pairs = pairs
module(...)

IMPASSABLE = -1
JUMP_PENALTY = 5 -- jumping is slower than flat ground

-- Whether a walker within limits can make a move that changes its height
-- by deltaZ: up less than its jump, down no further than its death drop.
function Walkable(deltaZ, limits)
	return deltaZ < limits.jumpHeight and deltaZ >= -limits.deathDropHeight
end

-- A walker model: the limits, and the strategy's fields over them.
function Model(limits, fields)
	local model = {
		stepHeight = limits.stepHeight,
		jumpHeight = limits.jumpHeight,
		deathDropHeight = limits.deathDropHeight,
		crouches = limits.crouches == true,
	}
	for key, value in pairs(fields) do model[key] = value end
	return model
end
