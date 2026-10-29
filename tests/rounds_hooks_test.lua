-- The round's moments as hooks, for addons: the rounds controller
-- (features/rounds/sv.lua) runs SetupStart, RoundStart, BonusRoundStart,
-- BonusRoundEnd and MatchEnded from the model's effects (and the map's
-- timers' setup), each once a moment, with what decided it. MatchStart is
-- the gamemode's (tests/gamemode_round_players_ready_test.lua).
--
-- The controller is loaded in a fake GMod with a hook library that runs
-- its listeners as GMod's does; every other engine global and WS function
-- is an inert stub. The effects are the model's, as games.gameplay.rounds
-- makes them (tests/rounds_game_test.lua pins their order).
local T = dofile("tests/harness.lua")
local FakeObjective = dofile("tests/fake_objective.lua")
local Teams = gameplay.teams
local Rounds = gameplay.rounds
local STATE = T.require("games.gameplay.rounds.state")

local SOURCE = T.ROOT .. "features/rounds/sv.lua"
local RED, NOBODY = Teams.RED, Teams.UNASSIGNED
local HOOKS = { "SetupStart", "RoundStart", "BonusRoundStart", "BonusRoundEnd", "MatchStart", "MatchEnded", "RoundStateChanged" }

local Inert = setmetatable({}, {
	__index = function(stub) return stub end,
	__call = function(stub) return stub end,
})

local function ConVar(default)
	return {
		GetFloat = function() return tonumber(default) end,
		GetInt = function() return math.floor(tonumber(default)) end,
		GetBool = function() return tonumber(default) ~= 0 end,
		GetString = function() return default end,
		GetDefault = function() return default end,
	}
end

