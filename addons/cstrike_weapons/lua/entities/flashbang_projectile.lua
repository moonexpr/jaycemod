AddCSLuaFile()

-- flashbang_projectile: CS:S's flashbang, thrown. Every player who can see
-- it is blinded white by its stats and facing, their ears ringing when it
-- is long. Bot soldiers' vision is their own and does not go white.

ENT.Base = "base_cstrike_grenade"
ENT.Model = "models/weapons/w_eq_flashbang_thrown.mdl"
ENT.BounceSound = "Flashbang.Bounce"

local WHITE = Color(255, 255, 255, 255)
local FADE = 1.5 -- the fade out is this many times the blindness
local RINGING, RING_DSP = 1, 35 -- seconds of blindness from which the ears ring, and the ringing's DSP

local function BlindSeconds(radius, blind, distance, facing)
	local near = 1 - math.Clamp(distance / radius, 0, 1)
	local scale = facing >= 0.5 and 1 or facing >= -0.5 and 0.5 or facing >= -1 and 0.2 or 0
	return blind * scale * near
end

function ENT:Detonate()
	local pos = self:GetPos()
	self:EmitSound("Flashbang.Explode")
	for _, ply in ipairs(player.GetAll()) do
		local eye = ply:EyePos()
		local distance = eye:Distance(pos)
		if ply:Alive() and distance < self.GrenadeRadius then
			local tr = util.TraceLine({ start = pos, endpos = eye, mask = MASK_OPAQUE, filter = self })
			if not tr.Hit then
				local toward = (pos - eye):GetNormalized()
				local seconds = BlindSeconds(self.GrenadeRadius, self.GrenadeBlind, distance, ply:GetAimVector():Dot(toward))
				if seconds > 0 then
					ply:ScreenFade(SCREENFADE.IN, WHITE, seconds * FADE, seconds)
					if seconds >= RINGING then ply:SetDSP(RING_DSP, false) end
				end
			end
		end
	end
	self:Remove()
end
