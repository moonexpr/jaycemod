-- team_control_point_round (CTeamControlPointRound,
-- team_control_point_round.cpp): the control points that make up one
-- mini-round, its priority among the rounds, and which team may not win it
-- by capping them all. A binding to the capture controller, whose master
-- chooses the round and fires OnStart, OnEnd and OnWonByTeam1/2 here.
-- Points() and GetName() serve the spawn rules (sv_teams_spawn).
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	self.wsKv = self.wsKv or {}
	self.wsKv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	self.capture = WS.Feature("capture")
	self.capture:BindRound(self, self.wsKv or {})
end

function ENT:OnRemove()
	self.capture:UnbindRound(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Points()
	return self.capture:RoundPoints(self)
end

function ENT:AcceptInput(name, activator, caller, value)
	return self.capture:RoundInput(self, string.lower(name), value)
end
