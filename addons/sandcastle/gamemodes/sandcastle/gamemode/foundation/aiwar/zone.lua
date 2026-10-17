-- The ground behind the setup gates: where the attackers wander in setup.
-- A flood over the nav mesh from their spawn areas, held back at the
-- gates, so it takes in the spawn rooms and every yard and corridor up to
-- the gates, and none of the map beyond them. A gate the war did not find
-- lets the flood out; `leaked` (an area of the far side reached, or too
-- many areas) says the zone cannot be trusted.
--
-- Areas are ids; the caller answers for the nav mesh.
local ipairs = ipairs
local Graph = require("foundation.core.graph")
module(...)

-- starts: area ids to flood from; Neighbors(id) -> ids; Blocked(id) ->
-- true for an area the flood may not enter; Outside(id) -> true for an area
-- only reached through a gate left open; limit: the most areas to take.
-- Returns the ids reached and whether the flood leaked.
function Flood(starts, Neighbors, Blocked, Outside, limit)
	local open = {}
	for _, id in ipairs(starts) do
		if not Blocked(id) then open[#open + 1] = id end
	end
	return Graph.Flood(open, Neighbors, function(id) return not Blocked(id) end, limit, Outside)
end

-- An item of the list picked with odds by weight: r in [0, 1).
function PickWeighted(items, Weight, r)
	local total = 0
	for _, item in ipairs(items) do total = total + Weight(item) end
	if total <= 0 then return items[1] end
	local target = r * total
	for _, item in ipairs(items) do
		target = target - Weight(item)
		if target < 0 then return item end
	end
	return items[#items]
end
