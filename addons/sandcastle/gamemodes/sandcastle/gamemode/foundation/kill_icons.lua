-- TF2's kill icons: the entries of its scripts/mod_textures.txt with a death
-- sheet (dfile: HUD/d_images and its _v2, _v3; dnegfile, the dark one for
-- the light box of a kill the player took part in), each a rectangle on its
-- sheet; and which icon a kill shows by what made it (the inflictor's
-- class): TF2's own by name, an HL2 weapon by TF2's like one (HL2), any
-- other TF2's skull. ws/cl_kill_feed.lua draws them.
local Keyvalues = require("foundation.core.parsers.keyvalues")
local lower, pairs, tonumber = string.lower, pairs, tonumber
module(...)

SKULL = "skull_tf"

-- HL2's weapons and what they throw, as TF2's like weapons.
HL2 = {
	weapon_smg1 = "smg",
	weapon_pistol = "pistol",
	weapon_357 = "revolver",
	weapon_shotgun = "shotgun_primary",
	weapon_crossbow = "crusaders_crossbow",
	crossbow_bolt = "crusaders_crossbow",
	weapon_rpg = "tf_projectile_rocket",
	rpg_missile = "tf_projectile_rocket",
	weapon_frag = "tf_projectile_pipe",
	npc_grenade_frag = "tf_projectile_pipe",
	grenade_ar2 = "tf_projectile_pipe",
	weapon_ar2 = "pomson", -- the pulse rifle: TF2's energy rifle
	prop_combine_ball = "pomson",
	weapon_crowbar = "wrench",
	weapon_stunstick = "bat",
	npc_turret_floor = "obj_sentrygun",
	entityflame = "flamethrower",
	env_fire = "flamethrower",
	ws_drg_vortigaunt = "righteous_bison", -- its beam
}

local FIELDS = { x = "x", y = "y", width = "w", height = "h" }

-- name -> { file, negative, x, y, w, h } (pixels on the sheet).
function Parse(text)
	local entries, icons = {}, {}
	Keyvalues.Read(text, function(path, key, value)
		local name = path[#path]
		if not name then return end
		local entry = entries[name] or {}
		entries[name] = entry
		key = lower(key)
		if key == "dfile" then entry.file = value
		elseif key == "dnegfile" then entry.negative = value
		elseif FIELDS[key] then entry[FIELDS[key]] = tonumber(value) end
	end)
	for name, entry in pairs(entries) do
		if entry.file then icons[name] = entry end
	end
	return icons
end

-- The icon a kill by class shows.
function For(icons, class)
	return icons[class] or icons[HL2[class] or ""] or icons[SKULL]
end
