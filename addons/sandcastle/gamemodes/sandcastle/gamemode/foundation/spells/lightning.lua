-- Lightning (CTFProjectile_SpellLightningOrb): a slow orb that passes
-- through everything but the world, which it bounces off, for 5 s. Every
-- 0.2 s it pulls enemies within 200 towards itself; every 0.25-0.35 s it
-- zaps 2 of them for 20 burn damage; at the end it zaps up to 16.
local require = require
local Teams = require("games.gameplay.teams")
local Spells = require("foundation.spells")
local SpellSet = require("foundation.spells.halloween")
local ipairs, min = ipairs, math.min
module(...)

INDEX = SpellSet.SPELL_LIGHTNING
PROJECTILE = "tf_projectile_lightningorb"
LIFETIME = 5 -- ExplodeAndRemoveThink
FLIGHT = { fuse = LIFETIME }

RADIUS = 200
DAMAGE = 20
FIRST_ZAP = 0.25
ZAP_INTERVAL_MIN, ZAP_INTERVAL_MAX = 0.25, 0.35
ZAPS = 2
FINAL_ZAPS = 16
ZAP_CANDIDATES = 5 -- ZapThink's pListOfEntities[5]
VORTEX_INTERVAL = 0.2
PULL = 2 -- ( vecTargetPos - vecSourcePos ) * 2
PULL_LIFT = 50
GROUND_LIFT = 150
ZAP_SOUND = "TFPlayer.MedicChargedDeath"
SOUND = "Halloween.spell_lightning_impact"
HIT = {
	[Teams.RED] = "spell_lightningball_hit_red",
	[Teams.BLUE] = "spell_lightningball_hit_blue",
}
BURST = {
	[Teams.RED] = "drg_cow_explosioncore_charged",
	[Teams.BLUE] = "drg_cow_explosioncore_charged_blue",
}

USE = {
	kind = Spells.USE_ATTACK,
	range = SpellSet.PROJECTILE_SPEED * SpellSet.Definition(INDEX).speedScale * LIFETIME,
	radius = RADIUS,
	needsLineOfSight = true,
	selfOnly = false,
}

function Cast(caster)
	SpellSet.CastWheel(caster)
	return SpellSet.Toss(caster, _M)
end

function NewShot(class, config, now)
	return {
		nextZap = now + FIRST_ZAP,
		nextVortex = now + VORTEX_INTERVAL,
	}
end

-- Zap: of the first ZAP_CANDIDATES found, shuffled, up to `count` living
-- enemies of the caster in sight (not phased or invulnerable) take a beam.
local function Zap(caster, where, count)
	local owner = caster:Owner()
	local found = caster:EntitiesInSphere(where.position, RADIUS)
	local list = {}
	for i = 1, min(#found, ZAP_CANDIDATES) do list[i] = found[i] end
	for i = #list, 2, -1 do
		local j = caster:RandomInt(1, i)
		list[i], list[j] = list[j], list[i]
	end
	local hits = 0
	for _, target in ipairs(list) do
		if hits >= count then break end
		if caster:IsAlive(target) and caster:TeamOf(target) ~= caster:TeamOf(owner)
			and caster:IsVisible(where.position, caster:Origin(target)) and not SpellSet.Spared(caster, target) then
			caster:Tracer(HIT[where.team], where.position, caster:EyePosition(target))
			caster:Damage(target, DAMAGE, SpellSet.DMG_BURN, where.projectile)
			hits = hits + 1
		end
	end
	if hits > 0 then caster:EmitSound(ZAP_SOUND) end
end

-- VortexThink: enemies in sight are drawn in, lifted off the ground.
local function Vortex(caster, where)
	for _, target in ipairs(caster:EntitiesInSphere(where.position, RADIUS)) do
		if caster:TeamOf(target) ~= where.team and caster:IsVisible(where.position, caster:Origin(target)) then
			local velocity = (where.position - caster:Origin(target)) * PULL + caster:Vector(0, 0, PULL_LIFT)
			if caster:IsOnGround(target) then velocity = velocity + caster:Vector(0, 0, GROUND_LIFT) end
			caster:SetVelocity(target, velocity)
		end
	end
end

function Tick(caster, state, where, now)
	if now >= state.nextVortex then
		Vortex(caster, where)
		state.nextVortex = now + VORTEX_INTERVAL
	end
	if now >= state.nextZap then
		Zap(caster, where, ZAPS)
		state.nextZap = now + caster:RandomFloat(ZAP_INTERVAL_MIN, ZAP_INTERVAL_MAX)
	end
	return nil
end

-- ExplodeAndRemove, at the end of its life.
function Impact(caster, impact)
	caster:Particle(BURST[impact.team], impact.position)
	caster:EmitSound(SOUND, impact.projectile)
	Zap(caster, impact, FINAL_ZAPS)
end
