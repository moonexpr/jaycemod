-- ws/sh_spawn_manager.lua: why a player is not spawning, in TF2's words,
-- from what the server shares: the lock (the global ws_spawn_lock) and
-- each player's status and respawn time (NW2), their team and whether
-- teams are played (WS.TeamPlay). Run against fakes.
local T = dofile("tests/harness.lua")
local S = T.require("foundation.spawn_manager")
local Teams = T.require("foundation.teams")

local OBS_MODE_NONE, OBS_MODE_ROAMING = 0, 6

-- A player on team (RED unless given).
local function Player(alive, observing, status, at, team)
	local p = {}
	function p:Team() return team or Teams.RED end
	function p:Alive() return alive end
	function p:GetObserverMode() return observing and OBS_MODE_ROAMING or OBS_MODE_NONE end
	function p:GetNW2Int(_, default) return status or default end
	function p:GetNW2Float(_, default) return at or default end
	return p
end

local function load(lock, teamPlay)
	local ws = {
		require = T.require,
		TEAM_SPECTATOR = Teams.SPECTATOR,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
		TeamPlay = function() return teamPlay ~= false end,
	}
	local env = setmetatable({
		WS = ws,
		OBS_MODE_NONE = OBS_MODE_NONE,
		GetGlobal2String = function(_, default) return lock or default end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_spawn_manager.lua")), env)()
	return ws
end

T.test("dead, a player is told their wait, or that they will not respawn", function()
	local ws = load()
	T.eq(ws.SpawnMessage(Player(false, false, S.WAVE, 15), 10), "Respawn in: 5 seconds")
	T.eq(ws.SpawnMessage(Player(false, false, S.WAVE, 15), 16), "Prepare to respawn")
	T.eq(ws.SpawnMessage(Player(false, false, S.ARENA, 0), 10), "No respawning in Arena Mode")
	T.eq(ws.SpawnMessage(Player(false, false, S.NONE, 0), 10), nil, "Sandbox: they click")
end)

T.test("alive, nothing is said", function()
	T.eq(load().SpawnMessage(Player(true, false, S.WAVE, 15), 10), nil)
end)

T.test("locked, the dead and the watching are told the lock, over any wait", function()
	local ws, held = load("nav"), S.Message(S.HELD, 0, "nav")
	T.eq(ws.SpawnMessage(Player(false, false, S.WAVE, 15), 10), held, "dead")
	T.eq(ws.SpawnMessage(Player(true, true), 10), held, "watching")
	T.eq(ws.SpawnMessage(Player(true, false), 10), nil, "playing on")
end)

T.test("in team play, a watching spectator is told so, and a teamless player to choose a team", function()
	local ws = load()
	T.eq(ws.SpawnMessage(Player(true, true, nil, nil, Teams.SPECTATOR), 10), "Spectator mode")
	T.eq(ws.SpawnMessage(Player(true, true, nil, nil, Teams.UNASSIGNED), 10), "Choose a team")
	T.eq(ws.HoldReason(Player(true, true, nil, nil, Teams.UNASSIGNED)), S.CHOOSE_TEAM)
end)

T.test("outside team play, nobody watching is held but by a lock", function()
	local ws = load(nil, false)
	T.eq(ws.HoldReason(Player(true, true, nil, nil, Teams.SPECTATOR)), S.NONE, "a spectator")
	T.eq(ws.HoldReason(Player(true, true, nil, nil, Teams.UNASSIGNED)), S.NONE, "teamless")
	T.eq(ws.SpawnMessage(Player(false, true, S.ARENA, 0), 10), nil, "dead in a round gone")
	T.eq(load("nav", false).HoldReason(Player(true, true)), S.HELD, "locked")
end)

T.finish()
