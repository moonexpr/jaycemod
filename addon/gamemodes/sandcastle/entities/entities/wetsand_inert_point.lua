-- Common base for TF2 point entities with nothing to do in GMod (the TFBot
-- hints): they keep their keyvalues and answer Enable, Disable, Toggle and
-- SetTeam, so the map's I/O to them resolves. Kill stays the engine's.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	self.wetsandKv = self.wetsandKv or {}
	self.wetsandKv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	local kv = self.wetsandKv or {}
	self.enabled = kv.startdisabled ~= "1"
	self.team = tonumber(kv.teamnum) or WETSAND.TEAM_UNASSIGNED
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

local INPUTS = {
	enable = function(self) self.enabled = true end,
	disable = function(self) self.enabled = false end,
	toggle = function(self) self.enabled = not self.enabled end,
	setteam = function(self, value) self.team = tonumber(value) or WETSAND.TEAM_UNASSIGNED end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end