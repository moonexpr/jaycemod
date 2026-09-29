-- Common base for the TF2 brush volumes: keeps every keyvalue, stores
-- outputs, loads the brush model for its bounds, and tracks Enable/Disable,
-- Toggle and SetTeam. Subclasses add their own inputs through ENT.Inputs.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wetsandKv = self.wetsandKv or {}
	self.wetsandKv[k] = value
	if k == "model" then self.brushModel = value end
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.wetsandKv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

function ENT:Initialize()
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetSolid(SOLID_NONE)
	self:SetNoDraw(true)
	self.enabled = self:Key("startdisabled", "0") ~= "1"
	self.team = tonumber(self:Key("teamnum", WETSAND.TEAM_UNASSIGNED)) or WETSAND.TEAM_UNASSIGNED
	if self.VolumeInit then self:VolumeInit() end
end

-- TeamNum 0 means any team.
function ENT:AllowsTeam(team)
	return self.team == WETSAND.TEAM_UNASSIGNED or self.team == team
end

local BASE_INPUTS = {
	enable = function(self) self.enabled = true end,
	disable = function(self) self.enabled = false end,
	toggle = function(self) self.enabled = not self.enabled end,
	setteam = function(self, value) self.team = tonumber(value) or WETSAND.TEAM_UNASSIGNED end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	local handler = (self.Inputs and self.Inputs[input]) or BASE_INPUTS[input]
	if not handler then return false end
	handler(self, value, activator)
	return true
end