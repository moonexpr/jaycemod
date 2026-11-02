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
--   URINE (Jarate), MARKED_FOR_DEATH: mini-crits taken.
--   MAD_MILK: whoever hurts its holder heals part of the damage (sv_hits.lua).
--   BLEEDING: TF_BLEEDING_DMG every TF_BLEEDING_FREQUENCY, dealt by whoever
--   inflicted it (WS.Inflict: a hit's condition, as CS:S's least loved
--   guns inflict theirs).
-- What players see of them (games.gameplay.players.condition_effects) is drawn by
-- cl_conditions.lua from the end of each, networked as ws_cond_<number>.
--   STUNNED (StunPlayer): slowed, and by its flags held still, disarmed or
--   humiliated (sh_core.lua).
-- Movement and stun state reach clients as NW2 vars for prediction:
-- ws_speed_boosted, the stun's ws_cond_<STUNNED>, ws_stun_speed_reduction,
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

-- CTFPlayerShared::RemoveAllCond: also ends a stun (TF_COND_STUNNED).
function WS.RemoveAllConditions(ply)
	if P.InCond(Conds(ply), C.HALLOWEEN_THRILLER, CurTime()) then ply:Freeze(false) end
	ply.wsConds = {}
	SyncNetworked(ply)
end

-- CTFPlayer::Regenerate's condition removals.
function WS.ClearConditionsOnRegenerate(ply)
	P.ClearOnRegenerate(Conds(ply))
	SyncNetworked(ply)
end

-- CTFPlayerShared::StunPlayer: TF_COND_STUNNED for as long as the stun
-- folded with the one held lasts; its slow and flags are kept beside it,
-- and mean nothing once the condition ends, however it ends.
function WS.StunPlayer(ply, duration, reduction, flags)
	local now = CurTime()
	local held = P.InCond(Conds(ply), C.STUNNED, now) and ply.wsStun or nil
	local stun = P.Stun(held, duration, reduction, flags, now)
	ply.wsStun = stun
	ply:SetNW2Float("ws_stun_speed_reduction", stun.reduction)
	ply:SetNW2Int("ws_stun_flags", stun.flags)
	WS.AddCondition(ply, C.STUNNED, stun.ends - now)
end

-- A condition attacker's hit inflicts on ent for seconds (gameplay.players'
-- Inflict, the longer of the one held and the new): BLEEDING hurts ent in
-- attacker's name; any other is held as it is.
function WS.Inflict(ent, attacker, cond, seconds)
	local now = CurTime()
	if cond == C.BLEEDING then
		ent.wsBleeder = attacker
		if not P.InCond(Conds(ent), cond, now) then ent.wsNextBleed = now + P.BLEED_INTERVAL end
	end
	P.Inflict(Conds(ent), cond, seconds, now)
	SyncNetworked(ent)
end

-- RemoveCond( TF_COND_STUNNED ): the stun ends now (Merasmus frees a bomb
-- head who reached him).
function WS.EndStun(ply)
	WS.RemoveCondition(ply, C.STUNNED)
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

-- CTFPlayerShared's bleed: TF_BLEEDING_DMG, a slash, dealt by whoever made
-- it bleed (the world, once they are gone), so its kill is theirs.
local function Bleed(ent)
	local bleeder = IsValid(ent.wsBleeder) and ent.wsBleeder or game.GetWorld()
	local dmg = DamageInfo()
	dmg:SetDamage(P.BLEED_DAMAGE)
	dmg:SetDamageType(DMG_SLASH)
	dmg:SetAttacker(bleeder)
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
					WS.AddCondition(ent, C.SPEED_BOOST, P.PERMANENT)
				else
					WS.RemoveCondition(ent, C.CRITBOOSTED_BONUS_TIME)
					WS.RemoveCondition(ent, C.SPEED_BOOST)
				end
			end
		end
	end
end

-- CTFPlayerShared's SetWeaponVisible( false ) for a loser (WS.IsLoser): its
-- active weapon is not drawn, nor a player's view model, until it is a
-- loser no more. Hidden again every think, as a weapon drawn anew shows; a
-- weapon put away is the engine's to hide and show.
local function SyncLoserWeapon(ent)
	local weapon, hidden = ent:GetActiveWeapon(), ent.wsLoserWeapon
	if IsValid(weapon) and WS.IsLoser(ent) then
		weapon:AddEffects(EF_NODRAW)
		ent.wsLoserWeapon = weapon
		if ent:IsPlayer() then ent:DrawViewModel(false) end
	elseif hidden then
		ent.wsLoserWeapon = nil
		if hidden == weapon then weapon:RemoveEffects(EF_NODRAW) end
		if ent:IsPlayer() then ent:DrawViewModel(true) end
	end
end

local function SyncLoserWeapons()
	for _, ply in ipairs(player.GetAll()) do SyncLoserWeapon(ply) end
	for _, t in ipairs({ WS.TEAM_RED, WS.TEAM_BLUE }) do
		for _, ent in ipairs(WS.TeamMembers(t)) do SyncLoserWeapon(ent) end
	end
end

local nextBurn = 0
timer.Create("ws_conditions", THINK_INTERVAL, 0, function()
	local now = CurTime()
	SyncBonusCrits(now)
	SyncLoserWeapons()
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
			local bleeds
			bleeds, ent.wsNextBleed = P.BleedTick(conds, ent.wsNextBleed, now)
			if bleeds and Alive(ent) then Bleed(ent) end
			if ent:IsPlayer() and P.InCond(conds, C.HALLOWEEN_QUICK_HEAL, now) and ent:Alive() and ent:Health() < ent:GetMaxHealth() then
				ent:SetHealth(math.min(ent:GetMaxHealth(), ent:Health() + math.ceil(QUICK_HEAL_RATE * THINK_INTERVAL)))
			end
		end
	end
end)
