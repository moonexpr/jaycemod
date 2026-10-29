-- func_hostage_rescue (CS:S): a hostage rescue zone, a brush the hostage
-- controller reads as a box (features/hostage/sv.lua's RescueBoxes); a
-- hostage led into it is rescued. It does nothing itself, and nothing
-- collides with it.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:Initialize()
	self:SetSolid(SOLID_BBOX)
	self:SetNotSolid(true)
	self:SetTrigger(false)
end
