-- wartactics.scenarios: scenarios any script registers, each with its
-- activation criteria, its Scenario class and, optionally, the behaviour its
-- scenario monitor runs. Registering is open while the game loads; at the
-- game's beginning Compile() makes an immutable structure built for the
-- choice, which is all a decision mid-game reads.
local T = dofile("tests/harness.lua")
local Scenarios = wartactics.scenarios
local Monitor = nextsoldier.monitor
local Behaviors = nextsoldier.behaviors

-- What NextSoldier's soldiers can run here: Holdout, a monitor, and Travel.
local HOLD = Monitor.New("Holdout", function() return nil end)
local BEHAVIORS = (function()
	local registry = Behaviors.New()
	registry:Register({ name = "Holdout", behavior = HOLD })
	registry:Register({ name = "Travel", behavior = nextsoldier.chart.CHART:State("Travel") })
	return registry:Compile(BEHAVIORS)
end)()

local function Class(name) return { NAME = name } end

local function Registry(specs)
	local registry = Scenarios.New()
	for _, spec in ipairs(specs or {}) do registry:Register(spec) end
	return registry
end

local ANY = { name = "any", priority = 0, scenario = Class("any") }
local PAYLOAD = { name = "payload", priority = 10, mode = "payload", scenario = Class("payload") }
local HOLDOUT = { name = "holdout", priority = 20, mode = "payload",
	active = function(c) return c.field ~= nil and c.field.holdout == true end, scenario = Class("holdout") }

T.test("the active scenario of highest priority is chosen; ties go to the name first", function()
	local compiled = Registry({ ANY, PAYLOAD, HOLDOUT }):Compile(BEHAVIORS)
	T.eq(compiled:Class(compiled:Choose({ mode = "koth" })).NAME, "any", "none but the catch-all holds")
	T.eq(compiled:Class(compiled:Choose({ mode = "payload" })).NAME, "payload", "the mode's")
	T.eq(compiled:Class(compiled:Choose({ mode = "payload", field = { holdout = true } })).NAME, "holdout", "the higher priority wins")
	local tied = Registry({ ANY, PAYLOAD, HOLDOUT, { name = "aardvark", priority = 20, mode = "payload",
		active = function(c) return c.field ~= nil and c.field.holdout == true end, scenario = Class("aardvark") } }):Compile(BEHAVIORS)
	T.eq(tied:Choose({ mode = "payload", field = { holdout = true } }).name, "aardvark", "a tie goes to the name first")
end)

