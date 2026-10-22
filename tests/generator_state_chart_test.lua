-- foundation.generator.state_chart: a hierarchical statechart, NextBot's
-- Action/Behavior engine without its stacks (game.generator.hfsm adds them).
local T = dofile("tests/harness.lua")
local Chart = T.require("foundation.generator.state_chart")
local Port = T.require("foundation.core.port")

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local function Has(text, part, what)
	T.eq(text:find(part, 1, true) ~= nil, true, what .. ": " .. text)
end

-- A guard the port is checked against, keeping a log of what its states do.
local function Guard()
	local guard = { log = {}, secret = "engine internals" }
	function guard:Note(entry) self.log[#self.log + 1] = entry end
	function guard:Secret() return self.secret end
	return guard
end

local GUARD_PORT = Port.New("Guard", { "Note" })

local function Log(guard)
	return table.concat(guard.log, ",")
end

-- Watch contains Look; Look turns to Listen on a noise; Watch ends on a
-- whistle. Every hook writes to the log.
local function WatchChart()
	local chart = Chart.Chart({
		name = "Watch",
		port = GUARD_PORT,
		events = { "OnNoise", "OnWhistle" },
		queries = { "ShouldShout", "IsCalm" },
		initial = function(states) return states.Watch:New() end,
	})
	local states = {
		Watch = chart:State("Watch"),
		Look = chart:State("Look"),
		Listen = chart:State("Listen"),
	}
	local Watch, Look, Listen = states.Watch, states.Look, states.Listen
	function Watch:InitialContainedAction(me) return Look:New() end
	function Watch:OnStart(me) me:Note("start Watch") return self:Continue() end
	function Watch:OnEnd(me) me:Note("end Watch") end
	function Watch:Update(me) me:Note("update Watch") return self:Continue() end
	function Watch:OnWhistle(me) return self:TryDone(Chart.RESULT_IMPORTANT, "whistle") end
	function Watch:IsCalm(me) return Chart.ANSWER_YES end
	function Look:OnStart(me) me:Note("start Look") return self:Continue() end
	function Look:OnEnd(me, nextState) me:Note("end Look for " .. (nextState and nextState:GetName() or "none")) end
	function Look:Update(me) me:Note("update Look") return self:Continue() end
	function Look:OnNoise(me, loud)
		if loud then return self:TryChangeTo(Listen:New(), Chart.RESULT_CRITICAL, "loud") end
		return self:TryToSustain(Chart.RESULT_TRY, "quiet")
	end
	function Look:ShouldShout(me) return Chart.ANSWER_NO end
	function Listen:OnStart(me) me:Note("start Listen") return self:Continue() end
	function Listen:Update(me) me:Note("update Listen") return self:Done("heard enough") end
	function Listen:ShouldShout(me) return Chart.ANSWER_YES end
	return chart, states
end

local function Running()
	local chart, states = WatchChart()
	local guard = Guard()
	local machine = chart:New(guard, states)
	machine:Update(0.1)
	return machine, guard, chart, states
end

T.test("the first update starts the states, a child before its container", function()
	local machine, guard = Running()
	T.eq(Log(guard), "start Look,start Watch", "the child starts first")
	T.eq(machine:Describe(), "Watch/Look", "innermost state's full name")
	machine:Update(0.1)
	T.eq(Log(guard), "start Look,start Watch,update Look,update Watch", "the child updates first")
end)

T.test("a state reaches its actor only through the chart's port", function()
	local chart = Chart.Chart({
		name = "Nosy",
		port = GUARD_PORT,
		initial = function(states) return states.Nosy:New() end,
	})
	local Nosy = chart:State("Nosy")
	local seen
	function Nosy:Update(me)
		seen = me.Secret
		return self:Continue()
	end
	local machine = chart:New(Guard(), { Nosy = Nosy })
	machine:Update(0.1)
	machine:Update(0.1)
	T.eq(seen, nil, "only the port's methods")
end)

T.test("an event's change waits for the next update, and only the child it reached changes", function()
	local machine, guard = Running()
	machine:Event("OnNoise", true)
	T.eq(machine:Describe(), "Watch/Look", "not yet")
	machine:Update(0.1)
	T.eq(machine:Describe(), "Watch/Listen", "the child changed, its container stayed")
	Has(Log(guard), "end Look for Listen", "the old state ends, told what follows")
end)

T.test("a child that is done leaves its container running alone", function()
	local machine = Running()
	machine:Event("OnNoise", true)
	machine:Update(0.1)
	machine:Update(0.1)
	T.eq(machine:Describe(), "Watch", "Listen is done")
	T.eq(machine:IsEmpty(), false, "Watch still runs")
end)

T.test("a sustained event changes nothing; a stronger one wins over a weaker", function()
	local machine = Running()
	machine:Event("OnNoise", false)
	machine:Update(0.1)
	T.eq(machine:Describe(), "Watch/Look", "sustained")
	machine:Event("OnNoise", true)
	machine:Event("OnNoise", false)
	machine:Update(0.1)
	T.eq(machine:Describe(), "Watch/Listen", "the critical change stands over a later weaker try")
end)

T.test("the outermost state done ends the machine, its states ending inside out", function()
	local machine, guard = Running()
	machine:Event("OnWhistle")
	machine:Update(0.1)
	T.eq(machine:IsEmpty(), true, "empty")
	T.eq(machine:Describe(), "", "nothing to describe")
	Has(Log(guard), "end Look for none,end Watch", "child first")
	machine:Update(0.1)
	T.eq(machine:IsEmpty(), true, "an empty machine stays empty")
end)

T.test("a query asks the innermost state first, then its containers", function()
	local machine = Running()
	T.eq(machine:Query("ShouldShout"), Chart.ANSWER_NO, "Look answers")
	T.eq(machine:Query("IsCalm"), Chart.ANSWER_YES, "Look is silent, so Watch answers")
	machine:Event("OnNoise", true)
	machine:Update(0.1)
	T.eq(machine:Query("ShouldShout"), Chart.ANSWER_YES, "Listen answers now")
end)

T.test("a state can ask only the states it contains", function()
	local chart = Chart.Chart({
		name = "Monitor",
		port = GUARD_PORT,
		queries = { "ShouldShout" },
		initial = function(states) return states.Outer:New() end,
	})
	local Outer, Inner = chart:State("Outer"), chart:State("Inner")
	local below
	function Outer:InitialContainedAction() return Inner:New() end
	function Outer:ShouldShout() return Chart.ANSWER_YES end
	function Outer:Update(me)
		below = self:QueryBelow(me, "ShouldShout")
		return self:Continue()
	end
	local machine = chart:New(Guard(), { Outer = Outer })
	machine:Update(0.1)
	machine:Update(0.1)
	T.eq(below, Chart.ANSWER_UNDEFINED, "Inner does not answer, and Outer is not asked")
	function Inner:ShouldShout() return Chart.ANSWER_NO end
	machine:Update(0.1)
	T.eq(below, Chart.ANSWER_NO, "Inner answers")
end)

T.test("destroying a machine ends its states", function()
	local machine, guard = Running()
	machine:Destroy()
	Has(Log(guard), "end Look for none,end Watch", "both end")
	T.eq(machine:IsEmpty(), true, "empty")
end)

T.test("a watcher hears each change before it happens", function()
	local machine = Running()
	local heard = {}
	machine:Watch({
		Transition = function(_, kind, from, to, reason)
			heard[#heard + 1] = from .. ">" .. tostring(to) .. ":" .. reason
		end,
		Event = function(_, name) heard[#heard + 1] = name end,
	})
	machine:Event("OnNoise", true)
	machine:Update(0.1)
	T.eq(table.concat(heard, " "), "OnNoise Look>Listen:loud", "the event, then the change")
end)

T.test("the stack lists each state with its depth", function()
	local machine = Running()
	local frames = machine:Stack()
	T.eq(#frames, 2, "two states")
	T.eq(frames[1].name .. frames[1].depth .. frames[2].name .. frames[2].depth, "Watch1Look2", "outermost first")
end)

T.test("a statechart has no stack: no suspending, and OnSuspend is no hook of its states", function()
	local chart = WatchChart()
	T.eq(chart:State("Plain").SuspendFor, nil, "no SuspendFor")
	local Plain = chart:State("Plain2")
	Has(Raises(function() function Plain:OnSuspend() end end), "OnSuspend", "refused")
end)

T.test("a chart refuses what it does not declare", function()
	local machine, _, chart = Running()
	Has(Raises(machine.Event, machine, "OnSmell"), "OnSmell", "an undeclared event")
	Has(Raises(machine.Query, machine, "ShouldRun"), "ShouldRun", "an undeclared query")
	local Look = chart:State("Look2")
	Has(Raises(function() function Look:OnSmell() end end), "OnSmell", "a handler for no event")
	Raises(chart.New, chart, {}, {})
	Raises(Chart.Chart, { name = "Bad", port = GUARD_PORT, events = { "Noise" }, initial = function() end })
	Raises(Chart.Chart, { name = "Bad", port = {}, initial = function() end })
end)

T.test("a machine refuses a first state of another chart", function()
	local _, states = WatchChart()
	local other = Chart.Chart({
		name = "Other",
		port = GUARD_PORT,
		initial = function() return states.Watch:New() end,
	})
	Has(Raises(other.New, other, Guard(), {}), "another chart", "refused")
end)

T.finish()
