-- The spawn manager, shared (ws/sv_spawn_manager.lua runs it): why a
-- player is not spawning, in TF2's words (games.system.spawn_manager), from
-- what the server shares: the lock (the global ws_spawn_lock, "" for none)
-- and each player's status and respawn time (NW2 ws_spawn_status,
-- ws_respawn_time). ws/cl_spawn_manager.lua shows it.
local S = WS.require("games.system.spawn_manager")

-- Why ply is held out of play (games.system.spawn_manager's Reason), NONE
-- when nothing holds them: the server spawns a watcher held for nothing
-- (ws/sv_spectate.lua), and the client says the reason (SpawnMessage).
function WS.HoldReason(ply)
	local team = ply:Team()
	return S.Reason({
		out = not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE,
		locked = GetGlobal2String("ws_spawn_lock", "") ~= "",
		teamPlay = WS.TeamPlay(),
		spectator = team == WS.TEAM_SPECTATOR,
		playing = team == WS.TEAM_RED or team == WS.TEAM_BLUE,
		alive = ply:Alive(),
		status = ply:GetNW2Int("ws_spawn_status", S.NONE),
	})
end

-- The words for ply at now, or nil when there is nothing to say.
function WS.SpawnMessage(ply, now)
	return S.Message(WS.HoldReason(ply), ply:GetNW2Float("ws_respawn_time", 0) - now,
		GetGlobal2String("ws_spawn_lock", ""))
end
