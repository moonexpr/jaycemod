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
	"hook PostCleanupMap ws_rounds_proxy",
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
		GetDefault = function() return default end,
	}
end

-- overrides: engine globals the test gives the file in place of the stub;
-- wsFields: WS functions in place of the stub.
local function Load(overrides, wsFields)
	overrides = overrides or {}
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
	for name, value in pairs(wsFields or {}) do ws[name] = value end
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
			if overrides[name] ~= nil then return overrides[name] end
			local value = _G[name]
			if value == nil then return Inert end
			return value
		end,
	})
	local controller = setfenv(assert(loadfile(SOURCE)), env)()
	return controller, wiring, ws
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

-- A map cleanup removes the timers the gamerules made, and the model's next
-- effect in the same batch may set the time limit timer's time: a removed
-- entity stays valid until the frame ends, so the controller must have let
-- go of it as it was unbound, and make a new one.
T.test("a listener added again from the same place replaces the old, as a file run again does", function()
	local Rounds = T.require("foundation.rounds")
	local phase = Rounds.PHASE_ARENA_START
	local before = #controller.listeners[phase]
	local ran = {}
	for run = 1, 2 do
		controller:AddRoundListener(phase, Rounds.LISTEN_LOGIC, function() ran[#ran + 1] = run end)
	end
	T.eq(#controller.listeners[phase], before + 1, "one listener")
	controller:RunListeners(phase)
	T.eq(table.concat(ran, ","), "2", "the newer one runs")
	controller:AddRoundListener(phase, Rounds.LISTEN_LOGIC, function() end)
	T.eq(#controller.listeners[phase], before + 2, "one from elsewhere is another")
end)

T.test("a timer the gamerules made is forgotten as it is unbound", function()
	for _, field in ipairs({ "timeLimitTimer", "stalemateTimer", "roundTimer" }) do
		local ent = { name = field }
		controller.timers[ent] = {}
		controller[field] = ent
		controller:UnbindTimer(ent)
		T.eq(controller[field] == ent, false, field .. " let go")
		T.eq(controller.timers[ent], nil, field .. " unbound")
	end
end)

T.test("unbinding another timer keeps the gamerules' own", function()
	local own, other = { name = "own" }, { name = "other" }
	controller.timers[own], controller.timers[other] = {}, {}
	controller.timeLimitTimer = own
	controller:UnbindTimer(other)
	T.eq(controller.timeLimitTimer, own, "kept")
end)

-- Every map has gamerules (WS.Rules): its tf_gamerules, or those the
-- controller makes. A fake map: its objective or none, and the gamerules
-- entities made on it, which bind as they spawn (their Initialize). As the
-- entities declare it, TF2's gamerules run rounds and Sandcastle's do not.
local RUNS_ROUNDS = { tf_gamerules = true, ws_gamerules = false }

local function Map(hasObjective)
	local map = { created = {}, published = {}, spawnStatus = {} }
	local function Entity(class)
		local ent = { class = class, valid = true, RunsRounds = RUNS_ROUNDS[class] }
		function ent:GetName() return self.name end
		function ent:SetName(name) self.name = name end
		function ent:Spawn() map.controller:BindProxy(self) end
		return ent
	end
	map.Entity = Entity
	local fakeEnts = {
		Create = function(class)
			local ent = Entity(class)
			map.created[#map.created + 1] = ent
			return ent
		end,
		FindByClass = function(class)
			return (hasObjective and class == "team_control_point") and { Inert } or {}
		end,
	}
	map.controller, _, map.ws = Load({
		ents = fakeEnts,
		IsValid = function(ent) return type(ent) == "table" and ent.valid == true end,
		SetGlobal2Bool = function(key, value) map.published[key] = value end,
	}, {
		SetSpawnStatus = function(ply, ...) map.spawnStatus[ply] = { ... } end,
	})
	-- the gamerules entity removed, and what it tells the controller
	function map:Remove(ent, replace)
		self.controller:UnbindProxy(ent, replace)
		ent.valid = false
	end
	function map:Made()
		local list = {}
		for i, ent in ipairs(self.created) do list[i] = ent.class .. "/" .. ent.name end
		return table.concat(list, " ")
	end
	return map
end

T.test("a map without an objective gets Sandcastle's gamerules, running no rounds", function()
	local map = Map(false)
	map.controller:EnsureProxy()
	T.eq(map:Made(), "ws_gamerules/ws_gamerules", "made")
	T.eq(map.ws.Rules, map.created[1], "WS.Rules")
	T.eq(map.published.ws_rounds_active, false, "no rounds")
end)

T.test("a map with an objective and no tf_gamerules gets one, named as TF2 names it, running rounds", function()
	local map = Map(true)
	map.controller:EnsureProxy()
	T.eq(map:Made(), "tf_gamerules/tf_gamerules", "made")
	T.eq(map.ws.Rules, map.created[1], "WS.Rules")
	T.eq(map.published.ws_rounds_active, true, "rounds")
end)

T.test("a map's own tf_gamerules are its rules, and none are made beside them", function()
	local map = Map(true)
	local own = map.Entity("tf_gamerules")
	own:Spawn()
	map.controller:EnsureProxy()
	T.eq(map:Made(), "", "none made")
	T.eq(map.ws.Rules, own, "WS.Rules")
end)

-- Another addon's cleanup (TF2 Multi-Fix's game.CleanUpMap 5 s into every
-- TF2 map) keeps no gamerules: the map's own come back with the map's
-- entities, but any the controller made are gone. It makes them again,
-- bound to the rounds as they stand.
T.test("gamerules removed by a cleanup are made again after it, rounds as they stood", function()
	for _, case in ipairs({
		{ objective = false, made = "ws_gamerules/ws_gamerules", rounds = false },
		{ objective = true, made = "tf_gamerules/tf_gamerules", rounds = true },
	}) do
		local map = Map(case.objective)
		map.controller:EnsureProxy()
		map:Remove(map.created[1], false)
		T.eq(#map.created, 1, "none made during the cleanup")
		map.controller:AfterCleanup()
		T.eq(map:Made(), case.made .. " " .. case.made, "made again")
		T.eq(map.ws.Rules, map.created[2], "WS.Rules")
		T.eq(map.published.ws_rounds_active, case.rounds, "rounds as they stood")
	end
end)

T.test("after a cleanup gamerules still bound stay", function()
	local map = Map(true)
	local own = map.Entity("tf_gamerules")
	own:Spawn()
	map.controller:AfterCleanup()
	T.eq(map:Made(), "", "none made")
end)

-- Removed any other way (a map's Kill), the gamerules are replaced at once,
-- under their name so the map's outputs still reach them, and the game
-- goes on.
T.test("gamerules removed outside a cleanup are replaced at once under their name", function()
	local map = Map(false)
	local own = map.Entity("tf_gamerules")
	own:SetName("tf_gamerules")
	own:Spawn()
	map:Remove(own, true)
	T.eq(map:Made(), "ws_gamerules/tf_gamerules", "replaced")
	T.eq(map.ws.Rules, map.created[1], "WS.Rules")
	T.eq(map.published.ws_rounds_active, true, "the rounds go on")
end)

-- A game begun on a map without rounds (foundation.gamemode's loadRounds)
-- runs them on the map's gamerules; begun before the map was set up (the
-- AI war's autostart), it makes them first.
T.test("a game begun on a map without rounds runs them on its gamerules", function()
	local map = Map(false)
	map.controller:EnsureProxy()
	map.controller:EnsureRules()
	T.eq(map:Made(), "ws_gamerules/ws_gamerules", "no other gamerules")
	T.eq(map.published.ws_rounds_active, true, "rounds")
end)

T.test("a game begun before the map was set up makes its gamerules", function()
	local map = Map(false)
	map.controller:EnsureRules()
	T.eq(map:Made(), "ws_gamerules/ws_gamerules", "made")
	T.eq(map.ws.Rules, map.created[1], "WS.Rules")
	T.eq(map.published.ws_rounds_active, true, "rounds")
end)

-- Without rounds there are no respawn waves: a death is Sandbox's, the
-- player clicking to respawn, as before gamerules were on every map.
T.test("a death without rounds leaves the spawn status alone", function()
	local map = Map(false)
	map.controller:EnsureProxy()
	local ply = {}
	map.ws.Rules = map.created[1]
	map.controller:OnPlayerDeath(ply)
	T.eq(map.spawnStatus[ply], nil, "no spawn status")
end)

T.finish()
