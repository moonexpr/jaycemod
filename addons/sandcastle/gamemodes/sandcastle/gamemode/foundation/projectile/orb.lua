-- An orb (CTFProjectile_SpellLightningOrb's flight): it flies straight,
-- solid to nothing but the world, which it bounces off (RocketTouch), and
-- ends when its fuse runs out. config { fuse }.
local require = require
local Projectile = require("foundation.projectile")
module(...)

local NONE, DETONATE, BOUNCE = Projectile.NONE, Projectile.DETONATE, Projectile.BOUNCE

GRAVITY = 0

function NewState(config, now)
	return { detonateAt = now + config.fuse }
end

function OnTouch(state, other)
	if other.world then return BOUNCE end
	return NONE
end

function Tick(state, now)
	if now >= state.detonateAt then return DETONATE end
	return NONE
end
