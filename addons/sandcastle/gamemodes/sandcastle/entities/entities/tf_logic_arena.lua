-- tf_logic_arena (CArenaLogic, tf_gamerules.cpp): makes the map arena. A
-- binding to the arena controller, which owns its model
-- (features.arena.round), fires its OnArenaRoundStart as the arena round
-- starts and its OnCapEnabled as the point opens. It has no inputs of its own.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	if string.lower(key) == "capenabledelay" then self.capEnableDelay = tonumber(value) end
end

function ENT:Initialize()
	self.arena = WS.Feature("arena")
	self.arena:BindLogic(self, { capEnableDelay = self.capEnableDelay })
end

function ENT:OnRemove()
	self.arena:UnbindLogic(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end
