-- trigger_capture_area (CTriggerAreaCapture, trigger_area_capture.cpp): the
-- volume players stand in to capture its control point. A binding to the
-- capture controller, which owns its capture (foundation.capture.area),
-- steps it each think and fires its outputs. On payload maps it rides the
-- cart and reports its cappers to the train watcher that claims it.
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
	self.capture = WS.Feature("capture")
	self.capture:BindArea(self, self.wsKv or {})
end

function ENT:OnRemove()
	self.capture:UnbindArea(self)
end

-- The watcher that moves the train this area rides (SetTrainWatcher).
function ENT:SetTrainWatcher(watcher)
	self.capture:SetAreaWatcher(self, watcher)
end

function ENT:IsBlocked()
	return self.capture:AreaBlocked(self)
end

function ENT:IsCapturing()
	return self.capture:AreaCapturing(self)
end

-- CaptureThink
function ENT:Think()
	self:NextThink(CurTime() + self.capture.AREA_THINK_TIME)
	self.capture:AreaThink(self)
	return true
end

function ENT:AcceptInput(name, activator, caller, value)
	return self.capture:AreaInput(self, string.lower(name), value)
end
