-- TF2 player conditions (CTFPlayerShared::AddCond / RemoveCond) and stuns
-- (StunPlayer), as far as GMod can express them: map triggers add and
-- remove them. The effects GMod can show are applied here and in sh_core.lua
-- (movement); the others are kept, so a later RemoveCond or a condition
-- filter still sees them, but do nothing.
--   INVULNERABLE: no damage taken. CRITBOOSTED(_PUMPKIN, _USER_BUFF): triple damage dealt.
--   BLAST_IMMUNE: no blast damage. SPEED_BOOST: +40% speed (max +105).
--   HALLOWEEN_QUICK_HEAL: heals 30 health a second, up to max health.
--   HALLOWEEN_THRILLER: the forced dance holds the player still (frozen).
-- Movement and stun state reach clients as NW2 vars for prediction:
-- wetsand_speed_boosted, wetsand_stun_end_time, wetsand_stun_speed_reduction,
-- wetsand_stun_flags.
local P = WETSAND.PlayerRules
local C = P.COND

-- HALLOWEEN_QUICK_HEAL: CTFPlayerShared::Heal(outer, 30, ...), per second.
local QUICK_HEAL_RATE = 30
local THINK_INTERVAL = 0.1

local function Conds(ply)
	ply.wetsandConds = ply.wetsandConds or {}
	return ply.wetsandConds
end

local function SyncMovement(ply)
	ply:SetNW2Bool("wetsand_speed_boosted", P.InCond(Conds(ply), C.SPEED_BOOST, CurTime()))
end

function WETSAND.AddCondition(ply, cond, duration)
	P.AddCond(Conds(ply), cond, duration, CurTime())
	if cond == C.BURNING then ply:Ignite(duration > 0 and duration or 10) end
	if cond == C.HALLOWEEN_THRILLER then ply:Freeze(true) end
	SyncMovement(ply)
end

function WETSAND.RemoveCondition(ply, cond)
	P.RemoveCond(Conds(ply), cond)
	if cond == C.BURNING then ply:Extinguish() end
	if cond == C.HALLOWEEN_THRILLER then ply:Freeze(false) end
	SyncMovement(ply)
end

function WETSAND.InCondition(ply, cond)
	return P.InCond(Conds(ply), cond, CurTime())
end

-- CTFPlayerShared::RemoveAllCond: also ends a stun.
function WETSAND.RemoveAllConditions(ply)
	if P.InCond(Conds(ply), C.HALLOWEEN_THRILLER, CurTime()) then ply:Freeze(false) end
	ply.wetsandConds = {}
	ply.wetsandStun = nil
	ply:SetNW2Float("wetsand_stun_end_time", 0)
	ply:SetNW2Int("wetsand_stun_flags", 0)
	SyncMovement(ply)
end

-- CTFPlayer::Regenerate's condition removals.
function WETSAND.ClearConditionsOnRegenerate(ply)
	P.ClearOnRegenerate(Conds(ply))
	ply:Extinguish()
	SyncMovement(ply)
end

function WETSAND.StunPlayer(ply, duration, reduction, flags)
	local stun = P.Stun(ply.wetsandStun, duration, reduction, flags, CurTime())
	ply.wetsandStun = stun
	ply:SetNW2Float("wetsand_stun_end_time", stun.ends)
	ply:SetNW2Float("wetsand_stun_speed_reduction", stun.reduction)
	ply:SetNW2Int("wetsand_stun_flags", stun.flags)
end

-- RemoveCond( TF_COND_STUNNED ): the stun ends now (Merasmus frees a bomb
-- head who reached him).
function WETSAND.EndStun(ply)
	ply.wetsandStun = nil
	ply:SetNW2Float("wetsand_stun_end_time", 0)
	ply:SetNW2Int("wetsand_stun_flags", 0)
end

-- A player starts each life with no conditions.
hook.Add("PlayerSpawn", "wetsand_conditions", WETSAND.RemoveAllConditions)
hook.Add("PostPlayerDeath", "wetsand_conditions", WETSAND.RemoveAllConditions)

hook.Add("EntityTakeDamage", "wetsand_conditions", function(target, dmg)
	if not target:IsPlayer() then return end
	local attacker = dmg:GetAttacker()
	local attackerConds = IsValid(attacker) and attacker:IsPlayer() and Conds(attacker) or {}
	local scale = P.DamageScale(Conds(target), attackerConds, dmg:IsDamageType(DMG_BLAST), CurTime())
	if scale ~= 1 then dmg:ScaleDamage(scale) end
end)

timer.Create("wetsand_conditions", THINK_INTERVAL, 0, function()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		local conds = ply.wetsandConds
		if conds and next(conds) then
			if #P.ExpireConds(conds, now) > 0 then SyncMovement(ply) end
			if P.InCond(conds, C.HALLOWEEN_QUICK_HEAL, now) and ply:Alive() and ply:Health() < ply:GetMaxHealth() then
				ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + math.ceil(QUICK_HEAL_RATE * THINK_INTERVAL)))
			end
		end
	end
end)
