-- Sandcastle's balance of Half-Life 2's weapons, for players and soldiers
-- alike. Each gun has a range: the pistol and the .357 are the long-range
-- guns, with more damage, a tight cone, a slower rate of fire, and no
-- falloff; the SMG's, AR2's and crossbow's bullets fall off past medium
-- range, the shotgun's past short range. The crossbow punches rather than
-- kills: no headshot crit and a hard knockback. The shotgun crits more the
-- nearer its target. Melee is left as it is;
-- the frag, the SLAM and the RPG hit harder. The gravity gun's punt hits a
-- player or an NPC for its own damage and throws them hard enough to be
-- slammed dead into a wall. The controller
-- (ws/sv_hits.lua, ws/sh_weapon_balance.lua) applies it to each hit and shot.
local math, pairs = math, pairs
local Scalar = math.scalar
local Css = gameplay.css_weapons
module(...)

-- damage: a hit's damage, in place of HL2's; cone: the full spread in
-- degrees; interval: the least seconds between two shots; range: how far
-- its bullets carry (a RANGE_*: they fall off past its FALLOFF, a long
-- one's never); closeCrits: it crits by
-- distance (CLOSE_CRITS); headshotCrit false: a headshot is no crit;
-- knockback: the speed a hit pushes its victim along the shot,
-- headshotKnockback times that on a headshot (the same without), lift: the
-- fraction of it added upward (a push along the ground is lost to friction),
-- stagger: the
-- seconds the victim is slowed and staggerSlow: by how much (none without);
-- blast: an explosion's damage at its centre, in place of HL2_BLAST. A
-- weapon's damage replaces HL2's for a bullet and for the gravity gun's
-- punt.
RANGE_LONG, RANGE_MEDIUM, RANGE_SHORT = "long", "medium", "short"

WEAPONS = {
	weapon_crossbow = {
		damage = 50,
		range = RANGE_MEDIUM,
		headshotCrit = false,
		knockback = 1400,
		headshotKnockback = 1.5,
		lift = 0.3,
	},
	weapon_pistol = {
		damage = 18,
		range = RANGE_LONG,
		cone = 0.5,
		interval = 0.3,
	},
	weapon_357 = {
		damage = 75,
		range = RANGE_LONG,
		cone = 0,
		interval = 1.0,
	},
	weapon_smg1 = { range = RANGE_MEDIUM },
	weapon_ar2 = { range = RANGE_MEDIUM },
	weapon_shotgun = {
		range = RANGE_SHORT,
		closeCrits = true,
	},
	weapon_crowbar = {
		damage = 20,
		interval = 2.0,
		pushback = 100,
		lift = .1,
	},
	weapon_stunstick = {
		damage = 20,
		interval = 2.0,
		pushback = 100,
		lift = .1,
	},
	weapon_frag = { 
		blast = 175,
		knockback = 1400,
		lift = 1
	},
	weapon_slam = { 
		blast = 200,
		knockback = 1400,
		lift = 1
	},
	weapon_rpg = { 
		blast = 75,
		knockback = 1400,
		lift = 1
	},
}

-- The gravity gun's punt (CWeaponPhysCannon::PuntNonVPhysics): HL2 hits a
-- character for 1 (DMG_CRUSH | DMG_PHYSGUN), pushing it along a unit
-- vector; here PUNT_THROW times the crowbar's push.
PUNT_THROW = 50
WEAPONS.weapon_physcannon = {
	damage = 10,
	knockback = PUNT_THROW * WEAPONS.weapon_crowbar.pushback,
	lift = 0.2,
}

-- The damage of HL2's explosives at their centre (GMod's skill convars:
-- sk_plr_dmg_fraggrenade, sk_plr_dmg_satchel, sk_plr_dmg_rpg_round), which
-- a blast's damage is scaled from.
HL2_BLAST = {
	weapon_frag = 125,
	weapon_slam = 150,
	weapon_rpg = 100,
}

-- The entity each weapon's hits come from, when not the weapon itself.
INFLICTORS = {
	crossbow_bolt = "weapon_crossbow",
	npc_grenade_frag = "weapon_frag",
	npc_satchel = "weapon_slam",
	npc_tripmine = "weapon_slam",
	rpg_missile = "weapon_rpg",
}

