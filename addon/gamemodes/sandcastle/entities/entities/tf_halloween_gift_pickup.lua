-- tf_halloween_gift_pickup (CHalloweenGiftPickup): a binding to a
-- foundation.holiday.gift model through the holiday controller, which
-- creates it with Configure{ player, lifetime } before Spawn. Only its
-- player is sent the entity, and only that player can take it; taking it
-- plays the pickup effects and gives nothing. Unclaimed, it is hidden from
-- everyone when it despawns and removed when the model says.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local THINK_INTERVAL = 0.1

-- CItem's trigger box.
local TOUCH_MINS, TOUCH_MAXS = Vector(-16, -16, 0), Vector(16, 16, 24)

function ENT:Configure(config)
	self.configured = config
end

function ENT:Initialize()
	self.system = WETSAND.require("foundation.holiday.gift")
	self.gift = WETSAND.Feature("holiday"):BindGift(self, self.configured)
	self:SetModel(self.system.MODEL)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionBounds(TOUCH_MINS, TOUCH_MAXS)
	self:SetTrigger(true)
	self:AddSolidFlags(FSOLID_NOT_SOLID)
	self:ResetSequence(self:LookupSequence("idle"))
	self:ShowOnlyTo(self.gift:Target())
end

-- CHalloweenGiftPickup::ShouldDraw, done by not sending it: every player
-- but the target, joiners included, is left out; nobody after it despawns.
function ENT:ShowOnlyTo(target)
	for _, ply in ipairs(player.GetAll()) do
		self:SetPreventTransmit(ply, ply ~= target)
	end
end

-- CItem::ItemTouch with SF_NORESPAWN: taken, then gone.
function ENT:Touch(other)
	if not (other:IsPlayer() and self.gift:Touch(other)) then return end
	ParticleEffect(self.system.TAKE_PARTICLE, self:GetPos(), angle_zero)
	for _, sound in ipairs(self.system.TAKE_SOUNDS) do WETSAND.PlaySoundTo(other, self, sound) end
	self:Remove()
end

function ENT:Think()
	local result = self.gift:Tick(CurTime())
	if result == self.system.REMOVE then
		self:Remove()
		return
	end
	self:ShowOnlyTo(self.gift:Target())
	self:NextThink(CurTime() + THINK_INTERVAL)
	return true
end
