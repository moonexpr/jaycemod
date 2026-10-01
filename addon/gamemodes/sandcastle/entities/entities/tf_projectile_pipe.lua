-- tf_projectile_pipe (CTFGrenadePipebombProjectile): a grenade launcher
-- pipe, a wetsand_projectile bound to foundation.projectile.pipe. It arcs,
-- bounces, and blows up when its fuse ends, through the combat controller's
-- Explode. It never collides with players (TFCOLLISION_GROUP_ROCKETS, as
-- tf_point_weapon_mimic sets it).
--
-- Configure{ damage, crit, team, attacker, launcher, radius, velocity, spin
-- (an Angle), fuse, explodeOnTouch, model, skin, scale, particle } before
-- Spawn: attacker is who the blast credits, launcher what fired it; model
-- defaults to the pipe's, particle (the blast's system, which its sender
-- precaches: Merasmus's bombs) to the explosion's.
AddCSLuaFile()

ENT.Base = "wetsand_projectile"
ENT.Type = "anim"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.pipe"

if CLIENT then return end

local Base = baseclass.Get("wetsand_projectile")

local PARTICLE_FILE = "particles/explosion.pcf"
local EXPLOSION_WALL = "ExplosionCore_Wall"
local EXPLOSION_MIDAIR = "ExplosionCore_MidAir"
local EXPLOSION_SOUND = "BaseExplosionEffect.Sound"
local PULL_OUT = 1 -- CTFWeaponBaseGrenadeProj::Explode moves the blast off the surface
local DEFAULT_SKIN, DEFAULT_SCALE = 0, 1

function ENT:Initialize()
	local config = self:Config()
	config.model = config.model or WETSAND.require(self.Variant).MODEL
	game.AddParticles(PARTICLE_FILE)
	Base.Initialize(self)
	if IsValid(config.launcher) then self:SetOwner(config.launcher) end
	self:SetSkin(config.skin or DEFAULT_SKIN)
	self:SetModelScale(config.scale or DEFAULT_SCALE)
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
end

function ENT:Detonate(trace)
	local origin = self:GetPos()
	if trace.Hit then origin = trace.HitPos + trace.HitNormal * PULL_OUT end
	local blast = WETSAND.require(self.Variant).Blast(self.projectile.state, origin)
	blast.inflictor = self
	ParticleEffect(self:Config().particle or (trace.Hit and EXPLOSION_WALL or EXPLOSION_MIDAIR), origin, angle_zero)
	self:EmitSound(EXPLOSION_SOUND)
	WETSAND.Feature("combat"):Explode(blast)
	self:Remove()
end
