-- The war's soldiers as NextSoldier profiles: npc_nextsoldier is one class,
-- as TF2's CTFBot is, and each kind of soldier is data (TF2's player class):
-- its models, weapons, factions, health and speeds, and for the vortigaunt
-- its own animations, blood and hull. A kind is the name features.aiwar.model
-- knows it by. The DrGBase classes the war fields otherwise (ws_drg_combine,
-- ws_drg_rebel, ws_drg_vortigaunt) hold the same.
local Factions = WS.require("ws.factions")
local ACT_IDLE, ACT_WALK, ACT_RUN, BLOOD_COLOR_GREEN, Vector = ACT_IDLE, ACT_WALK, ACT_RUN, BLOOD_COLOR_GREEN, Vector
module(...)

local SOLDIER_HEALTH, SOLDIER_WALK, SOLDIER_RUN = 100, 90, 220

PROFILES = {
	combine = {
		Models = { "models/player/combine_soldier.mdl", "models/player/combine_soldier_prisonguard.mdl" },
		Weapons = { "weapon_ar2", "weapon_smg1", "weapon_shotgun", "weapon_pistol" },
		Factions = { Factions.BLU, Factions.HL2_COMBINE },
		SpawnHealth = SOLDIER_HEALTH, WalkSpeed = SOLDIER_WALK, RunSpeed = SOLDIER_RUN,
	},
	rebel = {
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
		Models = { "models/vortigaunt.mdl" },
		Weapons = {},
		Factions = { Factions.RED, Factions.HL2_REBELS },
		SpawnHealth = 150, WalkSpeed = 80, RunSpeed = 210,
		BloodColor = BLOOD_COLOR_GREEN,
		CollisionBounds = Vector(13, 13, 72),
		IdleAnimation = ACT_IDLE, WalkAnimation = ACT_WALK, RunAnimation = ACT_RUN,
	},
}
