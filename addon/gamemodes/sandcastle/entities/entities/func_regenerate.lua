-- func_regenerate (CRegenerateZone): the resupply locker volume. A player it
-- serves (its team, or during team win the winners at every locker, never
-- in a stalemate) is resupplied at most once every 3 seconds
-- (CTFPlayer::Regenerate), hears Regenerate.Touch alone, and the locker prop
-- opens, then closes a second before the next use.
ENT.Type = "brush"
ENT.Base = "wetsand_brush_volume"

local NEXT_USE_TIME = 3.0
local SOUND = "Regenerate.Touch"

function ENT:VolumeInit()
	self.associatedModel = self:Key("associatedmodel")
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if not self.enabled then return true end
	local now, state, winner = CurTime(), WETSAND.State(), GetGlobal2Int("wetsand_round_winner", WETSAND.TEAM_UNASSIGNED)
	for _, ply in ipairs(WETSAND.PlayersInside(self)) do
		if now >= (ply.wetsandNextRegen or 0) and WETSAND.TeamRules.RegenerateAllowed(self.team, ply:Team(), state, winner) then
			self:Regenerate(ply)
		end
	end
	return true
end

-- CRegenerateZone::Regenerate
function ENT:Regenerate(ply)
	WETSAND.RegeneratePlayer(ply)
	ply.wetsandNextRegen = CurTime() + NEXT_USE_TIME
	WETSAND.PlaySoundTo(ply, ply, SOUND)
	local prop = WETSAND.FindByName(self.associatedModel)
	if IsValid(prop) then
		prop:Fire("SetAnimation", "open")
		prop:Fire("SetAnimation", "close", NEXT_USE_TIME - 1.0)
	end
end
