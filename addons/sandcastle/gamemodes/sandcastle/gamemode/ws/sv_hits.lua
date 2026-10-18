-- Every hit's friendly fire (mp_friendlyfire 0 spares teammates,
-- Teams.FriendlySpared) and crits (foundation.players' Hit): a crit-boosted
-- attacker, a headshot from any weapon, or a jarated victim, for players
-- and soldiers alike, by the conditions of both
-- (ws/sv_teams_conditions.lua). A crit is
-- marked DMG_CRITICAL (DMG_ACID's bit, as TF2's), so what reads the damage
-- after knows it. Then the hit is heard and told: a crit or mini-crit
-- sounds from its victim (TFPlayer.CritHit, CritHitMini; CritPain to a
-- player hit), and the attacking player is told its damage
-- (game_combat_text, ws/cl_hits.lua).
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

-- The hit each victim is taking, from EntityTakeDamage to PostEntityTakeDamage.
local taking = setmetatable({}, { __mode = "k" })

hook.Add("EntityTakeDamage", "ws_hits", function(target, dmg)
	local attacker = dmg:GetAttacker()
	-- the world, or an attacker gone, is of no team
	local attackerTeam = IsValid(attacker) and WS.TeamNumber(attacker) or WS.TEAM_UNASSIGNED
	if WS.TeamRules.FriendlySpared(WS.FriendlyFire(), attackerTeam, WS.TeamNumber(target), attacker == target) then
		return true
	end
	local scale, kind = P.Hit(WS.ConditionsOf(target), WS.ConditionsOf(attacker), CurTime(), {
		blast = dmg:IsDamageType(DMG_BLAST),
		selfHarm = attacker == target,
		headshot = Headshot(target),
		critical = dmg:IsDamageType(DMG_ACID),
	})
	if scale ~= 1 then dmg:ScaleDamage(scale) end
	if kind == P.HIT_CRIT then dmg:SetDamageType(bit.bor(dmg:GetDamageType(), DMG_ACID)) end
	taking[target] = kind
end)

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
	local kind = taking[target]
	taking[target] = nil
	if not took or kind == nil or not Combatant(target) then return end
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
