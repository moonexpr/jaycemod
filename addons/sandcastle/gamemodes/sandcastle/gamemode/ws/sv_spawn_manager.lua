-- The spawn manager's controller (games.system.spawn_manager): the gate every
-- player spawn goes through. Whatever spawns players (the rounds' waves and
-- round starts, a stopped game's pauses, admins, the holiday's teleports)
-- spawns them with WS.Respawn; GMod's own spawns, respawn clicks and team
-- requests pass the gate's hooks. A lock (WS.LockSpawns: the nav mesh being
-- generated, ws/sv_nav.lua) holds everyone back, a player who would spawn
-- watching meanwhile; lifting it (WS.UnlockSpawns) spawns all of them.
-- Every client is told the lock (the global ws_spawn_lock) and each player
-- why they are not spawning (WS.SetSpawnStatus), for ws/sh_spawn_manager.lua
-- to put in words.
local S = WS.require("games.system.spawn_manager")

-- Kept across a Lua refresh: the locks and the players held stay.
WS.SpawnManager = WS.SpawnManager or S.New()
local manager = WS.SpawnManager

local function Publish()
	SetGlobal2String("ws_spawn_lock", manager:LockedBy() or "")
end

local function Held(ply)
	ply:PrintMessage(HUD_PRINTCENTER, S.Message(S.HELD, 0, manager:LockedBy()))
end

function WS.LockSpawns(lock)
	manager:Lock(lock)
	Publish()
end

-- Lifts lock; once none is left, everyone held spawns.
function WS.UnlockSpawns(lock)
	local released = manager:Unlock(lock)
	Publish()
	for _, ply in ipairs(released) do
		if IsValid(ply) then
			WS.StopObserving(ply)
			ply:Spawn()
		end
	end
end

-- Spawns players due to (a wave, a round's start): those the gate lets
-- through.
function WS.Respawn(players)
	for _, ply in ipairs(manager:Spawnable(players)) do ply:Spawn() end
end

-- Whether ply may pick a team now (the gamemode's own team commands);
-- if not, they are told why.
function WS.MayChooseTeam(ply)
	if manager:MayChooseTeam() then return true end
	Held(ply)
	return false
end

-- Why a dead player is not spawning (a games.system.spawn_manager status)
-- and, for a wave, when it comes.
function WS.SetSpawnStatus(ply, status, at)
	ply:SetNW2Int("ws_spawn_status", status)
	ply:SetNW2Float("ws_respawn_time", at)
end

hook.Add("PlayerSpawn", "ws_spawn_manager", function(ply)
	if manager:Admit(ply) then return end
	WS.StartObserving(ply)
	return true
end)

hook.Add("PlayerDeathThink", "ws_spawn_manager", function(ply)
	if not manager:MayRespawn(ply) then return false end
end)

local function RefuseTeam(ply)
	if not WS.MayChooseTeam(ply) then return true end
end

hook.Add("PlayerRequestTeam", "ws_spawn_manager", RefuseTeam)
hook.Add("ShowTeam", "ws_spawn_manager", RefuseTeam)