-- CS:S's weapons deal their own damage (gameplay.css_weapons: by range and
-- hit group, a headshot already four times), so none is balanced here and a
-- headshot is no crit on top.
for class, weapon in pairs(Css.WEAPONS) do
	WEAPONS[class] = { headshotCrit = false }
	if weapon.grenade then INFLICTORS[weapon.grenade.projectile] = class end
end

-- By range: full damage to start units, falling to floor of it at finish
-- and beyond. A long range has none.
FALLOFF = {
	[RANGE_MEDIUM] = {
		start = 1024,
		finish = 2048,
		floor = 0.5,
	},
	[RANGE_SHORT] = {
		start = 512,
		finish = 1024,
		floor = 0.5,
	},
}

-- No crit at far units or beyond, rising to chance at near and nearer.
CLOSE_CRITS = {
	far = 512,
	near = 64,
	chance = 0.4,
}

-- The weapon class a hit's inflictor is balanced as, or nil.
function Weapon(class)
	if WEAPONS[class] then return class end
	return INFLICTORS[class]
end

-- 0 at from, 1 at to, clamped.
local function Progress(value, from, to)
	return Scalar.InverseLerp(from, to, value)
end

-- The fraction of its damage a bullet keeps at distance; all of it for a
-- long range.
local function Falloff(range, distance)
	local curve = FALLOFF[range]
	if not curve then return 1 end
	return 1 + (curve.floor - 1) * Progress(distance, curve.start, curve.finish)
end

local function CritChance(distance)
	return CLOSE_CRITS.chance * Progress(distance, CLOSE_CRITS.far, CLOSE_CRITS.near)
end

-- A hit by class (a weapon class or nil): hit = { damage (HL2's), bullet
-- (a bullet's), blast (an explosion's), punt (the gravity gun's), distance (from the attacker),
-- headshot, roll (in [0, 1), drawn by the caller) } -> its damage, whether
-- its headshot counts, and whether it is a crit by distance.
function Shot(class, hit)
	local weapon = WEAPONS[class]
	if not weapon then return hit.damage, hit.headshot, false end
	local damage = hit.damage
	if hit.blast and weapon.blast then damage = damage * weapon.blast / HL2_BLAST[class] end
	local crit = false
	if hit.punt then damage = weapon.damage or damage end
	if hit.bullet then
		damage = weapon.damage or damage
		damage = damage * Falloff(weapon.range, hit.distance)
		crit = weapon.closeCrits == true and hit.roll < CritChance(hit.distance)
	end
	return damage, hit.headshot and weapon.headshotCrit ~= false, crit
end

-- How class's hit pushes its victim, { speed (along the shot), lift
-- (upward), stagger (seconds), slow (the fraction of speed lost) }, or nil
-- for a weapon that does not knock back.
function Knockback(class, headshot)
	local weapon = WEAPONS[class]
	if not weapon or not weapon.knockback then return nil end
	local speed = weapon.knockback
	if headshot and weapon.headshotKnockback then speed = speed * weapon.headshotKnockback end
	return {
		speed = speed,
		lift = speed * weapon.lift,
		stagger = weapon.stagger,
		slow = weapon.staggerSlow,
	}
end

-- When class may fire after a shot at firedAt, or nil when its rate is the
-- engine's.
function NextShot(class, firedAt)
	local weapon = WEAPONS[class]
	if not weapon or not weapon.interval then return nil end
	return firedAt + weapon.interval
end

-- Whether class may fire at now, its last shot at firedAt (nil: never).
function CanFire(class, firedAt, now)
	if firedAt == nil then return true end
	local next = NextShot(class, firedAt)
	return next == nil or now >= next
end

-- A bullet's spread (FireBullets' Spread, the sine of half the cone), or
-- nil when it is the engine's.
function Spread(class)
	local weapon = WEAPONS[class]
	if not weapon or not weapon.cone then return nil end
	return math.sin(math.rad(weapon.cone / 2))
end

-- The damage the Store shows for class, HL2's being skill.
function Damage(class, skill)
	local weapon = WEAPONS[class]
	if not weapon then return skill end
	return weapon.damage or weapon.blast or skill
end
