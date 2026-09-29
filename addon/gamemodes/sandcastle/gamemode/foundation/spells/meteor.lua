-- Meteor shower (CTFProjectile_SpellMeteorShower and
-- CTFSpell_MeteorShowerSpawner): a jar that lands a spawner. For 4 s,
-- every 0.2 s, the spawner drops 1-2 meteors from 400-500 above a point
-- within 200 (45-60 below a ceiling), falling at 700. A meteor is a
-- fireball that bursts with tendrils; its damage of 50 is never read, as
-- the fireball's burst deals its own.
local require = require
local Teams = require("foundation.teams")
local Spells = require("foundation.spells")
local Tf2 = require("foundation.spells.tf2")
local Fireball = require("foundation.spells.fireball")
module(...)

INDEX = Tf2.SPELL_METEOR
PROJECTILE = "tf_projectile_spellmeteorshower"
FLIGHT = Tf2.JAR_FLIGHT
SPAWNER = "tf_spell_meteorshowerspawner"
METEOR = Fireball.PROJECTILE

SHOWER_TIME = 4
DROP_INTERVAL = 0.2
DROPS_MIN, DROPS_MAX = 1, 2
RANGE = 200
HEIGHT_MIN, HEIGHT_MAX = 400, 500
CEILING_NORMAL_Z = -0.6 -- m_vecImpactNormal.z <= -0.6: a ceiling
CEILING_MIN, CEILING_MAX = 45, 60
DRIFT = 75 -- flRandomAngleOffset
FALL_SPEED = 700
METEOR_DAMAGE = 50
RING = "bomibomicon_ring"
SOUND = "Halloween.spell_meteor_impact"
TENDRILS = {
	[Teams.RED] = "spell_fireball_tendril_parent_red",
	[Teams.BLUE] = "spell_fireball_tendril_parent_blue",
}

function Cast(caster)
	Tf2.CastWheel(caster)
	return Tf2.Toss(caster, _M)
end

function NewShot(class, config, now)
	return {
		class = class,
		normal = config.normal,
		finishAt = now + SHOWER_TIME,
		nextAt = now,
	}
end

-- SpawnMeteor, from a point near the spawner; a spot behind something is
-- pulled back 1 off what the trace hit.
local function Drop(caster, where, low, high, up)
	local range = RANGE
	local onPlane = caster:Vector(caster:RandomFloat(-range, range), caster:RandomFloat(-range, range), 0):GetNormalized()
	local point = where.position + onPlane * caster:RandomFloat(-range, range)
	local emit = point + caster:Vector(0, 0, up) * caster:RandomFloat(low, high)
	local velocity = caster:Vector(caster:RandomFloat(-DRIFT, DRIFT), caster:RandomFloat(-DRIFT, DRIFT), -FALL_SPEED)
	local trace = caster:TraceLine(where.position, emit)
	local spot = trace.endPos
	if trace.hit then spot = trace.endPos + trace.normal end
	caster:LaunchProjectile(METEOR, {
		spell = INDEX,
		position = spot,
		velocity = velocity,
		team = where.team,
		damage = METEOR_DAMAGE,
	})
end

-- MeteorShowerThink; the shower ends early when its caster changes team.
local function Rain(caster, state, where, now)
	if now < state.nextAt then return nil end
	if now >= state.finishAt or caster:TeamOf(caster:Owner()) ~= where.team then return Spells.DONE end
	state.nextAt = now + DROP_INTERVAL
	local low, high, up = HEIGHT_MIN, HEIGHT_MAX, 1
	if state.normal.z <= CEILING_NORMAL_Z then low, high, up = CEILING_MIN, CEILING_MAX, -1 end
	for _ = 1, caster:RandomInt(DROPS_MIN, DROPS_MAX) do Drop(caster, where, low, high, up) end
	return nil
end

-- Only the spawner acts over time.
local TICKS = {
	[SPAWNER] = Rain,
}

function Tick(caster, state, where, now)
	local tick = TICKS[state.class]
	if tick then return tick(caster, state, where, now) end
	return nil
end

-- The shower lands (its own Explode, which needs no thrower); a meteor
-- bursts.
local IMPACTS = {
	[PROJECTILE] = function(caster, impact)
		caster:Particle(RING, impact.position)
		caster:EmitSound(SOUND, impact.projectile)
		caster:Spawn(SPAWNER, {
			spell = INDEX,
			normal = impact.normal,
			team = impact.team,
		}, impact.position)
	end,
	[METEOR] = function(caster, impact)
		Fireball.Burst(caster, impact, TENDRILS[impact.team])
	end,
}

function Impact(caster, impact)
	IMPACTS[impact.class](caster, impact)
end
