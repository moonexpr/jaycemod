-- How well the AI war's soldiers shoot, by TF2's bot difficulty
-- (tf_bot_difficulty: EASY, NORMAL, HARD, EXPERT). EXPERT is the soldiers as
-- they were: DrGBase's dead-on aim at the enemy's centre, each gun's own
-- spread, and the first shot the moment they have an enemy. Below it a shot
-- turns off its aim by up to aimError degrees (Aim), its gun's spread is
-- scaled by spreadScale (Spread), and a soldier waits reaction seconds
-- before its first shot at a new enemy (TF2's IVision recognize time).
local abs, cos, floor, max, min, pi, rad, sin, sqrt = math.abs, math.cos, math.floor, math.max, math.min, math.pi, math.rad, math.sin, math.sqrt
local Geometry = math.geometry
module(...)

EASY, NORMAL, HARD, EXPERT = 0, 1, 2, 3
-- tf_bot_difficulty's default.
DEFAULT = NORMAL

local LEVELS = {
	[EASY] = { aimError = 10, spreadScale = 3.5, reaction = 1.0 },
	[NORMAL] = { aimError = 6, spreadScale = 2.5, reaction = 0.6 },
	[HARD] = { aimError = 3, spreadScale = 1.6, reaction = 0.3 },
	[EXPERT] = { aimError = 0, spreadScale = 1, reaction = 0 },
}

-- The level's marksmanship, a level out of range taking the nearest.
function For(level)
	return LEVELS[max(EASY, min(EXPERT, floor(level + 0.5)))]
end

-- dir (a unit { x, y, z }) turned off by up to errorDeg degrees: r1 and r2,
-- drawn by the caller in [0, 1], pick how far (spread evenly over the
-- cone's disc) and which way round.
function Aim(dir, errorDeg, r1, r2)
	if errorDeg <= 0 then return dir end
	local theta, phi = rad(errorDeg) * sqrt(r1), 2 * pi * r2
	-- two axes across dir, from whichever world axis is least along it
	local helper = abs(dir.z) < 0.9 and { x = 0, y = 0, z = 1 } or { x = 1, y = 0, z = 0 }
	local u = Geometry.Normalize(Geometry.Cross(dir, helper))
	local v = Geometry.Cross(dir, u)
	local across = Geometry.Add(Geometry.Scale(u, cos(phi)), Geometry.Scale(v, sin(phi)))
	return Geometry.Normalize(Geometry.Add(Geometry.Scale(dir, cos(theta)), Geometry.Scale(across, sin(theta))))
end

-- A bullet's spread (FireBullets' Spread) scaled on both axes.
function Spread(spread, scale)
	return { x = spread.x * scale, y = spread.y * scale, z = spread.z }
end
