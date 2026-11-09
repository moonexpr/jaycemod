-- func_capturezone (CCaptureZone, func_capture_zone.cpp): where a flag's
-- carrier captures it, CTF's intelligence or MvM's bomb. A binding to the
-- flag controller, which checks its carriers each think. Outputs:
-- OnCapture, OnCapTeam1, OnCapTeam2.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wsKv = self.wsKv or {}
	self.wsKv[k] = value
	if k == "model" then self.brushModel = value end
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetSolid(SOLID_NONE)
	self:SetNoDraw(true)
	local kv = self.wsKv or {}
	self.flag = WS.Feature("flag")
	self.flag:BindZone(self, {
		team = tonumber(kv.teamnum) or WS.TEAM_UNASSIGNED,
		disabled = kv.startdisabled == "1",
	})
end

function ENT:OnRemove()
	self.flag:UnbindZone(self)
end

-- Enable, Disable, SetTeam.
function ENT:AcceptInput(name, activator, caller, value)
	return self.flag:ZoneInput(self, string.lower(name), value)
end
