-- MEDIC!: a player or soldier calling for a medic. Its side's medics answer
-- it first for MEDIC_CALL_SHOWN seconds (the AI war's patients' calling,
-- features/aiwar/sv_field.lua), and its teammates see TF2's bubble over it
-- that long (ws_medic_call_end, ws/cl_medic_effects.lua). A player calls
-- with +use aimed at nothing (ws/sv_use.lua), once per call.
local MEDIC_CALL_SHOWN = 3

function WS.CallingMedic(ent)
	return CurTime() < ent:GetNW2Float("ws_medic_call_end", 0)
end

-- Calls for a medic; returns when the call ends.
function WS.CallMedic(ent)
	local ends = CurTime() + MEDIC_CALL_SHOWN
	ent:SetNW2Float("ws_medic_call_end", ends)
	return ends
end

hook.Add("WSPlayerUseNothing", "ws_medic_call", function(ply)
	if WS.TeamOf(ply) ~= WS.TEAM_UNASSIGNED and not WS.CallingMedic(ply) then WS.CallMedic(ply) end
end)
