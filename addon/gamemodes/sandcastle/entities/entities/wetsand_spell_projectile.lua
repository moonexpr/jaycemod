-- wetsand_spell_projectile: the base of the spell projectiles, a
-- wetsand_projectile whose flight is a foundation.projectile variant and
-- whose spell is a Shot of the spells controller. The caster port launches
-- one with SetOwner(caster) and Configure{ spell, position, velocity, team,
-- ... } (its spell's FLIGHT fields and any it adds) before Spawn. While it
-- flies the spells controller ticks its Shot; where it lands the Shot's
-- Impact runs. Teammates do not stop it (CTFGameRules::ShouldCollide).
--
-- A subclass sets ENT.Variant (its flight), ENT.Model and ENT.ModelScale,
-- and ENT.Trails (a particle per team) when it trails one.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_projectile"
ENT.Spawnable = false
ENT.Model = "models/weapons/c_models/urinejar.mdl"
ENT.ModelScale = 1

if CLIENT then return end

local Base = baseclass.Get("wetsand_projectile")

function ENT:Initialize()
	local config = self:Config()
	config.model = self.Model
	self.spells = WETSAND.Feature("spells")
	self.combat = WETSAND.Feature("combat")
	self.spells:BindSpellProjectile(self, config.spell, config)
	Base.Initialize(self)
	self:SetModelScale(self.ModelScale, 0)
	self:SetAngles(config.velocity:Angle())
	if self.CollisionGroup then self:SetCollisionGroup(self.CollisionGroup) end
	if self.Trails then ParticleEffectAttach(self.Trails[config.team], PATTACH_ABSORIGIN_FOLLOW, self, 0) end
end

function ENT:OnRemove()
	self.spells:Unbind(self)
end

function ENT:GetTeamNumber()
	return self:Config().team
end

local function IsCharacter(ent)
	return ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
end

function ENT:IsEnemy(other)
	return IsCharacter(other) and self.combat:TeamOf(other) ~= self:GetTeamNumber()
end

function ENT:Touch(other)
	if IsCharacter(other) and self.combat:TeamOf(other) == self:GetTeamNumber() then return end
	Base.Touch(self, other)
end

function ENT:Think()
	if self.spells:ThinkShot(self) then
		self:Remove()
		return
	end
	return Base.Think(self)
end

function ENT:Detonate(trace)
	self.spells:Impact(self, trace)
	self:Remove()
end
