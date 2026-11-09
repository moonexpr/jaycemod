-- A timed grenade: config { fuse, explodeOnTouch }. It detonates when the
-- fuse runs out; with explodeOnTouch it also detonates on an enemy it hits
-- before its first bounce off the world (CTFGrenadePipebombProjectile::
-- PipebombTouch and VPhysicsCollision). Everything else bounces.
local Projectile = gameplay.projectile
module(...)

local NONE, DETONATE, BOUNCE = Projectile.NONE, Projectile.DETONATE, Projectile.BOUNCE

GRAVITY = 1

function NewState(config, now)
	return {
		detonateAt = now + config.fuse,
		explodeOnTouch = config.explodeOnTouch == true,
		touchedWorld = false,
	}
end

function OnTouch(state, other)
	if other.world then
		state.touchedWorld = true
		return BOUNCE
	end
	if state.explodeOnTouch and not state.touchedWorld and other.enemy then return DETONATE end
	return BOUNCE
end

function Tick(state, now)
	if now >= state.detonateAt then return DETONATE end
	return NONE
end
