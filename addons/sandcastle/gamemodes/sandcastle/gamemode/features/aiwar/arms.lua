-- AI war weapon selection: CS:S stats come from the live SWEP instance,
-- while these profiles describe only the built-in HL2 weapons.
local error, format, huge, type = error, string.format, math.huge, type
module(...)

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

MELEE_REACH, MELEE_SWITCH = 64, 80

local FIELDS = {
	cone = "AICone",
	reach = "AIReach",
	chase = "AIChase",
	avoid = "AIAvoid",
	automatic = "AIAutomatic",
	melee = "AIMelee",
	damage = "AIDamage",
	interval = "AIInterval",
}

local function Profile(weapon)
	if type(weapon) == "string" then return WEAPONS[weapon] end
	if weapon and weapon.CStrikeWeapon then return weapon end
	if weapon and weapon.GetClass then return WEAPONS[weapon:GetClass()] end
end

local function Value(weapon, key)
	local profile = Profile(weapon)
	if not profile then return nil end
	if type(profile) == "table" and not profile.CStrikeWeapon then return profile[key] end
	return profile[FIELDS[key]]
end

local function Known(class, melee, slot)
	if type(class) ~= "string" or not class:match("^weapon_[%w_]+$") then
		error(format("arms: %s %s is not a weapon class", slot, tostring(class)), 3)
	end
	if class == "weapon_knife" then
		if not melee then error(format("arms: %s %s is a melee weapon", slot, class), 3) end
	elseif WEAPONS[class] then
		if (WEAPONS[class].melee == true) ~= melee then
			error(format("arms: %s %s is %s", slot, class, melee and "not a melee weapon" or "a melee weapon"), 3)
		end
	elseif melee then
		error(format("arms: %s %s is not a melee weapon", slot, class), 3)
	end
	return class
end

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

function Classes(loadout)
	return { loadout.primary, loadout.secondary, loadout.melee }
end

function Choose(loadout, distance, primaryWeapon, secondaryWeapon)
	if distance <= MELEE_SWITCH then return loadout.melee end
	local primary = primaryWeapon or loadout.primary
	local primaryReach = Value(primary, "reach")
	local primaryCone = Value(primary, "cone")
	if primaryReach == nil or primaryCone == nil then
		error("arms: the primary SWEP instance is unavailable", 2)
	end
	if distance <= primaryReach then return loadout.primary end
	local secondary = secondaryWeapon or loadout.secondary
	local secondaryCone = Value(secondary, "cone")
	if secondaryCone == nil then error("arms: the secondary SWEP instance is unavailable", 2) end
	if secondaryCone < primaryCone then return loadout.secondary end
	return loadout.primary
end

function Ranges(weapon)
	local melee = Value(weapon, "melee")
	if melee then return { attack = 0, melee = MELEE_REACH, chase = MELEE_REACH / 2, avoid = 0 } end
	local reach = Value(weapon, "reach")
	if reach == nil then return nil end
	return { attack = huge, melee = 0, chase = Value(weapon, "chase"), avoid = Value(weapon, "avoid") }
end

function Automatic(weapon) return Value(weapon, "automatic") == true end
function Melee(weapon) return Value(weapon, "melee") == true end
function Cone(weapon) return Value(weapon, "cone") end
function Reach(weapon) return Value(weapon, "reach") end
function Damage(weapon) return Value(weapon, "damage") end
function Interval(weapon) return Value(weapon, "interval") end
