-- The players expected from the previous map (games.gameplay.arrivals): the
-- humans on the server as a map ends, written to data/ and read as the next
-- loads, each counted in as their client loads (system_client_ready) or
-- leaves. The gamemode cuts a map's load countdown short once they are all
-- in (WS.ExpectedPlayersIn).
local Arrivals = gameplay.arrivals

local FILE = "ws_arrivals.txt" -- under garrysmod/data

-- Kept across a Lua refresh: the file was this map's at its load.
WS.Arrivals = WS.Arrivals or Arrivals.New(Arrivals.Read(file.Read(FILE, "DATA") or "", os.time()))

function WS.ExpectedPlayersIn()
	return WS.Arrivals:Done()
end

WS.Events.Listen("system_client_ready", "ws_arrivals", function(_, ply)
	WS.Arrivals:Arrived(ply:SteamID64())
end)

-- A player can leave while still loading, before any player hook sees them.
gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "ws_arrivals", function(data)
	WS.Arrivals:Left(util.SteamIDTo64(data.networkid))
end)

hook.Add("ShutDown", "ws_arrivals", function()
	local ids = {}
	for _, ply in ipairs(player.GetHumans()) do ids[#ids + 1] = ply:SteamID64() end
	file.Write(FILE, Arrivals.Write(ids, os.time()))
end)
