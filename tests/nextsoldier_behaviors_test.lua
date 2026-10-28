local T = dofile("tests/harness.lua")
local Behaviors = nextsoldier.behaviors
local Chart = nextsoldier.chart

local function Behavior(name) return Chart.CHART:State(name) end

T.test("a registered behaviour is got by its name once compiled", function()
	local registry = Behaviors.New()
	local Travel = Behavior("Travel")
	registry:Register({ name = "Travel", behavior = Travel })
	local compiled = registry:Compile()
	T.eq(compiled:Get("Travel"), Travel)
	T.eq(compiled:Has("Travel"), true)
	T.eq(compiled:Has("Chase"), false)
end)

T.test("an unknown name is refused, naming it", function()
	local compiled = Behaviors.New():Compile()
	local ok, err = pcall(compiled.Get, compiled, "Chase")
	T.eq(ok, false)
	T.eq(tostring(err):find("Chase", 1, true) ~= nil, true, tostring(err))
end)

T.test("a behaviour that is not a state of NextSoldier's chart is refused", function()
	local registry = Behaviors.New()
	T.eq(pcall(registry.Register, registry, { name = "Loose", behavior = npc.nextbot.Action:Extend("Loose") }), false)
	T.eq(pcall(registry.Register, registry, { name = "Nothing" }), false)
	T.eq(pcall(registry.Register, registry, { behavior = Behavior("Nameless") }), false)
end)

T.test("a name registered again replaces its behaviour", function()
	local registry = Behaviors.New()
	registry:Register({ name = "Chase", behavior = Behavior("Chase") })
	local Again = Behavior("Chase")
	registry:Register({ name = "Chase", behavior = Again })
	T.eq(registry:Compile():Get("Chase"), Again)
end)

T.test("the compiled behaviours are fixed: a later registration reaches the next compile only", function()
	local registry = Behaviors.New()
	registry:Register({ name = "Travel", behavior = Behavior("Travel") })
	local compiled = registry:Compile()
	registry:Register({ name = "Chase", behavior = Behavior("Chase") })
	T.eq(compiled:Has("Chase"), false)
	T.eq(registry:Compile():Has("Chase"), true)
	T.eq(pcall(function() compiled.extra = true end), false, "the compiled structure refuses a change")
end)

T.test("the names, in order", function()
	local registry = Behaviors.New()
	registry:Register({ name = "Travel", behavior = Behavior("Travel") })
	registry:Register({ name = "Chase", behavior = Behavior("Chase") })
	T.eq(table.concat(registry:Compile():Names(), " "), "Chase Travel")
end)

T.finish()
