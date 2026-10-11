-- The rounds controller's root, features/rounds/sv.lua, loaded once in a
-- fake GMod: its top level runs, and what it wires (hooks, console
-- commands, convar callbacks, timers, event listeners) is recorded by
-- T.Wiring. The recorded keys are the controller's wiring as it stands; a
-- reorganisation of the file must leave them exactly as they are.
--
-- The fake: the wiring tables come from T.Wiring; convars hold their
-- defaults; every other engine global the file reads, and every WS function
-- but require, is an inert stub, a table any field of which is the stub
-- and any call of which returns it, so the top level runs and nothing it
-- defers (timer.Simple) ever does.
local T = dofile("tests/harness.lua")
local Teams = T.require("foundation.teams")
local STATE = T.require("foundation.rounds.state")

local SOURCE = T.ROOT .. "features/rounds/sv.lua"

-- the wiring of features/rounds/sv.lua, sorted
local WIRING = {
	"concommand mp_forcewin",
	"cvars mp_maxrounds ws_rounds_limits",
	"cvars mp_timelimit ws_rounds_limits",
	"cvars mp_winlimit ws_rounds_limits",
	"hook AcceptInput ws_rounds_spawn_doors",
	"hook EntityKeyValue ws_rounds_new_map",
	"hook InitPostEntity ws_rounds",
	"hook Think ws_rounds",
	"hook WSMoneyEarned ws_rounds_limits",
	"hook WSTeamFrag ws_rounds_limits",
}

local Inert = setmetatable({}, {
	__index = function(stub) return stub end,
	__call = function(stub) return stub end,
})

-- A convar made by CreateConVar, holding its default.
local function ConVar(default)
	return {
		GetFloat = function() return tonumber(default) end,
		GetInt = function() return math.floor(tonumber(default)) end,
		GetBool = function() return tonumber(default) ~= 0 end,
		GetString = function() return default end,
	}
end

local function Load()
	local wiring = T.Wiring()
	local deferred = {} -- timer.Simple's functions, kept and never run
	local ws = setmetatable({
		require = T.require,
		FeatureParts = T.FeatureParts,
		Events = wiring.Events,
		STATE = STATE,
		TEAM_UNASSIGNED = Teams.UNASSIGNED,
		TEAM_SPECTATOR = Teams.SPECTATOR,
		TEAM_RED = Teams.RED,
		TEAM_BLUE = Teams.BLUE,
	}, { __index = function() return Inert end })
	local env = setmetatable({
		WS = ws,
		hook = wiring.hook,
		concommand = wiring.concommand,
		cvars = wiring.cvars,
		timer = {
			Create = wiring.timer.Create,
			Simple = function(_, fn) deferred[#deferred + 1] = fn end,
		},
		-- no convar exists already: each is made, holding its default
		GetConVar = function() return nil end,
		CreateConVar = function(_, default) return ConVar(default) end,
		CurTime = function() return 0 end,
	}, {
		__index = function(_, name)
			local value = _G[name]
			if value == nil then return Inert end
			return value
		end,
	})
	local controller = setfenv(assert(loadfile(SOURCE)), env)()
	return controller, wiring
end

local controller, wiring = Load()

T.test("the root returns a table", function()
	T.eq(type(controller), "table", "the controller")
end)

T.test("no wiring key is registered twice", function()
	local duplicates = wiring:Duplicates()
	T.eq(#duplicates, 0, "duplicates (" .. table.concat(duplicates, ", ") .. ")")
end)

T.test("the wiring keys are the baseline's", function()
	local keys = wiring:Registered()
	table.sort(keys)
	local actual, expected = table.concat(keys, "\n"), table.concat(WIRING, "\n")
	T.eq(actual, expected, "the sorted wiring keys")
end)

T.finish()
