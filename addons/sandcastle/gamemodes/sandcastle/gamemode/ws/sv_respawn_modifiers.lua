-- Respawn modifiers (games.gameplay.respawn_modifiers): what each player did
-- since their last spawn (enemies killed, players and soldiers; points
-- captured standing on them and blocked as their named defender, from the
-- capture areas; a death credited to an enemy, ws/sv_kill_credit.lua; a
-- suicide) moves their respawn sooner or later. The rounds controller asks
-- at each death (WS.RespawnAdjust), and the player is told every reason
-- (game_respawn_modifiers, under the respawn bar).
local M = gameplay.respawn_modifiers

local lives = setmetatable({}, { __mode = "k" }) -- player -> what they did since their last spawn

local function Fresh()
	return { kills = 0, captures = 0, defenses = 0, finishedOff = false, suicide = false }
end

local function Life(ply)
	lives[ply] = lives[ply] or Fresh()
	return lives[ply]
end

hook.Add("PlayerSpawn", "ws_respawn_modifiers", function(ply)
	lives[ply] = Fresh()
	ply.wsRespawnAdjust = 0
end)

-- Whether a fights for the team b is the enemy of.
local function Enemies(a, b)
	return WS.EnemyOf(WS.TeamNumber(a)) == WS.TeamNumber(b) and WS.TeamNumber(b) ~= WS.TEAM_UNASSIGNED
end

-- A team change kills the player too (WS.SetPlayerTeam): no suicide.
hook.Add("PlayerDeath", "ws_respawn_modifiers", function(victim, _, attacker)
	if attacker == victim then
		if not victim.wsChangingTeam then Life(victim).suicide = true end
	elseif IsValid(attacker) and attacker:IsPlayer() and Enemies(attacker, victim) then
		Life(attacker).kills = Life(attacker).kills + 1
	end
end)

hook.Add("OnNPCKilled", "ws_respawn_modifiers", function(npc, attacker)
	if IsValid(attacker) and attacker:IsPlayer() and Enemies(attacker, npc) then
		Life(attacker).kills = Life(attacker).kills + 1
	end
end)

hook.Add("WSPointCappers", "ws_respawn_modifiers", function(_, _, cappers)
	for _, ent in ipairs(cappers) do
		if ent:IsPlayer() then Life(ent).captures = Life(ent).captures + 1 end
	end
end)

hook.Add("WSPointBlocker", "ws_respawn_modifiers", function(_, _, blocker)
	if blocker:IsPlayer() then Life(blocker).defenses = Life(blocker).defenses + 1 end
end)

-- The seconds ply's death at deathTime moves their respawn, for a team
-- whose waves are wave seconds long (negative: sooner); the player is told
-- each reason.
function WS.RespawnAdjust(ply, deathTime, wave)
	local facts = Life(ply)
	facts.finishedOff = WS.DeathCredited(ply, deathTime)
	local list = M.For(facts)
	local total, limited = M.Total(list, wave)
	ply.wsRespawnAdjust = total
	WS.Events.Fire("game_respawn_modifiers", { modifiers = list, total = total, limited = limited }, ply)
	return total
end

-- The time a player dead since deathTime counts their respawn from: their
-- death, moved by their modifiers (none before their first death).
function WS.RespawnCountsFrom(ply, deathTime)
	return deathTime + (ply.wsRespawnAdjust or 0)
end
