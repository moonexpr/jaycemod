-- A NextSoldier path probe (ns_lanes_probe, features/aiwar/sv_probe.lua):
-- ws_drg_soldier's body, path and movement (its links refused, its hops
-- and vaults), and nothing of a fighter: no weapons, no enemies, no
-- target for anyone, and it collides with the world alone, so what stops
-- it is the map. Its controller walks it along a lane's points.
if not DrGBase then return end

ENT.Base = "ws_drg_soldier"
ENT.Type = "nextbot"
ENT.PrintName = "Path Probe"
ENT.Category = "Sandcastle"
ENT.Spawnable = false
ENT.Models = { "models/player/combine_soldier.mdl" }
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU

if SERVER then AddCSLuaFile() end

if SERVER then
	function ENT:CustomInitialize()
		baseclass.Get("ws_drg_soldier").CustomInitialize(self)
		self:SetNoTarget(true)
		self:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER) -- the world alone, yet a spawn door's trigger sees it
		self.NSRun = true
	end
end
