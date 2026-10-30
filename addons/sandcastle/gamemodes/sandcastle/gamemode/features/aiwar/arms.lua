-- The AI war soldiers' arms: every soldier carries a primary, a secondary
-- and a melee weapon (Loadout), and holds the one for its enemy's distance
-- (Choose): the melee weapon face to face, the primary within its reach,
-- beyond that whichever of its two guns is more precise (a shotgunner's
-- pistol, a rifleman's too). A gun fires at any enemy in sight (Ranges), so
-- a soldier opens fire as it calls them out, not only within DrGBase's range
-- for the hold type; tf_bot_difficulty's aim and spread (aiwar.marksmanship)
-- make far shots miss.
local error, format, huge, ipairs = error, string.format, math.huge, ipairs
local atan, deg = math.atan, math.deg
local Css = gameplay.css_weapons
module(...)

-- cone: how far a shot strays, in degrees (about HL2's NPC bullet cones;
-- only their order matters: the smallest is the most precise); reach: the
-- distance it fights best to (DrGBase's attack range for its hold type);
-- chase and avoid: how near DrGBase closes and how far it backs off, its
-- own for the hold type. A melee weapon: damage a strike, interval between
-- strikes (Half-Life's crowbar's, CCrowbar::Swing: a hit swings again 0.25
-- seconds on). automatic: it fires, or swings, for as long as its trigger
-- is held; the rest fire once a press (a bot soldier presses again:
-- nextsoldier.player_body).
WEAPONS = {
	weapon_crossbow = { cone = 0, reach = 3000, chase = 2000, avoid = 750 },
	weapon_357 = { cone = 1, reach = 750, chase = 500, avoid = 350 },
	weapon_pistol = { cone = 2, reach = 750, chase = 500, avoid = 350 },
	weapon_ar2 = { cone = 3, reach = 1500, chase = 1000, avoid = 750, automatic = true },
	weapon_smg1 = { cone = 5, reach = 1500, chase = 1000, avoid = 750, automatic = true },
	weapon_shotgun = { cone = 10, reach = 325, chase = 250, avoid = 175 },
	weapon_crowbar = { melee = true, damage = 25, interval = 0.25, automatic = true },
	weapon_stunstick = { melee = true, damage = 30, interval = 0.25, automatic = true },
}

-- CS:S's weapons (gameplay.css_weapons), for the CS:S modes' soldiers: a
-- gun's cone is its standing inaccuracy and spread, in degrees across; its
-- reach, chase and avoid its type's, as the HL2 gun nearest it; automatic
-- when CS:S fires it held. The knife strikes as its slash. Grenades are no
-- arms: a soldier does not carry them.
local CSS_RANGES = {
	Pistol = { reach = 750, chase = 500, avoid = 350 },
	SubMachinegun = { reach = 1000, chase = 700, avoid = 500 },
	Rifle = { reach = 1500, chase = 1000, avoid = 750 },
	Machinegun = { reach = 1500, chase = 1000, avoid = 750 },
	Shotgun = { reach = 325, chase = 250, avoid = 175 },
	SniperRifle = { reach = 3000, chase = 2000, avoid = 750 },
}
for _, class in ipairs(Css.CLASSES) do
	local w = Css.WEAPONS[class]
	if w.kind == Css.GUN then
		local ranges = CSS_RANGES[w.type]
		WEAPONS[class] = {
			cone = 2 * deg(atan(w.accuracy.stand + w.accuracy.spread)),
			reach = ranges.reach,
			chase = ranges.chase,
			avoid = ranges.avoid,
			automatic = w.fullAuto or nil,
		}
	elseif w.kind == Css.KNIFE then
		local slash = Css.KNIFE_STATS.slash
		WEAPONS[class] = { melee = true, damage = slash.damage, interval = slash.interval, automatic = true }
	end
end

-- How near a melee weapon strikes from, and how near an enemy is before the
-- soldier draws it (the farther, so it is out before it can strike).
MELEE_REACH, MELEE_SWITCH = 64, 80

local function Known(class, melee, slot)
	local weapon = WEAPONS[class]
	if not weapon then error(format("arms: %s %s is no weapon the soldiers know", slot, class), 3) end
	if (weapon.melee == true) ~= melee then
		error(format("arms: %s %s is %s", slot, class, melee and "not a melee weapon" or "a melee weapon"), 3)
	end
	return class
end

-- A kit's arms, { primary (classes, one drawn: random(n) gives 1..n),
-- secondary, melee }, as the loadout { primary, secondary, melee } it
-- carries; a slot missing, or a weapon unknown or in the wrong slot, is our
-- bug.
function Loadout(kit, random)
	local choices = kit.primary or {}
	if #choices == 0 then error("arms: a kit with no primary", 2) end
	if kit.secondary == nil then error("arms: a kit with no secondary", 2) end
	if kit.melee == nil then error("arms: a kit with no melee weapon", 2) end
	return {
		primary = Known(choices[random(#choices)], false, "primary"),
		secondary = Known(kit.secondary, false, "secondary"),
		melee = Known(kit.melee, true, "melee"),
	}
end

-- What it carries, in slot order.
function Classes(loadout)
	return { loadout.primary, loadout.secondary, loadout.melee }
end

-- The class to hold for an enemy distance away.
function Choose(loadout, distance)
	if distance <= MELEE_SWITCH then return loadout.melee end
	local primary = loadout.primary
	if distance <= WEAPONS[primary].reach then return primary end
	local secondary = loadout.secondary
	if WEAPONS[secondary].cone < WEAPONS[primary].cone then return secondary end
	return primary
end

-- DrGBase's ranges with the class held (its OnWeaponChange's): { attack
-- (RangeAttackRange), melee (MeleeAttackRange), chase (ReachEnemyRange),
-- avoid (AvoidEnemyRange) }; nil for a weapon the soldiers do not know.
function Ranges(class)
	local weapon = WEAPONS[class]
	if not weapon then return nil end
	if weapon.melee then return { attack = 0, melee = MELEE_REACH, chase = MELEE_REACH / 2, avoid = 0 } end
	return { attack = huge, melee = 0, chase = weapon.chase, avoid = weapon.avoid }
end