T.test("a choice asks only the scenarios of the context's mode and those of any mode", function()
	local asked = {}
	local function Asking(name, mode)
		return { name = name, priority = 5, mode = mode, scenario = Class(name),
			active = function() asked[#asked + 1] = name return false end }
	end
	local compiled = Registry({ ANY, Asking("koth_a", "koth"), Asking("payload_a", "payload"), Asking("anywhere", nil) }):Compile(BEHAVIORS)
	T.eq(compiled:Choose({ mode = "payload" }).name, "any", "falls to the catch-all")
	T.eq(table.concat(asked, " "), "anywhere payload_a", "koth's never asked")
	asked = {}
	compiled:Choose({ mode = "arena" })
	T.eq(table.concat(asked, " "), "anywhere", "an unknown mode asks only those of any mode")
end)

T.test("the compiled structure is immutable, and the registry's later changes do not reach it", function()
	local registry = Registry({ ANY, PAYLOAD })
	local compiled = registry:Compile(BEHAVIORS)
	local entry = compiled:Choose({ mode = "payload" })
	T.eq((pcall(function() entry.priority = 99 end)), false, "an entry refuses a change")
	T.eq((pcall(function() compiled.extra = true end)), false, "the structure refuses a new key")
	T.eq(entry.priority, 10, "unchanged")
	registry:Register({ name = "payload", priority = 10, mode = "payload", scenario = Class("replaced") })
	T.eq(compiled:Class(compiled:Choose({ mode = "payload" })).NAME, "payload", "the compiled one keeps what it was made from")
	local again = registry:Compile(BEHAVIORS)
	T.eq(again:Class(again:Choose({ mode = "payload" })).NAME, "replaced", "a new compile has the change")
end)

T.test("a scenario named by its module is required when chosen", function()
	local compiled = Registry({ { name = "freeform", priority = 0, scenario = "features.aiwar.scenario.freeform" } }):Compile(BEHAVIORS)
	T.eq(compiled:Class(compiled:Choose({})), T.require("features.aiwar.scenario.freeform").Scenario, "its Scenario")
end)

T.test("nothing active is refused, naming the context's mode", function()
	local compiled = Registry({ PAYLOAD }):Compile(BEHAVIORS)
	local ok, err = pcall(compiled.Choose, compiled, { mode = "koth" })
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("no scenario is active for mode koth", 1, true) ~= nil, true, tostring(err))
end)

T.test("a name registered again replaces its entry", function()
	local registry = Registry({ { name = "a", priority = 1, scenario = Class("old") }, { name = "a", priority = 1, scenario = Class("new") } })
	local compiled = registry:Compile(BEHAVIORS)
	local names = {}
	for i, entry in ipairs(compiled:Entries()) do names[i] = entry.name end
	T.eq(table.concat(names, " "), "a", "one entry")
	T.eq(compiled:Class(compiled:Choose({})).NAME, "new", "the new one")
end)

T.test("a scenario's monitor is a registered behaviour its scenario monitor runs, named on the entry", function()
	local compiled = Registry({ { name = "h", priority = 1, scenario = Class("h"), monitor = "Holdout" } }):Compile(BEHAVIORS)
	T.eq(compiled:Choose({}).monitor, "Holdout", "kept")
end)

T.test("the behaviours a scenario relies on are named on the entry", function()
	local compiled = Registry({ { name = "h", priority = 1, scenario = Class("h"), behaviors = { "Travel" } } }):Compile(BEHAVIORS)
	local names = compiled:Behaviors(compiled:Choose({}))
	T.eq(table.concat(names, " "), "Travel")
	names[1] = "Changed"
	T.eq(compiled:Behaviors(compiled:Choose({}))[1], "Travel", "a copy: the entry keeps its own")
	local none = Registry({ ANY }):Compile(BEHAVIORS)
	T.eq(#none:Behaviors(none:Choose({})), 0, "none named: none")
end)

T.test("a scenario naming a behaviour no one registered is refused as it compiles, naming both", function()
	for _, spec in ipairs({
		{ name = "lost", priority = 1, scenario = Class("lost"), monitor = "Missing" },
		{ name = "lost", priority = 1, scenario = Class("lost"), behaviors = { "Travel", "Missing" } },
	}) do
		local ok, err = pcall(function() Registry({ spec }):Compile(BEHAVIORS) end)
		T.eq(ok, false, "refused")
		T.eq(tostring(err):find("lost", 1, true) ~= nil and tostring(err):find("Missing", 1, true) ~= nil, true, tostring(err))
	end
end)

T.test("a spec missing a part is refused, blamed on the caller", function()
	local registry = Scenarios.New()
	local good = { name = "x", priority = 1, scenario = Class("x") }
	local function With(key, value)
		local spec = {}
		for k, v in pairs(good) do spec[k] = v end
		spec[key] = value
		return spec
	end
	for _, case in ipairs({
		{ "name", 5 }, { "name", "" }, { "priority", "high" }, { "mode", 3 }, { "active", true }, { "scenario", 3 },
		{ "monitor", 3 }, { "monitor", "" }, { "monitor", { NAME = "not a name" } },
		{ "behaviors", "Travel" }, { "behaviors", { 3 } },
	}) do
		local ok, err = pcall(function() registry:Register(With(case[1], case[2])) end)
		T.eq(ok, false, case[1] .. " refused")
		T.eq(tostring(err):find("wartactics_scenarios_test.lua", 1, true) ~= nil, true, "blamed on the caller: " .. tostring(err))
	end
end)

T.test("the shared registry is the one the war compiles", function()
	T.eq(type(Scenarios.Shared.Register), "function", "Register")
	T.eq(type(Scenarios.Shared.Compile), "function", "Compile")
end)

T.test("a monitor holds the state and contains the behaviour contains(state) gives", function()
	local Inner = npc.nextbot.Action:Extend("Inner")
	local Outer = Monitor.New("Outer", function(state) return Inner:New(state) end)
	local Through = Monitor.Passthrough("Through", function(state) return Inner:New(state) end)
	local state = {}
	local outer = Outer:New(state)
	T.eq(outer.state, state, "held")
	T.eq(getmetatable(outer:InitialContainedAction({})), Inner, "contains")
	T.eq(Outer.passthrough, false, "a monitor shows in the debug layer")
	T.eq(Through.passthrough, true, "a passthrough one does not")
	T.eq(core.class.IsA(Outer, npc.nextbot.Action), true, "a behaviour")
end)

T.finish()
