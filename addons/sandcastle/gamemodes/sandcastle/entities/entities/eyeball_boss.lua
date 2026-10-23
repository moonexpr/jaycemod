-- eyeball_boss (CEyeballBoss): MONOCULUS, a flying halloween_base_boss
-- bound to features.haunting.eyeball_boss. The variant's HOVER makes
-- ws_nextbot fly it with features.haunting.hover. This file implements
-- the eyeball's port and turns its body towards where it looks
-- (CEyeballBossBody). The maps spawn it from point_templates with teamnum 5;
-- the MONOCULUS spell spawns it on the caster's team.
AddCSLuaFile()

ENT.Base = "halloween_base_boss"
ENT.Type = "nextbot"
ENT.Spawnable = false
ENT.Variant = "features.haunting.eyeball_boss"

if CLIENT then return end

local Base = baseclass.Get("halloween_base_boss")

local LOOK_APPROACH_RATE = 3 -- CEyeballBossBody::Update's myApproachRate

-- CEyeballBoss::Spawn: bounds of ±50 about its origin.
function ENT:Initialize()
	Base.Initialize(self)
	local half = WS.require(self.Variant).HULL_HALF_WIDTH
	self:SetCollisionBounds(Vector(-half, -half, -half), Vector(half, half, half))
end

-- UpdateOnRemove hides the boss bar, however the eyeball goes. One removed
-- before it was bound (a cleanup sweeping it up first) never showed it, as
-- the base's OnRemove allows.
function ENT:OnRemove()
	if self.npc then self:SetBossHealth(0) end
	Base.OnRemove(self)
end

-- CEyeballBossBody::Update: turn towards the look-at spot, then animate.
function ENT:BodyUpdate()
	if self.lookAt then
		local toTarget = (self.lookAt - self:WorldSpaceCenter()):GetNormalized()
		local forward = (self:GetForward() + toTarget * LOOK_APPROACH_RATE * FrameTime()):GetNormalized()
		self:SetAngles(forward:Angle())
	end
	self:FrameAdvance()
end

-------------------------------------------------------------------------------
-- The eyeball's port (foundation.npc.eyeball_boss.METHODS)

function ENT:SetDesiredAltitude(h) self.hover:SetDesiredAltitude(h) end
function ENT:AimHeadTowards(v) self.lookAt = v end
function ENT:SetHidden(hidden) self:SetNoDraw(hidden) end

-- TheNavMesh->GetSimpleGroundHeight
function ENT:GroundHeight(v)
	local z = navmesh.GetGroundHeight(v)
	return z
end

-- TheNavMesh->GetNearestNavArea( v, anyZ, range )
function ENT:IsNearNavMesh(v, range)
	return IsValid(navmesh.GetNearestNavArea(v, true, range))
end

-- MASK_SOLID_BRUSHONLY, skipping every character (CTraceFilterNoNPCsOrPlayer).
function ENT:TraceWorld(from, to)
	local tr = util.TraceLine({
		start = from,
		endpos = to,
		mask = MASK_SOLID_BRUSHONLY,
		filter = self,
	})
	if tr.Hit then return tr.HitPos end
	return nil
end
