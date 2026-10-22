-- Every hit's friendly fire (mp_friendlyfire 0 spares teammates,
-- Teams.FriendlySpared), its weapon's balance (foundation.combat.weapon_balance:
-- its damage, whether its headshot counts, the shotgun's crit by distance,
-- the crossbow's knockback) and crits (foundation.players' Hit): a
-- crit-boosted attacker, a headshot, a rolled crit or a jarated victim, for
-- players and soldiers alike, by the conditions of both
-- (ws/sv_teams_conditions.lua). A crit is
-- marked DMG_CRITICAL (DMG_ACID's bit, as TF2's), so what reads the damage
-- after knows it. Then the hit is heard and told: a crit or mini-crit
-- sounds from its victim (TFPlayer.CritHit, CritHitMini; CritPain to a
-- player hit), and the attacking player is told its damage
-- (game_combat_text, ws/cl_hits.lua). A crit bullet is seen as one: TF2's
-- crit tracer in its shooter's team colour (foundation.combat.crit_effects).
-- An enemy's hit is remembered, and the environment's lethal one credited
-- to it (ws/sv_kill_credit.lua). One a projectile throws into a wall or
-- ceiling is hurt by the strike, dealt by its thrower, unless it threw
-- itself or a teammate (foundation.combat.impact).
local Balance = WS.require("foundation.combat.weapon_balance")
local BulletSteps = WS.require("foundation.combat.bullet_steps")
local Crit = WS.require("foundation.combat.crit_effects")
local Impact = WS.require("foundation.combat.impact")
local P = WS.PlayerRules
local E = WS.Events

-- Source has no locational damage in TF2: a hit's group only says whether
-- it was a headshot, recorded for the damage the same trace deals this
-- tick (ScalePlayerDamage and ScaleNPCDamage; the AI war's soldiers report
-- theirs from OnTraceAttack, ws/sh_drg_soldier.lua).
local traced = setmetatable({}, { __mode = "k" }) -- entity -> { tick, hitgroup }

function WS.TraceHit(ent, hitgroup)
	traced[ent] = { tick = engine.TickCount(), hitgroup = hitgroup }
end

-- These replace the base gamemode's, which doubles a headshot and quarters
-- a limb.
function GM:ScalePlayerDamage(ply, hitgroup) WS.TraceHit(ply, hitgroup) end
function GM:ScaleNPCDamage(npc, hitgroup) WS.TraceHit(npc, hitgroup) end

local function Headshot(ent)
	local trace = traced[ent]
	traced[ent] = nil
	return trace ~= nil and trace.tick == engine.TickCount() and trace.hitgroup == HITGROUP_HEAD
end

-- What a hit is told for: players, NPCs and NextBots, as TF2 tells hits on
-- players (and buildings), never on props; and what can be credited with
-- a kill (ws/sv_kill_credit.lua).
function WS.Combatant(ent)
	return ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
end
local Combatant = WS.Combatant

