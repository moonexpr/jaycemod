-- A grenade launcher pipe (CTFGrenadePipebombProjectile, regular mode): a
-- timed grenade (foundation.projectile.grenade) whose blast is
-- CTFWeaponBaseGrenadeProj::Explode's, with no half falloff. tf_point_weapon_mimic
-- fires these.
--
-- Config: the grenade's { fuse, explodeOnTouch } plus { damage, crit, team,
-- attacker, radius } and wetsand_projectile's { model, velocity, spin }.
local require = require
local Grenade = require("foundation.projectile.grenade")
module(...)

GRAVITY = Grenade.GRAVITY
MODEL = "models/weapons/w_models/w_grenade_grenadelauncher.mdl" -- TF_WEAPON_PIPEGRENADE_MODEL

function NewState(config, now)
	local state = Grenade.NewState(config, now)
	state.damage = config.damage
	state.crit = config.crit == true
	state.team = config.team
	state.attacker = config.attacker
	state.radius = config.radius
	return state
end

OnTouch = Grenade.OnTouch
Tick = Grenade.Tick

-- The foundation.combat Explosion config for a blast at origin. The binding
-- adds the inflictor.
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
