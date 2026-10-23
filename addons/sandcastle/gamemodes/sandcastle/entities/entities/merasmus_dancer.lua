-- merasmus_dancer (CMerasmusDancer): the Merasmus who dances with the
-- players while the Wheel of Fate's Dance lasts. The wheel controller
-- spawns him; he appears in a puff of smoke dancing, and Vanish takes him
-- in another, or BlastOff flies him off first. features.wheel.model
-- holds his model, dance, puff and timing.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false
ENT.AutomaticFrameAdvance = true

if CLIENT then return end

local MODEL = "features.wheel.model"
local STAFF_BODYGROUP = "staff"

function ENT:Initialize()
	local Wheel = WS.require(MODEL)
	self:SetModel(Wheel.DANCER_MODEL)
	self:SetSolid(SOLID_NONE)
	self:SetMoveType(MOVETYPE_NONE)
	self:PlayDance(self:LookupSequence(Wheel.DANCER_SEQUENCE))
	self:Poof()
end

-- PlaySequence and PlayActivity: from the start, the staff away.
function ENT:PlayDance(sequence)
	self:ResetSequence(sequence)
	self:SetCycle(0)
	self:SetPlaybackRate(1)
	self:SetBodygroup(self:FindBodygroupByName(STAFF_BODYGROUP), WS.require(MODEL).DANCER_STAFF)
end

function ENT:Poof()
	local Wheel = WS.require(MODEL)
	ParticleEffect(Wheel.DANCER_POOF_PARTICLE, self:GetPos(), self:GetAngles())
	self:EmitSound(Wheel.DANCER_POOF_SOUND)
end

-- Gone in a puff of smoke, after `seconds`.
function ENT:GoAfter(seconds)
	timer.Simple(seconds, function()
		if not IsValid(self) then return end
		self:Poof()
		self:Remove()
	end)
end

function ENT:Vanish() self:GoAfter(0) end

function ENT:BlastOff()
	self:PlayDance(self:SelectWeightedSequence(ACT_FLY))
	self:GoAfter(WS.require(MODEL).DANCER_BLAST_OFF_TIME)
end

function ENT:Think()
	self:NextThink(CurTime())
	return true
end
