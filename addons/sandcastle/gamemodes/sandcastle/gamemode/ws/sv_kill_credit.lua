-- Kill credit (foundation.kill_credit), for players and soldiers alike:
-- every combatant remembers the enemies who hurt it, and a lethal hit from
-- the environment (the world, a fall, a trigger: no player, NPC or
-- NextBot) within the window of an enemy's is that enemy's. The hit's
-- attacker is rewritten before it lands, so the scores, the kill feed and
-- the killer cam all credit them, as TF2's Event_Killed rewrites it. A
-- player so killed respawns sooner (WS.RespawnCountsFrom, the rounds'
-- respawn waves), and its death notice reads "finished off"
-- (foundation.kill_feed's FINISHED_OFF). The hit path (ws/sv_hits.lua)
-- calls both.
local Credit = WS.require("foundation.kill_credit")
local Feed = WS.require("foundation.kill_feed")

local damagers = setmetatable({}, { __mode = "k" }) -- victim -> Credit.Damagers()
local creditedAt = setmetatable({}, { __mode = "k" }) -- victim -> when its lethal hit was credited

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

-- The time a player dead since deathTime counts their respawn from: their
-- death, CREDITED_RESPAWN sooner when another was credited with it.
function WS.RespawnCountsFrom(ply, deathTime)
	if creditedAt[ply] == deathTime then return deathTime + Credit.CREDITED_RESPAWN end
	return deathTime
end

-- Whether the death a notice tells, of victim (a player, or the name
-- GetDeathNoticeEntityName gives an NPC), was credited this moment.
local function FinishedOff(gm, victim)
	local now = CurTime()
	if not isstring(victim) then return creditedAt[victim] == now end
	for ent, at in pairs(creditedAt) do
		if at == now and IsValid(ent) and gm:GetDeathNoticeEntityName(ent) == victim then return true end
	end
	return false
end

function GM:SendDeathNotice(attacker, inflictor, victim, flags)
	if FinishedOff(self, victim) then flags = bit.bor(flags, Feed.FINISHED_OFF) end
	self.BaseClass.SendDeathNotice(self, attacker, inflictor, victim, flags)
end

-- A life's damagers are forgotten with it.
hook.Add("PlayerSpawn", "ws_kill_credit", function(ply)
	damagers[ply] = nil
end)
