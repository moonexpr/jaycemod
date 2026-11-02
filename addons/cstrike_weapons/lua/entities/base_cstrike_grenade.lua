AddCSLuaFile()

-- base_cstrike_grenade: a thrown CS:S grenade (hegrenade_projectile,
-- flashbang_projectile, smokegrenade_projectile), a physics object that
-- bounces with its own sound and, its fuse spent, Detonates as its kind
-- does. A kind may hold its detonation until it has come to rest
-- (WaitsForRest: the smoke).

ENT.Type = "anim"
ENT.PrintName = "CS:S grenade"
ENT.Spawnable = false
ENT.Model = "models/weapons/w_eq_fraggrenade_thrown.mdl"
ENT.BounceSound = "HEGrenade.Bounce"
ENT.WaitsForRest = false
ENT.CStrikeWeapon = true

local REST = 10 -- units a second: slower is at rest
local BOUNCE_SPEED = 50 -- units a second of impact: slower makes no sound

function ENT:Initialize()
	self:SetModel(self.Model)
	if CLIENT then return end
	if not self.GrenadeFuse then error(self:GetClass() .. " has no CS:S grenade fuse") end
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end
	self.DetonateAt = CurTime() + self.GrenadeFuse
end

function ENT:PhysicsCollide(data)
	if data.Speed > BOUNCE_SPEED then self:EmitSound(self.BounceSound) end
end

function ENT:Think()
	if CLIENT or self.Detonated or CurTime() < self.DetonateAt then return end
	if self.WaitsForRest and self:GetVelocity():Length() > REST then
		self:NextThink(CurTime() + 0.1)
		return true
	end
	self.Detonated = true
	self:Detonate(IsValid(self.Thrower) and self.Thrower or self)
end

function ENT:Detonate(thrower) error(self:GetClass() .. " has no Detonate") end
