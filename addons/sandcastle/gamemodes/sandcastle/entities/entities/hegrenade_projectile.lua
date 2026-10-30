-- hegrenade_projectile: CS:S's HE grenade, thrown. It blasts its damage at
-- its centre, falling to none at its radius (gameplay.css_weapons'
-- GRENADES), credited to its thrower; the balance leaves the blast as it is
-- (weapon_balance's INFLICTORS).
AddCSLuaFile()

ENT.Base = "base_css_grenade"
ENT.CSSClass = "weapon_hegrenade"
ENT.Model = "models/weapons/w_eq_fraggrenade_thrown.mdl"
ENT.BounceSound = "HEGrenade.Bounce"

function ENT:Detonate(thrower)
	local grenade, pos = self:Grenade(), self:GetPos()
	local effect = EffectData()
	effect:SetOrigin(pos)
	util.Effect("Explosion", effect, true, true)
	self:EmitSound("BaseGrenade.Explode")
	util.BlastDamage(self, thrower, pos, grenade.radius, grenade.damage)
	self:Remove()
end
