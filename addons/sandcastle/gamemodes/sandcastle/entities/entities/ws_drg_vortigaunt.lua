-- The Resistance's medic for the AI war (RED, its home team): a
-- vortigaunt, a DrGBase NextBot on its plain base (drgbase_nextbot: the
-- vortigaunt model has HL2's NPC activities, not a player's), steered by
-- the war's orders as its soldiers are (WS.DrgSoldier). It carries no
-- weapon; it heals with a beam (features/aiwar's medics).
-- Spawned, it is in Team RED's faction and HL2's rebels' (sh_factions.lua);
-- the AI war moves it to the faction of the team it fights for.
if not DrGBase then return end

ENT.Base = "drgbase_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "Vortigaunt Medic"
ENT.Category = "Sandcastle"
ENT.Spawnable = true
ENT.Models = { "models/vortigaunt.mdl" }
-- loaded with the map, in both realms, so the first to spawn does not hang the game
for _, model in ipairs(ENT.Models) do util.PrecacheModel(model) end
ENT.BloodColor = BLOOD_COLOR_GREEN
ENT.CollisionBounds = Vector(13, 13, 72)
ENT.Factions = { FACTION_TEAM_RED, FACTION_REBELS }

ENT.SpawnHealth = 150
ENT.WalkSpeed = 80
ENT.RunSpeed = 210
ENT.RagdollOnDeath = false -- dies into clientside ragdolls (WS.DrgSoldier)
ENT.WalkAnimation = ACT_WALK
ENT.RunAnimation = ACT_RUN
ENT.IdleAnimation = ACT_IDLE

if SERVER then AddCSLuaFile() end

WS.DrgSoldier(ENT, "drgbase_nextbot")

list.Set("NPC", "ws_drg_vortigaunt", { Name = ENT.PrintName, Class = "ws_drg_vortigaunt", Category = "Sandcastle" })
