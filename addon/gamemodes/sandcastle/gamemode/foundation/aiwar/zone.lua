-- The ground behind the setup gates: where the attackers wander in setup.
-- A flood over the nav mesh from their spawn areas, held back at the
-- gates, so it takes in the spawn rooms and every yard and corridor up to
-- the gates, and none of the map beyond them. A gate the war did not find
-- lets the flood out; `leaked` (an area of the far side reached, or too
-- many areas) says the zone cannot be trusted.
--
-- Areas are ids; the caller answers for the nav mesh.
local ipairs = ipairs
module(...)

-- starts: area ids to flood from; Neighbors(id) -> ids; Blocked(id) ->
-- true for an area the flood may not enter; Outside(id) -> true for an area
-- only reached through a gate left open; limit: the most areas to take.
-- Returns the ids reached and whether the flood leaked.
function Flood(starts, Neighbors, Blocked, Outside, limit)
	local seen, zone, head = {}, {}, 1
	for _, id in ipairs(starts) do
		if not seen[id] and not Blocked(id) then
			seen[id] = true
			zone[#zone + 1] = id
		end
	end
	while head <= #zone do
		local id = zone[head]
		head = head + 1
		if Outside(id) then return zone, true end
		for _, next in ipairs(Neighbors(id)) do
			if not seen[next] then
				seen[next] = true
				if not Blocked(next) then
					if #zone >= limit then return zone, true end
					zone[#zone + 1] = next
				end
			end
		end
	end
	return zone, false
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
