-- Kill icons: the entries of a scripts/mod_textures.txt with a death sheet
-- (dfile: TF2's HUD/d_images and its _v2, _v3; dnegfile, the dark one for
-- the light box of a kill the player took part in), each a rectangle on its
-- sheet. TF2's are its own; Sandcastle's ws/kill_icons_sheet.lua
-- has HL2's weapons in TF2's look, by class (.devtools/bin/kill_icons_art.py
-- draws them). Which icon a kill shows goes by what made it (the inflictor's
-- class): its own, else its alias's (HL2), else TF2's skull; but a boss's
-- kill shows the boss, whatever it struck with.
-- ws/cl_kill_feed.lua draws them.
local Keyvalues = require("foundation.encoding.keyvalues")
local lower, pairs, select, tonumber = string.lower, pairs, select, tonumber
module(...)

SKULL = "skull_tf"

-- What HL2's weapons throw as their weapon, and what has no icon of its
-- own as TF2's like one.
HL2 = {
	crossbow_bolt = "weapon_crossbow",
	rpg_missile = "weapon_rpg",
	npc_grenade_frag = "weapon_frag",
	grenade_ar2 = "weapon_smg1",
	prop_combine_ball = "weapon_ar2",
	npc_satchel = "weapon_slam",
	npc_tripmine = "weapon_slam",
	npc_turret_floor = "obj_sentrygun",
	entityflame = "flamethrower",
	env_fire = "flamethrower",
	ws_drg_vortigaunt = "righteous_bison", -- its beam
	prop_physics_multiplayer = "prop_physics", -- the gravity gun and its box
	prop_physics_respawnable = "prop_physics",
	prop_physics_override = "prop_physics",
	func_physbox = "prop_physics",
	prop_ragdoll = "prop_physics",
	tf_projectile_spellpumpkin = "tf_pumpkin_bomb", -- it bursts into pumpkins
}

-- Killers whose every kill shows themselves: MONOCULUS fires TF2's own rockets.
BOSSES = {
	eyeball_boss = true,
	headless_hatman = true,
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

-- Parsed sheets as one, a later sheet's icon over an earlier one's.
function Over(...)
	local icons = {}
	for i = 1, select("#", ...) do
		for name, icon in pairs((select(i, ...))) do icons[name] = icon end
	end
	return icons
end

-- The icon a kill shows: by the class of what struck, or of its killer
-- (nil if not known) when that is a boss.
function For(icons, class, killer)
	if BOSSES[killer or ""] and icons[killer] then return icons[killer] end
	return icons[class] or icons[HL2[class] or ""] or icons[SKULL]
end
