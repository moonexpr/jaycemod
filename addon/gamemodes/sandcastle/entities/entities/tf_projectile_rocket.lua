-- tf_projectile_rocket (CTFProjectile_Rocket): a rocket, a wetsand_projectile
-- bound to foundation.projectile.rocket. It flies straight from where it is
-- spawned and blows up on the first thing it touches, through the combat
-- controller's Explode.
--
-- Configure{ damage, crit, team, attacker, launcher, velocity, model,
-- radius, sound } before Spawn: attacker is who the blast credits, launcher
-- the entity that fired it (never hit by it); model defaults to the TF2
-- rocket's, radius to TF_ROCKET_RADIUS; sound plays at launch. MONOCULUS
-- fires these (eyeball_projectile.mdl, crit unless a spell's).
AddCSLuaFile()

ENT.Base = "wetsand_projectile"
ENT.Type = "anim"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.rocket"

if CLIENT then return end

local Base = baseclass.Get("wetsand_projectile")

local PARTICLE_FILES = {
	"particles/rockettrail.pcf",
	"particles/explosion.pcf",
	"particles/eyeboss.pcf",
}
local EXPLOSION_WALL = "ExplosionCore_Wall"
local EXPLOSION_MIDAIR = "ExplosionCore_MidAir"
local EXPLOSION_SOUND = "BaseExplosionEffect.Sound"
local PULL_OUT = 1 -- CTFBaseRocket::Explode moves the blast off the surface

function ENT:Initialize()
	local Rocket = WETSAND.require(self.Variant)
	local config = self:Config()
	config.model = config.model or Rocket.MODEL
	for _, pcf in ipairs(PARTICLE_FILES) do game.AddParticles(pcf) end
	Base.Initialize(self)
	if IsValid(config.launcher) then self:SetOwner(config.launcher) end
	self:SetAngles(config.velocity:Angle())
	if config.sound then self:EmitSound(config.sound) end
	for _, trail in ipairs(Rocket.Trails(self.projectile.state)) do
		ParticleEffectAttach(trail, PATTACH_ABSORIGIN_FOLLOW, self, 0)
	end
end

-- CTFBaseRocket::Explode: the thing it hit takes the full damage.
function ENT:Detonate(trace)
	local Rocket = WETSAND.require(self.Variant)
	local origin = self:GetPos()
	if trace.Hit then origin = trace.HitPos + trace.HitNormal * PULL_OUT end
	local blast = Rocket.Blast(self.projectile.state, origin)
	blast.inflictor = self
	if IsValid(trace.Entity) then blast.enemy = trace.Entity end
	ParticleEffect(trace.HitWorld and EXPLOSION_WALL or EXPLOSION_MIDAIR, origin, angle_zero)
	self:EmitSound(EXPLOSION_SOUND)
	WETSAND.Feature("combat"):Explode(blast)
	self:Remove()
end
