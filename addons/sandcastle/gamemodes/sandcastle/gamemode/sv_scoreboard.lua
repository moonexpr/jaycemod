-- What the scoreboard (ws/cl_scoreboard.lua) needs of the NPCs that
-- fight for a team (WS.SetTeamMember, which networks their team as
-- ws_team): their kills, as the NW2 int ws_kills, since GMod keeps
-- frags for players only; and a player's frag for killing another team's NPC,
-- as for killing its player. A dead NPC leaves its column. Every kill of the
-- enemy is its team's frag too (WSTeamFrag).
local UNASSIGNED = WS.TEAM_UNASSIGNED

-- A soldier's kill counts after its war lets it go (its killer may die with it).
local function Fighter(ent)
	return IsValid(ent) and not ent:IsPlayer() and WS.LastTeamNumber(ent) ~= UNASSIGNED
end

-- A kill of the other game team's player or NPC is its killer's team's frag:
-- WSTeamFrag(team) tells whoever counts them (the round's frag limit,
-- games.gameplay.rounds.limits).
local GAME_TEAMS = { [WS.TEAM_RED] = true, [WS.TEAM_BLUE] = true }

local function TeamFrag(attacker, victimTeam)
	local team = WS.LastTeamNumber(attacker)
	if GAME_TEAMS[team] and GAME_TEAMS[victimTeam] and team ~= victimTeam then hook.Run("WSTeamFrag", team) end
end

local function Credit(attacker, victimTeam)
	TeamFrag(attacker, victimTeam)
	if attacker:IsPlayer() then
		if victimTeam ~= UNASSIGNED and victimTeam ~= attacker:Team() then attacker:AddFrags(1) end
	elseif Fighter(attacker) then
		attacker:SetNW2Int("ws_kills", attacker:GetNW2Int("ws_kills", 0) + 1)
	end
end

hook.Add("PlayerDeath", "ws_scoreboard", function(victim, _, attacker)
	if Fighter(attacker) then
		Credit(attacker, victim:Team())
	elseif IsValid(attacker) and attacker:IsPlayer() then
		-- GMod counts a player's frag of a player itself
		TeamFrag(attacker, victim:Team())
	end
end)

hook.Add("OnNPCKilled", "ws_scoreboard", function(npc, attacker)
	npc:SetNW2Int("ws_team", UNASSIGNED)
	if IsValid(attacker) and attacker ~= npc then Credit(attacker, WS.LastTeamNumber(npc)) end
end)
