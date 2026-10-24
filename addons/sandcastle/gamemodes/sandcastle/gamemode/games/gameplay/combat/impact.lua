-- Impact damage: a combatant a projectile's knockback throws (the
-- crossbow's punch, an explosion's blast, games.gameplay.combat.weapon_balance)
-- is hurt by the wall or ceiling it strikes within WINDOW of the throw, by
-- its speed into the surface, dealt by whoever threw it. Floors are left to
-- fall damage. Nobody is hurt by throwing themselves or a teammate. Every
-- strike sounds, soft or hard as it hurts (Sounds). The
-- controller (ws/sv_hits.lua) watches the thrown and traces what they hit.
local Geometry = math.geometry
local math = math
module(...)

WINDOW = 1.5 -- seconds after a throw that a strike counts
MIN_SPEED = 600 -- units/s into the surface that hurt nothing
DAMAGE_PER_SPEED = 0.06 -- damage for each unit/s past MIN_SPEED
MAX_DAMAGE = 60
WALL_NORMAL_Z = 0.7 -- a surface whose normal rises more is a floor
STOP_FRACTION = 0.5 -- a throw whose speed falls to this in a tick has struck something

-- Whether a throw by attackerTeam of victimTeam (selfHarm: one's own) can
-- hurt: only an enemy's.
function Harms(attackerTeam, victimTeam, selfHarm)
	return not selfHarm and attackerTeam ~= victimTeam
end

-- Whether a throw moving at before, then at after a tick later, was
-- stopped by something.
function Stopped(before, after)
	return before > 0 and after <= before * STOP_FRACTION
end

-- Whether a surface whose normal rises normalZ is struck: a wall or a
-- ceiling, not a floor.
function Struck(normalZ)
	return normalZ < WALL_NORMAL_Z
end

-- The speed of velocity into a surface of normal ({ x, y, z }): none when
-- moving off it.
function Into(velocity, normal)
	return math.max(0, -Geometry.Dot(velocity, normal))
end

-- The damage of striking a surface at speed into it.
function Damage(speed)
	return math.min(MAX_DAMAGE, math.max(0, speed - MIN_SPEED) * DAMAGE_PER_SPEED)
end

-- HL2's body impacts (physics/body/body_medium_impact_*), each strike one at
-- random (the caller draws it): a strike too slow to hurt thuds soft.
local function Variants(kind, count)
	local paths = {}
	for i = 1, count do paths[i] = "physics/body/body_medium_impact_" .. kind .. i .. ".wav" end
	return paths
end

SOFT_SOUNDS = Variants("soft", 7)
HARD_SOUNDS = Variants("hard", 6)

-- The sounds a strike dealing damage plays from.
function Sounds(damage)
	return damage > 0 and HARD_SOUNDS or SOFT_SOUNDS
end
