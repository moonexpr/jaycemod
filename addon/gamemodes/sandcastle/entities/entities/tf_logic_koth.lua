-- tf_logic_koth (CKothLogic, tf_gamerules.cpp): makes the map King of the
-- Hill. A binding to the koth controller, which owns its model
-- (foundation.rounds.koth), makes the two team clocks at every RoundSpawn
-- and locks the points at RoundActivate. It has no outputs.
ENT.Type = "point"
ENT.Base = "base_point"

-- Keyvalue -> the model's field, as a number.
local NUMBER_KEYS = {
	timer_length = "timerLength",
	unlock_point = "unlockPoint",
}

function ENT:KeyValue(key, value)
	self.wetsandKv = self.wetsandKv or {}
	local field = NUMBER_KEYS[string.lower(key)]
	if field then self.wetsandKv[field] = tonumber(value) end
end

function ENT:Initialize()
	self.koth = WETSAND.Feature("koth")
	self.koth:BindLogic(self, self.wetsandKv or {})
end

function ENT:OnRemove()
	self.koth:UnbindLogic(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- RoundSpawn, RoundActivate, SetRedTimer, SetBlueTimer, AddRedTimer, AddBlueTimer.
function ENT:AcceptInput(name, activator, caller, value)
	return self.koth:LogicInput(self, string.lower(name), value)
end
