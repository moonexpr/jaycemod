-- The DrGBase factions of TF2's two teams, "Team RED" and "Team BLU"
-- (ws/sh_factions.lua makes them FACTION_TEAM_RED and FACTION_TEAM_BLU,
-- beside DrGBase's own FACTION_COMBINE and the rest). A DrGBase NextBot or
-- player on a playing team is in its team's faction and no other, so its
-- teammates are its allies (DrGBase's D_LI for a shared faction); the AI war
-- relates each soldier to each faction (ALL). Names are upper case, as
-- DrGBase keeps them.
local ipairs = ipairs
local Teams = require("games.gameplay.teams")
module(...)

RED = "FACTION_SANDCASTLE_TEAM_RED"
BLU = "FACTION_SANDCASTLE_TEAM_BLU"

LABEL = { [RED] = "Team RED", [BLU] = "Team BLU" }

local OF = { [Teams.RED] = RED, [Teams.BLUE] = BLU }

ALL = {
	{ team = Teams.RED, faction = RED },
	{ team = Teams.BLUE, faction = BLU },
}

-- The team's faction, or nil for a team that does not play.
function Of(team)
	return OF[team]
end

-- What joining `team` takes: the team factions to leave (every one but its
-- own), and the one to join (nil for a team that does not play).
function Change(team)
	local leave = {}
	for _, entry in ipairs(ALL) do
		if entry.team ~= team then leave[#leave + 1] = entry.faction end
	end
	return leave, OF[team]
end
