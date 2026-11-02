local SMOKE = "particle/particle_smokegrenade"
local FLARE = Material("sprites/light_glow02_add")

function EFFECT:Init(data)
	local pos = data:GetOrigin()
	local radius = math.max(data:GetScale(), 1)
	local emitter = ParticleEmitter(pos, true)

	for _ = 1, 24 do
		local direction = VectorRand():GetNormalized()
		local particle = emitter:Add(FLARE, pos + direction * 6)
		if particle then
			particle:SetVelocity(direction * math.Rand(180, 420))
			particle:SetDieTime(math.Rand(0.2, 0.6))
			particle:SetStartAlpha(255)
			particle:SetEndAlpha(0)
			particle:SetStartSize(math.Rand(18, 38))
			particle:SetEndSize(0)
			particle:SetColor(255, math.random(120, 210), 45)
		end
	end

	for _ = 1, 18 do
		local direction = VectorRand()
		local particle = emitter:Add(SMOKE, pos + direction * 8)
		if particle then
			particle:SetVelocity(direction * radius * math.Rand(0.2, 0.5) + Vector(0, 0, 70))
			particle:SetAirResistance(100)
			particle:SetDieTime(math.Rand(0.8, 1.6))
			particle:SetStartAlpha(210)
			particle:SetEndAlpha(0)
			particle:SetStartSize(math.Rand(24, 48))
			particle:SetEndSize(math.Rand(70, 120))
			particle:SetColor(105, 100, 95)
			particle:SetRoll(math.Rand(0, 360))
			particle:SetRollDelta(math.Rand(-0.3, 0.3))
		end
	end

	emitter:Finish()
end

function EFFECT:Think()
	return false
end

function EFFECT:Render()
end
