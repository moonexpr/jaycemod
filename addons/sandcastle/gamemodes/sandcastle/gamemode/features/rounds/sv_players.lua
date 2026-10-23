-- Part of the rounds controller (sv.lua): the players, their teams and their scores.
local GAME_TEAMS = ...
local UNASSIGNED = WS.TEAM_UNASSIGNED
local Credit = gameplay.kill_credit
local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

-- Players -----------------------------------------------------------------------

local function TeamPlayers(t)
	local players = {}
	for _, ply in ipairs(player.GetAll()) do
		if WS.TeamOf(ply) == t then players[#players + 1] = ply end
	end
	return players
end

-- A player counts once their client has finished loading (system_client_ready,
-- ws/sh_events.lua), so the pre-round freeze is not spent on a
-- loading screen. Bots have no client to report it.
local function Ready(ply)
	return WS.IsReady(ply) or ply:IsBot()
end

-- BHavePlayers: someone ready and on RED or BLU, or something else fighting
-- for a team (the AI war says so through WSHaveCombatants).
local function HavePlayers()
	for _, ply in ipairs(player.GetAll()) do
		if Ready(ply) and WS.TeamOf(ply) ~= UNASSIGNED then return true end
	end
	return hook.Run("WSHaveCombatants") == true
end

local function Scores()
	return {
		[RED] = team.GetScore(RED),
		[BLUE] = team.GetScore(BLUE),
	}
end

-- Each team's players, its live ones, and its live soldiers (the AI war
-- says how many through WSTeamCombatants): sudden death ends only when
-- a side's last soldier is down too.
local function TeamLife()
	local teams = {}
	for _, t in ipairs(GAME_TEAMS) do
		local players, alive = TeamPlayers(t), 0
		for _, ply in ipairs(players) do
			if ply:Alive() then alive = alive + 1 end
		end
		teams[t] = {
			players = #players,
			alive = alive,
			soldiers = hook.Run("WSTeamCombatants", t) or 0,
		}
	end
	return teams
end

local function EachPlayer(fn)
	for _, ply in ipairs(player.GetAll()) do fn(ply) end
end

-- Every RED player to BLU and every BLU player to RED, and their scores
-- (CTFGameRules::HandleSwitchTeams).
local function SwitchTeams()
	EachPlayer(function(ply)
		local t = WS.TeamOf(ply)
		if t ~= UNASSIGNED then WS.SetPlayerTeam(ply, WS.EnemyOf(t), true) end
	end)
	local red, blu = team.GetScore(RED), team.GetScore(BLUE)
	team.SetScore(RED, blu)
	team.SetScore(BLUE, red)
end

-- CTFGameRules::HandleScrambleTeams: the players dealt out by score (their
-- points: kills and assists, games.gameplay.kill_credit; L.Scramble), the first
-- side at random, and the teams' scores reset.
local function ScrambleTeams()
	local players, byId = {}, {}
	EachPlayer(function(ply)
		if WS.TeamOf(ply) ~= UNASSIGNED then
			players[#players + 1] = { id = ply:UserID(), score = Credit.Points(ply:Frags(), ply:GetNW2Int("ws_assists", 0)) }
			byId[ply:UserID()] = ply
		end
	end)
	for id, t in pairs(WS.TeamRules.Scramble(players, math.random(0, 1) == 0 and RED or BLUE)) do
		WS.SetPlayerTeam(byId[id], t, true)
	end
	team.SetScore(RED, 0)
	team.SetScore(BLUE, 0)
	PrintMessage(HUD_PRINTTALK, "The teams have been scrambled.")
end

return {
	TeamPlayers = TeamPlayers,
	HavePlayers = HavePlayers,
	Scores = Scores,
	TeamLife = TeamLife,
	EachPlayer = EachPlayer,
	SwitchTeams = SwitchTeams,
	ScrambleTeams = ScrambleTeams,
}
