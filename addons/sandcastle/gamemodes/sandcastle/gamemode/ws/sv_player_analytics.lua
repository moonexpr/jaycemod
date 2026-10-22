-- Player analytics (games.gameplay.player_analytics): each human player's joins
-- and leaves, and their victories (an enemy player or soldier killed, a
-- point captured standing on it or a flag captured carrying it, a round won
-- on the winning team), appended to data/sandcastle/player_events.txt, a
-- line each, as they happen: a few lines a minute, nothing per tick. Bots
-- and the AI war's soldiers are not players here. A map change ends every
-- session (ShutDown) and the next map starts it again, which the model
-- reads as one session.
--
-- ws_analytics_exclude lists SteamID64s left out (the developers): nothing
-- of theirs is recorded, and the report leaves out what was. Set it in the
-- server's own server.cfg, not in the repo. A list that does not parse
-- records nothing at all, and says so, rather than record a developer.
--
-- ws_analytics_players prints retention and the time to a first victory;
-- WS.PlayerAnalytics() returns the same as tables. Both read the whole log,
-- and need the server options privilege.
local PA = WS.require("games.gameplay.player_analytics")
local Permissions = WS.require("games.system.permissions")

local DIR = "sandcastle"
local LOG = DIR .. "/player_events.txt"
local HOOK = "ws_player_analytics"
local GAME_TEAMS = {
	[WS.TEAM_RED] = true,
	[WS.TEAM_BLUE] = true,
}

local exclude = CreateConVar("ws_analytics_exclude", "", FCVAR_PROTECTED,
	"SteamID64s left out of player analytics (developers), separated by commas")

local function Excluded()
	return PA.Excluded(exclude:GetString())
end

local function Human(ent)
	return IsValid(ent) and ent:IsPlayer() and not ent:IsBot()
end

local function Record(event)
	local ok, excluded = pcall(Excluded)
	if not ok then
		ErrorNoHalt("ws_analytics_exclude: " .. tostring(excluded) .. "; recording nothing until it is fixed\n")
		return
	end
	event = PA.Exclude(event, excluded)
	if not event then return end
	file.CreateDir(DIR)
	file.Append(LOG, PA.Encode(event) .. "\n")
end

local function Victory(kind, players)
	local ids = {}
	for _, ply in ipairs(players) do
		if Human(ply) then ids[#ids + 1] = ply:SteamID64() end
	end
	if #ids > 0 then Record(PA.Victory(kind, ids, os.time())) end
end

hook.Add("PlayerInitialSpawn", HOOK, function(ply)
	if Human(ply) then Record(PA.Join(ply:SteamID64(), os.time())) end
end)

hook.Add("PlayerDisconnected", HOOK, function(ply)
	if Human(ply) then Record(PA.Leave(ply:SteamID64(), os.time())) end
end)

hook.Add("ShutDown", HOOK, function()
	for _, ply in ipairs(player.GetHumans()) do Record(PA.Leave(ply:SteamID64(), os.time())) end
end)

-- An enemy: of the other game team.
local function Enemies(attacker, victimTeam)
	local own = attacker:Team()
	return GAME_TEAMS[own] and GAME_TEAMS[victimTeam] and own ~= victimTeam
end

hook.Add("PlayerDeath", HOOK, function(victim, _, attacker)
	if Human(attacker) and attacker ~= victim and Enemies(attacker, victim:Team()) then Victory(PA.KILL, { attacker }) end
end)

hook.Add("OnNPCKilled", HOOK, function(npc, attacker)
	if Human(attacker) and Enemies(attacker, WS.LastTeamNumber(npc)) then Victory(PA.KILL, { attacker }) end
end)

hook.Add("WSPointCappers", HOOK, function(_, _, occupants) Victory(PA.CAPTURE, occupants) end)

hook.Add("WSFlagCaptured", HOOK, function(_, _, carrier) Victory(PA.CAPTURE, { carrier }) end)

hook.Add("WSRoundWin", HOOK, function(winner)
	if GAME_TEAMS[winner] then Victory(PA.ROUND, team.GetPlayers(winner)) end
end)

-- Reading --------------------------------------------------------------------------

-- The log's events; a line that is not one fails the read, naming it.
local function Events()
	local text = file.Read(LOG, "DATA") or ""
	local events, number = {}, 0
	for line in string.gmatch(text, "[^\n]+") do
		number = number + 1
		events[#events + 1] = PA.Parse(line, number)
	end
	return events
end

function WS.PlayerAnalytics()
	local now = os.time()
	local players = PA.Players(Events(), now, Excluded())
	return {
		players = table.Count(players),
		retention = PA.Retention(players, now),
		firstVictory = PA.FirstVictory(players),
	}
end

local function Duration(seconds)
	if seconds == nil then return "-" end
	if seconds < 3600 then return string.format("%dm", math.floor(seconds / 60)) end
	if seconds < 86400 then return string.format("%.1fh", seconds / 3600) end
	return string.format("%.1fd", seconds / 86400)
end

local function Share(count, of)
	if count == nil then return "not yet" end
	return string.format("%d (%d%%)", count, math.Round(100 * count / of))
end

local KIND_NAMES = {
	[PA.ANY] = "any",
	[PA.KILL] = "a kill",
	[PA.CAPTURE] = "a capture",
	[PA.ROUND] = "a round won",
}

local function Report()
	local a = WS.PlayerAnalytics()
	local lines = { string.format("Players: %d (humans; data/%s)", a.players, LOG), "", "Retention, by the day first seen (UTC):",
		"  day         new  back next day   back within 7 days" }
	for _, c in ipairs(a.retention) do
		lines[#lines + 1] = string.format("  %s  %4d  %-14s  %s", os.date("!%Y-%m-%d", c.day * PA.DAY), c.new, Share(c.day1, c.new), Share(c.day7, c.new))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "First victory:                had it  not yet  median play  median sessions  median since first seen"
	for _, kind in ipairs({ PA.ANY, PA.KILL, PA.CAPTURE, PA.ROUND }) do
		local v = a.firstVictory[kind]
		lines[#lines + 1] = string.format("  %-27s %6d  %7d  %11s  %15s  %s", KIND_NAMES[kind], v.won, v.notYet, Duration(v.medianPlaySeconds),
			v.medianSessions and tostring(v.medianSessions) or "-", Duration(v.medianWallSeconds))
	end
	return table.concat(lines, "\n")
end

concommand.Add("ws_analytics_players", function(ply)
	if not WS.Can(ply, Permissions.SERVER_OPTIONS) then return end
	local ok, text = pcall(Report)
	if not ok then text = "ws_analytics_players: " .. tostring(text) end
	for line in string.gmatch(text, "[^\n]+") do
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
	end
end, nil, "Players' retention and time to a first victory, from data/" .. LOG)
