-- The pumpkin bomb (CTFPumpkinBomb, tf_pumpkin_bomb.cpp): a pumpkin with 1
-- health that blows up when hurt. A map's pumpkin is HALLOWEEN's, and
-- anyone's damage sets it off as the attacker's team. A team pumpkin (the
-- MIRV spell drops them) explodes only for its own team; anything else, its
-- lifetime, or trigger_hurt melts it into goop.
--
-- Config (SetInitParams): { scale, damage, radius, team, lifetime, isSpell },
-- every field optional; a map's pumpkin sets none, since the C++ reads no
-- keyvalues. isSpell only picks TF2's kill icon, which GMod lacks.
local require = require
local Hazards = require("foundation.hazards")
local Teams = require("games.gameplay.teams")
module(...)

MODEL = "models/props_halloween/pumpkin_explode.mdl"
TEAM_MODEL = "models/props_halloween/pumpkin_explode_teamcolor.mdl"

-- CTFPumpkinBomb::CTFPumpkinBomb
TEAM = Teams.HALLOWEEN
DAMAGE = 150
RADIUS = 300
SCALE = 1
HEALTH = 1

-- PumpkinTouch: a projectile touching the pumpkin hits it for 10 (DMG_CRUSH).
PROJECTILE_TOUCH_DAMAGE = 10

EXPLODE_PARTICLE = "pumpkin_explode"
EXPLODE_SOUND = "Halloween.PumpkinExplode" -- TE_TFExplosion's, for TF_WEAPON_PUMPKIN_BOMB
GOOP_RED, GOOP_BLUE = "spell_pumpkin_mirv_goop_red", "spell_pumpkin_mirv_goop_blue"

-- The team model's skins are "opposite of what you'd think so Blue team can
-- Hurt Blue Pumpkins"; the map model has one.
SKIN_HALLOWEEN, SKIN_RED, SKIN_BLUE = 0, 1, 2

function NewState(config, now)
	local expireAt = nil
	if config.lifetime and config.lifetime > 0 then expireAt = now + config.lifetime end
	return {
		team = config.team or TEAM,
		damage = config.damage or DAMAGE,
		radius = config.radius or RADIUS,
		scale = config.scale or SCALE,
		health = HEALTH,
		expireAt = expireAt,
	}
end

local function IsTeamPumpkin(state)
	return state.team ~= Teams.HALLOWEEN
end

-- RemovePumpkin's and OnTakeDamage's goop: RED's, or BLU's for any other.
local function Goop(state)
	if state.team == Teams.RED then return GOOP_RED end
	return GOOP_BLUE
end

function Team(state) return state.team end

function Body(state)
	if not IsTeamPumpkin(state) then
		return {
			model = MODEL,
			skin = SKIN_HALLOWEEN,
			scale = state.scale,
			move = Hazards.MOVE_PHYSICS,
		}
	end
	return {
		model = TEAM_MODEL,
		skin = state.team == Teams.BLUE and SKIN_BLUE or SKIN_RED,
		scale = state.scale,
		move = Hazards.MOVE_TOSS,
	}
end

-- Event_Killed: the blast is the attacker's, as its team.
local function Explosion(state, team)
	local particles = {}
	if IsTeamPumpkin(state) then particles[#particles + 1] = Goop(state) end
	particles[#particles + 1] = EXPLODE_PARTICLE
	return Hazards.Explode({
		team = team,
		damage = state.damage,
		radius = state.radius,
		halfFalloff = true,
		forceFriendlyFire = false,
		particles = particles,
		sound = EXPLODE_SOUND,
		attachment = nil,
		gibs = true,
		output = nil,
		activatorIsAttacker = false,
	})
end

local function Melt(state)
	return Hazards.Fizzle({ Goop(state) })
end

-- OnTakeDamage: its own team's damage always kills; any other team's melts
-- a team pumpkin and kills a map pumpkin.
function OnDamaged(state, damage)
	if damage.team == state.team then
		state.health = HEALTH
	elseif IsTeamPumpkin(state) then
		return Melt(state)
	end
	state.health = Hazards.TakeHealth(state.health, damage.amount)
	if state.health > 0 then return Hazards.Nothing end
	return Explosion(state, damage.team)
end

-- PumpkinTouch
function OnTouch(state, toucher)
	if toucher.leaving then return Hazards.Nothing end
	if toucher.projectile then
		if IsTeamPumpkin(state) and toucher.team ~= state.team then return Melt(state) end
		return OnDamaged(state, {
			team = toucher.team,
			amount = PROJECTILE_TOUCH_DAMAGE,
		})
	end
	if toucher.triggerHurt then return Melt(state) end
	return Hazards.Nothing
end

-- The RemovePumpkin think, when SetInitParams gave a lifetime.
function Tick(state, now)
	if state.expireAt and now >= state.expireAt then return Melt(state) end
	return Hazards.Nothing
end
