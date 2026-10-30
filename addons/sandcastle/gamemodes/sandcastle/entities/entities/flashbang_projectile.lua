-- flashbang_projectile: CS:S's flashbang, thrown. Every player who can see
-- it is blinded white for as long as gameplay.css_weapons' FlashBlind
-- says (how near, how they face it), their ears ringing when it is long.
-- Bot soldiers' vision is their own and does not go white.
AddCSLuaFile()

local Css = gameplay.css_weapons

ENT.Base = "base_css_grenade"
ENT.CSSClass = "weapon_flashbang"
ENT.Model = "models/weapons/w_eq_flashbang_thrown.mdl"
ENT.BounceSound = "Flashbang.Bounce"

local WHITE = Color(255, 255, 255, 255)
local FADE = 1.5 -- the fade out is this many times the blindness
local RINGING, RING_DSP = 1, 35 -- seconds of blindness from which the ears ring, and the ringing's DSP

function ENT:Detonate()
	local grenade, pos = self:Grenade(), self:GetPos()
	self:EmitSound("Flashbang.Explode")
	for _, ply in ipairs(player.GetAll()) do
		local eye = ply:EyePos()
		local distance = eye:Distance(pos)
		if ply:Alive() and distance < grenade.radius then
			local tr = util.TraceLine({ start = pos, endpos = eye, mask = MASK_OPAQUE, filter = self })
			if not tr.Hit then
				local toward = (pos - eye):GetNormalized()
				local seconds = Css.FlashBlind(grenade, distance, ply:GetAimVector():Dot(toward))
				if seconds > 0 then
					ply:ScreenFade(SCREENFADE.IN, WHITE, seconds * FADE, seconds)
					if seconds >= RINGING then ply:SetDSP(RING_DSP, false) end
				end
			end
		end
	end
	self:Remove()
end
