-- A rocket (CTFBaseRocket, CTFProjectile_Rocket): it flies straight and
-- blows up on the first thing it touches (RocketTouch), hurting everything
-- within TF_ROCKET_RADIUS by foundation.combat's rules.
--
-- Config: { damage, crit, team, attacker, radius } plus wetsand_projectile's
-- { model, velocity }. attacker is who the blast credits (TF2's scorer: the
-- launcher's owner, or the launcher); radius is optional, for launchers
-- with their own (tf_point_weapon_mimic's SplashRadius).
local require = require
local Projectile = require("foundation.projectile")
local Teams = require("foundation.teams")
module(...)

GRAVITY = 0
ROCKET_RADIUS = 146 -- TF_ROCKET_RADIUS
MODEL = "models/weapons/w_models/w_rocket.mdl"

-- C_TFProjectile_Rocket::CreateTrails
TRAIL = "rockettrail"
local CRIT_TRAILS = {
	[Teams.RED] = "critical_rocket_red",
	[Teams.BLUE] = "critical_rocket_blue",
}
local CRIT_TRAIL_OTHER = "eyeboss_projectile"

function NewState(config, now)
	return {
		damage = config.damage,
		crit = config.crit == true,
		team = config.team,
		attacker = config.attacker,
		radius = config.radius or ROCKET_RADIUS,
	}
end

function OnTouch(state, other)
	return Projectile.DETONATE
end

function Tick(state, now)
	return Projectile.NONE
end

-- CTFBaseRocket::Explode: the foundation.combat Explosion config for a blast
-- at origin. The binding adds the inflictor and the entity hit directly.
function Blast(state, origin)
	return {
		origin = origin,
		radius = state.radius,
		damage = state.damage,
		attackerTeam = state.team,
		attacker = state.attacker,
		halfFalloff = false,
		forceFriendlyFire = false,
		crit = state.crit,
	}
end

-- The particle trails the rocket carries.
function Trails(state)
	local trails = { TRAIL }
	if state.crit then trails[#trails + 1] = CRIT_TRAILS[state.team] or CRIT_TRAIL_OTHER end
	return trails
end
