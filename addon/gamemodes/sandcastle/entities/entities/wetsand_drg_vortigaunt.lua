-- The Resistance's medic for the AI war (BLU): a vortigaunt, a DrGBase
-- NextBot on its plain base (drgbase_nextbot: the vortigaunt model has
-- HL2's NPC activities, not a player's), steered by the war's orders as its
-- soldiers are (WETSAND.DrgSoldier). It carries no weapon; it heals with a
-- beam (features/aiwar's medics).
if not DrGBase then return end

ENT.Base = "drgbase_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "Vortigaunt Medic (Sandcastle)"
ENT.Category = "Sandcastle"
ENT.Spawnable = true
ENT.Models = { "models/vortigaunt.mdl" }
ENT.BloodColor = BLOOD_COLOR_GREEN
ENT.CollisionBounds = Vector(13, 13, 72)
ENT.Factions = { FACTION_REBELS }

ENT.SpawnHealth = 150
ENT.WalkSpeed = 80
ENT.RunSpeed = 210
ENT.RagdollOnDeath = true
ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = ACT_RUN
ENT.IdleAnimation = ACT_IDLE

if SERVER then AddCSLuaFile() end

WETSAND.DrgSoldier(ENT, "drgbase_nextbot")

list.Set("NPC", "wetsand_drg_vortigaunt", { Name = ENT.PrintName, Class = "wetsand_drg_vortigaunt", Category = "Sandcastle" })
