-- ws/sv_spawn_manager.lua: the spawn manager's controller, the gate every
-- player spawn goes through. Locked (WS.LockSpawns), nobody picks a team, a
-- player who would spawn watches, the dead stay down and a wave
-- (WS.Respawn) brings nobody; unlocked, all of them spawn. Every client is
-- told the lock, and each player why they are not spawning. Run against
-- fakes of hook, the NW2 globals and players.
local T = dofile ("tests/harness.lua")
local S = system.spawn_manager

local function Player (alive, team)
	local p = { alive = alive, team = team or 2, spawns = 0, centre = {}, nw = {} }
	function p:Team () return self.team end
	function p:Alive () return self.alive end
	function p:Spawn () self.spawns, self.alive = self.spawns + 1, true end
	function p:StripWeapons () self.stripped = true end
	function p:Spectate (mode) self.observerMode = mode end
	function p:UnSpectate () self.observerMode = nil end
	function p:PrintMessage (_, text) self.centre [#self.centre + 1] = text end
	function p:SetNW2Int (k, v) self.nw [k] = v end
	function p:SetNW2Float (k, v) self.nw [k] = v end
	return p
end

local function load ()
	local s = { hooks = {}, globals = {}, classes = {} }
	s.ws =
	{
		require = T.require,
		Spectator =
		{
			Enter = function (ply, team)
				s.classes [ply] = "player_spectator"
				ply:StripWeapons ()
				ply:Spectate (team == 1 and 5 or 1)
			end
		}
	}
	local env = setmetatable (
		{
			WS = s.ws,
			player_manager = { SetPlayerClass = function (ply, class) s.classes [ply] = class end },
			hook = { Add = function (event, _, fn) s.hooks [event] = fn end },
			SetGlobal2String = function (k, v) s.globals [k] = v end,
			IsValid = function (p) return p ~= nil end,
			HUD_PRINTCENTER = 4,
			OBS_MODE_FIXED = 1,
			OBS_MODE_ROAMING = 5,
			TEAM_SPECTATOR = 1
		}, { __index = _G })
	setfenv (assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/sv_spawn_manager.lua")), env) ()
	return s
end

T.test ("unlocked, the gate lets everything through", function ()
	local s, ply = load (), Player (false)
	T.eq (s.hooks.PlayerSpawn (ply),      nil, "spawns as the gamemode says")
	T.eq (s.hooks.PlayerDeathThink (ply), nil, "respawns as the gamemode says")
	T.eq (s.hooks.PlayerRequestTeam (ply, 2), nil)
	T.eq (s.hooks.ShowTeam (ply),             nil)
	s.ws.Respawn ({ ply })
	T.eq (ply.spawns, 1, "a wave spawns")
end)

T.test ("locked, nobody picks a team, spawns or respawns, and every client is told the lock", function ()
	local s = load ()
	s.ws.LockSpawns ("nav")
	T.eq (s.globals.ws_spawn_lock, "nav", "told")
	local joiner, dead, waved = Player (true), Player (false), Player (false)
	T.eq (s.hooks.PlayerSpawn (joiner),    true,               "no spawn")
	T.eq (s.classes [joiner],              "player_spectator", "uses the spectator class")
	T.eq (joiner.observerMode,             1,                  "native fixed observer outside the spectator team")
	T.eq (joiner.stripped,                 true,               "no weapons")
	T.eq (s.hooks.PlayerDeathThink (dead), false,              "stays down")
	s.ws.Respawn ({ waved })
	T.eq (waved.spawns,                          0,                            "the wave brings nobody")
	T.eq (s.hooks.PlayerRequestTeam (joiner, 2), true,                         "refused")
	T.eq (s.hooks.ShowTeam (joiner),             true,                         "no team menu")
	T.eq (joiner.centre [#joiner.centre],        S.Message (S.HELD, 0, "nav"), "told why")
	T.eq (s.ws.MayChooseTeam (joiner),           false,                        "for the gamemode's own team commands")
end)

T.test ("unlocked again, everyone held spawns, and the living play on", function ()
	local s = load ()
	local living, joiner, dead, waved = Player (true), Player (true), Player (false), Player (false)
	s.ws.LockSpawns ("nav")
	s.hooks.PlayerSpawn (joiner)
	s.hooks.PlayerDeathThink (dead)
	s.ws.Respawn ({ waved })
	s.ws.UnlockSpawns ("nav")
	T.eq (s.globals.ws_spawn_lock, "",  "told it is lifted")
	T.eq (joiner.observerMode,     nil, "leaves native observer mode")
	T.eq (joiner.spawns, 1)
	T.eq (dead.spawns,   1)
	T.eq (waved.spawns,  1)
	T.eq (living.spawns,                       0,   "never held")
	T.eq (s.hooks.PlayerSpawn (Player (true)), nil, "spawns as usual")
end)

T.test ("each player is told why they are not spawning", function ()
	local s, ply = load (), Player (false)
	s.ws.SetSpawnStatus (ply, S.WAVE, 42)
	T.eq (ply.nw.ws_spawn_status, S.WAVE)
	T.eq (ply.nw.ws_respawn_time, 42)
end)

T.finish ()
