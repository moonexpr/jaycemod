-- The teams' DrGBase factions (foundation.factions): FACTION_TEAM_RED and
-- FACTION_TEAM_BLU, beside DrGBase's own FACTION_COMBINE and the rest, for
-- an NPC's ENT.Factions. On the server, WETSAND.JoinTeamFaction puts a
-- player or a DrGBase NextBot in its team's faction and out of the other's;
-- WETSAND.SetPlayerTeam and WETSAND.SetTeamMember call it, so whoever is on
-- a team is in its faction. Without DrGBase there are no factions to join.
local Factions = WETSAND.require("foundation.factions")

FACTION_TEAM_RED = Factions.RED
FACTION_TEAM_BLU = Factions.BLU

if CLIENT then return end

function WETSAND.JoinTeamFaction(ent, team)
	if not DrGBase then return end
	local leave, join = Factions.Change(team)
	if ent:IsPlayer() then
		for _, faction in ipairs(leave) do ent:DrG_LeaveFaction(faction) end
		if join then ent:DrG_JoinFaction(join) end
	elseif ent.IsDrGNextbot then
		for _, faction in ipairs(leave) do ent:LeaveFaction(faction) end
		if join then ent:JoinFaction(join) end
	end
end
