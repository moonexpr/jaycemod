-- Where the AI war's soldiers join the fight on a map without TF2's team
-- spawns (info_player_teamspawn): each team at its faction's HL2
-- deathmatch spawns (FACTION_CLASSES: the Combine's, the rebels'), whichever
-- team the faction fights for;
-- a team without them at the nav mesh's hiding spots, split between the
-- teams (Split) so each has its own side of the map; and on a map without
-- hiding spots, at its shared player starts (SHARED_CLASSES).
--
-- Positions are { x, y, z } tables.
local ipairs, sort = ipairs, table.sort
local ceil = math.ceil
local Teams = require("foundation.teams")
local AiWar = require("foundation.aiwar")
module(...)

FACTION_CLASSES = {
	[AiWar.COMBINE] = { "info_player_combine" },
	[AiWar.RESISTANCE] = { "info_player_rebel" },
}
SHARED_CLASSES = { "info_player_deathmatch", "info_player_start" }

local function Present(classes, present)
	local list = {}
	for _, class in ipairs(classes) do
		if present(class) then list[#list + 1] = class end
	end
	return list
end

-- The spawn classes of faction (an id: foundation.aiwar's COMBINE,
-- RESISTANCE) the map has (present(class) -> bool); none sends its team to
-- the hiding spots.
function Classes(faction, present)
	return Present(FACTION_CLASSES[faction] or {}, present)
end

-- The shared player start classes the map has.
function Shared(present)
	return Present(SHARED_CLASSES, present)
end

-- The team's share of the hiding spots: sorted along the longer side of
-- their extent, RED the low half and BLU the high, the middle one of an odd
-- count both teams'.
function Split(spots, team)
	if #spots == 0 then return {} end
	local loX, hiX, loY, hiY = spots[1].x, spots[1].x, spots[1].y, spots[1].y
	for _, p in ipairs(spots) do
		if p.x < loX then loX = p.x end
		if p.x > hiX then hiX = p.x end
		if p.y < loY then loY = p.y end
		if p.y > hiY then hiY = p.y end
	end
	local axis = (hiX - loX >= hiY - loY) and "x" or "y"
	local sorted = {}
	for i, p in ipairs(spots) do sorted[i] = p end
	sort(sorted, function(a, b) return a[axis] < b[axis] end)
	local half = ceil(#sorted / 2)
	local from, to = 1, half
	if team == Teams.BLUE then from, to = #sorted - half + 1, #sorted end
	local share = {}
	for i = from, to do share[#share + 1] = sorted[i] end
	return share
end
