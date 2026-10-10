-- tf_logic_cp_timer (CCPTimerLogic, tf_gamerules.cpp): a countdown that
-- starts once team_number may capture the controlpoint, holds the round
-- timer meanwhile, and ends when it has run out and nobody is capping
-- (cp_degrootkeep's keep). A binding to the capture controller, which
-- finds the point at each RoundSpawn, shows the countdown under the point
-- and fires OnCountdownStart and OnCountdownEnd here.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	self.wsKv = self.wsKv or {}
	self.wsKv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	self.capture = WS.Feature("capture")
	self.capture:BindPointTimer(self, self.wsKv or {})
end

function ENT:OnRemove()
	self.capture:UnbindPointTimer(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Think()
	self:NextThink(self.capture:PointTimerThink(self))
	return true
end

function ENT:AcceptInput(name, activator, caller, value)
	return self.capture:PointTimerInput(self, string.lower(name))
end
