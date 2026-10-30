-- hostage_entity (CS:S): where the map puts a hostage, and the observer of
-- the entity it spawns there as the hostage: the class cs_logic_hostage
-- names (npc_civilian unless the map says otherwise; a prop_physics would
-- do). It binds to the hostage controller (features/hostage), which loads
-- with it, and answers two things of its hostage: whether it is alive
-- (Lives) and whether it stands in a rescue zone (InRescueZone, a
-- func_hostage_rescue). Everything else the hostage does is its own.
--
-- It spawns its hostage a tick after it is made, once every entity of the
-- map (cs_logic_hostage among them) is; until then it has none (Spawned).
-- It goes with its hostage, and its hostage with it.
ENT.Type = "point"

function ENT:Initialize()
	self.hostage = WS.Feature("hostage")
	self.hostage:Bind(self)
	timer.Simple(0, function()
		if IsValid(self) then self:SpawnBody() end
	end)
end

function ENT:SpawnBody()
	local config = self.hostage:Config()
	local body = ents.Create(config.bodyClass)
	if not IsValid(body) then error("hostage_entity: no entity class " .. config.bodyClass .. " to spawn as its hostage") end
	if config.bodyModel then body:SetModel(config.bodyModel) end
	body:SetPos(self:GetPos())
	body:SetAngles(self:GetAngles())
	body.wsHostageObserver = self
	body:Spawn()
	body:Activate()
	self.body = body
end

-- Whether it has spawned its hostage (which may since have died).
function ENT:Spawned() return self.body ~= nil end

-- Its hostage, or nil before it spawns and once it is gone.
function ENT:Body() return IsValid(self.body) and self.body or nil end

-- Its hostage lives: it is there, and one that lives by its health (an NPC,
-- a NextBot) has some left; anything else (a prop: a breakable one is
-- removed as it breaks) lives until it is removed. Not Alive, which the
-- engine's Entity has and which a scripted entity's own does not shadow.
function ENT:Lives()
	local body = self:Body()
	if not body then return false end
	if body:IsNPC() or body:IsNextBot() then return body:Health() > 0 end
	return true
end

-- Its hostage stands in an enabled func_hostage_rescue.
function ENT:InRescueZone()
	local body = self:Body()
	if not body then return false end
	for _, zone in ipairs(ents.FindByClass("func_hostage_rescue")) do
		if zone:Holds(body) then return true end
	end
	return false
end

function ENT:OnRemove()
	if self.hostage then self.hostage:Unbind(self) end
	SafeRemoveEntity(self.body)
end
