-- What a crit looks like as it flies, as TF2 shows it: a crit bullet's
-- tracer (CTFWeaponBase::GetTracerType, with FireBullet's _crit for a
-- DMG_CRITICAL shot) and a crit projectile's trail (C_TFProjectile_Rocket's
-- and C_TFProjectile_Arrow's critical_rocket_*, a grenade's
-- critical_grenade_*), each in its shooter's team's colour: RED's for RED,
-- BLU's for anyone else, as GetTracerType picks. The controller
-- (ws/sv_hits.lua, ws/sh_crit_effects.lua) draws them.
local Teams = require("games.gameplay.teams")
local ipairs, pairs = ipairs, pairs
module(...)

-- The particle files the effects play from.
FILES = { "particles/bullet_tracers.pcf", "particles/rockettrail.pcf", "particles/stickybomb.pcf" }

local TRACER = "bullet_tracer01" -- tf_weapon_shotgun's, the scattergun's and the pistols' TracerEffect

-- By the projectile's class: the trail's name without its team.
TRAILS = {
	rpg_missile = "critical_rocket",
	crossbow_bolt = "critical_rocket",
	npc_grenade_frag = "critical_grenade",
}

local function Colour(team)
	return team == Teams.RED and "red" or "blue"
end

-- A crit bullet's tracer for team.
function Tracer(team)
	return TRACER .. "_" .. Colour(team) .. "_crit"
end

-- A crit projectile's trail for its class and team, or nil for a class
-- with none.
function Trail(class, team)
	local trail = TRAILS[class]
	if not trail then return nil end
	return trail .. "_" .. Colour(team)
end

-- Every particle the effects play, each once.
PARTICLES = {}
do
	local seen = {}
	local function Add(name)
		if seen[name] then return end
		seen[name] = true
		PARTICLES[#PARTICLES + 1] = name
	end
	for _, team in ipairs({ Teams.RED, Teams.BLUE }) do
		Add(Tracer(team))
		for class in pairs(TRAILS) do Add(Trail(class, team)) end
	end
end
