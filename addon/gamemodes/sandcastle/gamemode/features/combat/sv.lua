-- The combat feature's controller. It binds projectile entities to
-- foundation.projectile models, fires weapon mimics' projectiles
-- (foundation.combat.weapon_mimic), runs foundation.combat Explosions against
-- the world, and answers the side questions the combatant port asks: an
-- entity's team, and whether it stands in a respawn room. The rules live in
-- the models; this file only finds entities, traces, and deals damage.
local Combat = WETSAND.require("foundation.combat")
local Projectile = WETSAND.require("foundation.projectile")

-- MASK_RADIUS_DAMAGE (tf_gamerules.cpp): what stops a blast.
local BLAST_MASK = bit.band(MASK_SHOT, bit.bnot(CONTENTS_HITBOX))

local WEAPON_MIMIC = "foundation.combat.weapon_mimic"

local Controller = {}

-- The model for a wetsand_projectile entity; its variant is a
-- foundation.projectile part.
function Controller:BindProjectile(ent, variantName, config)
	return Projectile.New(WETSAND.require(variantName), config, CurTime())
end

-- tf_point_weapon_mimic: config from its keyvalues (see
-- foundation.combat.weapon_mimic). The first mimic loads the model.
function Controller:BindWeaponMimic(ent, config)
	return WETSAND.require(WEAPON_MIMIC).New(config)
end

-- CTFPointWeaponMimic::Fire, count times: each projectile leaves the
-- mimic's origin, credited to the mimic and never hitting it.
function Controller:FireWeaponMimic(ent, mimic, count)
	local angles = ent:GetAngles()
	local aim = {
		forward = angles:Forward(),
		right = angles:Right(),
		up = angles:Up(),
	}
	for _ = 1, count do
		local shot = mimic:Shot(aim, math.Rand, math.random)
		local config = shot.config
		config.attacker = ent
		config.launcher = ent
		if config.spin then config.spin = Angle(config.spin.x, config.spin.y, config.spin.z) end
		local projectile = ents.Create(shot.class)
		projectile:SetPos(ent:GetPos())
		projectile:SetAngles(config.velocity:Angle())
		projectile:Configure(config)
		projectile:Spawn()
	end
end

-- A player's team; an entity that takes sides reports its own through
-- GetTeamNumber (wetsand_combat_nextbot does); anything else has none.
function Controller:TeamOf(ent)
	if ent:IsPlayer() then return ent:Team() end
	if ent.GetTeamNumber then return ent:GetTeamNumber() end
	return WETSAND.TEAM_UNASSIGNED
end

-- Whether ent's centre is inside an active func_respawnroom of any team.
-- TF2's NPCs skip victims on spawn-room nav areas (TF_NAV_SPAWN_ROOM_RED or
-- _BLUE); GMod's nav areas carry no such attribute, so the rooms stand in.
function Controller:InRespawnRoom(ent)
	local point = ent:WorldSpaceCenter()
	for _, room in ipairs(ents.FindByClass("func_respawnroom")) do
		if room.active and room:PointIsWithin(point) then return true end
	end
	return false
end

-- CTFRadiusDamageInfo::ApplyToEntity's trace: players and the thing that
-- blew up do not block the blast; the victim itself does not count.
local function BlastReaches(origin, ent, inflictor)
	local tr = util.TraceLine({
		start = origin,
		endpos = ent:WorldSpaceCenter(),
		mask = BLAST_MASK,
		filter = function(hit) return hit ~= inflictor and not hit:IsPlayer() end,
	})
	return tr.Fraction == 1 or tr.Entity == ent
end

-- Source's DMG_CRITICAL is DMG_ACID's bit.
local function Deal(ent, amount, config, attacker, inflictor)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(config.crit and bit.bor(DMG_BLAST, DMG_ACID) or DMG_BLAST)
	dmg:SetAttacker(attacker)
	dmg:SetInflictor(inflictor)
	dmg:SetDamagePosition(config.origin)
	ent:TakeDamageInfo(dmg)
end

-- CTFGameRules::RadiusDamage: every entity whose bounds reach into the
-- radius gets what the Explosion says. Besides the Explosion's fields,
-- config may name the inflictor (default the attacker; it never hurts
-- itself) and the enemy a projectile hit directly (taking full damage). An
-- attacker that is gone, or none, is the world.
function Controller:Explode(config)
	local explosion = Combat.Explosion.New(config)
	local origin, radius = config.origin, config.radius
	local attacker = IsValid(config.attacker) and config.attacker or game.GetWorld()
	local inflictor = IsValid(config.inflictor) and config.inflictor or attacker
	for _, ent in ipairs(ents.FindInSphere(origin, radius)) do
		-- CEntitySphereQuery tests boxes, so RadiusDamage checks the
		-- nearest point too.
		if ent ~= inflictor and ent:NearestPoint(origin):Distance(origin) <= radius then
			local amount = explosion:DamageTo({
				team = self:TeamOf(ent),
				isAttacker = ent == attacker,
				distance = explosion:DistanceTo(ent:WorldSpaceCenter(), ent:GetPos(), ent == config.enemy),
				visible = BlastReaches(origin, ent, inflictor),
			})
			if amount then Deal(ent, amount, config, attacker, inflictor) end
		end
	end
end

return Controller
