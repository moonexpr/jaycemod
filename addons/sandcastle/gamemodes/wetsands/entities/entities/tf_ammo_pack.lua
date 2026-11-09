-- tf_ammo_pack (CTFAmmoPack): the medium ammo pack a player drops on death.
-- Anyone alive may take it, its dropper only after 0.75s; it gives half of
-- each weapon's ammo and is gone after 30s. It tumbles as a debris physics
-- object, which players do not touch, so pickup is tested by distance.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

if CLIENT then return end

local P = WS.PlayerRules
local MODEL = "models/items/ammopack_medium.mdl"
local PICKUP_RADIUS = 40

function ENT:Initialize()
	self:SetModel(MODEL)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	self:PhysWake()
	self.createdAt = CurTime()
	SafeRemoveEntityDelayed(self, P.DROPPED_PACK.lifetime)
end

function ENT:MayPickUp(ply)
	if not WS.IsAliveInGame(ply) then return false end
	return ply ~= self:GetOwner() or CurTime() >= self.createdAt + P.DROPPED_PACK.ownerDelay
end

-- CTFAmmoPack::PackTouch
function ENT:Think()
	for _, ent in ipairs(ents.FindInSphere(self:WorldSpaceCenter(), PICKUP_RADIUS)) do
		if ent:IsPlayer() and self:MayPickUp(ent) and WS.GiveAmmoFraction(ent, P.DROPPED_PACK.ratio) then
			WS.PlaySoundTo(ent, ent, "AmmoPack.Touch")
			self:Remove()
			return
		end
	end
	self:NextThink(CurTime() + 0.1)
	return true
end
