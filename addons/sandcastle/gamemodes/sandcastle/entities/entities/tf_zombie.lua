-- tf_zombie (CZombie): TF2's skeleton, a ws_combat_nextbot bound to
-- foundation.npc.zombie, which holds every rule.
--
-- Config, given with Configure before Spawn by its spawner or skull
-- grenade: { team, lifetime, owner, skeletonType }. One the map places has
-- none; its TeamNum and modelscale keyvalues are read (health and
-- max_health are overwritten, as in TF2). Output OnDeath. Only the engine's
-- own inputs (Kill) work, as in TF2: there is no AcceptInput, so anything
-- else (precipice sends Enable) is refused.
AddCSLuaFile()

ENT.Base = "ws_combat_nextbot"
ENT.Type = "nextbot"
ENT.Spawnable = false
ENT.Variant = "foundation.npc.zombie"

if CLIENT then return end

local Base = baseclass.Get("ws_combat_nextbot")

local MAX_ACTIVE_NAME = "tf_max_active_zombie"
local MAX_ACTIVE_HELP = "Skeletons over this many make the oldest (except kings) suicide"
local maxActive = nil -- the convar, created by the first skeleton

local function MaxActive(Zombie)
	maxActive = maxActive or CreateConVar(MAX_ACTIVE_NAME, tostring(Zombie.MAX_ACTIVE_DEFAULT), FCVAR_CHEAT, MAX_ACTIVE_HELP)
	return maxActive:GetInt()
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	Base.KeyValue(self, key, value)
end

-- The model and owner come before the model binds, since its NewState
-- dresses the model and reads the owner; the team the model settles on
-- (HALLOWEEN for any but RED or BLU) is then the entity's.
function ENT:Initialize()
	local Zombie = WS.require(self.Variant)
	local config = Zombie.BindingConfig(self.configured, self.kv or {}, MaxActive(Zombie))
	self:Configure(config)
	self:SetModel(Zombie.Model(config.skeletonType))
	self:PrecacheGibs()
	if config.owner then self:SetOwner(config.owner) end
	Base.Initialize(self)
	self.team = self.npc:State().team
	local scale = self:GetModelScale()
	local mins, maxs = Zombie.HULL_MINS, Zombie.HULL_MAXS
	self:SetCollisionBounds(Vector(mins[1], mins[2], mins[3]) * scale, Vector(maxs[1], maxs[2], maxs[3]) * scale)
end

-- The model asks whether its killer was a player or NPC (TF2's
-- CBaseCombatCharacter).
function ENT:DamageEvent(dmg)
	local event = Base.DamageEvent(self, dmg)
	local attacker = event.attacker
	event.attackerIsCharacter = IsValid(attacker) and (attacker:IsPlayer() or attacker:IsNPC() or attacker:IsNextBot())
	return event
end

-- CZombie::UpdateOnRemove: however it goes, it breaks into gibs (the crown
-- goes with it, through DeleteOnRemove).
function ENT:OnRemove()
	self:GibBreakClient(vector_origin)
	Base.OnRemove(self)
end
