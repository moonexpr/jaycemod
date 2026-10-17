-- func_regenerate (CRegenerateZone): the resupply locker volume. A player it
-- serves (its team, or during team win the winners at every locker, never
-- in a stalemate) is resupplied at most once every 3 seconds
-- (CTFPlayer::Regenerate), hears Regenerate.Touch alone, and the locker prop
-- opens, then closes a second before the next use.
ENT.Type = "brush"
ENT.Base = "ws_brush_volume"

local NEXT_USE_TIME = 3.0
local SOUND = "Regenerate.Touch"

function ENT:VolumeInit()
	self.associatedModel = self:Key("associatedmodel")
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if not self.enabled then return true end
	local now, state, winner = CurTime(), WS.State(), GetGlobal2Int("ws_round_winner", WS.TEAM_UNASSIGNED)
	for _, ply in ipairs(WS.PlayersInside(self)) do
		if now >= (ply.wsNextRegen or 0) and WS.TeamRules.RegenerateAllowed(self.team, ply:Team(), state, winner) then
			self:Regenerate(ply)
		end
	end
	return true
end

-- CRegenerateZone::Regenerate
function ENT:Regenerate(ply)
	WS.RegeneratePlayer(ply)
	ply.wsNextRegen = CurTime() + NEXT_USE_TIME
	WS.PlaySoundTo(ply, ply, SOUND)
	local prop = WS.FindByName(self.associatedModel)
	if IsValid(prop) then
		prop:Fire("SetAnimation", "open")
		prop:Fire("SetAnimation", "close", NEXT_USE_TIME - 1.0)
	end
end
