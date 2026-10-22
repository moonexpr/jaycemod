-- The combat system: an Explosion decides who a blast hurts and how much
-- (CTFRadiusDamageInfo and CTFGameRules::RadiusDamage). The combat
-- controller finds the entities in the radius, traces the blast to each, and
-- deals what DamageTo answers as DMG_BLAST, adding DMG_ACID for a crit.
--
-- Explosion.New{ origin, radius, damage, attackerTeam, attacker,
-- halfFalloff, forceFriendlyFire, crit }: origin is an engine vector,
-- attacker the entity credited (the controller's business, as are the
-- optional inflictor and enemy, the entity a projectile hit directly).
-- Then per victim:
--   :DistanceTo(center, origin, direct) -> the distance DamageTo takes;
--   :DamageTo{ team, isAttacker, distance, visible } -> amount | nil.
local require = require
local Teams = require("games.gameplay.teams")
local math, setmetatable = math, setmetatable
module(...)

CRIT_MULTIPLIER = 3 -- TF_DAMAGE_CRIT_MULTIPLIER

HALF_FALLOFF = 0.5 -- DMG_HALF_FALLOFF's

Explosion = {}
Explosion.__index = Explosion

function Explosion.New(config)
	return setmetatable({ config = config }, Explosion)
end

-- CTFRadiusDamageInfo::CalculateFalloff: the fraction of the damage left at
-- the edge.
local function Falloff(config)
	if config.halfFalloff then return HALF_FALLOFF end
	return config.damage / config.radius
end

-- CTFRadiusDamageInfo::ApplyToEntity: the nearer of the victim's centre and
-- origin; 0 for the entity a projectile hit directly (its GetEnemy()).
function Explosion:DistanceTo(center, origin, direct)
	if direct then return 0 end
	local from = self.config.origin
	return math.min((from - center):Length(), (from - origin):Length())
end

-- Teammates are spared, except the attacker itself, unless friendly fire is
-- forced; a blast with no team has no teammates.
local function Spared(config, victim)
	if victim.isAttacker or config.forceFriendlyFire then return false end
	return config.attackerTeam ~= Teams.UNASSIGNED and victim.team == config.attackerTeam
end

-- RemapValClamped(distance, 0, radius, damage, damage * falloff), tripled
-- for a crit. Nothing passes through the world, a blast with no radius
-- (CTFGameRules::RadiusDamage) hurts nobody, and neither does one that
-- comes to no damage (CTFRadiusDamageInfo::ApplyToEntity), so a harmless
-- blast sets off no pumpkin.
function Explosion:DamageTo(victim)
	local config = self.config
	if config.radius <= 0 or not victim.visible or Spared(config, victim) then return nil end
	local t = math.min(victim.distance, config.radius) / config.radius
	local amount = config.damage + (config.damage * Falloff(config) - config.damage) * t
	if amount <= 0 then return nil end
	if config.crit then amount = amount * CRIT_MULTIPLIER end
	return amount
end
