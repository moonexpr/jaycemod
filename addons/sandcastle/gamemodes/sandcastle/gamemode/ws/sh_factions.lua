-- The teams' factions (ws.factions): FACTION_TEAM_RED and FACTION_TEAM_BLU,
-- beside HL2's, for a soldier's ENT.Factions. On the server,
-- WS.JoinTeamFaction puts a NextBot with factions in its team's and out of
-- the other's; WS.SetPlayerTeam and WS.SetTeamMember call it. A player's
-- faction is its team's: NextSoldier's base reads it from the team.
local Factions = WS.require("ws.factions")

FACTION_TEAM_RED = Factions.RED
FACTION_TEAM_BLU = Factions.BLU

if CLIENT then return end

function WS.JoinTeamFaction(ent, team)
	if not ent.JoinFaction then return end
	local leave, join = Factions.Change(team)
	for _, faction in ipairs(leave) do ent:LeaveFaction(faction) end
	if join then ent:JoinFaction(join) end
end
