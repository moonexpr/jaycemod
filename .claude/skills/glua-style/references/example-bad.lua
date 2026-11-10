-- MyAddon - player tracker
-- BAD example: this file violates the GLua Best Practices.
-- Do NOT copy this file. Compare it against example-good.lua and find every violation.

playerCount = 0
trackedPlayers = {}

local function refresh()
	playerCount = table.Count(trackedPlayers)
end

local function untrackPlayer(ply)
	-- remove player from list
	trackedPlayers[ply] = nil
	refresh()
end

local function sendPlayerCount(ply)
	net.Start("gmod.one/myaddon/player-count")
	net.WriteUInt(playerCount, 16)
	net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "gmod.one/myaddon/on-player-initial-spawn", function(ply)
	if (IsValid(ply) == false) then return end
	if (trackedPlayers[ply] == nil) then
		trackedPlayers[ply] = true
		playerCount = playerCount + 1
		sendPlayerCount(ply)
	end

	timer.Create("gmod.one/myaddon/greet-" .. ply:SteamID64(), 5, 1, function()
		if (!IsValid(ply)) then return end

		ply:ChatPrint('Welcome!')
	end)
end)

hook.Add("PlayerDisconnected", "gmod.one/myaddon/untrack-players", function(ply)
	if (trackedPlayers[ply] != nil) then
		trackedPlayers[ply] = nil
		playerCount = playerCount - 1
		print("Count: " .. tostring(playerCount))
	end
end)

net.Receive("gmod.one/myaddon/request-count", function(_, ply)
	if (playerCount == 0) then return end

	sendPlayerCount(ply)
end)

timer.Create("gmod.one/myaddon/heartbeat", 60, 0, function()
	if (playerCount == 0) then return end

	for k, v in pairs(trackedPlayers) do
		print("tracking " .. v)
	end
end)
