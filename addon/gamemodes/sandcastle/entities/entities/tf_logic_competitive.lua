-- tf_logic_competitive (CCompetitiveLogic, tf_gamerules.cpp): the map's
-- hook for competitive play, which maps wire to their spawn doors. The
-- rounds controller fires OnSpawnRoomDoorsShouldLock as a pre-round starts
-- and OnSpawnRoomDoorsShouldUnlock as it ends (CTFGameRules::PreRound_Start
-- and PreRound_End) and between rounds (BetweenRounds_Start, also a stopped
-- game).
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	WETSAND.Feature("rounds")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end
