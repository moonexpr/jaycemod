-- team_control_point_master (CTeamControlPointMaster,
-- team_control_point_master.cpp): chooses the mini-round to play and
-- declares a round won when one team owns every point in play. A binding to
-- the capture controller, which owns its model (foundation.capture.master)
-- and fires OnWonByTeam1/2.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	self.wsKv = self.wsKv or {}
	self.wsKv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	self.capture = WS.Feature("capture")
	self.capture:BindMaster(self, self.wsKv or {})
end

function ENT:OnRemove()
	self.capture:UnbindMaster(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:AcceptInput(name, activator, caller, value)
	return self.capture:MasterInput(self, string.lower(name), value)
end
