-- ghost (CGhost): a Halloween ghost, a ws_combat_nextbot bound to
-- features.haunting.ghost, which holds its rules. It is solid to nothing
-- (CGhost::ShouldCollide), and implements the ghost's port: FeelerHit.
-- Configure{ lifetime } before Spawn (the haunting controller does).
AddCSLuaFile()

ENT.Base = "ws_combat_nextbot"
ENT.Type = "nextbot"
ENT.Spawnable = false
ENT.Variant = "features.haunting.ghost"

if CLIENT then return end

local Base = baseclass.Get("ws_combat_nextbot")

function ENT:Initialize()
	self:SetModel(WS.require(self.Variant).MODEL)
	Base.Initialize(self)
	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetSolid(SOLID_NONE)
	self:AddSolidFlags(FSOLID_NOT_SOLID)
end

-- CTraceFilterNoNPCsOrPlayer, MASK_PLAYERSOLID.
function ENT:FeelerHit(from, to)
	local tr = util.TraceLine({
		start = from,
		endpos = to,
		mask = MASK_PLAYERSOLID,
		filter = function(ent) return not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) end,
	})
	if tr.Hit then return tr.Fraction end
	return nil
end
