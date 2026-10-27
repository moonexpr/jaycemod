-- games.nextsoldier.scenarios: scenarios any script registers, each with its
-- activation criteria, its Scenario class and, optionally, the behaviour its
-- scenario monitor runs; the war plays the active one of highest priority.
local T = dofile("tests/harness.lua")
local Scenarios = nextsoldier.scenarios
local Monitor = nextsoldier.monitor

local function Class(name) return { NAME = name } end

local function Fresh()
	return Scenarios.New()
end

T.test("the active scenario of highest priority is chosen; ties go to the name first", function()
	local registry = Fresh()
	local any, payload, holdout = Class("any"), Class("payload"), Class("holdout")
	registry:Register({ name = "any", priority = 0, active = function() return true end, scenario = any })
	registry:Register({ name = "payload", priority = 10, active = function(c) return c.mode == "payload" end, scenario = payload })
	registry:Register({ name = "holdout", priority = 20, active = function(c) return c.mode == "payload" and c.field and c.field.holdout end, scenario = holdout })
	T.eq(registry:Class(registry:Choose({ mode = "koth" })), any, "none but the catch-all holds")
	T.eq(registry:Class(registry:Choose({ mode = "payload" })), payload, "the mode's")
	T.eq(registry:Class(registry:Choose({ mode = "payload", field = { holdout = true } })), holdout, "the higher priority wins")
	registry:Register({ name = "aardvark", priority = 20, active = function(c) return c.field and c.field.holdout end, scenario = Class("aardvark") })
	T.eq(registry:Choose({ mode = "payload", field = { holdout = true } }).name, "aardvark", "a tie goes to the name first")
end)

T.test("a scenario named by its module is loaded the first time it is chosen", function()
	local registry = Fresh()
	registry:Register({ name = "freeform", priority = 0, active = function() return true end, scenario = "features.aiwar.scenario.freeform" })
	local entry = registry:Choose({})
	T.eq(registry:Class(entry), T.require("features.aiwar.scenario.freeform").Scenario, "its Scenario")
end)

T.test("nothing active is refused, naming the context's mode", function()
	local registry = Fresh()
	registry:Register({ name = "payload", priority = 10, active = function(c) return c.mode == "payload" end, scenario = Class("p") })
	local ok, err = pcall(registry.Choose, registry, { mode = "koth" })
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("no scenario is active", 1, true) ~= nil, true, tostring(err))
end)

T.test("a name registered again replaces its entry, keeping its place", function()
	local registry = Fresh()
	registry:Register({ name = "a", priority = 1, active = function() return true end, scenario = Class("old") })
	registry:Register({ name = "a", priority = 1, active = function() return true end, scenario = Class("new") })
	local names = {}
	for i, entry in ipairs(registry:Entries()) do names[i] = entry.name end
	T.eq(table.concat(names, " "), "a", "one entry")
	T.eq(registry:Class(registry:Choose({})).NAME, "new", "the new one")
end)

T.test("a scenario's monitor is a behaviour its scenario monitor runs, kept on the entry", function()
	local registry = Fresh()
	local Hold = Monitor.New("Holdout", function() return nil end)
	registry:Register({ name = "h", priority = 1, active = function() return true end, scenario = Class("h"), monitor = Hold })
	T.eq(registry:Choose({}).monitor, Hold, "kept")
end)

T.test("a spec missing a part is refused, blamed on the caller", function()
	local registry = Fresh()
	local good = { name = "x", priority = 1, active = function() return true end, scenario = Class("x") }
	local function Without(key, value)
		local spec = {}
		for k, v in pairs(good) do spec[k] = v end
		spec[key] = value
		return spec
	end
	for _, case in ipairs({
		{ "name", 5 }, { "name", "" }, { "priority", "high" }, { "active", true }, { "scenario", 3 }, { "monitor", "Hold" },
	}) do
		local ok, err = pcall(function() registry:Register(Without(case[1], case[2])) end)
		T.eq(ok, false, case[1] .. " refused")
		T.eq(tostring(err):find("games_nextsoldier_scenarios_test.lua", 1, true) ~= nil, true, "blamed on the caller: " .. tostring(err))
	end
	local Plain = { NAME = "not a behaviour" }
	T.eq((pcall(registry.Register, registry, Without("monitor", Plain))), false, "a monitor must be a behaviour")
end)

T.test("the shared registry is the one the war chooses from", function()
	T.eq(getmetatable(Scenarios.Shared) ~= nil, true, "a registry")
	T.eq(type(Scenarios.Shared.Register), "function", "Register")
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
