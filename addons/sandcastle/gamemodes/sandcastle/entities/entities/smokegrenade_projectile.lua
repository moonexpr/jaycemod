-- smokegrenade_projectile: CS:S's smoke grenade, thrown. Once its fuse is
-- spent and it has come to rest, it pours a cloud of CS:S's smoke
-- (particle/particle_smokegrenade) its radius wide that stands for its
-- duration (gameplay.cstrike_weapons' GRENADES), then goes. The cloud is each
-- client's own; bot soldiers still see through it.
AddCSLuaFile()

ENT.Base = "base_cstrike_grenade"
ENT.CSSClass = "weapon_smokegrenade"
ENT.Model = "models/weapons/w_eq_smokegrenade_thrown.mdl"
ENT.BounceSound = "SmokeGrenade.Bounce"
ENT.WaitsForRest = true

local PUFFS = 60
local PUFF_SIZE, PUFF_GROWN = 60, 140
local FADE = 3 -- seconds a puff takes to thin out after the cloud's duration

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "SmokedAt")
end

function ENT:Detonate()
	self:EmitSound("BaseSmokeEffect.Sound")
	self:SetSmokedAt(CurTime())
	SafeRemoveEntityDelayed(self, self:Grenade().duration + FADE)
end

if CLIENT then
	local MATERIAL = "particle/particle_smokegrenade"

	function ENT:Think()
		if self.Smoked or self:GetSmokedAt() == 0 then return end
		self.Smoked = true
		local grenade, pos = self:Grenade(), self:GetPos()
		local emitter = ParticleEmitter(pos)
		for _ = 1, PUFFS do
			local p = emitter:Add(MATERIAL, pos + VectorRand() * 8)
			if p then
				local out = VectorRand()
				out.z = math.abs(out.z) * 0.5
				p:SetVelocity(out * grenade.radius * math.Rand(0.5, 1))
				p:SetAirResistance(100)
				p:SetCollide(true)
				p:SetBounce(0.2)
				p:SetDieTime(grenade.duration + math.Rand(0, FADE))
				p:SetStartAlpha(255)
				p:SetEndAlpha(0)
				p:SetStartSize(PUFF_SIZE)
				p:SetEndSize(PUFF_GROWN)
				p:SetRoll(math.Rand(0, 360))
				p:SetRollDelta(math.Rand(-0.2, 0.2))
				local shade = math.random(150, 190)
				p:SetColor(shade, shade, shade)
			end
		end
		emitter:Finish()
	end
end
