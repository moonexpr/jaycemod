-- The hazards system: a Hazard model per hazard entity (a pumpkin bomb, a
-- generic bomb, a zapper, a croc), turning what happens to it (damage, inputs,
-- touches, time) into outcomes the hazards controller carries out. It holds
-- the rule every hazard shares: once it has exploded or fizzled it is dead,
-- and nothing more happens to it (TF2's m_bDead).
--
-- New(variant, config, now), then:
--   :Damaged{ team, amount }: team is the attacker's;
--   :Input(name, value): name lower-cased;
--   :Touch{ target, team, projectile, triggerHurt, leaving, now }: target
--     is an opaque handle, team the toucher's (a projectile's thrower's),
--     projectile and triggerHurt what it is, leaving an end of touch, now
--     the time of a start of touch;
--   :Tick(now);
-- each returning an outcome, a table whose kind is one of:
--   NONE;
--   EXPLODE { team, damage, radius, halfFalloff, forceFriendlyFire,
--     particles, sound, attachment, gibs, output, activatorIsAttacker }:
--     a blast credited to the attacker, as team; particles and sound play at
--     the named attachment (nil: the origin); output fires with the attacker
--     as activator when activatorIsAttacker, otherwise with the hazard;
--   FIZZLE { particles }: gone without a blast;
--   ZAP { targets, particle }: a beam to each target, nothing more;
--   ANIMATE { model, sequence, target }: a prop of model appears at the
--     target's feet, plays sequence once and is gone at its end;
--   HURT { hits, damage, dmgType }: each hit { target, outputs } takes
--     damage from the hazard, which then fires that hit's outputs with
--     itself as activator.
-- Plus :Team(), :Body(), :Accepts(name) and :CreditsOwner() for the binding.
--
-- A variant is a part (features.hazards.model.<name>) providing
-- NewState(config, now) and Team(state), and any of Body(state) -> { model,
-- skin, scale, move } (absent: a point entity), OnDamaged(state, damage),
-- INPUTS (a table keyed by the input names it takes) with
-- OnInput(state, name, value), OnTouch(state, toucher) and
-- Tick(state, now); an absent handler returns NONE. CREDITS_OWNER true makes
-- the binding credit an attacker's owner (the archer, not the arrow).
local setmetatable = setmetatable
local ceil, floor = math.ceil, math.floor
module(...)

NONE, EXPLODE, FIZZLE, ZAP = "none", "explode", "fizzle", "zap"
ANIMATE, HURT = "animate", "hurt"

-- How a hazard with a body moves: vphysics (MOVETYPE_VPHYSICS), or falling
-- and bouncing (MOVETYPE_FLYGRAVITY with MOVECOLLIDE_FLY_BOUNCE).
MOVE_PHYSICS, MOVE_TOSS = "vphysics", "flygravity"

Nothing = { kind = NONE }

-- fields: EXPLODE's, less kind.
function Explode(fields)
	fields.kind = EXPLODE
	return fields
end

function Fizzle(particles)
	return {
		kind = FIZZLE,
		particles = particles,
	}
end

function Zap(targets, particle)
	return {
		kind = ZAP,
		targets = targets,
		particle = particle,
	}
end

function Animate(model, sequence, target)
	return {
		kind = ANIMATE,
		model = model,
		sequence = sequence,
		target = target,
	}
end

function Hurt(hits, damage, dmgType)
	return {
		kind = HURT,
		hits = hits,
		damage = damage,
		dmgType = dmgType,
	}
end

local Hazard = {}
Hazard.__index = Hazard

function New(variant, config, now)
	return setmetatable({
		variant = variant,
		state = variant.NewState(config, now),
		dead = false,
	}, Hazard)
end

function Hazard:Team() return self.variant.Team(self.state) end
function Hazard:CreditsOwner() return self.variant.CREDITS_OWNER == true end
function Hazard:IsFinished() return self.dead end

function Hazard:Body()
	if self.variant.Body == nil then return nil end
	return self.variant.Body(self.state)
end

-- The variant's handler, unless the hazard is dead or the variant has none.
local function Handle(self, handler, ...)
	if self.dead or handler == nil then return Nothing end
	local outcome = handler(self.state, ...)
	if outcome.kind == EXPLODE or outcome.kind == FIZZLE then self.dead = true end
	return outcome
end

function Hazard:Damaged(damage) return Handle(self, self.variant.OnDamaged, damage) end
function Hazard:Touch(toucher) return Handle(self, self.variant.OnTouch, toucher) end
function Hazard:Tick(now) return Handle(self, self.variant.Tick, now) end

-- Whether the variant takes the input; the engine handles the rest (Kill,
-- AddOutput).
function Hazard:Accepts(name)
	local inputs = self.variant.INPUTS
	return inputs ~= nil and inputs[name] ~= nil
end

function Hazard:Input(name, value)
	if not self:Accepts(name) then return Nothing end
	return Handle(self, self.variant.OnInput, name, value)
end

-- CBaseEntity::OnTakeDamage: health is an integer, so what is left after a
-- hit truncates toward zero; at 0 or below the entity is killed.
function TakeHealth(health, amount)
	local left = health - amount
	if left >= 0 then return floor(left) end
	return ceil(left)
end
