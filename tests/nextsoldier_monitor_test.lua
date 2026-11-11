-- nextsoldier.behavior.monitor: a behaviour holding a soldier's state and containing one.
local T = dofile ("tests/harness.lua")
local Monitor = nextsoldier.behavior.monitor

T.test ("a monitor holds the state and contains the behaviour contains(state) gives", function ()
	local Inner = npc.nextbot.Action:Extend ("Inner")
	local Outer = Monitor.New ("Outer", function (state) return Inner:New (state) end)
	local Through = Monitor.Passthrough ("Through", function (state) return Inner:New (state) end)
	local state = {}
	local outer = Outer:New (state)
	T.eq (outer.state, state, "held")
	T.eq (getmetatable (outer:InitialContainedAction ({})), Inner, "contains")
	T.eq (Outer.passthrough, false, "a monitor shows in the debug layer")
	T.eq (Through.passthrough, true, "a passthrough one does not")
	T.eq (core.class.IsA (Outer, npc.nextbot.Action), true, "a behaviour")
end)

T.finish ()
