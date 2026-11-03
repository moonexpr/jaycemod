-- wartactics.bridge: where the tactics engine and NextSoldier meet. It builds
-- the monitors once, as states of NextSoldier's own chart, and registers them
-- by name; a soldier then runs them as it runs any behaviour, with nothing of
-- the bridge between.
local T = dofile("tests/harness.lua")
local Class = core.class
local Bridge = wartactics.bridge
local CHART = nextsoldier.chart.CHART

local MONITORS = { "TacticalMonitor", "SquadMonitor", "ScenarioMonitor" }

T.test("the monitors are states of NextSoldier's chart", function()
	for _, name in ipairs(MONITORS) do
		T.eq(Class.IsA(Bridge[name], CHART.base), true, name)
	end
end)

T.test("the registry gives the classes themselves, with no wrapper", function()
	local compiled = nextsoldier.behaviors.Shared:Compile()
	for _, name in ipairs(MONITORS) do T.eq(compiled:Get(name), Bridge[name], name) end
end)

T.test("the monitors are built once", function()
	local first = Bridge.TacticalMonitor
	T.eq(wartactics.bridge.TacticalMonitor, first, "the same class at each read")
end)

T.finish()
