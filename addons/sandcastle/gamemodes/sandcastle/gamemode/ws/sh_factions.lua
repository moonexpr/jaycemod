-- The teams' DrGBase factions (ws.factions): FACTION_TEAM_RED and
-- FACTION_TEAM_BLU, beside DrGBase's own FACTION_COMBINE and the rest, for
-- an NPC's ENT.Factions. On the server, WS.JoinTeamFaction puts a
-- player or a DrGBase NextBot in its team's faction and out of the other's;
-- WS.SetPlayerTeam and WS.SetTeamMember call it, so whoever is on
-- a team is in its faction. Without DrGBase there are no factions to join.
local Factions = WS.require("ws.factions")

FACTION_TEAM_RED = Factions.RED
FACTION_TEAM_BLU = Factions.BLU

if CLIENT then return end

-- A player's faction is held for DrGBase alone (NextSoldier's base reads a
-- player's from its team); a NextBot with factions (DrGBase's, or
-- base_nextsoldier's, which needs no DrGBase) is moved itself.
function WS.JoinTeamFaction(ent, team)
	local leave, join = Factions.Change(team)
	if ent:IsPlayer() then
		if not DrGBase then return end
		for _, faction in ipairs(leave) do ent:DrG_LeaveFaction(faction) end
		if join then ent:DrG_JoinFaction(join) end
	elseif ent.JoinFaction then
		for _, faction in ipairs(leave) do ent:LeaveFaction(faction) end
		if join then ent:JoinFaction(join) end
	end
end