-- The hit each victim is taking, from EntityTakeDamage to
-- PostEntityTakeDamage: { kind, class, headshot, credited (the
-- environment's lethal hit, credited to an enemy) }.
local taking = setmetatable({}, { __mode = "k" })

-- The class of what dealt the hit: the projectile or weapon that did, or,
-- for a bullet the attacker fired itself, the weapon it holds.
local function WeaponClass(dmg)
	local inflictor, attacker = dmg:GetInflictor(), dmg:GetAttacker()
	if IsValid(inflictor) and inflictor ~= attacker then return inflictor:GetClass() end
	if not IsValid(attacker) or not attacker.GetActiveWeapon then return nil end
	local weapon = attacker:GetActiveWeapon()
	return IsValid(weapon) and weapon:GetClass() or nil
end

local function Distance(attacker, target)
	if not IsValid(attacker) then return 0 end
	return attacker:GetPos():Distance(target:GetPos())
end

-- One roll per attacker a tick, so a shotgun's pellets crit together.
local rolls = setmetatable({}, { __mode = "k" }) -- attacker -> { tick, roll }

local function Roll(attacker)
	if not IsValid(attacker) then return math.random() end
	local tick, rolled = engine.TickCount(), rolls[attacker]
	if rolled == nil or rolled.tick ~= tick then
		rolled = { tick = tick, roll = math.random() }
		rolls[attacker] = rolled
	end
	return rolled.roll
end

local function Spared(target, attacker)
	-- the world, or an attacker gone, is of no team
	local attackerTeam = IsValid(attacker) and WS.TeamNumber(attacker) or WS.TEAM_UNASSIGNED
	return WS.TeamRules.FriendlySpared(WS.FriendlyFire(), attackerTeam, WS.TeamNumber(target), attacker == target)
end

-- What attacker's hit on target with class (balanced, or nil) does:
-- its damage, whether its headshot counts, and its scale and kind
-- (foundation.players' Hit). shot: { damage, bullet, blast, headshot,
-- critical (marked a crit already) }.
local function Judge(target, attacker, class, shot)
	local damage, headshot, rolled = Balance.Shot(class, {
		damage = shot.damage,
		bullet = shot.bullet,
		blast = shot.blast,
		distance = Distance(attacker, target),
		headshot = shot.headshot,
		roll = Roll(attacker),
	})
	local scale, kind = P.Hit(WS.ConditionsOf(target), WS.ConditionsOf(attacker), CurTime(), {
		blast = shot.blast,
		selfHarm = attacker == target,
		headshot = headshot,
		rolled = rolled,
		critical = shot.critical,
	})
	return damage, headshot, scale, kind
end

-- The victim of the strike being dealt now.
local striking = nil

hook.Add("EntityTakeDamage", "ws_hits", function(target, dmg)
	local attacker = dmg:GetAttacker()
	if Spared(target, attacker) then return true end
	-- a strike is its own hit, of no weapon: it neither throws nor is balanced
	local class = striking ~= target and Balance.Weapon(WeaponClass(dmg)) or nil
	local damage, headshot, scale, kind = Judge(target, attacker, class, {
		damage = dmg:GetDamage(),
		bullet = dmg:IsBulletDamage(),
		blast = dmg:IsDamageType(DMG_BLAST),
		headshot = Headshot(target),
		critical = dmg:IsDamageType(DMG_ACID),
	})
	dmg:SetDamage(damage)
	if scale ~= 1 then dmg:ScaleDamage(scale) end
	if kind == P.HIT_CRIT then dmg:SetDamageType(bit.bor(dmg:GetDamageType(), DMG_ACID)) end
	taking[target] = {
		kind = kind,
		class = class,
		headshot = headshot,
		credited = Combatant(target) and WS.CreditEnvironmentalHit(target, dmg),
	}
end)

-- The way a hit pushes: along its force, or else from its attacker.
local function PushDirection(target, dmg)
	local force = dmg:GetDamageForce()
	if force:LengthSqr() > 0 then return force:GetNormalized() end
	local attacker = dmg:GetAttacker()
	if not IsValid(attacker) then return nil end
	return (target:WorldSpaceCenter() - attacker:WorldSpaceCenter()):GetNormalized()
end

-- The thrown, each until its window ends or it strikes: victim -> { by,
-- ends, velocity (at the last tick) }.
local thrown = setmetatable({}, { __mode = "k" })

local function Velocity(ent)
	return ent.loco and ent.loco:GetVelocity() or ent:GetVelocity()
end

-- victim thrown by attacker is watched for a strike, if it can be hurt by one.
local function Throw(victim, attacker)
	if not IsValid(attacker) then return end
	if not Impact.Harms(WS.TeamNumber(attacker), WS.TeamNumber(victim), attacker == victim) then return end
	thrown[victim] = { by = attacker, ends = CurTime() + Impact.WINDOW, velocity = Velocity(victim) }
end

-- The surface ahead of a victim moving at velocity, struck this tick: a
-- trace of its bounds along where it was going.
local function SurfaceAhead(victim, velocity)
	local pos = victim:GetPos()
	local reach = velocity:Length() * engine.TickInterval() * 2 + 2
	return util.TraceHull({
		start = pos,
		endpos = pos + velocity:GetNormalized() * reach,
		mins = victim:OBBMins(),
		maxs = victim:OBBMaxs(),
		filter = victim,
		mask = MASK_PLAYERSOLID,
	})
end

local function Strike(victim, throw, velocity)
	local before = throw.velocity
	if not Impact.Stopped(before:Length(), velocity:Length()) then return false end
	local tr = SurfaceAhead(victim, before)
	if not tr.Hit or not Impact.Struck(tr.HitNormal.z) then return false end
	local damage = Impact.Damage(Impact.Into(before, tr.HitNormal))
	if damage > 0 and IsValid(throw.by) then
		local strike = DamageInfo()
		strike:SetDamage(damage)
		strike:SetAttacker(throw.by)
		strike:SetInflictor(throw.by)
		strike:SetDamageType(DMG_CRUSH)
		strike:SetDamagePosition(tr.HitPos)
		striking = victim
		victim:TakeDamageInfo(strike)
		striking = nil
	end
	return true
end

hook.Add("Tick", "ws_hits_impact", function()
	if next(thrown) == nil then return end
	local now = CurTime()
	for victim, throw in pairs(thrown) do
		if not IsValid(victim) or victim:Health() <= 0 or now > throw.ends then
			thrown[victim] = nil
		else
			local velocity = Velocity(victim)
			if Strike(victim, throw, velocity) then
				thrown[victim] = nil
			else
				throw.velocity = velocity
			end
		end
	end
end)

-- The crossbow's punch: the victim thrown along the shot and, a player,
-- staggered by a weapon that staggers.
local function KnockBack(target, dmg, hit)
	local push = Balance.Knockback(hit.class, hit.headshot)
	if push == nil or target:Health() <= 0 then return end
	local dir = PushDirection(target, dmg)
	if dir == nil then return end
	local velocity = dir * push.speed + Vector(0, 0, push.lift)
	if target.loco then
		target.loco:Jump()
		target.loco:SetVelocity(target.loco:GetVelocity() + velocity)
	else
		target:SetVelocity(velocity)
	end
	if target:IsPlayer() and push.stagger then WS.StunPlayer(target, push.stagger, push.slow, bit.bor(P.STUN.MOVEMENT, P.STUN.NO_EFFECTS)) end
	Throw(target, dmg:GetAttacker())
end

local HIT_SOUNDS = {
	[P.HIT_CRIT] = "TFPlayer.CritHit",
	[P.HIT_MINICRIT] = "TFPlayer.CritHitMini",
}

-- The top of the victim's bounds.
local function Top(ent)
	return ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z)
end

hook.Add("PostEntityTakeDamage", "ws_hits", function(target, dmg, took)
	local hit = taking[target]
	taking[target] = nil
	if not took or hit == nil or not Combatant(target) then return end
	-- the environment's hit, though credited, is no one's to be told of
	if hit.credited then return end
	WS.RecordDamager(target, dmg:GetAttacker())
	local kind = hit.kind
	KnockBack(target, dmg, hit)
	local sound = HIT_SOUNDS[kind]
	if sound then
		local filter = RecipientFilter()
		filter:AddPAS(target:GetPos())
		if target:IsPlayer() then
			filter:RemovePlayer(target)
			local victim = RecipientFilter()
			victim:AddPlayer(target)
			target:EmitSound("TFPlayer.CritPain", nil, nil, nil, nil, nil, nil, victim)
		end
		target:EmitSound(sound, nil, nil, nil, nil, nil, nil, filter)
	end
	local attacker = dmg:GetAttacker()
	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= target then
		E.Fire("game_combat_text", {
			victim = target,
			amount = dmg:GetDamage(),
			kind = kind,
			pos = Top(target),
		}, attacker)
	end
end)

-- Whether a bullet that traced tr is a crit to see: every bullet of a
-- crit-boosted shooter, hit or miss, and any the hit rules make a crit (a
-- headshot, the shotgun's close crit by the roll its hit takes this tick).
local function CritBullet(attacker, tr, dmginfo)
	if P.CritBoosted(WS.ConditionsOf(attacker), CurTime()) then return true end
	local target = tr.Entity
	if not (IsValid(target) and Combatant(target)) or target == attacker or Spared(target, attacker) then return false end
	local _, _, _, kind = Judge(target, attacker, Balance.Weapon(WeaponClass(dmginfo)), {
		damage = dmginfo:GetDamage(),
		bullet = true,
		blast = false,
		headshot = tr.HitGroup == HITGROUP_HEAD,
		critical = dmginfo:IsDamageType(DMG_ACID),
	})
	return kind == P.HIT_CRIT
end

-- The crit's tracer from the weapon's muzzle (its view model's, to its
-- holder in first person), seen by everyone. A player's shot is predicted,
-- and the server's effects while it runs reach everyone but the shooter
-- (SuppressHostEvents), who would never see its own crits.
local function CritTracer(weapon, attacker, tr)
	local muzzle = IsValid(weapon) and weapon:LookupAttachment("muzzle") or 0
	local host = GetPredictionPlayer()
	if IsValid(host) then SuppressHostEvents(NULL) end
	util.ParticleTracerEx(Crit.Tracer(WS.TeamNumber(attacker)), tr.StartPos, tr.HitPos, true,
		IsValid(weapon) and weapon:EntIndex() or 0, muzzle > 0 and muzzle or -1)
	if IsValid(host) then SuppressHostEvents(host) end
end

WS.BulletSteps:Add("ws_crit_tracers", BulletSteps.TRACERS, function(ent, data)
	local weapon = ent:IsWeapon() and ent or (ent.GetActiveWeapon and ent:GetActiveWeapon()) or NULL
	local callback = data.Callback
	data.Callback = function(attacker, tr, dmginfo)
		if IsValid(attacker) and CritBullet(attacker, tr, dmginfo) then CritTracer(weapon, attacker, tr) end
		if callback then return callback(attacker, tr, dmginfo) end
	end
	return BulletSteps.CHANGED
end)
