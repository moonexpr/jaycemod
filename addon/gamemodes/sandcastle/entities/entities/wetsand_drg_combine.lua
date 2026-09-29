-- The Combine's soldier for the AI war (RED): wetsand_drg_soldier in the
-- Combine's player models, with the Combine's weapons (its support wear
-- the metrocops' model: features/aiwar's kits).
if not DrGBase then return end

ENT.Base = "wetsand_drg_soldier"
ENT.Type = "nextbot"
ENT.PrintName = "Combine Soldier (Sandcastle)"
ENT.Category = "Sandcastle"
ENT.Spawnable = true
ENT.Models = {
	"models/player/combine_soldier.mdl",
	"models/player/combine_soldier_prisonguard.mdl",
}
ENT.Weapons = { "weapon_ar2", "weapon_smg1", "weapon_shotgun", "weapon_pistol" }
ENT.Factions = { FACTION_COMBINE }

if SERVER then AddCSLuaFile() end

list.Set("NPC", "wetsand_drg_combine", { Name = ENT.PrintName, Class = "wetsand_drg_combine", Category = "Sandcastle" })
