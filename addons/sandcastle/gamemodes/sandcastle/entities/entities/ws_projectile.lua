-- ws_projectile: the base of every thrown or fired projectile, a thin
-- binding to a games.gameplay.projectile model. A subclass sets
-- ENT.Variant = "games.gameplay.projectile.<variant>" and overrides
-- Detonate(trace), and IsEnemy(other) when it has sides. It knows no teams.
--
-- Config, given with Configure(config) before Spawn: { model, velocity,
-- spin (an Angle) } plus the variant's own fields. The variant's GRAVITY
-- chooses straight flight (0) or ballistic flight with that gravity scale.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local STRAIGHT = 0
-- CTFWeaponBaseGrenadeProj::Detonate traces from 8 above to 24 below.
local DETONATE_TRACE_UP, DETONATE_TRACE_DOWN = 8, 32

function ENT:Configure(config)
	self.configured = config
end

function ENT:Config()
	return self.configured
end

function ENT:Initialize()
	local config = self:Config()
	self.system = gameplay.projectile
	self:SetModel(config.model)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
	self.projectile = WS.Feature("combat"):BindProjectile(self, self.Variant, config)
	local gravity = self.projectile:Gravity()
	if gravity == STRAIGHT then
		self:SetMoveType(MOVETYPE_FLY)
	else
		self:SetMoveType(MOVETYPE_FLYGRAVITY)
		self:SetGravity(gravity)
	end
	self:SetMoveCollide(MOVECOLLIDE_FLY_BOUNCE)
	self:SetVelocity(config.velocity)
	if config.spin then self:SetLocalAngularVelocity(config.spin) end
end

-- Whether touching `other` counts as hitting an enemy. With no sides,
-- nothing does.
function ENT:IsEnemy(other)
	return false
end

-- The model's answer, as engine effects. BOUNCE is the engine's own.
function ENT:Apply(outcome, trace)
	if outcome == self.system.DETONATE then
		self:Detonate(trace)
	elseif outcome == self.system.EXPIRE then
		self:Remove()
	end
end

function ENT:Touch(other)
	if other == self:GetOwner() or not other:IsSolid() then return end
	self:Apply(self.projectile:Touch({
		world = other:IsWorld(),
		enemy = self:IsEnemy(other),
	}), self:GetTouchTrace())
end

function ENT:DetonateTrace()
	local spot = self:GetPos() + Vector(0, 0, DETONATE_TRACE_UP)
	return util.TraceLine({
		start = spot,
		endpos = spot - Vector(0, 0, DETONATE_TRACE_DOWN),
		filter = self,
		mask = MASK_SHOT_HULL,
	})
end

function ENT:Think()
	local outcome = self.projectile:Tick(CurTime())
	self:Apply(outcome, outcome == self.system.DETONATE and self:DetonateTrace())
	self:NextThink(CurTime())
	return true
end

-- Subclasses explode, spawn or splash here.
function ENT:Detonate(trace)
	self:Remove()
end
