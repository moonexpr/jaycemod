-- func_respawnflag (CFuncRespawnFlagZone, func_respawnflag.cpp): a flag
-- dropped in it, or whose carrier walks into it, goes home at once, as its
-- OnReturn says (mvm_bigrock's death pit, deathpit_resetbomb). A binding to
-- the flag controller, which checks its flags each think. Inputs: Enable,
-- Disable.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wsKv = self.wsKv or {}
	self.wsKv[k] = value
	if k == "model" then self.brushModel = value end
end

function ENT:Initialize()
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetSolid(SOLID_NONE)
	self:SetNoDraw(true)
	self.flag = WS.Feature("flag")
	self.flag:BindResetZone(self, { disabled = (self.wsKv or {}).startdisabled == "1" })
end

function ENT:OnRemove()
	self.flag:UnbindResetZone(self)
end

-- CBaseTrigger::PointIsWithin, on the brush's bounds.
function ENT:PointIsWithin(pos)
	return self:WorldToLocal(pos):WithinAABox(self:OBBMins(), self:OBBMaxs())
end

-- Whether a move from `from` to `to` ends in or passes through the zone: a
-- carrier falling through a death pit between two thinks still touched it,
-- as TF2's continuous touch would see.
function ENT:Crossed(from, to)
	if self:PointIsWithin(to) then return true end
	return util.IntersectRayWithOBB(from, to - from, self:GetPos(), self:GetAngles(), self:OBBMins(), self:OBBMaxs()) ~= nil
end

function ENT:AcceptInput(name, activator, caller, value)
	return self.flag:ResetZoneInput(self, string.lower(name))
end
