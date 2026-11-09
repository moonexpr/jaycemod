-- cs_gamerules: CS:S's gamerules proxy (CCSGameRulesProxy): Sandcastle's
-- gamerules (ws_gamerules), running rounds from the start, as on any CS:S
-- map, and answering CS:S's round-end inputs (features.hostage.rules) as a
-- map's outputs send them. The rounds controller makes them for the hostage
-- mode (features/rounds/sv.lua's EnsureProxy).
ENT.Type = "point"
ENT.Base = "ws_gamerules"
ENT.RunsRounds = true

function ENT:AcceptInput(name, activator, caller, value)
	local ending = WS.require("features.hostage.rules").Input(string.lower(name))
	if not ending then return self.BaseClass.AcceptInput(self, name, activator, caller, value) end
	self.wsLastInput = string.format("%s from %s at %.2f", name, tostring(caller), CurTime())
	if ending.draw then
		self:SetStalemate(gameplay.rounds.STALEMATE.TIMER, true, false)
	else
		self:SetWinningTeam(ending.winner, ending.reason, true, false, false)
	end
	return true
end
