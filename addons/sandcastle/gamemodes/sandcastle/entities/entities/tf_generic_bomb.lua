-- tf_generic_bomb (CTFGenericBomb): a binding to a
-- features.hazards.generic_bomb model through the hazards controller.
-- Keyvalues damage, radius, health, explode_particle, sound, friendlyfire
-- and passActivator, plus model, skin, modelscale and TeamNum; input
-- Detonate; output OnDetonate.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local VARIANT = "features.hazards.generic_bomb"

-- Keyvalues read as atof and atoi do: a non-number is 0. A missing
-- modelscale is the engine's 1.
local ATOF_FALLBACK = 0
local DEFAULT_SCALE = 1

local function Float(value)
	return tonumber(value) or ATOF_FALLBACK
end

local function Int(value)
	local n = Float(value)
	if n < 0 then return math.ceil(n) end
	return math.floor(n)
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	local kv = self.kv or {}
	self.hazards = WS.Feature("hazards")
	self.hazard = self.hazards:Bind(self, VARIANT, {
		damage = Float(kv.damage),
		radius = Float(kv.radius),
		health = Int(kv.health),
		explodeParticle = kv.explode_particle,
		sound = kv.sound,
		friendlyFire = Int(kv.friendlyfire),
		passActivator = Int(kv.passactivator) ~= 0,
		team = Int(kv.teamnum),
		model = kv.model,
		skin = Int(kv.skin),
		scale = tonumber(kv.modelscale) or DEFAULT_SCALE,
	})
	-- CTFGenericBomb::Precache
	if kv.explode_particle and kv.explode_particle ~= "" then PrecacheParticleSystem(kv.explode_particle) end
end

function ENT:OnRemove()
	self.hazards:Unbind(self)
end

-- The team the combat controller sees: TeamNum's.
function ENT:GetTeamNumber()
	return self.hazard:Team()
end

function ENT:OnTakeDamage(dmg)
	self.hazards:Damaged(self, dmg)
end

function ENT:Touch(other)
	self.hazards:Touched(self, other)
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if not self.hazard:Accepts(input) then return false end
	self.hazards:Input(self, input, value)
	return true
end
