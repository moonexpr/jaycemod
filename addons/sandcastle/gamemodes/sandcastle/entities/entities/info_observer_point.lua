-- A fixed spectator camera. The observer uses this point's position, angles
-- and field of view; parenting lets the camera follow a moving map entity.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	self.wsKv = self.wsKv or {}
	self.wsKv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local value = (self.wsKv or {})[name]
	if value == nil or value == "" then return default end
	return value
end

function ENT:Initialize()
	self.enabled = self:Key("startdisabled", "0") ~= "1"
	self.team = tonumber(self:Key("teamnum", TF_TEAM_UNASSIGNED)) or TF_TEAM_UNASSIGNED
	self.fov = tonumber(self:Key("fov", 0)) or 0
	if self:Key("match_summary", "0") == "1" then self.enabled = false end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:IsEnabled()
	return self.enabled
end

function ENT:TeamNum()
	return self.team
end

function ENT:FOV()
	return self.fov
end

function ENT:AssociatedEntity()
	local name = self:Key("associated_team_entity")
	if not name then return NULL end
	if not IsValid(self.associated) then self.associated = WS.FindByName(name) end
	return self.associated
end

local INPUTS = {
	enable = function(self) self.enabled = true end,
	disable = function(self) self.enabled = false end,
	setteam = function(self, value) self.team = tonumber(value) or TF_TEAM_UNASSIGNED end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
