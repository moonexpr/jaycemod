-- The factions of TF2's two teams, "Team RED" and "Team BLU"
-- (ws/sh_factions.lua makes them FACTION_TEAM_RED and FACTION_TEAM_BLU,
-- beside HL2's). A soldier or player on a playing team is in its team's
-- faction and no other, so its teammates are its allies (D_LI for a shared
-- faction, nextsoldier.relations); the AI war relates each soldier to each
-- faction (ALL). Names are upper case, as DrGBase, whose names we keep,
-- wrote them.
local ipairs = ipairs
local Teams = gameplay.teams
module(...)

RED = "FACTION_SANDCASTLE_TEAM_RED"
BLU = "FACTION_SANDCASTLE_TEAM_BLU"
-- HL2's sides, by DrGBase's own names for them (its FACTION_COMBINE and
-- FACTION_REBELS), so its NextBots and NextSoldier's share them, and ours
-- need no DrGBase.
HL2_COMBINE = "FACTION_HL2_COMBINE"
HL2_REBELS = "FACTION_HL2_REBELS"

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
