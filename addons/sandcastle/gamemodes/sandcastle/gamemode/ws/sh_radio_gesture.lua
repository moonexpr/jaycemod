-- GMod's chat gesture (base GM:GrabEarAnimation: a hand to the ear while the
-- player types) is a radio call, so only a player dressed as the Combine
-- (foundation.npc.voices: its soldiers' and metrocops' models) makes it.
local Voices = WS.require("foundation.npc.voices")

function GM:GrabEarAnimation(ply, plyTable)
	local voice = Voices.For(ply:GetModel())
	if voice and voice.affiliation == Voices.COMBINE then
		return self.BaseClass.GrabEarAnimation(self, ply, plyTable)
	end
end
