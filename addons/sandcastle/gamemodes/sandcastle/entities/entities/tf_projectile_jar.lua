-- tf_projectile_jar (CTFProjectile_Jar): a jar of Jarate, a
-- ws_projectile bound to games.gameplay.projectile.jar. It breaks on the
-- world or a player (PipebombTouch), splashes (peejar_impact, Jar.Explode)
-- and soaks whoever games.gameplay.projectile.jar's Drenches says, for 10 s
-- (JarExplode). The Wheel of Fate's rain drops them, nobody's.
--
-- Configure{ velocity, spin (an Angle), team } before Spawn.
AddCSLuaFile()

ENT.Base = "ws_projectile"
ENT.Type = "anim"
ENT.Spawnable = false
ENT.Variant = "games.gameplay.projectile.jar"

if CLIENT then return end

local Base = baseclass.Get("ws_projectile")

local PARTICLE_FILE = "particles/item_fx.pcf"
local PULL_OUT = 1 -- CTFProjectile_Jar::Explode moves the splash off the surface
local NO_FUSE = math.huge -- a jar breaks only on what it hits
local NO_ARMING = 0
local DRY_WATER_LEVEL = 2 -- waist deep and over, a player cannot get wet (CanGetWet)
-- JarExplode's trace: MASK_SHOT without hitboxes, through players.
local SPLASH_MASK = bit.band(MASK_SHOT, bit.bnot(CONTENTS_HITBOX))

function ENT:Initialize()
	local Jar = WS.require(self.Variant)
	local config = self:Config()
	config.model = Jar.MODEL
	config.fuse = NO_FUSE
	config.armDelay = NO_ARMING
	game.AddParticles(PARTICLE_FILE)
	PrecacheParticleSystem(Jar.IMPACT_PARTICLE)
	Base.Initialize(self)
end

function ENT:IsEnemy(other)
	return other:IsPlayer()
end

-- What the jar's rule needs to know of a player near the splash.
local function Near(ply, origin)
	local wall = util.TraceLine({
		start = origin,
		endpos = ply:GetPos(),
		mask = SPLASH_MASK,
		filter = function(ent) return not ent:IsPlayer() end,
	})
	local Targeting = WS.require("games.npc.targeting")
	return {
		team = ply:Team(),
		alive = ply:Alive(),
		distance = ply:NearestPoint(origin):Distance(origin),
		wallBetween = wall.HitWorld,
		invulnerable = Targeting.IsInvulnerable(function(cond) return WS.InCondition(ply, cond) end),
		phased = WS.InCondition(ply, WS.PlayerRules.COND.PHASE),
		wet = ply:WaterLevel() >= DRY_WATER_LEVEL,
	}
end

function ENT:Detonate(trace)
	local Jar = WS.require(self.Variant)
	local origin = self:GetPos()
	if trace.Hit then origin = trace.HitPos + trace.HitNormal * PULL_OUT end
	ParticleEffect(Jar.IMPACT_PARTICLE, origin, angle_zero)
	EmitSound(Jar.EXPLODE_SOUND, origin, 0)
	local team = self:Config().team
	for _, ent in ipairs(ents.FindInSphere(origin, Jar.RADIUS)) do
		if ent:IsPlayer() and Jar.Drenches(Near(ent, origin), team) then
			WS.AddCondition(ent, WS.PlayerRules.COND.URINE, Jar.URINE_TIME)
		end
	end
	self:Remove()
end
