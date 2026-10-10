-- The AI war's soldier: a DrGBase human NextBot (drgbase_nextbot_human,
-- github.com/Dragoteryx/drgbase, which the AI war requires) that fights as
-- DrGBase's human AI does (aiming, firing, reloading, chasing and keeping
-- its distance by weapon) while the war's orders steer it
-- (WS.DrgSoldier, ws/sh_drg_soldier.lua).
-- ws_drg_combine and ws_drg_rebel are its two sides.
if not DrGBase then return end

ENT.Base = "drgbase_nextbot_human"
ENT.Type = "nextbot"
ENT.PrintName = "Combatant"
ENT.Category = "Sandcastle"
ENT.Spawnable = false

ENT.SpawnHealth = 100
ENT.WalkSpeed = 90
ENT.RunSpeed = 220
ENT.RagdollOnDeath = false -- dies into clientside ragdolls (WS.DrgSoldier)

if SERVER then AddCSLuaFile() end

WS.DrgSoldier(ENT, "drgbase_nextbot_human")
