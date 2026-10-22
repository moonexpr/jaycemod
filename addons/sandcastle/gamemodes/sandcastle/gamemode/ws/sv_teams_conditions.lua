-- TF2 player conditions (CTFPlayerShared::AddCond / RemoveCond) and stuns
-- (StunPlayer), as far as GMod can express them: map triggers, spells and
-- the round add and remove them, on players and the AI war's soldiers
-- alike. The effects GMod can show are applied here, in sv_hits.lua
-- (damage) and in sh_core.lua (movement); the others are kept, so a later
-- RemoveCond or a condition filter still sees them, but do nothing.
--   INVULNERABLE: no damage taken. CRITBOOSTED(_PUMPKIN, _USER_BUFF,
--   _BONUS_TIME): triple damage dealt; the winners of a round or the match
--   hold BONUS_TIME while they celebrate (Teams.BonusCrits).
--   BLAST_IMMUNE: no blast damage. SPEED_BOOST: +40% speed (max +105).
--   BURNING: afterburn, TF_BURNING_DMG every TF_BURNING_FREQUENCY, put out
--   by water.
--   HALLOWEEN_QUICK_HEAL: heals 30 health a second, up to max health.
--   HALLOWEEN_THRILLER: the forced dance holds the player still (frozen).
--   URINE (Jarate): mini-crits taken.
-- What players see of them (games.gameplay.players.condition_effects) is drawn by
-- cl_conditions.lua from the end of each, networked as ws_cond_<number>.
-- Movement and stun state reach clients as NW2 vars for prediction:
-- ws_speed_boosted, ws_stun_end_time, ws_stun_speed_reduction,
-- ws_stun_flags.
local P = WS.PlayerRules
local C = P.COND
local Effects = WS.require("games.gameplay.players.condition_effects")

-- HALLOWEEN_QUICK_HEAL: CTFPlayerShared::Heal(outer, 30, ...), per second.
local QUICK_HEAL_RATE = 30
local THINK_INTERVAL = 0.1
-- TF_BURNING_FREQUENCY, TF_BURNING_DMG; a burn with no end of its own lasts
-- BURN_SECONDS. Water to the waist puts it out (WL_Waist).
local BURN_INTERVAL, BURN_DAMAGE, BURN_SECONDS = 0.5, 4, 10
local WATER_WAIST = 2

-- Every entity that has held a condition.
local holders = setmetatable({}, { __mode = "k" })

local function Conds(ent)
	if not ent.wsConds then
		ent.wsConds = {}
		holders[ent] = true
	end
	return ent.wsConds
end

-- An entity's conditions to read; the world and others never given one
-- hold none.
local NONE = {}
function WS.ConditionsOf(ent)
	return IsValid(ent) and ent.wsConds or NONE
end

local function SyncNetworked(ent)
	local conds, now = Conds(ent), CurTime()
	if ent:IsPlayer() then ent:SetNW2Bool("ws_speed_boosted", P.InCond(conds, C.SPEED_BOOST, now)) end
	for _, cond in ipairs(Effects.NETWORKED) do
		ent:SetNW2Float("ws_cond_" .. cond, P.InCond(conds, cond, now) and conds[cond] or 0)
	end
end

-- Catching a condition not held plays its sound (Fire.Engulf for a fire).
function WS.AddCondition(ent, cond, duration)
	if cond == C.BURNING and duration <= 0 then duration = BURN_SECONDS end
	local now = CurTime()
	local ignite = not P.InCond(Conds(ent), cond, now) and Effects.IgniteSound(cond)
	if ignite then ent:EmitSound(ignite) end
	P.AddCond(Conds(ent), cond, duration, now)
	if cond == C.HALLOWEEN_THRILLER then ent:Freeze(true) end
	SyncNetworked(ent)
end

function WS.RemoveCondition(ent, cond)
	P.RemoveCond(Conds(ent), cond)
	if cond == C.HALLOWEEN_THRILLER then ent:Freeze(false) end
	SyncNetworked(ent)
end

function WS.InCondition(ent, cond)
	return P.InCond(WS.ConditionsOf(ent), cond, CurTime())
end

