-- entity_spawn_manager (CEntitySpawnManager): keeps up to entity_count
-- entities of class entity_name at random free entity_spawn_points naming
-- it. Payload maps use it for tf_pumpkin_bomb, which GMod does not have;
-- a class GMod cannot create simply spawns nothing.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "entity_name" then
		self.entityName = value
	elseif k == "entity_count" then
		self.entityCount = tonumber(value) or 0
	elseif k == "respawn_time" then
		self.respawnTime = tonumber(value) or 0
	elseif k == "drop_to_ground" then
		self.dropToGround = value == "1"
	elseif k == "random_rotation" then
		self.randomRotation = value == "1"
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Initialize()
	self.entityCount = self.entityCount or 0
	self.respawnTime = self.respawnTime or 0
	-- CEntitySpawnManager::Activate runs once every map entity exists.
	timer.Simple(0, function()
		if IsValid(self) then self:SpawnAllEntities() end
	end)
end

function ENT:Points()
	local points = {}
	for _, p in ipairs(ents.FindByClass("entity_spawn_point")) do
		if p.managerName == self:GetName() then points[#points + 1] = p end
	end
	return points
end

-- CEntitySpawnManager::SpawnAllEntities
function ENT:SpawnAllEntities()
	if not self.entityName or self.entityName == "" then return end
	local used, points = 0, self:Points()
	for _, p in ipairs(points) do
		if p:IsUsed() then used = used + 1 end
	end
	for _ = 1, math.min(#points, self.entityCount) - used do self:SpawnEntity() end
end

-- CEntitySpawnManager::GetRandomUnusedIndex
function ENT:RandomUnusedPoint()
	local points = self:Points()
	if #points == 0 then return nil end
	local start = math.random(#points)
	for i = 0, #points - 1 do
		local p = points[(start + i - 1) % #points + 1]
		if not p:IsUsed() then return p end
	end
	return nil
end

-- CEntitySpawnManager::SpawnEntityAt
function ENT:SpawnEntity()
	local point = self:RandomUnusedPoint()
	if not point then return false end
	local ent = ents.Create(self.entityName)
	if not IsValid(ent) then return false end
	local origin = point:GetPos()
	if self.dropToGround then
		origin = util.TraceLine({ start = origin, endpos = origin - Vector(0, 0, 500), mask = MASK_SOLID, filter = ent }).HitPos
	end
	ent:SetPos(origin)
	ent:Spawn()
	if self.randomRotation then
		ent:SetAngles(Angle(0, math.Rand(0, 360), 0))
	else
		ent:SetAngles(point:GetAngles())
	end
	point:SetSpawned(ent, self)
	return true
end
