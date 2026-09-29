-- tf_projectile_spellspawnzombie (CreateSpellSpawnZombie and
-- CTFProjectile_SpellSpawnZombie): a skull grenade that hatches a skeleton
-- where it lands. A wetsand_projectile on the timed grenade model; it never
-- detonates on touch. foundation.npc.zombie holds its throw and what it
-- hatches.
--
-- Config, given with Configure before Spawn: { thrower, team, skeletonType }.
-- A skeleton breaking throws MINIs; the skeleton horde spell throws NORMALs.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "wetsand_projectile"
ENT.Spawnable = false
ENT.Variant = "foundation.projectile.grenade"

if CLIENT then return end

local Base = baseclass.Get("wetsand_projectile")

-- InitialExplodeEffects pulls the skeleton this far out of the surface.
local HATCH_LIFT = 2
local GOOP_FILE = "particles/halloween.pcf"
local particlesReady = false -- the file added and the goops precached, once per map

-- The server adds the file and precaches every team's goop, which the skull
-- sends when it hatches; clients add it in the npc feature
-- (features/npc/sh.lua), which the hatched skeleton loads.
local function ReadyParticles(Zombie)
	if particlesReady then return end
	particlesReady = true
	game.AddParticles(GOOP_FILE)
	for _, name in ipairs({ Zombie.GOOP_HALLOWEEN, Zombie.GOOP_RED, Zombie.GOOP_BLUE }) do
		PrecacheParticleSystem(name)
	end
end

function ENT:Configure(skull)
	self.skull = skull
end

function ENT:Initialize()
	self.zombie = WETSAND.require("foundation.npc.zombie")
	ReadyParticles(self.zombie)
	local throw = self.zombie.SkullThrow(math.Rand, Vector)
	self:SetPos(self:GetPos() + throw.offset)
	self:SetAngles(AngleRand())
	if IsValid(self.skull.thrower) then self:SetOwner(self.skull.thrower) end
	Base.Configure(self, {
		model = throw.model,
		velocity = throw.velocity,
		spin = Angle(throw.spin.x, throw.spin.y, throw.spin.z),
		fuse = throw.fuse,
		explodeOnTouch = throw.explodeOnTouch,
	})
	Base.Initialize(self)
end

function ENT:GetTeamNumber()
	return self.skull.team
end

-- The thrower may be gone by now (a broken skeleton is); then, or when it
-- was not a player, the skeleton has no owner.
function ENT:Detonate(trace)
	local Zombie, skull = self.zombie, self.skull
	local thrower = skull.thrower
	local config = Zombie.HatchConfig(skull, IsValid(thrower) and thrower:IsPlayer())
	WETSAND.Feature("npc"):Spawn(Zombie.ZOMBIE_CLASS, config, trace.HitPos + trace.HitNormal * HATCH_LIFT, angle_zero)
	ParticleEffect(Zombie.GoopParticle(skull.team), self:GetPos(), angle_zero)
	self:EmitSound(Zombie.SKULL_SOUND)
	self:Remove()
end
