-- The Resistance's soldier for the AI war (BLU): wetsand_drg_soldier in the
-- rebels' player models, with the Resistance's weapons.
-- Spawned, it is in Team BLU's faction and HL2's rebels' (sh_factions.lua);
-- the AI war moves it to the faction of the team it fights for.
if not DrGBase then return end

ENT.Base = "wetsand_drg_soldier"
ENT.Type = "nextbot"
ENT.PrintName = "Rebel Fighter"
ENT.Category = "Sandcastle"
ENT.Spawnable = true
ENT.Models = {
	"models/player/group03/male_01.mdl", "models/player/group03/male_02.mdl", "models/player/group03/male_03.mdl",
	"models/player/group03/male_04.mdl", "models/player/group03/male_05.mdl", "models/player/group03/male_06.mdl",
	"models/player/group03/male_07.mdl", "models/player/group03/male_08.mdl", "models/player/group03/male_09.mdl",
	"models/player/group03/female_01.mdl", "models/player/group03/female_02.mdl", "models/player/group03/female_03.mdl",
	"models/player/group03/female_04.mdl", "models/player/group03/female_06.mdl",
}
ENT.Weapons = { "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_pistol", "weapon_crossbow", "weapon_357" }
ENT.Factions = { FACTION_TEAM_BLU, FACTION_REBELS }

if SERVER then AddCSLuaFile() end

list.Set("NPC", "wetsand_drg_rebel", { Name = ENT.PrintName, Class = "wetsand_drg_rebel", Category = "Sandcastle" })
