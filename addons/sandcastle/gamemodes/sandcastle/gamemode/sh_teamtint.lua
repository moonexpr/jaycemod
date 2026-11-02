-- Team Tint (addons/teamtint), when it is installed: every NPC and NextBot
-- on a team (WS.SetTeamMember's ws_team) shows it, RED or BLU, in TF2's
-- shading. Its tool's override shows a team a body does not fight for, a
-- debug tool: while the AI war is on, only admins may set it. Death
-- ragdolls take their body's team in ws/cl_npc_ragdolls.lua.
local REPRESENTATIONS = { [WS.TEAM_RED] = "red", [WS.TEAM_BLUE] = "blu" }

if CLIENT then
	hook.Add("TeamTintTeamOf", "ws_teamtint", function(ent)
		return REPRESENTATIONS[ent:GetNW2Int("ws_team", WS.TEAM_UNASSIGNED)]
	end)
else
	hook.Add("TeamTintCanOverride", "ws_teamtint", function(ply)
		if WS.AiWarActive() and not ply:IsAdmin() then return false end
	end)
end
