-- wheel_of_doom (CWheelOfDoom): the Wheel of Fate, a binding to a
-- foundation.holiday.wheel model through the wheel controller. Keyvalues
-- effect_duration and has_spiral; inputs Spin and ClearAllEffects (Kill and
-- AddOutput are the engine's); outputs OnEffectApplied and OnEffectExpired.
-- Its screen (buff_plane.mdl) is hidden until a spin; with has_spiral a
-- spiral (wof_plane2.mdl, CWheelOfDoomSpiral) grows behind it while it
-- spins, at 0.55 of its size a second, and shrinks away after.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

local MODEL = "foundation.holiday.wheel"
local SPIRAL_RATE = 0.55 -- WHEEL_SPIRAL_GROW_RATE and _SHRINK_RATE, of full size a second
local SPIRAL_FULL = 1
local SPIRAL_NOT_SOLID = "0" -- prop_dynamic's solid keyvalue: none

-- Keyvalues read as atof and atoi do: a non-number is 0.
local NUMBER_FALLBACK = 0

local function Number(value)
	return tonumber(value) or NUMBER_FALLBACK
end

function ENT:KeyValue(key, value)
	self.kv = self.kv or {}
	self.kv[string.lower(key)] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	local kv = self.kv or {}
	local Wheel = WS.require(MODEL)
	self:SetModel(Wheel.MODEL)
	self:SetSolid(SOLID_BBOX)
	self:AddSolidFlags(FSOLID_NOT_SOLID)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetNoDraw(true)
	self.wheels = WS.Feature("wheel")
	self.wheel = self.wheels:Bind(self, {
		duration = Number(kv.effect_duration),
		hasSpiral = Number(kv.has_spiral) ~= 0,
	})
	if self.wheel.hasSpiral then self:MakeSpiral(Wheel.SPIRAL_MODEL) end
end

function ENT:MakeSpiral(model)
	local spiral = ents.Create("prop_dynamic")
	spiral:SetModel(model)
	spiral:SetKeyValue("solid", SPIRAL_NOT_SOLID)
	spiral:SetPos(self:GetPos())
	spiral:SetAngles(self:GetAngles())
	spiral:SetParent(self)
	spiral:Spawn()
	spiral:SetModelScale(0)
	spiral:SetNoDraw(true)
	self:DeleteOnRemove(spiral)
	self.spiral = spiral
end

-- GrowAndBecomeVisible and ShrinkAndHide: the engine eases the scale.
function ENT:GrowSpiral()
	local spiral = self.spiral
	if not IsValid(spiral) then return end
	spiral:SetNoDraw(false)
	spiral:SetModelScale(SPIRAL_FULL, (SPIRAL_FULL - spiral:GetModelScale()) / SPIRAL_RATE)
end

function ENT:ShrinkSpiral()
	local spiral = self.spiral
	if not IsValid(spiral) then return end
	local seconds = spiral:GetModelScale() / SPIRAL_RATE
	spiral:SetModelScale(0, seconds)
	timer.Simple(seconds, function()
		if IsValid(spiral) and spiral:GetModelScale() == 0 then spiral:SetNoDraw(true) end
	end)
end

function ENT:OnRemove()
	self.wheels:Unbind(self)
end

function ENT:AcceptInput(name, activator, caller, value)
	local Wheel = WS.require(MODEL)
	local input = string.lower(name)
	if input ~= Wheel.INPUT_SPIN and input ~= Wheel.INPUT_CLEAR then return false end
	self.wheels:Input(self, input)
	return true
end
