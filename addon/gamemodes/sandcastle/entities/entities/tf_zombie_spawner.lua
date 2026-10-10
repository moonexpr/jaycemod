-- tf_zombie_spawner (CZombieSpawner): a binding from its keyvalues and
-- inputs to a foundation.npc.spawner model the npc controller owns and
-- thinks. The controller spawns tf_zombie at this spawner's origin with no
-- owner. Keyvalues TeamNum, zombie_lifetime, max_zombies, infinite_zombies,
-- zombie_type (read by foundation.npc.zombie's SpawnerConfig). Inputs
-- Enable, Disable, SetMaxActiveZombies; Kill is the engine's.
ENT.Type = "point"
ENT.Base = "base_point"

-- FIELD_INTEGER inputs read as atoi does: a non-number is 0.
local ATOI_FALLBACK = 0

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Initialize()
	local Zombie = WS.require("foundation.npc.zombie")
	self.spawner = WS.Feature("npc"):BindSpawner(self, Zombie.SpawnerConfig(self.kv or {}))
end

local INPUTS = {
	enable = function(self)
		self.spawner:Enable(CurTime())
	end,
	disable = function(self)
		self.spawner:Disable()
	end,
	setmaxactivezombies = function(self, value)
		self.spawner:SetMaxActive(math.floor(tonumber(value) or ATOI_FALLBACK))
	end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
