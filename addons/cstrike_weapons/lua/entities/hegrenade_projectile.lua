AddCSLuaFile()

-- hegrenade_projectile: CS:S's HE grenade, thrown. It blasts its damage at
-- its centre, falling to none at its radius, credited to its thrower.

ENT.Base = "base_cstrike_grenade"
ENT.Model = "models/weapons/w_eq_fraggrenade_thrown.mdl"
ENT.BounceSound = "HEGrenade.Bounce"

function ENT:Detonate(thrower)
	local pos = self:GetPos()
	local effect = EffectData()
	effect:SetOrigin(pos)
	effect:SetScale(self.GrenadeRadius)
	util.Effect("cstrike_explosion", effect, true, true)
	self:EmitSound("BaseGrenade.Explode")
	util.BlastDamage(self, thrower, pos, self.GrenadeRadius, self.GrenadeDamage)
	self:Remove()
end
