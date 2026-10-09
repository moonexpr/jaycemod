-- A proxy: an unseen box an admin right-clicks (Sandbox's properties) for an
-- entity with no body of its own to click, its Target (a cart's
-- team_train_watcher, from the cart or one of its checkpoints:
-- features/payload). Only the right-click's trace finds it: properties'
-- GetHovered falls back to a MASK_ALL trace that reaches the debris group,
-- and the box answers no other mask, so bullets (MASK_SHOT), players and
-- NPCs pass through. Its box is networked, so the client's trace finds it
-- too.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false
ENT.PhysgunDisabled = true
ENT.m_tblToolsAllowed = {}

function ENT:SetupDataTables()
	self:NetworkVar("Entity", 0, "Target")
	self:NetworkVar("Vector", 0, "Mins")
	self:NetworkVar("Vector", 1, "Maxs")
end

function ENT:Initialize()
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_OBB)
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	self:EnableCustomCollisions(true)
	self:DrawShadow(false)
end

-- Only the right-click's trace hits it.
function ENT:TestCollision(start, delta, isBox, extents, mask)
	if mask ~= MASK_ALL then return end
	local hitPos, normal, fraction = util.IntersectRayWithOBB(start, delta, self:GetPos(), self:GetAngles(), self:GetMins(), self:GetMaxs())
	if not hitPos then return end
	return { HitPos = hitPos, Normal = normal, Fraction = fraction }
end

if SERVER then return end

function ENT:Draw() end

-- The box arrives after Initialize on a client.
function ENT:Think()
	local mins, maxs = self:GetMins(), self:GetMaxs()
	if mins ~= self.boundsMins or maxs ~= self.boundsMaxs then
		self.boundsMins, self.boundsMaxs = mins, maxs
		self:SetCollisionBounds(mins, maxs)
	end
end
