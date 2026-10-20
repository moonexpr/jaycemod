-- The kill feed for the AI war's soldiers. GMod's death notices name an NPC
-- "#<class>" with team -1, drawn in a fixed NPC colour; a soldier's notice
-- takes the team its faction fights for instead (foundation.aiwar's
-- factions: the Combine and the Resistance, each on its home team until
-- the sides trade), so it is drawn in that team's colour, and each class
-- is given its display name (ws/cl_kill_feed.lua).
local pairs, sub = pairs, string.sub
local AiWar = require("foundation.aiwar")
module(...)

NPC_TEAM = -1 -- the team a death notice gives an NPC

-- class -> its faction's id
SOLDIERS = {}
for id, faction in pairs(AiWar.FACTIONS) do
	for class in pairs(faction.classes) do SOLDIERS[class] = id end
end

-- The team to show a notice's name in: for a soldier's class ("<class>" as
-- GMod's feed passes an entity, or "#<class>"), the team its faction fights
-- for in sides (foundation.aiwar's Sides; without it, its home); else the
-- notice's own team, as for a death with no name (nil: a fall, a suicide).
function Team(name, team, sides)
	if team ~= NPC_TEAM or name == nil then return team end
	local class = sub(name, 1, 1) == "#" and sub(name, 2) or name
	local faction = SOLDIERS[class]
	if not faction then return team end
	return sides and sides[faction] or AiWar.FACTIONS[faction].home
end
