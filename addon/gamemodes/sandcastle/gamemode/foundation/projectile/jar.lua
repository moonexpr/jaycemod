-- A jar (CTFProjectile_Jar in pipebomb mode): thrown, it breaks on the world
-- or on an enemy (PipebombTouch, VPhysicsCollision) and when its fuse runs
-- out; anything else it bounces off. config { fuse, armDelay }: for its
-- first armDelay seconds it ignores every touch (the MIRV's pumpkin
-- bomblets, m_flImpactTime). A Jarate jar (tf_projectile_jar) breaks into
-- a splash: Drenches says who it soaks (JarExplode).
local require = require
local Projectile = require("foundation.projectile")
module(...)

local NONE, DETONATE, BOUNCE = Projectile.NONE, Projectile.DETONATE, Projectile.BOUNCE

GRAVITY = 1

MODEL = "models/weapons/c_models/urinejar.mdl" -- TF_WEAPON_PEEJAR_MODEL
IMPACT_PARTICLE = "peejar_impact"
EXPLODE_SOUND = "Jar.Explode" -- TF_WEAPON_PEEJAR_EXPLODE_SOUND
RADIUS = 200 -- JAR_EXPLODE_RADIUS
URINE_TIME = 10

-- JarExplode: a player near the splash is soaked unless dead, out of
-- reach, behind the world, of the jar's team, ubered, phased or in water
-- (CanGetWet). near = { team, alive, distance, wallBetween, invulnerable,
-- phased, wet }. A jar with no thrower (the Wheel of Fate's) is nobody's
-- team, so it soaks everyone.
function Drenches(near, jarTeam)
	if not near.alive or near.distance > RADIUS or near.wallBetween then return false end
	if near.team == jarTeam then return false end
	return not (near.invulnerable or near.phased or near.wet)
end

function NewState(config, now)
	return {
		detonateAt = now + config.fuse,
		armedAt = now + config.armDelay,
		armed = config.armDelay <= 0,
	}
end

function OnTouch(state, other)
	if state.armed and (other.world or other.enemy) then return DETONATE end
	return BOUNCE
end

function Tick(state, now)
	state.armed = now >= state.armedAt
	if now >= state.detonateAt then return DETONATE end
	return NONE
end
