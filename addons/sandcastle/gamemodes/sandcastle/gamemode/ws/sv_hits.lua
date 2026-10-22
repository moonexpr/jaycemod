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
-- (game_combat_text, ws/cl_hits.lua).
local Balance = WS.require("foundation.combat.weapon_balance")
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

-- The hit each victim is taking, from EntityTakeDamage to
-- PostEntityTakeDamage: { kind, class, headshot }.
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

hook.Add("EntityTakeDamage", "ws_hits", function(target, dmg)
	local attacker = dmg:GetAttacker()
	-- the world, or an attacker gone, is of no team
	local attackerTeam = IsValid(attacker) and WS.TeamNumber(attacker) or WS.TEAM_UNASSIGNED
	if WS.TeamRules.FriendlySpared(WS.FriendlyFire(), attackerTeam, WS.TeamNumber(target), attacker == target) then
		return true
	end
	local blast = dmg:IsDamageType(DMG_BLAST)
	local class = Balance.Weapon(WeaponClass(dmg))
	local damage, headshot, rolled = Balance.Shot(class, {
		damage = dmg:GetDamage(),
		bullet = dmg:IsBulletDamage(),
		blast = blast,
		distance = Distance(attacker, target),
		headshot = Headshot(target),
		roll = Roll(attacker),
	})
	dmg:SetDamage(damage)
	local scale, kind = P.Hit(WS.ConditionsOf(target), WS.ConditionsOf(attacker), CurTime(), {
		blast = blast,
		selfHarm = attacker == target,
		headshot = headshot,
		rolled = rolled,
		critical = dmg:IsDamageType(DMG_ACID),
	})
	if scale ~= 1 then dmg:ScaleDamage(scale) end
	if kind == P.HIT_CRIT then dmg:SetDamageType(bit.bor(dmg:GetDamageType(), DMG_ACID)) end
	taking[target] = {
		kind = kind,
		class = class,
		headshot = headshot,
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
end

local HIT_SOUNDS = {
	[P.HIT_CRIT] = "TFPlayer.CritHit",
	[P.HIT_MINICRIT] = "TFPlayer.CritHitMini",
}

-- The top of the victim's bounds.
local function Top(ent)
	return ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z)
end

-- What a hit is told for: players, NPCs and NextBots, as TF2 tells hits on
-- players (and buildings), never on props.
local function Combatant(ent)
	return ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
end

hook.Add("PostEntityTakeDamage", "ws_hits", function(target, dmg, took)
	local hit = taking[target]
	taking[target] = nil
	if not took or hit == nil or not Combatant(target) then return end
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
