-- The war's soldiers as NextSoldier profiles: npc_nextsoldier is one class,
-- as TF2's CTFBot is, and each kind of soldier is data (TF2's player class):
-- its models, weapons, factions, health and speeds, and for the vortigaunt
-- its own animations, blood and hull. A kind is the name features.aiwar.model
-- knows it by.
local Factions = require("ws.factions")
local ACT_IDLE, ACT_WALK, ACT_RUN, BLOOD_COLOR_GREEN = ACT_IDLE, ACT_WALK, ACT_RUN, BLOOD_COLOR_GREEN
module(...)

local SOLDIER_HEALTH, SOLDIER_WALK, SOLDIER_RUN = 100, 90, 220

PROFILES = {
	combine = {
		PrintName = "Combine Soldier",
		Models = { "models/player/combine_soldier.mdl", "models/player/combine_soldier_prisonguard.mdl" },
		Weapons = { "weapon_ar2", "weapon_smg1", "weapon_shotgun", "weapon_pistol" },
		Factions = { Factions.BLU, Factions.HL2_COMBINE },
		SpawnHealth = SOLDIER_HEALTH, WalkSpeed = SOLDIER_WALK, RunSpeed = SOLDIER_RUN,
	},
	rebel = {
		PrintName = "Rebel Fighter",
		Models = {
			"models/player/group03/male_01.mdl", "models/player/group03/male_02.mdl", "models/player/group03/male_03.mdl",
			"models/player/group03/male_04.mdl", "models/player/group03/male_05.mdl", "models/player/group03/male_06.mdl",
			"models/player/group03/male_07.mdl", "models/player/group03/male_08.mdl", "models/player/group03/male_09.mdl",
			"models/player/group03/female_01.mdl", "models/player/group03/female_02.mdl", "models/player/group03/female_03.mdl",
			"models/player/group03/female_04.mdl", "models/player/group03/female_06.mdl",
		},
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
