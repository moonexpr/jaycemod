-- A jar (CTFProjectile_Jar in pipebomb mode): thrown, it breaks on the world
-- or on an enemy (PipebombTouch, VPhysicsCollision) and when its fuse runs
-- out; anything else it bounces off. config { fuse, armDelay }: for its
-- first armDelay seconds it ignores every touch (the MIRV's pumpkin
-- bomblets, m_flImpactTime).
local require = require
local Projectile = require("foundation.projectile")
module(...)

local NONE, DETONATE, BOUNCE = Projectile.NONE, Projectile.DETONATE, Projectile.BOUNCE

GRAVITY = 1

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
