-- Sandcastle's balance of Half-Life 2's weapons, for players and soldiers
-- alike. The crossbow punches rather than kills: less damage, no headshot
-- crit, a hard knockback and a stagger. The pistol and the .357 are the
-- long-range guns: more damage, a tight cone, a slower rate of fire, and no
-- falloff, where the SMG's and AR2's bullets fall off past medium range.
-- The shotgun crits more the nearer its target. Melee is left as it is;
-- the frag, the SLAM and the RPG hit harder. The controller
-- (ws/sv_hits.lua, ws/sh_weapon_balance.lua) applies it to each hit and shot.
local math = math
module(...)

-- damage: a hit's damage, in place of HL2's; cone: the full spread in
-- degrees; interval: the least seconds between two shots; falloff: its
-- bullets fall off with distance (FALLOFF); closeCrits: it crits by
-- distance (CLOSE_CRITS); headshotCrit false: a headshot is no crit;
-- knockback: the speed a hit pushes its victim along the shot,
-- headshotKnockback times that on a headshot, lift: the fraction of it
-- added upward (a push along the ground is lost to friction), stagger: the
-- seconds the victim is slowed and staggerSlow: by how much; blast: an explosion's damage at its centre, in place of
-- HL2_BLAST.
WEAPONS = {
	weapon_crossbow = {
		damage = 40,
		headshotCrit = false,
		knockback = 700,
		headshotKnockback = 1.5,
		lift = 0.3,
		stagger = 0.5,
		staggerSlow = 0.5,
	},
	weapon_pistol = {
		damage = 18,
		cone = 0.5,
		interval = 0.3,
	},
	weapon_357 = {
		damage = 75,
		cone = 0,
		interval = 1.0,
	},
	weapon_smg1 = { falloff = true },
	weapon_ar2 = { falloff = true },
	weapon_shotgun = { closeCrits = true },
	weapon_crowbar = {},
	weapon_stunstick = {},
	weapon_frag = { blast = 175 },
	weapon_slam = { blast = 200 },
	weapon_rpg = { blast = 150 },
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

-- Full damage to start units, falling to floor of it at finish and beyond.
FALLOFF = {
	start = 1024,
	finish = 2048,
	floor = 0.5,
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
	return math.min(math.max((value - from) / (to - from), 0), 1)
end

local function Falloff(distance)
	return 1 + (FALLOFF.floor - 1) * Progress(distance, FALLOFF.start, FALLOFF.finish)
end

local function CritChance(distance)
	return CLOSE_CRITS.chance * Progress(distance, CLOSE_CRITS.far, CLOSE_CRITS.near)
end

-- A hit by class (a weapon class or nil): hit = { damage (HL2's), bullet
-- (a bullet's), blast (an explosion's), distance (from the attacker),
-- headshot, roll (in [0, 1), drawn by the caller) } -> its damage, whether
-- its headshot counts, and whether it is a crit by distance.
function Shot(class, hit)
	local weapon = WEAPONS[class]
	if not weapon then return hit.damage, hit.headshot, false end
	local damage = hit.damage
	if hit.blast and weapon.blast then damage = damage * weapon.blast / HL2_BLAST[class] end
	local crit = false
	if hit.bullet then
		damage = weapon.damage or damage
		if weapon.falloff then damage = damage * Falloff(hit.distance) end
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
	if headshot then speed = speed * weapon.headshotKnockback end
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
