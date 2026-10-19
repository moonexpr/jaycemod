-- The spawn manager, shared (ws/sv_spawn_manager.lua runs it): why a
-- player is not spawning, in TF2's words (foundation.spawn_manager), from
-- what the server shares: the lock (the global ws_spawn_lock, "" for none)
-- and each player's status and respawn time (NW2 ws_spawn_status,
-- ws_respawn_time). ws/cl_spawn_manager.lua shows it.
local S = WS.require("foundation.spawn_manager")

-- The words for ply at now, or nil when there is nothing to say: under a
-- lock, the lock's to the dead and the watching; else, dead, their status.
function WS.SpawnMessage(ply, now)
	local lock = GetGlobal2String("ws_spawn_lock", "")
	local out = not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE
	if lock ~= "" and out then return S.Message(S.HELD, 0, lock) end
	if ply:Alive() then return nil end
	return S.Message(ply:GetNW2Int("ws_spawn_status", S.NONE), ply:GetNW2Float("ws_respawn_time", 0) - now)
end
