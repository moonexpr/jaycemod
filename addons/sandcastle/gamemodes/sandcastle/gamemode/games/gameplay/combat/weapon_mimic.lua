-- A weapon mimic (tf_point_weapon_mimic, CTFPointWeaponMimic): a point that
-- fires a BLU weapon's projectiles along its angles when told to. Rockets
-- (tf_projectile_rocket) and grenades (tf_projectile_pipe) fire; arrows and
-- stickies do not (the maps use neither), and the binding says so once.
--
-- New{ weaponType, speedMin, speedMax, spreadAngle, damage, splashRadius,
-- crits, modelScale, modelOverride } from the keyvalues, then :Fires() and
-- :Shot(aim, randomFloat, randomInt) -> { class, config }: the projectile
-- class and its Configure table, less the attacker and launcher (the
-- mimic), which the binding adds. aim = { forward, right, up } are the
-- mimic's direction vectors, which support + and * by a number. FireSound
-- and ParticleEffect are read by CTFPointWeaponMimic and never played.
local require = require
local Teams = require("games.gameplay.teams")
local abs, cos, floor, max, rad, sin = math.abs, math.cos, math.floor, math.max, math.rad, math.sin
local setmetatable = setmetatable
module(...)

-- eWeaponType
WEAPON_STANDARD_ROCKET = 0
WEAPON_STANDARD_GRENADE = 1
WEAPON_STANDARD_ARROW = 2
WEAPON_STICKY_GRENADE = 3

TEAM = Teams.BLUE -- every mimic and its projectiles ChangeTeam(TF_TEAM_BLUE)

ROCKET_CLASS = "tf_projectile_rocket"
PIPE_CLASS = "tf_projectile_pipe"

-- FireGrenade
GRENADE_FUSE = 2 -- SetDetonateTimerLength
GRENADE_SKIN = 1 -- m_nSkin: BLU
GRENADE_SPIN = 600 -- AngularImpulse(600, RandomInt(-1200, 1200), 0)
GRENADE_TUMBLE = 1200

HALF_TURN = 180 -- GetFiringAngles turns about forward by up to this either way

local Mimic = {}
Mimic.__index = Mimic

function New(config)
	return setmetatable({
		config = config,
	}, Mimic)
end

-- InputFireMultiple: Max(1, abs(n)) shots.
function FireCount(n)
	return max(1, abs(floor(n)))
end

-- GetFiringAngles as a direction: turned about up by half the spread at
-- most, then about the aim by any angle; straight when there is no spread.
local function Direction(spread, aim, randomFloat)
	if spread == 0 then return aim.forward end
	local half = spread / 2
	local off = rad(randomFloat(-half, half))
	local around = rad(randomFloat(-HALF_TURN, HALF_TURN))
	local side = aim.right * cos(around) + aim.up * sin(around)
	return aim.forward * cos(off) + side * sin(off)
end

local function Velocity(config, aim, randomFloat)
	local direction = Direction(config.spreadAngle, aim, randomFloat)
	return direction * randomFloat(config.speedMin, config.speedMax) -- GetSpeed
end

-- FireRocket: the rocket's own radius (TF_ROCKET_RADIUS); SplashRadius is
-- not passed on.
local function Rocket(config, aim, randomFloat, randomInt)
	return {
		class = ROCKET_CLASS,
		config = {
			damage = config.damage,
			crit = config.crits,
			team = TEAM,
			velocity = Velocity(config, aim, randomFloat),
			model = config.modelOverride,
		},
	}
end

-- FireGrenade
local function Grenade(config, aim, randomFloat, randomInt)
	local velocity = Velocity(config, aim, randomFloat)
	return {
		class = PIPE_CLASS,
		config = {
			damage = config.damage,
			crit = config.crits,
			team = TEAM,
			radius = config.splashRadius,
			velocity = velocity,
			spin = {
				x = GRENADE_SPIN,
				y = randomInt(-GRENADE_TUMBLE, GRENADE_TUMBLE),
				z = 0,
			},
			fuse = GRENADE_FUSE,
			explodeOnTouch = false,
			model = config.modelOverride,
			skin = GRENADE_SKIN,
			scale = config.modelScale,
		},
	}
end

local WEAPONS = {
	[WEAPON_STANDARD_ROCKET] = Rocket,
	[WEAPON_STANDARD_GRENADE] = Grenade,
}

function Mimic:Fires()
	return WEAPONS[self.config.weaponType] ~= nil
end

function Mimic:Shot(aim, randomFloat, randomInt)
	return WEAPONS[self.config.weaponType](self.config, aim, randomFloat, randomInt)
end
