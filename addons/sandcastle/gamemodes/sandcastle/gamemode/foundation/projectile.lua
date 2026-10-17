-- The projectile system: a Projectile model per projectile entity, holding
-- its variant's state and the rules every projectile shares: an optional
-- lifetime (config.lifetime seconds, then EXPIRE), and that it detonates or
-- expires only once.
--
-- A variant is a part (foundation.projectile.<name>) providing GRAVITY (0
-- flies straight; above 0, ballistic with that gravity scale),
-- NewState(config, now), OnTouch(state, other) -> outcome and
-- Tick(state, now) -> outcome. `other` is what the binding saw it touch:
-- { world, enemy }, enemy meaning damageable and hostile.
local setmetatable = setmetatable
module(...)

NONE, DETONATE, BOUNCE, EXPIRE = "none", "detonate", "bounce", "expire"

local Projectile = {}
Projectile.__index = Projectile

function New(variant, config, now)
	local expireAt = nil
	if config.lifetime then expireAt = now + config.lifetime end
	return setmetatable({
		variant = variant,
		state = variant.NewState(config, now),
		expireAt = expireAt,
		finished = false,
	}, Projectile)
end

function Projectile:Gravity() return self.variant.GRAVITY end
function Projectile:IsFinished() return self.finished end

local function Finish(self, outcome)
	if outcome == DETONATE or outcome == EXPIRE then self.finished = true end
	return outcome
end

function Projectile:Touch(other)
	if self.finished then return NONE end
	return Finish(self, self.variant.OnTouch(self.state, other))
end

-- The variant's own timing (a fuse) comes before the lifetime.
function Projectile:Tick(now)
	if self.finished then return NONE end
	local outcome = self.variant.Tick(self.state, now)
	if outcome == NONE and self.expireAt and now >= self.expireAt then outcome = EXPIRE end
	return Finish(self, outcome)
end
