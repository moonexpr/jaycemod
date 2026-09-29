-- Common base for the TF2 point entities Sandcastle accepts and ignores
-- (Merasmus, the Halloween minigames). They keep every keyvalue, store
-- their On* outputs so the map's connections resolve, accept the inputs a
-- subclass names in ENT.StubInputs, and fire nothing. The first of each
-- class on a map logs its ENT.StubReason once; with ENT.StubRemoves it then
-- removes itself. Kill and AddOutput stay the engine's.
ENT.Type = "point"
ENT.Base = "base_point"

ENT.StubInputs = {}
ENT.StubReason = "not supported; ignored"
ENT.StubRemoves = false

local MESSAGE = "%s: %s"
local logged = {}

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Initialize()
	local class = self:GetClass()
	if not logged[class] then
		logged[class] = true
		print(string.format(MESSAGE, class, self.StubReason))
	end
	if self.StubRemoves then SafeRemoveEntityDelayed(self, 0) end
end

function ENT:AcceptInput(name, activator, caller, value)
	return self.StubInputs[string.lower(name)] == true
end
