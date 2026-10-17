-- info_observer_point: a fixed spectator camera (CObserverPoint, tf_player.cpp).
-- sv_spectate.lua puts observers here in fixed mode, at this point's position
-- and angles, with its fov; a point parented to the cart moves with it.
-- It stays server-only: the observer's own position is the camera.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	self.wsKv = self.wsKv or {}
	self.wsKv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.wsKv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

function ENT:Initialize()
	self.enabled = self:Key("startdisabled", "0") ~= "1"
	self.team = tonumber(self:Key("teamnum", WS.TEAM_UNASSIGNED)) or WS.TEAM_UNASSIGNED
	self.welcome = self:Key("defaultwelcome", "0") == "1"
	self.fov = tonumber(self:Key("fov", 0)) or 0
	-- CObserverPoint::Activate: the match summary camera stays off until the
	-- end-of-match screen, which Sandcastle does not have.
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

function ENT:IsDefaultWelcome()
	return self.welcome
end

function ENT:FOV()
	return self.fov
end

-- The entity named by associated_team_entity (a team_control_point in every
-- installed map), found once it exists.
function ENT:AssociatedEntity()
	local name = self:Key("associated_team_entity")
	if not name then return NULL end
	if not IsValid(self.associated) then self.associated = WS.FindByName(name) end
	return self.associated
end

local INPUTS = {
	enable = function(self) self.enabled = true end,
	disable = function(self) self.enabled = false end,
	setteam = function(self, value) self.team = tonumber(value) or WS.TEAM_UNASSIGNED end,
}

-- Other inputs (SetParent, Kill, ...) fall through to the engine.
function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
