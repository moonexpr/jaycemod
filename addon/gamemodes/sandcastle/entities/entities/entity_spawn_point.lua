-- entity_spawn_point (CEntitySpawnPoint): a spot an entity_spawn_manager
-- fills. When its entity is removed, the spot is free again after 10s and
-- the manager tries to refill it after its respawn_time, then every 5s.
ENT.Type = "point"
ENT.Base = "base_point"

local NODE_FREE_DELAY = 10
local RETRY_INTERVAL = 5

function ENT:KeyValue(key, value)
	if string.lower(key) == "spawn_manager_name" then self.managerName = value end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:IsUsed()
	return IsValid(self.spawned)
end

function ENT:SetSpawned(ent, manager)
	self.spawned = ent
	ent:CallOnRemove("wetsand_spawn_point", function()
		if not IsValid(self) or not IsValid(manager) then return end
		self.nodeFree = CurTime() + NODE_FREE_DELAY
		self:RetryAfter(manager, manager.respawnTime)
	end)
end

-- CEntitySpawnPoint::RespawnNotifyThink
function ENT:RetryAfter(manager, delay)
	timer.Simple(delay, function()
		if not IsValid(self) or not IsValid(manager) then return end
		if CurTime() > self.nodeFree and manager:SpawnEntity() then return end
		self:RetryAfter(manager, RETRY_INTERVAL)
	end)
end
