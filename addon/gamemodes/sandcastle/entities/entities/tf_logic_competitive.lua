-- tf_logic_competitive (CCompetitiveLogic, tf_gamerules.cpp): the map's
-- hook for competitive play. TF2 fires OnSpawnRoomDoorsShouldUnlock when
-- the game waits between rounds (the tournament ready-up) and when a
-- pre-round ends, and OnSpawnRoomDoorsShouldLock when a pre-round starts;
-- the map wires them to its spawn doors. Sandcastle fires the unlock when
-- the game is stopped for free play (tf_gamerules' Halt), which TF2 plays
-- as that ready-up state.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:SpawnRoomDoorsShouldLock()
	self:TriggerOutput("OnSpawnRoomDoorsShouldLock", self)
end

function ENT:SpawnRoomDoorsShouldUnlock()
	self:TriggerOutput("OnSpawnRoomDoorsShouldUnlock", self)
end
