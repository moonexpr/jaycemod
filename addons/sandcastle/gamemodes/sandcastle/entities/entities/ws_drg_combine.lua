-- The Combine's soldier for the AI war (RED): ws_drg_soldier in the
-- Combine's player models, with the Combine's weapons (its support wear
-- the metrocops' model: features/aiwar's kits).
-- Spawned, it is in Team RED's faction and HL2's Combine (sh_factions.lua);
-- the AI war moves it to the faction of the team it fights for.
if not DrGBase then return end

ENT.Base = "ws_drg_soldier"
ENT.Type = "nextbot"
ENT.PrintName = "Combine Soldier"
ENT.Category = "Sandcastle"
ENT.Spawnable = true
ENT.Models = {
	"models/player/combine_soldier.mdl",
	"models/player/combine_soldier_prisonguard.mdl",
}
ENT.Weapons = { "weapon_ar2", "weapon_smg1", "weapon_shotgun", "weapon_pistol" }
ENT.Factions = { FACTION_TEAM_RED, FACTION_COMBINE }

if SERVER then AddCSLuaFile() end

list.Set("NPC", "ws_drg_combine", { Name = ENT.PrintName, Class = "ws_drg_combine", Category = "Sandcastle" })
