-- Kill credit (games.gameplay.kill_credit), for players and soldiers alike:
-- every combatant remembers the enemies who hurt it, and a lethal hit from
-- the environment (the world, a fall, a trigger: no player, NPC or
-- NextBot) within the window of an enemy's is that enemy's. The hit's
-- attacker is rewritten before it lands, so the scores, the kill feed and
-- the killer cam all credit them, as TF2's Event_Killed rewrites it. A
-- player so killed respawns sooner (WS.DeathCredited, a respawn modifier:
-- ws/sv_respawn_modifiers.lua), and its death notice reads "finished off"
-- (features.aiwar.kill_feed's FINISHED_OFF). The hit path (ws/sv_hits.lua)
-- calls both. A kill's assister is the latest other enemy who hurt the
-- victim within ASSIST_WINDOW (CTFGameRules::GetAssister's damager rule):
-- counted as ws_assists (the scoreboard's column and points) and named in
-- the kill feed beside the killer (game_kill_assist). A victim slammed dead
-- into a surface (ws/sv_hits.lua's strike, WS.MarkSlammed) shows the
-- impact's icon (features.aiwar.kill_feed's SLAMMED).
local Credit = gameplay.kill_credit
local Feed = WS.require("features.aiwar.kill_feed")
local E = WS.Events

local ASSISTS = "ws_assists" -- the NW2 int a player's or soldier's assists are counted in

local damagers = setmetatable({}, { __mode = "k" }) -- victim -> Credit.Damagers()
local creditedAt = setmetatable({}, { __mode = "k" }) -- victim -> when its lethal hit was credited
local assistedAt = setmetatable({}, { __mode = "k" }) -- victim -> when its death was assisted
local assistedBy = setmetatable({}, { __mode = "k" }) -- victim -> its assister
local slammedAt = setmetatable({}, { __mode = "k" }) -- victim -> when a strike was dealt it

-- victim is being dealt a strike now: if it dies of it, its death notice
-- shows the impact.
function WS.MarkSlammed(victim)
	slammedAt[victim] = CurTime()
end

-- A hit that landed on victim, remembered when an enemy dealt it.
function WS.RecordDamager(victim, attacker)
	if not (IsValid(attacker) and WS.Combatant(attacker)) then return end
	if not Credit.Remembered(WS.TeamNumber(attacker), WS.TeamNumber(victim), attacker == victim) then return end
	damagers[victim] = damagers[victim] or Credit.Damagers()
	damagers[victim]:Record(attacker, CurTime())
end

-- Credits dmg, about to land on victim, to the enemy who hurt victim last,
-- when it comes from the environment and is enough to kill (armor may yet
-- save victim: then nobody died). Whether it did.
function WS.CreditEnvironmentalHit(victim, dmg)
	local attacker = dmg:GetAttacker()
	if IsValid(attacker) and WS.Combatant(attacker) then return false end
	if damagers[victim] == nil or dmg:GetDamage() < victim:Health() then return false end
	local now = CurTime()
	local credited = damagers[victim]:Recent(now, Credit.ENVIRONMENT_WINDOW)
	if not IsValid(credited) then return false end
	dmg:SetAttacker(credited)
	creditedAt[victim] = now
	return true
end

-- Whether the death of ply at deathTime was credited to another.
function WS.DeathCredited(ply, deathTime)
	return creditedAt[ply] == deathTime
end

-- The enemy who helped scorer kill victim: the latest other who hurt it
-- within ASSIST_WINDOW, or nil. A death no combatant scored (a suicide, the
-- world's uncredited) has none.
local function Assister(victim, scorer)
	if damagers[victim] == nil or scorer == victim or not (IsValid(scorer) and WS.Combatant(scorer)) then return nil end
	local assister = damagers[victim]:Recent(CurTime(), Credit.ASSIST_WINDOW, scorer)
	return IsValid(assister) and assister or nil
end

local function Assisted(victim, scorer)
	local assister = Assister(victim, scorer)
	if assister == nil then return end
	assister:SetNW2Int(ASSISTS, assister:GetNW2Int(ASSISTS, 0) + 1)
	assistedAt[victim], assistedBy[victim] = CurTime(), assister
end

-- These run before the gamemode's own PlayerDeath and OnNPCKilled, which
-- send the death notice.
hook.Add("PlayerDeath", "ws_kill_credit", function(victim, _, attacker) Assisted(victim, attacker) end)
hook.Add("OnNPCKilled", "ws_kill_credit", function(npc, attacker) Assisted(npc, attacker) end)

-- Of the victims marked in times (victim -> when) this moment, the one a
-- death notice tells of (victim: a player, or the name
-- GetDeathNoticeEntityName gives an NPC), or nil.
local function Told(gm, victim, times)
	local now = CurTime()
	if not isstring(victim) then return times[victim] == now and victim or nil end
	for ent, at in pairs(times) do
		if at == now and IsValid(ent) and gm:GetDeathNoticeEntityName(ent) == victim then return ent end
	end
	return nil
end

-- A player's name, or an NPC's as death notices give it.
local function NoticeName(gm, ent)
	if ent:IsPlayer() then return ent:Nick() end
	return gm:GetDeathNoticeEntityName(ent)
end

-- An AI war soldier by its kind (one class is every kind's: Feed.Notice).
function GM:GetDeathNoticeEntityName(ent)
	local kind = ent:GetNW2String("NSKind", "")
	if kind ~= "" then return Feed.Notice(kind) end
	return self.BaseClass.GetDeathNoticeEntityName(self, ent)
end

function GM:SendDeathNotice(attacker, inflictor, victim, flags)
	if Told(self, victim, creditedAt) then flags = bit.bor(flags, Feed.FINISHED_OFF) end
	if Told(self, victim, slammedAt) then flags = bit.bor(flags, Feed.SLAMMED) end
	self.BaseClass.SendDeathNotice(self, attacker, inflictor, victim, flags)
	local dead = Told(self, victim, assistedAt)
	if dead == nil then return end
	local assister = assistedBy[dead]
	if not IsValid(assister) then return end
	E.Fire("game_kill_assist", {
		victim = isstring(victim) and victim or NoticeName(self, victim),
		assister = NoticeName(self, assister),
		team = assister:IsPlayer() and assister:Team() or Feed.NPC_TEAM,
	})
end

-- A life's damagers are forgotten with it.
hook.Add("PlayerSpawn", "ws_kill_credit", function(ply)
	damagers[ply] = nil
end)
