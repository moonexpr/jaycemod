-- MyAddon - player tracker
-- An example file that follows the GLua Best Practices.
-- Demonstrates: hook naming, net messages, timers, early returns,
-- file-local state, no unnecessary IsValid checks, print varargs,
-- hot-global localization, server-side net registration,
-- per-player rate limiting of client-triggered messages.
-- Client-side net receivers are omitted for brevity - this is a style
-- example, not a complete addon. In a real addon the server-only hooks,
-- receivers and timers below would live in a server file (see the realm
-- separation rules); they are kept in one file here for readability.

local IsValid = IsValid
local tableCount = table.Count

local HEARTBEAT_INTERVAL = 60
local GREET_DELAY = 5
local REQUEST_COOLDOWN = 1

if SERVER then
	util.AddNetworkString("gmod.one/myaddon/player-count")
	util.AddNetworkString("gmod.one/myaddon/request-count")
end

local playerCount = 0
local trackedPlayers = {}
local nextRequest = {}

local function refreshPlayerCount()
	playerCount = tableCount(trackedPlayers)
end

local function untrackPlayer(ply)
	trackedPlayers[ply] = nil
	nextRequest[ply] = nil
	refreshPlayerCount()
end

local function sendPlayerCount(ply)
	net.Start("gmod.one/myaddon/player-count")
	net.WriteUInt(playerCount, 16)
	net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "gmod.one/myaddon/track-players", function(ply)
	-- No IsValid check needed here: the player just spawned and is guaranteed valid
	trackedPlayers[ply] = true
	refreshPlayerCount()
	sendPlayerCount(ply)

	timer.Create("gmod.one/myaddon/greet-" .. ply:SteamID64(), GREET_DELAY, 1, function()
		-- IsValid check is required here: the player may have disconnected before this timer triggers
		if IsValid(ply) == false then return end

		ply:ChatPrint("Welcome!")
	end)
end)

hook.Add("PlayerDisconnected", "gmod.one/myaddon/untrack-players", untrackPlayer)

net.Receive("gmod.one/myaddon/request-count", function(_, ply)
	if playerCount == 0 then return end
	if (nextRequest[ply] or 0) > CurTime() then return end

	nextRequest[ply] = CurTime() + REQUEST_COOLDOWN
	sendPlayerCount(ply)
end)

timer.Create("gmod.one/myaddon/heartbeat", HEARTBEAT_INTERVAL, 0, function()
	if playerCount == 0 then return end

	print("MyAddon: tracking", playerCount, "players")
end)
