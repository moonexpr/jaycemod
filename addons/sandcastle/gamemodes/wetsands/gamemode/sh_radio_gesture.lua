-- GMod's chat gesture (base GM:GrabEarAnimation: a hand to the ear while the
-- player types) is a radio call, so only a player dressed as the Combine
-- (ws.voices: its soldiers' and metrocops' models) makes it.
local Voices = WS.require ("includes.voices")
DEFINE_BASECLASS ("gamemode_sandcastle")

function GM:GrabEarAnimation (ply, plyTable)
	local voice = Voices.For (ply:GetModel ())
	if voice and voice.affiliation == Voices.COMBINE then
		return BaseClass.GrabEarAnimation (self, ply, plyTable)
	end
end
