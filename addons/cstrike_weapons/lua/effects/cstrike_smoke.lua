local MATERIAL = "particle/particle_smokegrenade"
local PUFFS = 60
local PUFF_SIZE, PUFF_GROWN = 60, 140
local FADE = 3

function EFFECT:Init(data)
	local pos = data:GetOrigin()
	local radius = data:GetScale()
	local duration = data:GetMagnitude()
	local emitter = ParticleEmitter(pos)

	for _ = 1, PUFFS do
		local particle = emitter:Add(MATERIAL, pos + VectorRand() * 8)
		if particle then
			local direction = VectorRand()
			direction.z = math.abs(direction.z) * 0.5
			particle:SetVelocity(direction * radius * math.Rand(0.5, 1))
			particle:SetAirResistance(100)
			particle:SetCollide(true)
			particle:SetBounce(0.2)
			particle:SetDieTime(duration + math.Rand(0, FADE))
			particle:SetStartAlpha(255)
			particle:SetEndAlpha(0)
			particle:SetStartSize(PUFF_SIZE)
			particle:SetEndSize(PUFF_GROWN)
			particle:SetRoll(math.Rand(0, 360))
			particle:SetRollDelta(math.Rand(-0.2, 0.2))
			local shade = math.random(150, 190)
			particle:SetColor(shade, shade, shade)
		end
	end

	emitter:Finish()
end

function EFFECT:Think()
	return false
end

function EFFECT:Render()
end
