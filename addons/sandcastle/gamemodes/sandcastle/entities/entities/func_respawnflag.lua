-- func_respawnflag (CFuncRespawnFlagZone, func_respawnflag.cpp): a flag
-- dropped in it, or whose carrier walks into it, goes home at once, as its
-- OnReturn says (mvm_bigrock's death pit, deathpit_resetbomb). Inputs: Enable,
-- Disable.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:KeyValue (key, value)
	local k = string.lower (key)
	self.wsKv = self.wsKv or {}
	self.wsKv [k] = value
	if k == "model" then self.brushModel = value end
end

function ENT:Initialize ()
	if self.brushModel then self:SetModel (self.brushModel) end
	self:SetSolid (SOLID_NONE)
	self:SetNoDraw (true)
	self.enabled = (self.wsKv or {}).startdisabled ~= "1"
end

-- CBaseTrigger::PointIsWithin, on the brush's bounds.
function ENT:PointIsWithin (pos)
	return self:WorldToLocal (pos):WithinAABox (self:OBBMins (), self:OBBMaxs ())
end

-- Whether a move from `from` to `to` ends in or passes through the zone: a
-- carrier falling through a death pit between two thinks still touched it,
-- as TF2's continuous touch would see.
function ENT:Crossed (from, to)
	if self:PointIsWithin (to) then return true end
	return util.IntersectRayWithOBB (from, to - from, self:GetPos (), self:GetAngles (), self:OBBMins (), self:OBBMaxs ()) ~= nil
end

-- CFuncRespawnFlagZone::Touch: a flag whose carrier crossed the zone goes
-- home, firing its own outputs. Whether it did.
function ENT:CarrierCrossed (flag, from, to)
	if not self.enabled or not self:Crossed (from, to) then return false end
	flag:Reset ()
	return true
end

local INPUTS =
{
	enable = true,
	disable = false
}

function ENT:AcceptInput (name, activator, caller, value)
	local enabled = INPUTS [string.lower (name)]
	if enabled == nil then return false end
	self.enabled = enabled
	return true
end
