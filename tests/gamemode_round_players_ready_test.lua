-- RoundPlayersReady: the gamemode controller (features/gamemode/sv.lua)
-- runs the hook once as a game is set to begin with its players, whichever
-- way it came to: a request for Gameplay mode (the Begin Game button, the
-- console's sv_gameplay_enabled, the AI war), a wait for players that ends
-- (MvM's ready-up), or a map's load countdown opening (cut short by Hurry
-- as the expected players come in, or reaching its last stretch without
-- them). Late addons register what they bring (a NextSoldier scenario)
-- before it runs.
--
-- The controller is loaded in a fake GMod: a hook library that runs its
-- listeners as GMod's does, a clock, convars, players and a rounds feature
-- under the test's hand; every other engine global and WS function is an
-- inert stub.
local T = dofile("tests/harness.lua")
local Gamemode = system.gamemode
local Teams = gameplay.teams
local Rounds = gameplay.rounds

local SOURCE = T.ROOT .. "features/gamemode/sv.lua"
local HOOK = "RoundPlayersReady"

local Inert = setmetatable({}, {
	__index = function(stub) return stub end,
	__call = function(stub) return stub end,
})

local function Convar(value)
	return {
		value = value,
		GetBool = function(self) return self.value end,
		SetBool = function(self, v) self.value = v end,
	}
end

local function Player(team)
	local nw = {}
	return {
		team = team,
		GetNW2Bool = function(_, key, default)
			if nw[key] == nil then return default end
			return nw[key]
		end,
		SetNW2Bool = function(_, key, value) nw[key] = value end,
		Team = function(self) return self.team end,
		Nick = function() return "Pat" end,
	}
end

-- A game world: w.now, w.enabled (sv_gameplay_enabled at load), w.waiting
-- (mp_waitingforplayers), w.mvm, w.needed (the rounds mode's
-- PLAYERS_NEEDED), w.players, w.expectedIn (WS.ExpectedPlayersIn); w.ready,
-- how many times RoundPlayersReady ran, and w.heard, the hooks heard in order.
local function World(over)
	local w = {
		now = 100,
		enabled = false,
		waiting = false,
		mvm = false,
		needed = Rounds.Mode.PLAYERS_NEEDED,
		players = {},
		expectedIn = false,
		ready = 0,
		heard = {},
	}
	for k, v in pairs(over or {}) do w[k] = v end
	return w
end

local function Load(w)
	local listeners = {}
	local hook = {
		Add = function(name, id, fn)
			listeners[name] = listeners[name] or {}
			listeners[name][id] = fn
		end,
		Run = function(name, ...)
			for _, fn in pairs(listeners[name] or {}) do
				local value = fn(...)
				if value ~= nil then return value end
			end
		end,
	}
	hook.Add(HOOK, "test_addon", function()
		w.ready = w.ready + 1
		w.heard[#w.heard + 1] = HOOK
	end)
	hook.Add("MatchStart", "test_addon", function() w.heard[#w.heard + 1] = "MatchStart" end)
	local rounds = {
		Mode = function()
			return { PLAYERS_NEEDED = w.needed, OBJECTIVE = true }
		end,
	}
	local convars = {
		sv_gameplay_enabled = Convar(w.enabled),
		sv_gameplay_disable_sandbox = Convar(false),
	}
	local ws = setmetatable({
		require = T.require,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
		TEAM_UNASSIGNED = Teams.UNASSIGNED,
		TEAM_SPECTATOR = Teams.SPECTATOR,
		Active = function() return true end,
		Feature = function(name)
			if name == "rounds" then return rounds end
			return Inert
		end,
		TeamOf = function(ply) return ply.team end,
		ExpectedPlayersIn = function() return w.expectedIn end,
		-- the gamerules: beginning the game starts the rounds, whose first
		-- state change is heard as it comes
		Rules = {
			BeginGame = function() w.heard[#w.heard + 1] = "BeginGame" end,
			Halt = function() end,
			CleanUp = function() end,
		},
	}, { __index = function() return Inert end })
	local env = setmetatable({
		WS = ws,
		hook = hook,
		IsValid = function(value) return value ~= nil end,
		CurTime = function() return w.now end,
		GetConVar = function(name) return convars[name] end,
		CreateConVar = function() return Convar(w.waiting) end,
		GetGlobal2Bool = function(name, default)
			if name == "ws_mvm" then return w.mvm end
			return default
		end,
		player = {
			GetAll = function() return w.players end,
			GetHumans = function() return w.players end,
		},
		game = { GetMap = function() return "pl_test" end },
		ents = { FindByClass = function() return {} end },
		timer = { Create = function() end, Remove = function() end },
	}, {
		__index = function(_, name)
			local value = _G[name]
			if value == nil then return Inert end
			return value
		end,
	})
	return setfenv(assert(loadfile(SOURCE)), env)()
end

T.test("an admin's Begin Game, in Sandbox mode with the players there, runs it once", function()
	local w = World()
	local controller = Load(w)
	T.eq(controller:Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_BUTTON, nil), true, "granted")
	T.eq(w.ready, 1, "ran once")
	controller:Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_BUTTON, nil)
	T.eq(w.ready, 1, "a second request, refused as already counting, does not run it again")
end)

T.test("an admin setting sv_gameplay_enabled 1 in the console runs it", function()
	local w = World()
	Load(w):SettingChanged(true, nil)
	T.eq(w.ready, 1, "ran once")
end)

T.test("the AI war's request for Gameplay mode runs it", function()
	local w = World()
	Load(w):Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_AI_WAR, nil, { title = "AI war", lines = {} })
	T.eq(w.ready, 1, "ran once")
end)

T.test("an MvM game waits for its defenders, and runs it once the last one readies up", function()
	local pat = Player(Teams.RED)
	local w = World({ waiting = true, mvm = true, needed = { team = Teams.RED, count = 1 }, players = { pat } })
	local controller = Load(w)
	controller:Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_BUTTON, nil)
	T.eq(w.ready, 0, "not while it waits")
	controller:WaitTick()
	T.eq(w.ready, 0, "nor while the defender is not ready")
	controller:ToggleReady(pat)
	T.eq(w.ready, 1, "ran once the defender readied up")
	controller:WaitTick()
	T.eq(w.ready, 1, "once")
end)

T.test("a game waiting for players runs it once they come", function()
	local w = World({ waiting = true, needed = { count = 2 }, players = { Player(Teams.RED) } })
	local controller = Load(w)
	controller:Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_BUTTON, nil)
	T.eq(w.ready, 0, "one of two: it waits")
	w.players[2] = Player(Teams.BLUE)
	controller:WaitTick()
	T.eq(w.ready, 1, "ran once the second came")
end)

T.test("a map loading in Gameplay mode runs it as the expected players hurry its countdown, not at load", function()
	local w = World({ enabled = true })
	local controller = Load(w)
	controller:StartAtLoad()
	T.eq(w.ready, 0, "not as the load's countdown starts")
	w.now = w.now + 1
	controller:Tick()
	T.eq(w.ready, 0, "nor while the players are still loading")
	w.expectedIn = true
	w.now = w.now + 1
	controller:Tick()
	T.eq(w.ready, 1, "ran once they were in")
	for _ = 1, Gamemode.HURRIED_COUNTDOWN + 1 do
		w.now = w.now + 1
		controller:Tick()
	end
	T.eq(w.ready, 1, "once, through the countdown's end")
end)

-- The match starts with the countdown's first pre-round (the scores
-- cleared, everyone on a team), after its players were ready and before
-- the rounds begin, so its first round's state changes come after it.
T.test("a game's countdown runs MatchStart once, at its first pre-round, before the rounds begin", function()
	local w = World()
	local controller = Load(w)
	controller:Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_BUTTON, nil)
	w.now = w.now + Gamemode.ADMIN_LINE_AT - Gamemode.PREROUND_AT - 1
	controller:Tick()
	T.eq(table.concat(w.heard, " "), HOOK, "not before the pre-round")
	w.now = w.now + 1
	controller:Tick()
	T.eq(table.concat(w.heard, " "), HOOK .. " MatchStart BeginGame", "at it, before the rounds begin")
	for _ = 1, Gamemode.PREROUND_AT + 1 do
		w.now = w.now + 1
		controller:Tick()
	end
	T.eq(table.concat(w.heard, " "), HOOK .. " MatchStart BeginGame", "once, through Gameplay mode's beginning")
end)

T.test("a load's countdown its expected players never cut short runs it at its last stretch", function()
	local w = World({ enabled = true })
	local controller = Load(w)
	controller:StartAtLoad()
	w.now = w.now + Gamemode.LOAD_COUNTDOWN - Gamemode.HURRIED_COUNTDOWN
	controller:Tick()
	T.eq(w.ready, 1, "ran once")
end)

T.test("a request in Gameplay mode, or for Sandbox mode, does not run it", function()
	local w = World({ enabled = true })
	local controller = Load(w)
	controller:Request(Gamemode.GAMEPLAY, Gamemode.SOURCE_BUTTON, nil)
	controller:Request(Gamemode.SANDBOX, Gamemode.SOURCE_BUTTON, nil)
	T.eq(w.ready, 0, "never")
end)

T.finish()
