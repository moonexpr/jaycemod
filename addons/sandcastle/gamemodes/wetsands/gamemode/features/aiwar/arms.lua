-- AI war weapon selection: CS:S stats come from the live SWEP instance,
-- while these profiles describe the HL2 and Black Mesa weapons.
local error, format, huge, ipairs, type = error, string.format, math.huge, ipairs, type
module (...)

WEAPONS =
{
	weapon_crossbow = { cone = 0, reach = 3000, chase = 2000, avoid = 750 },
	weapon_357 = { cone = 1, reach = 750, chase = 500, avoid = 350 },
	weapon_pistol = { cone = 2, reach = 750, chase = 500, avoid = 350 },
	weapon_ar2 = { cone = 3, reach = 1500, chase = 1000, avoid = 750, automatic = true },
	weapon_smg1 = { cone = 5, reach = 1500, chase = 1000, avoid = 750, automatic = true },
	weapon_shotgun = { cone = 10, reach = 325, chase = 250, avoid = 175 },
	weapon_crowbar = { melee = true, damage = 25, interval = 0.25, automatic = true },
	weapon_stunstick = { melee = true, damage = 30, interval = 0.25, automatic = true },

	-- Black Mesa's, from their own code. A cone is its Spread's full angle, as HL2's above.
	-- TODO: weapon_bmesa_frag, weapon_bmesa_satchel, weapon_bmesa_tripmine
	weapon_bmesa_crowbar = { melee = true, damage = 10, interval = 0.25, automatic = true },
	weapon_bmesa_glock = { cone = 6, reach = 750, chase = 500, avoid = 350, automatic = true }, -- 8 damage, 0.3 s
	weapon_bmesa_357 = { cone = 1, reach = 2000, chase = 1200, avoid = 500, automatic = true }, -- 45, 0.75 s
	weapon_bmesa_mp5 = { cone = 5, reach = 1500, chase = 1000, avoid = 750, automatic = true }, -- 8, 0.1 s
	weapon_bmesa_shotgun = { cone = 11, reach = 325, chase = 250, avoid = 175, automatic = true }, -- 7 x 8, 0.6 s
	-- a bolt flies at 2500 a second, and it reloads for 2.1: not for what moves far off
	weapon_bmesa_crossbow = { cone = 0, reach = 2500, chase = 1800, avoid = 750, automatic = true },
	-- a rocket starts at 192 a second, and its blast reaches 300
	weapon_bmesa_rpg = { cone = 0, reach = 3000, chase = 1500, avoid = 500, minimum = 400, automatic = true },
	weapon_bmesa_tau = { cone = 1, reach = 2000, chase = 1200, avoid = 500, automatic = true }, -- 25, 0.32 s
	weapon_bmesa_gluon = { cone = 0, reach = 1000, chase = 600, avoid = 200, automatic = true },
	-- a hornet flies at 1200 a second, seeking, about a cone of 6 off its aim
	weapon_bmesa_hivehand = { cone = 6, reach = 800, chase = 500, avoid = 200, automatic = true }
}

MELEE_REACH, MELEE_SWITCH = 64, 80
-- The distance it readies itself for with no enemy.
IDLE_DISTANCE = 1000
-- A gun it holds is kept over a better fit while the enemy is past this share of that one's
-- reach: an enemy moving about a reach's end does not have it swapping back and forth.
local KEEP_NEAR = 0.75

local FIELDS =
{
	cone = "AICone",
	reach = "AIReach",
	chase = "AIChase",
	avoid = "AIAvoid",
	automatic = "AIAutomatic",
	melee = "AIMelee",
	damage = "AIDamage",
	interval = "AIInterval"
}

local function Profile (weapon)
	if type (weapon) == "string" then return WEAPONS [weapon] end
	if weapon and weapon.CStrikeWeapon then return weapon end
	if weapon and weapon.GetClass then return WEAPONS [weapon:GetClass ()] end
end

local function Value (weapon, key)
	local profile = Profile (weapon)
	if not profile then return nil end
	if type (profile) == "table" and not profile.CStrikeWeapon then return profile [key] end
	return profile [FIELDS [key]]
end