-- CTFPlayerShared::RemoveAllCond: also ends a stun.
function WS.RemoveAllConditions(ply)
	if P.InCond(Conds(ply), C.HALLOWEEN_THRILLER, CurTime()) then ply:Freeze(false) end
	ply.wsConds = {}
	ply.wsStun = nil
	ply:SetNW2Float("ws_stun_end_time", 0)
	ply:SetNW2Int("ws_stun_flags", 0)
	SyncNetworked(ply)
end

-- CTFPlayer::Regenerate's condition removals.
function WS.ClearConditionsOnRegenerate(ply)
	P.ClearOnRegenerate(Conds(ply))
	SyncNetworked(ply)
end

function WS.StunPlayer(ply, duration, reduction, flags)
	local stun = P.Stun(ply.wsStun, duration, reduction, flags, CurTime())
	ply.wsStun = stun
	ply:SetNW2Float("ws_stun_end_time", stun.ends)
	ply:SetNW2Float("ws_stun_speed_reduction", stun.reduction)
	ply:SetNW2Int("ws_stun_flags", stun.flags)
end

-- RemoveCond( TF_COND_STUNNED ): the stun ends now (Merasmus frees a bomb
-- head who reached him).
function WS.EndStun(ply)
	ply.wsStun = nil
	ply:SetNW2Float("ws_stun_end_time", 0)
	ply:SetNW2Int("ws_stun_flags", 0)
end

-- A player starts each life with no conditions.
hook.Add("PlayerSpawn", "ws_conditions", WS.RemoveAllConditions)
hook.Add("PostPlayerDeath", "ws_conditions", WS.RemoveAllConditions)

-- Afterburn, from nobody: what set the fire is not kept.
local function Burn(ent)
	local dmg = DamageInfo()
	dmg:SetDamage(BURN_DAMAGE)
	dmg:SetDamageType(DMG_BURN)
	dmg:SetAttacker(game.GetWorld())
	dmg:SetInflictor(game.GetWorld())
	ent:TakeDamageInfo(dmg)
end

local function Alive(ent)
	if ent:IsPlayer() then return ent:Alive() end
	return ent:Health() > 0
end

-- The winners' crits while they celebrate, on each team's players and
-- soldiers; everyone else's go.
local function SyncBonusCrits(now)
	local state = WS.State()
	local winner = WS.Winner(state)
	for _, t in ipairs({ WS.TEAM_RED, WS.TEAM_BLUE }) do
		local boosted = WS.TeamRules.BonusCrits(state, winner, t)
		local members = WS.TeamMembers(t)
		for _, ply in ipairs(team.GetPlayers(t)) do members[#members + 1] = ply end
		for _, ent in ipairs(members) do
			if boosted ~= P.InCond(WS.ConditionsOf(ent), C.CRITBOOSTED_BONUS_TIME, now) then
				if boosted then
					WS.AddCondition(ent, C.CRITBOOSTED_BONUS_TIME, P.PERMANENT)
				else
					WS.RemoveCondition(ent, C.CRITBOOSTED_BONUS_TIME)
				end
			end
		end
	end
end

local nextBurn = 0
timer.Create("ws_conditions", THINK_INTERVAL, 0, function()
	local now = CurTime()
	SyncBonusCrits(now)
	local burnTick = now >= nextBurn
	if burnTick then nextBurn = now + BURN_INTERVAL end
	for ent in pairs(holders) do
		local conds = ent.wsConds
		if IsValid(ent) and next(conds) then
			if #P.ExpireConds(conds, now) > 0 then SyncNetworked(ent) end
			if P.InCond(conds, C.BURNING, now) and Alive(ent) then
				if ent:WaterLevel() >= WATER_WAIST then
					WS.RemoveCondition(ent, C.BURNING)
				elseif burnTick then
					Burn(ent)
				end
			end
			if ent:IsPlayer() and P.InCond(conds, C.HALLOWEEN_QUICK_HEAL, now) and ent:Alive() and ent:Health() < ent:GetMaxHealth() then
				ent:SetHealth(math.min(ent:GetMaxHealth(), ent:Health() + math.ceil(QUICK_HEAL_RATE * THINK_INTERVAL)))
			end
		end
	end
end)
