-- tf_pumpkin_bomb (CTFPumpkinBomb): a binding to a
-- foundation.hazards.pumpkin_bomb model through the hazards controller. A
-- map's pumpkin reads no keyvalues (TF2 ignores the FGD's). The MIRV spell
-- makes team pumpkins: ents.Create("tf_pumpkin_bomb"), then
-- Configure{ scale, damage, radius, team, lifetime, isSpell } before Spawn.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local VARIANT = "foundation.hazards.pumpkin_bomb"
local THINK_INTERVAL = 0.1 -- for a team pumpkin's lifetime

function ENT:Configure(config)
	self.configured = config
end

function ENT:Initialize()
	self.hazards = WS.Feature("hazards")
	self.hazard = self.hazards:Bind(self, VARIANT, self.configured or {})
end

function ENT:OnRemove()
	self.hazards:Unbind(self)
end

-- The team the combat controller sees: HALLOWEEN's, or a spell's caster's.
function ENT:GetTeamNumber()
	return self.hazard:Team()
end

function ENT:OnTakeDamage(dmg)
	self.hazards:Damaged(self, dmg)
end

function ENT:Touch(other)
	self.hazards:Touched(self, other)
end

function ENT:Think()
	self.hazards:Think(self)
	self:NextThink(CurTime() + THINK_INTERVAL)
	return true
end