-- The controller, and heard: name -> the argument lists each run of that
-- hook was heard with, by a listener as an addon's.
local function Load()
	local wiring = T.Wiring()
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
	local heard = { order = {} }
	for _, name in ipairs(HOOKS) do
		heard[name] = {}
		hook.Add(name, "test_addon", function(...)
			heard[name][#heard[name] + 1] = { ... }
			heard.order[#heard.order + 1] = name
		end)
	end
	local ws = setmetatable({
		require = T.require,
		FeatureParts = T.FeatureParts,
		Events = wiring.Events,
		STATE = STATE,
		TEAM_UNASSIGNED = Teams.UNASSIGNED,
		TEAM_SPECTATOR = Teams.SPECTATOR,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
		State = function() return STATE.RND_RUNNING end,
		-- the gamerules' fact watch is a transaction on the slow lane
		SlowTransactions = list.schedule.New({ Now = function() return 0 end }),
	}, { __index = function() return Inert end })
	local env = setmetatable({
		WS = ws,
		hook = hook,
		concommand = wiring.concommand,
		cvars = wiring.cvars,
		timer = { Create = function() end, Simple = function() end, Remove = function() end },
		GetConVar = function() return nil end,
		CreateConVar = function(_, default) return ConVar(default) end,
		CurTime = function() return 0 end,
		IsValid = function() return false end,
		player = { GetAll = function() return {} end, GetHumans = function() return {} end },
		ents = { FindByClass = function() return {} end, GetAll = function() return {} end },
		team = { GetPlayers = function() return {} end, AddScore = function() end },
	}, {
		__index = function(_, name)
			local value = _G[name]
			if value == nil then return Inert end
			return value
		end,
	})
	return setfenv(assert(loadfile(SOURCE)), env)(), heard
end

local function Hook(name, args) return { kind = "hook", name = name, args = args } end

T.test("a round that runs (the model's WSRoundActive) runs RoundStart", function()
	local controller, heard = Load()
	controller:Apply({ Hook("WSRoundActive", {}) })
	T.eq(#heard.RoundStart, 1, "once")
end)

T.test("a round won opens the bonus round: BonusRoundStart, with the winner and why", function()
	local controller, heard = Load()
	controller:Apply({ Hook("WSRoundWin", { RED, Rounds.WINREASON.ALL_POINTS_CAPTURED }) })
	T.eq(#heard.BonusRoundStart, 1, "once")
	T.eq(heard.BonusRoundStart[1][1], RED, "the winner")
	T.eq(heard.BonusRoundStart[1][2], Rounds.WINREASON.ALL_POINTS_CAPTURED, "why")
end)

T.test("leaving TEAM_WIN, however, ends the bonus round: BonusRoundEnd", function()
	for _, to in ipairs({ STATE.PREROUND, STATE.GAME_OVER, STATE.BETWEEN_RNDS }) do
		local controller, heard = Load()
		controller:Apply({ { kind = "state", from = STATE.TEAM_WIN, to = to } })
		T.eq(#heard.BonusRoundEnd, 1, "to state " .. to)
	end
	local controller, heard = Load()
	controller:Apply({ { kind = "state", from = STATE.PREROUND, to = STATE.RND_RUNNING } })
	T.eq(#heard.BonusRoundEnd, 0, "no other state change")
end)

-- RoundStateChanged is late: it runs once everything the change brought
-- has (the batch of the model's effects it came in all applied).
T.test("every round state change runs RoundStateChanged (previous, next), after all the change brought", function()
	local controller, heard = Load()
	controller:Apply({
		{ kind = "state", from = STATE.PREROUND, to = STATE.RND_RUNNING },
		Hook("WSRoundActive", {}),
	})
	T.eq(table.concat(heard.order, " "), "RoundStart RoundStateChanged", "after the round's start")
	T.eq(heard.RoundStateChanged[1][1] .. " " .. heard.RoundStateChanged[1][2], STATE.PREROUND .. " " .. STATE.RND_RUNNING,
		"the states before and after")
end)

T.test("a batch of several changes runs RoundStateChanged for each, in order, once all are applied", function()
	local controller, heard = Load()
	controller:Apply({
		{ kind = "state", from = STATE.RND_RUNNING, to = STATE.TEAM_WIN },
		Hook("WSRoundWin", { RED, Rounds.WINREASON.ALL_POINTS_CAPTURED }),
		{ kind = "intermission", winner = RED, reason = "Reached the win limit", ["until"] = 40 },
		{ kind = "state", from = STATE.TEAM_WIN, to = STATE.GAME_OVER },
	})
	T.eq(table.concat(heard.order, " "),
		"BonusRoundStart MatchEnded BonusRoundEnd RoundStateChanged RoundStateChanged", "last")
	T.eq(heard.RoundStateChanged[1][2] .. " " .. heard.RoundStateChanged[2][2], STATE.TEAM_WIN .. " " .. STATE.GAME_OVER, "in order")
	controller:Apply({ Hook("WSRoundActive", {}) })
	T.eq(#heard.RoundStateChanged, 2, "a batch without a change runs none")
end)

T.test("the match's end, its winner decided, runs MatchEnded with the winner and why", function()
	local controller, heard = Load()
	controller:Apply({ { kind = "intermission", winner = RED, reason = "Reached the win limit", ["until"] = 40 } })
	T.eq(#heard.MatchEnded, 1, "once")
	T.eq(heard.MatchEnded[1][1], RED, "the winner")
	T.eq(heard.MatchEnded[1][2], "Reached the win limit", "why")
	controller, heard = Load()
	controller:Apply({ { kind = "intermission", winner = NOBODY, reason = Rounds.STALEMATE_GAME_OVER, ["until"] = 40 } })
	T.eq(heard.MatchEnded[1][1], NOBODY, "a drawn match: nobody won")
end)

-- The controller's round model, driven as the map's think does, into its
-- pre-round, then to RND_RUNNING.
local function World()
	return {
		havePlayers = true,
		teams = { [Teams.RED] = { players = 1, alive = 1 }, [Teams.BLUE] = { players = 1, alive = 1 } },
		scores = { [Teams.RED] = 0, [Teams.BLUE] = 0 },
		timerMayExpire = true,
		mapHasActiveTimer = true,
		objective = FakeObjective.Objective(),
	}
end
local T0 = 100

local function Preround(controller)
	controller.round:Think(T0, World())
	T.eq(controller.round:State(), STATE.PREROUND, "pre-round")
end

local function Run(controller)
	controller.round:Think(controller.round:PreroundEnd(), World())
	T.eq(controller.round:State(), STATE.RND_RUNNING, "running")
end

-- A map's setup timer arms its setup as it is made (the pre-round's
-- cleanup), and counts it down once the round runs: setup starts then.
T.test("a round that runs in setup runs SetupStart after RoundStart, not as its timer arms it", function()
	local controller, heard = Load()
	controller:SetSetup(true)
	T.eq(#heard.SetupStart, 0, "not armed on a halted map")
	controller:SetSetup(false)
	Preround(controller)
	controller:SetSetup(true)
	T.eq(#heard.SetupStart, 0, "nor in the pre-round")
	Run(controller)
	controller:Apply({ Hook("WSRoundActive", {}) })
	T.eq(table.concat(heard.order, " "), "RoundStart SetupStart", "as the round runs")
end)

T.test("a round that runs out of setup runs no SetupStart", function()
	local controller, heard = Load()
	Preround(controller)
	Run(controller)
	controller:Apply({ Hook("WSRoundActive", {}) })
	T.eq(#heard.SetupStart, 0, "none")
end)

T.test("setup turned on while the round runs runs SetupStart, once", function()
	local controller, heard = Load()
	Preround(controller)
	Run(controller)
	controller:SetSetup(true)
	T.eq(#heard.SetupStart, 1, "on")
	controller:SetSetup(true)
	T.eq(#heard.SetupStart, 1, "already in setup: not again")
	controller:SetSetup(false)
	T.eq(#heard.SetupStart, 1, "its end is not a start")
end)

T.finish()
