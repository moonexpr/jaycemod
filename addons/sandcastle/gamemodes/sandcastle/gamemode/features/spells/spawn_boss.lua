-- Spawn boss (CTFProjectile_SpellSpawnBoss): a jar that summons a MONOCULUS
-- of the caster's team, owned by the caster (a spell eyeball: immune, gone
-- after 8 s). It tries a hull straight above where it hit and at the four
-- corners, each swept up to the hover height; the eyeball appears where the
-- first free sweep stops. With no room the caster gets the spell back.
local require = require
local Teams = require("games.gameplay.teams")
local Spells = require("features.spells.model")
local SpellSet = require("features.spells.halloween")
local HalloweenBoss = require("foundation.npc.halloween_boss")
local EyeballBoss = require("foundation.npc.eyeball_boss")
local ipairs = ipairs
module(...)

INDEX = SpellSet.SPELL_SPAWN_BOSS
PROJECTILE = "tf_projectile_spellspawnboss"
FLIGHT = SpellSet.JAR_FLIGHT

RADIUS = 1
SURFACE_OFFSET = 30
BLOAT = 5
PARTICLE = "eyeboss_death"
SOUND = "Halloween.spell_spawn_boss"

-- vTest: the corners, in half widths, at the boss's height.
local CORNERS = {
	{ 0, 0 },
	{ 1, 1 },
	{ -1, -1 },
	{ 1, -1 },
	{ -1, 1 },
}

USE = {
	kind = Spells.USE_SUMMON,
	range = SpellSet.THROW_RANGE,
	radius = 0,
	needsLineOfSight = true,
	selfOnly = false,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	return SpellSet.Toss(caster, _M)
end

local function Summon(caster, impact)
	local owner = caster:Owner()
	local contact = impact.hitPosition
	local vector = function(x, y, z) return caster:Vector(x, y, z) end
	local class, config = HalloweenBoss.SpawnAt(HalloweenBoss.BOSS_MONOCULUS, contact, caster:TeamOf(owner), owner, vector)
	local half = EyeballBoss.HULL_HALF_WIDTH
	local height = 2 * half
	local mins = caster:Vector(-half - BLOAT, -half - BLOAT, -half)
	local maxs = caster:Vector(half + BLOAT, half + BLOAT, half + BLOAT)
	local sweep = caster:Vector(0, 0, EyeballBoss.HOVER.hoverHeight)
	for _, corner in ipairs(CORNERS) do
		local start = contact + caster:Vector(corner[1] * half, corner[2] * half, height) + impact.normal * SURFACE_OFFSET
		local trace = caster:TraceHull(start, start + sweep, mins, maxs)
		if not trace.startSolid then
			caster:SpawnNPC(class, config, trace.endPos)
			return true
		end
	end
	return false
end

local JAR = {
	radius = RADIUS,
	Initial = Summon,
	particles = {
		[Teams.RED] = PARTICLE,
		[Teams.BLUE] = PARTICLE,
	},
	sound = SOUND,
	blast = true,
}

function Impact(caster, impact)
	if SpellSet.JarImpact(caster, impact, JAR) then return nil end
	return Spells.REFUND
end
