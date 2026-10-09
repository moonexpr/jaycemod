-- The kill feed for the AI war's soldiers. GMod's death notices name an NPC
-- "#<class>" with team -1, drawn in a fixed NPC colour; a soldier's notice
-- takes its side's team instead (rebels and vortigaunts BLU, the Combine
-- RED, as the war fields them), so it is drawn in that team's colour, and
-- each class is given its display name (wetsand/cl_kill_feed.lua).
local sub = string.sub
local Teams = require("foundation.teams")
module(...)

NPC_TEAM = -1 -- the team a death notice gives an NPC

SOLDIERS = {
	wetsand_drg_rebel = Teams.BLUE,
	wetsand_drg_vortigaunt = Teams.BLUE,
	wetsand_drg_combine = Teams.RED,
}

-- The team to show a notice's name in: a soldier's side for "#<class>",
-- else the notice's own team.
function Team(name, team)
	if team ~= NPC_TEAM or sub(name, 1, 1) ~= "#" then return team end
	return SOLDIERS[sub(name, 2)] or team
end
