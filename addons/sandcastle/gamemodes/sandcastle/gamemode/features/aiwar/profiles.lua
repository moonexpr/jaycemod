-- The war's soldiers as NextSoldier profiles: npc_nextsoldier is one class,
-- as TF2's CTFBot is, and each kind of soldier is data (TF2's player class):
-- its player-model category, weapons, factions, health and speeds, and for
-- the vortigaunt its own animations, blood and hull. A kind is the name
-- features.aiwar.model knows it by.
local Factions = require("ws.factions")
local ACT_IDLE, ACT_WALK, ACT_RUN, BLOOD_COLOR_GREEN = ACT_IDLE, ACT_WALK, ACT_RUN, BLOOD_COLOR_GREEN
module(...)

local SOLDIER_HEALTH, SOLDIER_WALK, SOLDIER_RUN = 100, 90, 220

PROFILES = {
	combine = {
		PrintName = "Combine Soldier",
		Weapons = { "weapon_ar2", "weapon_smg1", "weapon_shotgun", "weapon_pistol" },
		Factions = { Factions.BLU, Factions.HL2_COMBINE },
		SpawnHealth = SOLDIER_HEALTH, WalkSpeed = SOLDIER_WALK, RunSpeed = SOLDIER_RUN,
	},
	rebel = {
		PrintName = "Rebel Fighter",
		Weapons = { "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_pistol", "weapon_crossbow", "weapon_357" },
		Factions = { Factions.RED, Factions.HL2_REBELS },
		SpawnHealth = SOLDIER_HEALTH, WalkSpeed = SOLDIER_WALK, RunSpeed = SOLDIER_RUN,
	},
	vortigaunt = {
		PrintName = "Vortigaunt Medic",
		Models = { "models/vortigaunt.mdl" },
		Weapons = {},
		Factions = { Factions.RED, Factions.HL2_REBELS },
		SpawnHealth = 150, WalkSpeed = 80, RunSpeed = 210,
		BloodColor = BLOOD_COLOR_GREEN,
		CollisionBounds = { x = 13, y = 13, z = 72 }, -- half its width, its height
		IdleAnimation = ACT_IDLE, WalkAnimation = ACT_WALK, RunAnimation = ACT_RUN,
	},
}

MODEL_CATEGORIES = {
	combine = "Combine",
	rebel = "Resistence",
}

function ModelCategory(kind, mode, red)
	if mode == "hostage" or mode == "defuse" then
		return red and "Terrorist" or "Counter-Terrorists"
	end
	return MODEL_CATEGORIES[kind]
end
