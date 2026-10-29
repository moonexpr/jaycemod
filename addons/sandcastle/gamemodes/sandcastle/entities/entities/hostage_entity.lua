-- hostage_entity (CS:S): a hostage, on NextSoldier's base (base_nextsoldier)
-- with the war soldier's movement (WS.WarSoldier: its climbs, vaults, hops),
-- as npc_pathfollower is. A binding to the hostage controller
-- (features/hostage), which says whom it follows; its one behaviour, in place
-- of the base's intention, walks to that soldier and stands otherwise. It
-- fights nothing, is no one's target and cannot be hurt: RED keeps it, BLU
-- frees it, and the rescue is decided by the rules, not by a corpse.
AddCSLuaFile()

ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "Hostage"
ENT.Spawnable = false
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU
ENT.RagdollOnDeath = false
ENT.WalkSpeed = 120
ENT.RunSpeed = 190

WS.WarSoldier(ENT)

if CLIENT then return end

-- The hostage stops this far from its rescuer.
local FOLLOW_GAP = 90

local SoldierInitialize = ENT.CustomInitialize
function ENT:CustomInitialize()
	SoldierInitialize(self)
	self:SetModel(WS.require("features.hostage.models").Pick(self:EntIndex()))
	self:SetNoTarget(true)
	-- players walk through it (ws_nextbot's PLAYERS_PASS_THROUGH group): a
	-- rescuer turning back for it in a narrow hall is not walled in by it
	self:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
	self.NSRun = true
	self.hostage = WS.Feature("hostage")
	self.hostage:Bind(self)
end

local SoldierRemove = ENT.OnRemove
function ENT:OnRemove()
	if self.hostage then self.hostage:Unbind(self) end
	SoldierRemove(self)
end

-- No hurt reaches it.
function ENT:OnInjured(dmg)
	dmg:SetDamage(0)
end

-- Whom the hostage follows (an entity), or nil.
function ENT:SetLeader(leader)
	self.leader = leader
end

-- Led into the rescue zone: out of the round, standing where it was.
function ENT:Rescued()
	self.rescued = true
	self.leader = nil
	self.NSTarget = nil
	self.NSFrozen = true
	self:SetNoDraw(true)
	self:SetNotSolid(true)
end

-- Its one behaviour: after its rescuer, to FOLLOW_GAP of them; else it stands.
function ENT:IntentionUpdate()
	local leader = self.leader
	if self.rescued or not IsValid(leader) or self:GetPos():Distance(leader:GetPos()) <= FOLLOW_GAP then
		self.NSTarget = nil
		return
	end
	self.NSTarget = leader:GetPos()
	self:NSSteer()
end
