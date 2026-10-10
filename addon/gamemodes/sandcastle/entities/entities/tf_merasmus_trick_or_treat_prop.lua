-- tf_merasmus_trick_or_treat_prop (CTFMerasmusTrickOrTreatProp): a prop
-- Merasmus may be hiding in, which he spawns as he hides; no map places one.
-- Its rules are foundation.npc.merasmus's: a player's blast destroys it at
-- once (PropDamage), and when it breaks it bursts, drops an ammo pack and
-- tells Merasmus, whose hiding action decides whether he was in it. A
-- player touching it is his business too (a bomb head blows it up). It goes
-- when he does.
--
-- Configure{ boss, model, yaw, health } before Spawn.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local TOUCH_INTERVAL = 0.1
local TOUCH_MARGIN = 2 -- how near a player's box must come to touch it
local LOOT_CLASS = "tf_ammo_pack"

function ENT:Configure(config)
	self.configured = config
end

function ENT:Initialize()
	local config = self.configured
	self.boss = config.boss
	self.rules = WS.require("foundation.npc.merasmus")
	self:SetModel(config.model)
	self:SetAngles(Angle(0, config.yaw, 0))
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_NONE)
	self:GetPhysicsObject():EnableMotion(false)
	self:SetMaxHealth(config.health)
	self:SetHealth(config.health)
	ParticleEffect(self.rules.PROP_PARTICLE, self:WorldSpaceCenter(), self:GetAngles())
	self.boss:DeleteOnRemove(self)
	self:NextThink(CurTime())
end

-- Event_Killed: a burst, an ammo pack, then Merasmus hears of it.
function ENT:BurstOpen(attacker)
	self.broken = true
	local center = self:WorldSpaceCenter()
	ParticleEffect(self.rules.PROP_PARTICLE, center, self:GetAngles())
	self:EmitSound(self.rules.PROP_SOUND)
	local loot = ents.Create(LOOT_CLASS)
	loot:SetPos(center)
	loot:Spawn()
	loot:SetModelScale(self.rules.PROP_LOOT_MODEL_SCALE)
	self.boss:OnPropKilled(self, attacker)
	self:Remove()
end

function ENT:OnTakeDamage(dmg)
	if self.broken then return 0 end
	ParticleEffect(self.rules.BLOOD_PARTICLE, dmg:GetDamagePosition(), self:GetAngles())
	local attacker = dmg:GetAttacker()
	local playerBlast = IsValid(attacker) and attacker:IsPlayer() and dmg:IsDamageType(DMG_BLAST)
	local amount = self.rules.PropDamage(dmg:GetDamage(), playerBlast, self:Health())
	self:SetHealth(self:Health() - amount)
	if self:Health() <= 0 then self:BurstOpen(attacker) end
	return amount
end

-- Touch: a static physics prop reports no touches, so players against its
-- box are found each tenth of a second.
function ENT:Think()
	local mins, maxs = self:WorldSpaceAABB()
	local margin = Vector(TOUCH_MARGIN, TOUCH_MARGIN, TOUCH_MARGIN)
	for _, ent in ipairs(ents.FindInBox(mins - margin, maxs + margin)) do
		if self.broken then break end
		if ent:IsPlayer() and ent:Alive() then self.boss:OnPropTouched(self, ent) end
	end
	self:NextThink(CurTime() + TOUCH_INTERVAL)
	return true
end
