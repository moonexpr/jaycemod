-- The kill feed for the AI war's soldiers. GMod's death notices name an NPC
-- "#<class>" with team -1, drawn in a fixed NPC colour; a soldier's notice
-- takes its side's team instead (rebels and vortigaunts BLU, the Combine
-- RED, as the war fields them), so it is drawn in that team's colour, and
-- each class is given its display name (ws/cl_kill_feed.lua).
local sub = string.sub
local Teams = require("foundation.teams")
module(...)

NPC_TEAM = -1 -- the team a death notice gives an NPC

SOLDIERS = {
	ws_drg_rebel = Teams.BLUE,
	ws_drg_vortigaunt = Teams.BLUE,
	ws_drg_combine = Teams.RED,
}

-- The team to show a notice's name in: a soldier's side for its class
-- ("<class>" as GMod's feed passes an entity, or "#<class>"), else the
-- notice's own team, as for a death with no name (nil: a fall, a suicide).
function Team(name, team)
	if team ~= NPC_TEAM or name == nil then return team end
	local class = sub(name, 1, 1) == "#" and sub(name, 2) or name
	return SOLDIERS[class] or team
end
