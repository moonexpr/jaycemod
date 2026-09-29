-- The generic bomb (CTFGenericBomb, tf_generic_bomb.cpp): a mapper's prop
-- with health that blows up when it dies or on Detonate, then fires
-- OnDetonate. plr_hacksaw_event's skulls count toward a math_counter and
-- make the shooter cheer; pl_breadspace's spawn templates.
--
-- Config, from its keyvalues: { damage, radius, health, explodeParticle,
-- sound, friendlyFire, passActivator, team, model, skin, scale }. An empty
-- explodeParticle or sound is none.
local require = require
local Hazards = require("foundation.hazards")
module(...)

-- EWhoToDamage, the friendlyfire keyvalue
DAMAGE_ATTACKER_AND_ATTACKER_ENEMIES, DAMAGE_EVERYONE = 0, 1

INPUT_DETONATE = "detonate"
INPUTS = { [INPUT_DETONATE] = true }
OUTPUT_DETONATE = "OnDetonate"
EXPLODE_ATTACHMENT = "alt-origin" -- where the blast, particle and gibs start

-- GenericTouch: a projectile touching the bomb hits it for 10 (DMG_CRUSH).
PROJECTILE_TOUCH_DAMAGE = 10

-- Event_Killed takes the owner of an attacker that has one (an arrow's).
CREDITS_OWNER = true

local function NoneIfEmpty(s)
	if s == nil or s == "" then return nil end
	return s
end

function NewState(config, now)
	return {
		team = config.team,
		damage = config.damage,
		radius = config.radius,
		health = config.health,
		particle = NoneIfEmpty(config.explodeParticle),
		sound = NoneIfEmpty(config.sound),
		everyone = config.friendlyFire == DAMAGE_EVERYONE,
		passActivator = config.passActivator,
		model = config.model,
		skin = config.skin,
		scale = config.scale,
	}
end

function Team(state) return state.team end

function Body(state)
	return {
		model = state.model,
		skin = state.skin,
		scale = state.scale,
		move = Hazards.MOVE_PHYSICS,
	}
end

-- Event_Killed: the blast takes the attacker's team, or keeps the bomb's
-- own when Detonate gave no attacker.
local function Explosion(state, team)
	return Hazards.Explode({
		team = team,
		damage = state.damage,
		radius = state.radius,
		halfFalloff = true,
		forceFriendlyFire = state.everyone,
		particles = { state.particle },
		sound = state.sound,
		attachment = EXPLODE_ATTACHMENT,
		gibs = true,
		output = OUTPUT_DETONATE,
		activatorIsAttacker = state.passActivator,
	})
end

function OnDamaged(state, damage)
	state.health = Hazards.TakeHealth(state.health, damage.amount)
	if state.health > 0 then return Hazards.Nothing end
	return Explosion(state, damage.team)
end

-- Detonate
function OnInput(state, name, value)
	return Explosion(state, state.team)
end

function OnTouch(state, toucher)
	if toucher.leaving or not toucher.projectile then return Hazards.Nothing end
	return OnDamaged(state, {
		team = toucher.team,
		amount = PROJECTILE_TOUCH_DAMAGE,
	})
end
