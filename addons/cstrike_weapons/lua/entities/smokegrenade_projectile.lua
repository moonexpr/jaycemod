AddCSLuaFile()

-- smokegrenade_projectile: CS:S's smoke grenade, thrown. Once its fuse is
-- spent and it has come to rest, it pours a cloud of CS:S's smoke
-- (particle/particle_smokegrenade) for the duration in its weapon stats.
-- The cloud is each client's own; bot soldiers still see through it.

ENT.Base = "base_cstrike_grenade"
ENT.Model = "models/weapons/w_eq_smokegrenade_thrown.mdl"
ENT.BounceSound = "SmokeGrenade.Bounce"
ENT.WaitsForRest = true

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "SmokedAt")
end

function ENT:Detonate()
	self:EmitSound("BaseSmokeEffect.Sound")
	self:SetSmokedAt(CurTime())
	SafeRemoveEntityDelayed(self, self.GrenadeDuration + 3)
end

if CLIENT then
	function ENT:Think()
		if self.Smoked or self:GetSmokedAt() == 0 then return end
		self.Smoked = true
		local effect = EffectData()
		effect:SetOrigin(self:GetPos())
		effect:SetScale(self.GrenadeRadius)
		effect:SetMagnitude(self.GrenadeDuration)
		util.Effect("cstrike_smoke", effect, true, true)
	end
end
