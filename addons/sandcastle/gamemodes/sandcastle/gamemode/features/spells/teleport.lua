-- Teleport (CTFProjectile_SpellTransposeTeleport): a jar that remembers its
-- last 5 positions, one every 0.05 s. Where it lands, the living caster
-- gains 30 health and moves to the newest spot its hull fits, trying first
-- 50 off the surface it hit, then back along the trail.
local require = require
local Teams = require("games.gameplay.teams")
local Spells = require("features.spells.model")
local SpellSet = require("features.spells.halloween")
local ipairs, remove = ipairs, table.remove
module(...)

INDEX = SpellSet.SPELL_TELEPORT
PROJECTILE = "tf_projectile_spelltransposeteleport"
FLIGHT = SpellSet.JAR_FLIGHT

RADIUS = 5
TRAIL_INTERVAL = 0.05
TRAIL_LENGTH = 5
SURFACE_OFFSET = 50
HEAL = 30
FLASH = "eyeboss_tp_player"
SOUND = "Building_Teleporter.Ready"

USE = {
	kind = Spells.USE_MOBILITY,
	range = SpellSet.THROW_RANGE,
	radius = 0,
	needsLineOfSight = true,
	selfOnly = false,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	return SpellSet.Toss(caster, _M)
end

function NewShot(class, config, now)
	return {
		trail = {},
		nextRecord = now + TRAIL_INTERVAL,
	}
end

-- RecordPosThink
function Tick(caster, state, where, now)
	if now < state.nextRecord then return nil end
	local trail = state.trail
	trail[#trail + 1] = where.position
	if #trail > TRAIL_LENGTH then remove(trail, 1) end
	state.nextRecord = now + TRAIL_INTERVAL
	return nil
end

-- InitialExplodeEffects
local function Initial(caster, impact)
	local owner = caster:Owner()
	if not caster:IsAlive(owner) then return false end
	caster:Heal(owner, HEAL)
	local spots = {}
	for i, spot in ipairs(impact.state.trail) do spots[i] = spot end
	spots[#spots + 1] = impact.hitPosition + impact.normal * SURFACE_OFFSET
	for i = #spots, 1, -1 do
		if caster:Fits(owner, spots[i]) then
			caster:Particle(FLASH, caster:Origin(owner))
			caster:Teleport(owner, spots[i])
			caster:ScreenFade(owner)
			return true
		end
	end
	return false
end

local JAR = {
	radius = RADIUS,
	Initial = Initial,
	particles = {
		[Teams.RED] = FLASH,
		[Teams.BLUE] = FLASH,
	},
	sound = SOUND,
	blast = true,
}

function Impact(caster, impact)
	SpellSet.JarImpact(caster, impact, JAR)
end
