-- wartactics.bridge: where the tactics engine and NextSoldier meet. It builds
-- the monitors once, as states of NextSoldier's own chart, and registers them
-- by name; a soldier then runs them as it runs any behaviour, with nothing of
-- the bridge between.
local T = dofile("tests/harness.lua")
local Class = core.class
local Bridge = wartactics.bridge
local CHART = nextsoldier.behavior.CHART

local MONITORS = { "TacticalMonitor", "SquadMonitor", "ScenarioMonitor" }

T.test("the monitors are states of NextSoldier's chart", function()
	for _, name in ipairs(MONITORS) do
		T.eq(Class.IsA(Bridge[name], CHART.base), true, name)
	end
end)

T.test("the registry gives the classes themselves, with no wrapper", function()
	local compiled = nextsoldier.behavior.registry.Shared:Compile()
	for _, name in ipairs(MONITORS) do T.eq(compiled:Get(name), Bridge[name], name) end
end)

T.test("the monitors are built once", function()
	local first = Bridge.TacticalMonitor
	T.eq(wartactics.bridge.TacticalMonitor, first, "the same class at each read")
end)

T.test("Overwatch answers a squad's request to vacate over its radio, its losses counted", function()
	local Director = nextsoldier.squad.interactions.director
	local Radio = nextsoldier.squad.comms.radio
	local order, leader = nextsoldier.behavior.group_identity.Muster({ x = 0, y = 0, z = 0 }), {}
	order:Lead(leader)
	order.size = 6
	local overwatch = Bridge.Overwatch({ target = function() return nil end })
	Director.Set(order, overwatch)
	Director.Request(order, { kind = "VACATE" })
	T.eq(Director.Directive(order).kind, "VACATE", "a guard lost, the squad strong: cleared")
	local said = Radio.Calls(order)
	T.eq(said[#said].from, Radio.DIRECTOR, "over the radio, from the director")
	Director.Forget(order)
	Director.Request(order, { kind = "VACATE" })
	T.eq(Director.Directive(order).kind, "DEFEND", "a second lost and nowhere to strike: lie in wait")
end)

T.test("Overwatch takes the guards the squad reports lost", function()
	local Director = nextsoldier.squad.interactions.director
	local order = nextsoldier.behavior.group_identity.Muster({ x = 0, y = 0, z = 0 })
	order:Lead({})
	order.size = 6
	local target = { x = 5, y = 5, z = 0 }
	Director.Set(order, Bridge.Overwatch({ target = function() return target end }))
	Director.Request(order, { kind = "VACATE", missing = 2 })
	T.eq(Director.Directive(order).kind, "ATTACK", "two lost at once: assault")
end)

T.test("Overwatch strikes where the mode says the enemy comes from", function()
	local Director = nextsoldier.squad.interactions.director
	local order = nextsoldier.behavior.group_identity.Muster({ x = 0, y = 0, z = 0 })
	order:Lead({})
	order.size = 6
	local target = { x = 5, y = 5, z = 0 }
	Director.Set(order, Bridge.Overwatch({ target = function(o) return o == order and target or nil end }))
	Director.Request(order, {})
	Director.Forget(order)
	Director.Request(order, {})
	T.eq(Director.Directive(order).kind == "ATTACK" and Director.Directive(order).target == target, true, "assault it")
end)

T.finish()