local function Known (class, melee, slot)
	if type (class) ~= "string" or not class:match ("^weapon_[%w_]+$") then
		error (format ("arms: %s %s is not a weapon class", slot, tostring (class)), 3)
	end
	if class == "weapon_knife" then
		if not melee then error (format ("arms: %s %s is a melee weapon", slot, class), 3) end
	elseif WEAPONS [class] then
		if (WEAPONS [class].melee == true) ~= melee then
			error (format ("arms: %s %s is %s", slot, class, melee and "not a melee weapon" or "a melee weapon"), 3)
		end
	elseif melee then
		error (format ("arms: %s %s is not a melee weapon", slot, class), 3)
	end
	return class
end

function Loadout (kit, random)
	local choices = kit.primary or {}
	if #choices == 0 then error ("arms: a kit with no primary", 2) end
	if kit.secondary == nil then error ("arms: a kit with no secondary", 2) end
	if kit.melee == nil then error ("arms: a kit with no melee weapon", 2) end
	return
	{
		primary = Known (choices [random (#choices)], false, "primary"),
		secondary = Known (kit.secondary, false, "secondary"),
		melee = Known (kit.melee, true, "melee")
	}
end

function Classes (loadout)
	return { loadout.primary, loadout.secondary, loadout.melee }
end

function Choose (loadout, distance, primaryWeapon, secondaryWeapon)
	if distance <= MELEE_SWITCH then return loadout.melee end
	local primary = primaryWeapon or loadout.primary
	local primaryReach = Value (primary, "reach")
	local primaryCone = Value (primary, "cone")
	if primaryReach == nil or primaryCone == nil then
		error ("arms: the primary SWEP instance is unavailable", 2)
	end
	if distance <= primaryReach then return loadout.primary end
	local secondary = secondaryWeapon or loadout.secondary
	local secondaryCone = Value (secondary, "cone")
	if secondaryCone == nil then error ("arms: the secondary SWEP instance is unavailable", 2) end
	if secondaryCone < primaryCone then return loadout.secondary end
	return loadout.primary
end

-- How near an enemy may be for it to be fired at all: a blast's reach, else nothing.
function Minimum (weapon) return Value (weapon, "minimum") or 0 end

-- Which of what it carries a soldier holds at this distance from its enemy, nil with nothing
-- to fight with; a player class gives whatever it gives, tools among them, and what this
-- cannot measure is no weapon. Face to face, its melee weapon. Else the gun with the shortest
-- reach that covers the distance, the one made for it, or what it holds when that is close;
-- else its longest. Nothing inside its Minimum. usable(weapon): whether it can
-- fire.
function Pick (weapons, distance, held, usable)
	local melee, covering, longest
	local coveringReach, longestReach = huge, -huge
	for _, weapon in ipairs (weapons) do
		if usable (weapon) and distance >= Minimum (weapon) then
			local reach = Value (weapon, "reach")
			if Value (weapon, "melee") then
				melee = melee or weapon
			elseif reach then
				if reach >= distance and reach < coveringReach then covering, coveringReach = weapon, reach end
				if reach > longestReach then longest, longestReach = weapon, reach end
			end
		end
	end
	if melee and distance <= MELEE_SWITCH then return melee end
	if held and usable (held) and not Value (held, "melee") and distance >= Minimum (held) then
		local reach = Value (held, "reach")
		if reach and reach >= distance and (held == covering or distance > coveringReach * KEEP_NEAR) then return held end
	end
	return covering or longest or melee
end

function Ranges (weapon)
	local melee = Value (weapon, "melee")
	if melee then return { attack = 0, melee = MELEE_REACH, chase = MELEE_REACH / 2, avoid = 0 } end
	local reach = Value (weapon, "reach")
	if reach == nil then return nil end
	return { attack = huge, melee = 0, chase = Value (weapon, "chase"), avoid = Value (weapon, "avoid") }
end

function Automatic (weapon) return Value (weapon, "automatic") == true end
function Melee (weapon) return Value (weapon, "melee") == true end
function Cone (weapon) return Value (weapon, "cone") end
function Reach (weapon) return Value (weapon, "reach") end
function Damage (weapon) return Value (weapon, "damage") end
function Interval (weapon) return Value (weapon, "interval") end
