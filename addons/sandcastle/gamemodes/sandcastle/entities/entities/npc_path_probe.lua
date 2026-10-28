-- A NextSoldier path probe (ns_lanes_probe, features/aiwar/sv_probe.lua): on
-- NextSoldier's base with the war's soldier hooks (WS.WarSoldier), so its
-- body, path and movement (its links refused, its hops and vaults) are a
-- soldier's, and nothing of a fighter: no weapons, no enemies, no target
-- for anyone, and it collides with the world alone, so what stops it is
-- the map. Its controller walks it along a lane's points.
ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "Path Probe"
ENT.Category = "Sandcastle"
ENT.Spawnable = false
ENT.Models = { "models/player/combine_soldier.mdl" }
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU
ENT.RagdollOnDeath = false

if SERVER then AddCSLuaFile() end

WS.WarSoldier(ENT)

if SERVER then
	local SoldierInitialize = ENT.CustomInitialize

	function ENT:CustomInitialize()
		SoldierInitialize(self)
		self:SetNoTarget(true)
		self:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER) -- the world alone, yet a spawn door's trigger sees it
		self.NSRun = true
	end
end
