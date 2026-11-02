local FLASH = Material("sprites/light_glow02_add")

function EFFECT:Init(data)
	local pos = data:GetOrigin()
	local duration = data:GetScale()

	if duration > 0 then
		if CStrikeFlashbang then CStrikeFlashbang.Apply(duration) end
		return
	end

	local emitter = ParticleEmitter(pos, true)
	for _ = 1, 16 do
		local direction = VectorRand()
		local particle = emitter:Add(FLASH, pos + direction * 4)
		if particle then
			particle:SetVelocity(direction * math.Rand(80, 180))
			particle:SetDieTime(math.Rand(0.12, 0.3))
			particle:SetStartAlpha(255)
			particle:SetEndAlpha(0)
			particle:SetStartSize(math.Rand(12, 24))
			particle:SetEndSize(0)
			particle:SetColor(255, 255, 255)
		end
	end
	emitter:Finish()
end

function EFFECT:Think()
	return false
end

function EFFECT:Render()
end
