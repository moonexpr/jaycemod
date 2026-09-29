local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local N = T.require("foundation.npc")
local Actor = T.require("foundation.npc.actor")

local Action, Behavior = N.Action, N.Behavior

-- An action log shared by the probe actions of one test.
local log

local function Log(entry)
	log[#log + 1] = entry
end

local function Expect(expected, what)
	T.eq(table.concat(log, ", "), table.concat(expected, ", "), what)
	log = {}
end

-- A probe action: every hook logs "<name>:<hook>" and then runs the
-- scripted function for that hook, or returns Continue.
local HOOKS = { "OnStart", "Update", "OnSuspend", "OnResume" }

local function Probe(name, script)
	script = script or {}
	local class = Action:Extend(name)
	for _, hook in ipairs(HOOKS) do
		class[hook] = function(self, me, arg)
			Log(name .. ":" .. hook)
			if script[hook] then return script[hook](self, me, arg) end
			return self:Continue()
		end
	end
	function class:OnEnd(me, nextAction)
		Log(name .. ":OnEnd")
		if script.OnEnd then script.OnEnd(self, me, nextAction) end
	end
	if script.child then
		function class:InitialContainedAction(me) return script.child() end
	end
	for event, handler in pairs(script.events or {}) do
		class[event] = function(self, me, ...)
			Log(name .. ":" .. event)
			return handler(self, me, ...)
		end
	end
	return class
end

local function Setup()
	log = {}
	return Fake.Actor()
end

-- InvokeOnStart

T.test("the child starts before its parent", function()
	local me = Setup()
	local Child = Probe("Child")
	local Parent = Probe("Parent", { child = function() return Child:New() end })
	local b = Behavior:New(Parent:New(), "Test")
	b:Update(me, 0.1)
	Expect({ "Child:OnStart", "Parent:OnStart" }, "first update starts only")
	T.eq(b:Describe(), "Parent/Child", "describe")
end)

-- InvokeUpdate

T.test("an update runs the child first and the parent last", function()
	local me = Setup()
	local Child = Probe("Child")
	local Parent = Probe("Parent", { child = function() return Child:New() end })
	local b = Behavior:New(Parent:New(), "Test")
	b:Update(me, 0.1)
	log = {}
	b:Update(me, 0.1)
	Expect({ "Child:Update", "Parent:Update" }, "second update")
end)

T.test("a pending event result is honoured before the child updates", function()
	local me = Setup()
	local Next = Probe("Next")
	local Child = Probe("Child")
	local Parent = Probe("Parent", {
		child = function() return Child:New() end,
		events = {
			OnStuck = function(self) return self:TryChangeTo(Next:New(), N.RESULT_TRY, "stuck") end,
		},
	})
	local b = Behavior:New(Parent:New(), "Test")
	b:Update(me, 0.1)
	b:Event(me, "OnStuck")
	log = {}
	b:Update(me, 0.1)
	Expect({ "Child:OnEnd", "Parent:OnEnd", "Next:OnStart" }, "change from the event")
	T.eq(b:Describe(), "Next", "describe")
end)

-- ApplyResult: CHANGE_TO

T.test("ChangeTo ends the old action, starts the new one, and applies a result from OnStart at once", function()
	local me = Setup()
	local seen = {}
	local C = Probe("C", { OnStart = function(self, me, prior) seen.cPrior = prior:GetName(); return self:Continue() end })
	local B = Probe("B", { OnStart = function(self, me, prior) seen.bPrior = prior:GetName(); return self:ChangeTo(C:New(), "chain") end })
	local A = Probe("A", {
		Update = function(self) return self:ChangeTo(B:New(), "go") end,
		OnEnd = function(self, me, nextAction) seen.aNext = nextAction:GetName() end,
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	log = {}
	b:Update(me, 0.1)
	Expect({ "A:Update", "A:OnEnd", "B:OnStart", "B:OnEnd", "C:OnStart" }, "chain")
	T.eq(seen.aNext, "B", "A's next action")
	T.eq(seen.bPrior, "A", "B's prior action")
	T.eq(seen.cPrior, "B", "C's prior action")
	T.eq(b:Describe(), "C", "describe")
end)

T.test("a changed-to action inherits the parent and the buried action", function()
	local me = Setup()
	local C = Probe("C", { Update = function(self) return self:Done("finished") end })
	local B = Probe("B", { Update = function(self) return self:ChangeTo(C:New(), "go") end })
	local A = Probe("A", { Update = function(self) return self:SuspendFor(B:New(), "cover") end })
	local Parent = Probe("Parent", { child = function() return A:New() end })
	local b = Behavior:New(Parent:New(), "Test")
	b:Update(me, 0.1) -- start
	b:Update(me, 0.1) -- A suspends for B
	T.eq(b:Describe(), "Parent/B", "B covers A")
	b:Update(me, 0.1) -- B changes to C
	T.eq(b:Describe(), "Parent/C", "C in B's place")
	log = {}
	b:Update(me, 0.1) -- C is done, so A resumes
	Expect({ "C:Update", "C:OnEnd", "A:OnResume", "Parent:Update" }, "C resumes A")
	T.eq(b:Describe(), "Parent/A", "A resumed")
end)

-- ApplyResult: SUSPEND_FOR and DONE

T.test("SuspendFor suspends the child and then the action, and Done resumes them", function()
	local me = Setup()
	local B = Probe("B", { Update = function(self) return self:Done("finished") end })
	local Child = Probe("Child")
	local suspended = false
	local A = Probe("A", {
		child = function() return Child:New() end,
		Update = function(self)
			if suspended then return self:Continue() end
			suspended = true
			return self:SuspendFor(B:New(), "interrupt")
		end,
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	log = {}
	b:Update(me, 0.1)
	Expect({ "Child:Update", "A:Update", "Child:OnSuspend", "A:OnSuspend", "B:OnStart" }, "suspend")
	T.eq(b:Describe(), "B", "B on top")
	b:Update(me, 0.1)
	Expect({ "B:Update", "B:OnEnd", "Child:OnResume", "A:OnResume" }, "resume")
	T.eq(b:Describe(), "A/Child", "A back on top")
end)

T.test("SuspendFor clears the suspending action's own pending event result", function()
	local me = Setup()
	local b
	local B = Probe("B")
	local A = Probe("A", {
		events = { OnStuck = function(self) return self:TryDone(N.RESULT_TRY, "stuck") end },
		Update = function(self, me)
			b:Event(me, "OnStuck") -- an event raised by A's own work
			return self:SuspendFor(B:New(), "interrupt")
		end,
	})
	b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	b:Update(me, 0.1)
	log = {}
	b:Update(me, 0.1)
	Expect({ "B:Update" }, "B is not out of scope")
	T.eq(b:Describe(), "B", "describe")
end)

T.test("OnSuspend returning Done ends the action instead of burying it", function()
	local me = Setup()
	local B = Probe("B", { Update = function(self) return self:Done("finished") end })
	local A = Probe("A", {
		Update = function(self) return self:SuspendFor(B:New(), "interrupt") end,
		OnSuspend = function(self) return self:Done("give way") end,
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	log = {}
	b:Update(me, 0.1)
	Expect({ "A:Update", "A:OnSuspend", "A:OnEnd", "B:OnStart" }, "A ends")
	b:Update(me, 0.1)
	Expect({ "B:Update", "B:OnEnd" }, "nothing to resume")
	T.eq(b:IsEmpty(), true, "empty")
end)

-- InvokeOnEnd

T.test("ending an action ends its children top down, then itself, each once", function()
	local me = Setup()
	local Next = Probe("Next")
	local C2 = Probe("C2")
	local C1 = Probe("C1", { Update = function(self) return self:SuspendFor(C2:New(), "cover") end })
	local P = Probe("P", { child = function() return C1:New() end })
	local changed = false
	local R = Probe("R", {
		child = function() return P:New() end,
		Update = function(self)
			if not changed then
				changed = true
				return self:Continue()
			end
			return self:ChangeTo(Next:New(), "leave")
		end,
	})
	local b = Behavior:New(R:New(), "Test")
	b:Update(me, 0.1) -- start
	b:Update(me, 0.1) -- C1 suspends for C2
	T.eq(b:Describe(), "R/P/C2", "nested stack")
	log = {}
	b:Update(me, 0.1)
	Expect({ "C2:Update", "P:Update", "R:Update", "C2:OnEnd", "C1:OnEnd", "P:OnEnd", "R:OnEnd", "Next:OnStart" }, "end order")
end)

-- PROCESS_EVENT

T.test("an unstarted action ignores events", function()
	local me = Setup()
	local A = Probe("A", { events = { OnStuck = function(self) return self:TryDone() end } })
	local b = Behavior:New(A:New(), "Test")
	b:Event(me, "OnStuck")
	Expect({}, "no handler ran")
	b:Update(me, 0.1)
	Expect({ "A:OnStart" }, "A starts normally")
end)

T.test("an event walks down the buried actions while each continues, then into the child", function()
	local me = Setup()
	local Child = Probe("Child", { events = { OnStuck = function(self) return self:TryContinue() end } })
	local B = Probe("B", { events = { OnStuck = function(self) return self:TryContinue() end } })
	local A = Probe("A", {
		child = function() return Child:New() end,
		Update = function(self) return self:SuspendFor(B:New(), "cover") end,
		events = { OnStuck = function(self) return self:TryToSustain(N.RESULT_TRY, "busy") end },
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	b:Update(me, 0.1) -- A suspends for B
	log = {}
	b:Event(me, "OnStuck")
	-- B is on top with no child; A answers, so the walk stops there. A's
	-- child is not B's child, so it hears nothing.
	Expect({ "B:OnStuck", "A:OnStuck" }, "walk")
end)

T.test("an event reaches the parent's stack first, then the active child", function()
	local me = Setup()
	local Child = Probe("Child", { events = { OnInjured = function(self, me, dmg) Log("amount " .. dmg.amount); return self:TryContinue() end } })
	local Parent = Probe("Parent", {
		child = function() return Child:New() end,
		events = { OnInjured = function(self) return self:TryContinue() end },
	})
	local b = Behavior:New(Parent:New(), "Test")
	b:Update(me, 0.1)
	log = {}
	b:Event(me, "OnInjured", { amount = 30 })
	Expect({ "Parent:OnInjured", "Child:OnInjured", "amount 30" }, "order and payload")
end)

T.test("a stored event result is replaced only by one of greater or equal priority", function()
	local me = Setup()
	local C = Probe("C")
	local D = Probe("D")
	local E = Probe("E")
	local function Target()
		return Probe("A", {
			events = {
				OnStuck = function(self) return self:TryChangeTo(C:New(), N.RESULT_TRY, "first") end,
				OnUnStuck = function(self) return self:TryChangeTo(D:New(), N.RESULT_TRY, "equal wins") end,
				OnIgnite = function(self) return self:TryChangeTo(E:New(), N.RESULT_IMPORTANT, "higher wins") end,
				OnContact = function(self) return self:TryDone(N.RESULT_TRY, "lower loses") end,
			},
		})
	end
	local b = Behavior:New(Target():New(), "Test")
	b:Update(me, 0.1)
	b:Event(me, "OnStuck")
	b:Event(me, "OnUnStuck")
	b:Update(me, 0.1)
	T.eq(b:Describe(), "D", "equal priority replaces")
	b = Behavior:New(Target():New(), "Test")
	b:Update(me, 0.1)
	b:Event(me, "OnIgnite")
	b:Event(me, "OnContact")
	b:Update(me, 0.1)
	T.eq(b:Describe(), "E", "a lower priority is discarded")
end)

T.test("a SUSPEND_FOR left on a buried action puts its action on top of the stack", function()
	local me = Setup()
	local C = Probe("C")
	local B = Probe("B")
	local A = Probe("A", {
		Update = function(self) return self:SuspendFor(B:New(), "cover") end,
		events = { OnStuck = function(self) return self:TrySuspendFor(C:New(), N.RESULT_TRY, "from below") end },
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	b:Update(me, 0.1) -- A suspends for B
	b:Event(me, "OnStuck") -- B continues, so A answers
	log = {}
	b:Update(me, 0.1)
	Expect({ "B:OnSuspend", "C:OnStart" }, "C covers B")
	T.eq(b:Describe(), "C", "C on top")
end)

T.test("a covering action is out of scope when a buried action wants a change, and the resume is skipped", function()
	local me = Setup()
	local C = Probe("C")
	local B = Probe("B")
	local A = Probe("A", {
		Update = function(self) return self:SuspendFor(B:New(), "cover") end,
		events = { OnStuck = function(self) return self:TryChangeTo(C:New(), N.RESULT_TRY, "from below") end },
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	b:Update(me, 0.1) -- A suspends for B
	b:Event(me, "OnStuck")
	log = {}
	b:Update(me, 0.1)
	Expect({ "B:OnEnd" }, "B leaves without updating, and A does not resume")
	T.eq(b:Describe(), "A", "A on top, still suspended")
	b:Update(me, 0.1)
	Expect({ "A:OnEnd", "C:OnStart" }, "A honours its change")
	T.eq(b:Describe(), "C", "describe")
end)

T.test("after a skipped resume, a new suspension covers the resumed action, not the ended one", function()
	local me = Setup()
	local b
	local C = Probe("C")
	local B = Probe("B", {
		Update = function(self, me)
			b:Event(me, "OnStuck") -- A answers from below while B works
			return self:Done("finished")
		end,
	})
	local A = Probe("A", {
		Update = function(self) return self:SuspendFor(B:New(), "cover") end,
		events = { OnStuck = function(self) return self:TrySuspendFor(C:New(), N.RESULT_TRY, "from below") end },
	})
	b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	b:Update(me, 0.1) -- A suspends for B
	log = {}
	b:Update(me, 0.1)
	Expect({ "B:Update", "A:OnStuck", "B:OnEnd" }, "B is done; A's resume is skipped")
	b:Update(me, 0.1)
	-- ~Action cleared A's link to the ended B, so A itself is suspended.
	Expect({ "A:OnSuspend", "C:OnStart" }, "C covers A")
	T.eq(b:Describe(), "C", "describe")
end)

-- Behavior

T.test("a Behavior whose last action finished is empty and does nothing", function()
	local me = Setup()
	local A = Probe("A", {
		Update = function(self) return self:Done("finished") end,
		events = { OnStuck = function(self) return self:TryDone() end },
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	b:Update(me, 0.1)
	T.eq(b:IsEmpty(), true, "empty")
	log = {}
	b:Update(me, 0.1)
	b:Event(me, "OnStuck")
	Expect({}, "nothing runs")
	T.eq(b:Describe(), "", "describe")
end)

T.test("destroying a Behavior ends its actions once it has run", function()
	local me = Setup()
	local Child = Probe("Child")
	local A = Probe("A", { child = function() return Child:New() end })
	local never = Behavior:New(A:New(), "Test")
	never:Destroy()
	Expect({}, "a behavior never updated ends nothing")
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	log = {}
	b:Destroy()
	Expect({ "Child:OnEnd", "A:OnEnd" }, "ends")
	T.eq(b:IsEmpty(), true, "empty")
end)

T.test("an event handler that returns nothing is an error", function()
	local me = Setup()
	local A = Probe("A", { events = { OnStuck = function() end } })
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	T.eq(pcall(b.Event, b, me, "OnStuck"), false, "raises")
end)

T.test("ChangeTo with no action is an error", function()
	local me = Setup()
	local A = Probe("A", { Update = function(self) return self:ChangeTo(nil, "oops") end })
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	T.eq(pcall(b.Update, b, me, 0.1), false, "raises")
end)

T.test("New calls Init with its arguments", function()
	local Chase = Action:Extend("Chase")
	function Chase:Init(target, range)
		self.target = target
		self.range = range
	end
	local a = Chase:New("victim", 50)
	T.eq(a.target, "victim", "target")
	T.eq(a.range, 50, "range")
	T.eq(a:GetName(), "Chase", "name")
end)

-- Timers (util_shared.h)

-- Queries

-- A query probe: answers ShouldAttack with `answer` (nil: no method) and
-- logs that it was asked.
local function Answering(name, answer, script)
	local class = Probe(name, script)
	if answer ~= nil then
		function class:ShouldAttack(me, them)
			Log(name .. ":ShouldAttack")
			return answer
		end
	end
	return class
end

T.test("a query asks the innermost child first, then what it buries, then its container", function()
	local me = Setup()
	local Top = Answering("Top", N.ANSWER_UNDEFINED)
	local Buried = Answering("Buried", N.ANSWER_UNDEFINED, { Update = function(self) return self:SuspendFor(Top:New(), "cover") end })
	local Outer = Answering("Outer", N.ANSWER_YES, { child = function() return Buried:New() end })
	local b = Behavior:New(Outer:New(), "test")
	b:Update(me, 0.1)
	b:Update(me, 0.1)
	log = {}
	T.eq(b:Query(me, "ShouldAttack", "them"), N.ANSWER_YES, "the container answers")
	Expect({ "Top:ShouldAttack", "Buried:ShouldAttack", "Outer:ShouldAttack" }, "innermost, buried, container")
end)

T.test("the first defined answer wins, and nothing defined is undefined", function()
	local me = Setup()
	local Inner = Answering("Inner", N.ANSWER_NO)
	local Outer = Answering("Outer", N.ANSWER_YES, { child = function() return Inner:New() end })
	local b = Behavior:New(Outer:New(), "test")
	b:Update(me, 0.1)
	log = {}
	T.eq(b:Query(me, "ShouldAttack"), N.ANSWER_NO, "the inner NO outranks the outer YES")
	Expect({ "Inner:ShouldAttack" }, "the outer is not asked")
	T.eq(b:Query(me, "ShouldHurry"), N.ANSWER_UNDEFINED, "nobody answers ShouldHurry")
	T.eq(Behavior:New(nil, "empty"):Query(me, "ShouldAttack"), N.ANSWER_UNDEFINED, "an empty behavior")
end)

T.test("a group passes an event to each member once, in the order they joined", function()
	local seen = {}
	local function Member(name) return { Event = function(_, event, arg) seen[#seen + 1] = name .. ":" .. event .. ":" .. arg end } end
	local a, b = Member("a"), Member("b")
	local group = N.Group.New()
	group:Add(a)
	group:Add(b)
	group:Add(a)
	group:Event("OnCommandApproach", "x")
	T.eq(table.concat(seen, " "), "a:OnCommandApproach:x b:OnCommandApproach:x", "each once")
	group:Remove(a)
	seen = {}
	group:Event("OnCommandPause", "y")
	T.eq(table.concat(seen, " "), "b:OnCommandPause:y", "a left")
end)

T.test("an unstarted countdown has elapsed; a started one elapses after its duration", function()
	local clock = Fake.Clock(10)
	local t = N.CountdownTimer(clock)
	T.eq(t:HasStarted(), false, "unstarted")
	T.eq(t:IsElapsed(), true, "unstarted is elapsed")
	T.eq(t:GetCountdownDuration(), 0, "no duration")
	t:Start(5)
	T.eq(t:HasStarted(), true, "started")
	T.eq(t:IsElapsed(), false, "just started")
	clock:Advance(5)
	T.eq(t:IsElapsed(), false, "at exactly its end")
	T.near(t:GetRemainingTime(), 0, 1e-9, "remaining")
	clock:Advance(0.01)
	T.eq(t:IsElapsed(), true, "after its end")
	T.near(t:GetElapsedTime(), 5.01, 1e-9, "elapsed")
	t:Reset()
	T.near(t:GetRemainingTime(), 5, 1e-9, "reset keeps the duration")
	T.eq(t:GetCountdownDuration(), 5, "duration")
	t:Invalidate()
	T.eq(t:HasStarted(), false, "invalidated")
	T.eq(t:IsElapsed(), true, "invalidated is elapsed")
end)

T.test("an unstarted interval is very old; a started one measures from its start", function()
	local clock = Fake.Clock(10)
	local t = N.IntervalTimer(clock)
	T.eq(t:HasStarted(), false, "unstarted")
	T.eq(t:GetElapsedTime(), N.INTERVAL_UNSTARTED, "unstarted elapsed")
	t:Start()
	clock:Advance(2)
	T.eq(t:HasStarted(), true, "started")
	T.near(t:GetElapsedTime(), 2, 1e-9, "elapsed")
	T.eq(t:IsLessThen(3), true, "less than 3")
	T.eq(t:IsGreaterThen(1), true, "greater than 1")
	T.eq(t:IsGreaterThen(2), false, "not greater than 2")
	t:Reset()
	T.near(t:GetElapsedTime(), 0, 1e-9, "reset")
	t:Invalidate()
	T.eq(t:GetElapsedTime(), N.INTERVAL_UNSTARTED, "invalidated")
end)

-- The Npc model: a variant, its state and its Behavior

local function Variant(overrides)
	local Idle = Probe("Idle", {
		Update = function(self, me)
			self.state.ticks = self.state.ticks + 1
			if self.state.ticks == 3 then me:EmitSound("Bored") end
			return self:Continue()
		end,
		events = { OnKilled = function(self, me) me:Remove(); return self:TryDone(N.RESULT_CRITICAL, "dead") end },
	})
	function Idle:Init(state) self.state = state end
	local variant = {
		KIND = "probe",
		NewState = function(config, actor)
			actor:SetHealth(config.health)
			return {
				ticks = 0,
				age = config.age,
			}
		end,
		InitialAction = function(state) return Idle:New(state) end,
	}
	for k, v in pairs(overrides or {}) do variant[k] = v end
	return variant
end

T.test("an Npc runs its variant's Behavior against its actor, as a scenario", function()
	local me = Setup()
	local npc = N.Npc.New(Variant(), { health = 50 }, me)
	T.eq(me:GetHealth(), 50, "NewState ran with the actor")
	for _ = 1, 4 do npc:Update(0.1) end
	T.eq(npc:State().ticks, 3, "three updates after the start")
	T.eq(#me:Called("EmitSound"), 1, "one sound")
	T.eq(npc:Describe(), "Idle", "describe")
	npc:Event("OnKilled", { amount = 50 })
	npc:Update(0.1)
	T.eq(me.removed, true, "removed")
	T.eq(npc:IsEmpty(), true, "empty after death")
end)

T.test("an Npc accepts all damage unless its variant filters it", function()
	local me = Setup()
	local open = N.Npc.New(Variant(), { health = 50 }, me)
	T.eq(open:FilterDamage({ amount = 10 }), true, "no filter")
	local picky = N.Npc.New(Variant({ FilterDamage = function(state, dmg, actor) return dmg.amount > 20 end }), { health = 50 }, me)
	T.eq(picky:FilterDamage({ amount = 10 }), false, "filtered")
	T.eq(picky:FilterDamage({ amount = 30 }), true, "passed")
end)

T.test("culling marks the live states the variant picks", function()
	local oldestFirst = function(states)
		local picked = {}
		for i = 1, #states - 2 do picked[#picked + 1] = states[i] end
		return picked
	end
	local variant = Variant({ Cull = oldestFirst })
	local npcs = {}
	for i = 1, 4 do
		local config = {
			health = 50,
			age = i,
		}
		npcs[i] = N.Npc.New(variant, config, Fake.Actor())
	end
	npcs[2].actor.alive = false
	local culled = N.Cull(variant, npcs)
	T.eq(#culled, 1, "one over the cap of two among three live")
	T.eq(culled[1].age, 1, "the oldest")
	T.eq(npcs[1]:State().culled, true, "marked")
	T.eq(npcs[3]:State().culled, nil, "kept")
	T.eq(#N.Cull(Variant(), npcs), 0, "a variant without Cull culls nothing")
end)

T.test("destroying an Npc ends its actions", function()
	local me = Setup()
	local npc = N.Npc.New(Variant(), { health = 50 }, me)
	npc:Update(0.1)
	log = {}
	npc:Destroy()
	Expect({ "Idle:OnEnd" }, "ended")
end)

-- Debugging (wetsand_nb_debug BEHAVIOR): the stack and the watcher

-- A watcher that writes down what its Behavior tells it.
local function Watcher()
	local watcher = { seen = {} }
	function watcher:Transition(kind, fromName, toName, reason, starting)
		self.seen[#self.seen + 1] = table.concat({ tostring(kind), fromName, tostring(toName), tostring(reason), tostring(starting) }, " ")
	end
	function watcher:Event(name)
		self.seen[#self.seen + 1] = "event " .. name
	end
	return watcher
end

T.test("a Behavior's stack lists each action, then its children a level deeper, then the actions buried under it", function()
	local me = Setup()
	local B = Probe("B")
	local Child = Probe("Child")
	local suspended = false
	local A = Probe("A", {
		child = function() return Child:New() end,
		Update = function(self)
			if suspended then return self:Continue() end
			suspended = true
			return self:SuspendFor(B:New(), "interrupt")
		end,
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	local frames = b:Stack()
	T.eq(#frames, 2, "A( Child ) before the suspension")
	T.eq(frames[1].name .. frames[1].depth, "A1", "A outermost")
	T.eq(frames[2].name .. frames[2].depth, "Child2", "Child inside it")
	b:Update(me, 0.1)
	frames = b:Stack()
	T.eq(#frames, 3, "B<<A( Child )")
	T.eq(frames[1].name .. frames[1].depth .. tostring(frames[1].suspended), "B1false", "B on top")
	T.eq(frames[2].name .. frames[2].depth .. tostring(frames[2].suspended), "A1true", "A buried under it")
	T.eq(frames[3].name .. frames[3].depth .. tostring(frames[3].suspended), "Child2true", "A's child, suspended with it")
end)

T.test("an empty Behavior has an empty stack", function()
	T.eq(#Behavior:New(nil, "Test"):Stack(), 0, "no frames")
end)

T.test("a watcher sees each start and change with its reason, and each event", function()
	local me = Setup()
	local B = Probe("B")
	local A = Probe("A", { Update = function(self) return self:ChangeTo(B:New(), "bored") end })
	local b = Behavior:New(A:New(), "Test")
	local watcher = Watcher()
	b:Watch(watcher)
	b:Update(me, 0.1)
	b:Update(me, 0.1)
	b:Event(me, "OnInjured", {})
	T.eq(table.concat(watcher.seen, "; "), table.concat({
		N.CHANGE_TO .. " A A Starting Action true",
		N.CHANGE_TO .. " A B bored false",
		"event OnInjured",
	}, "; "), "seen")
	b:Watch(nil)
	b:Event(me, "OnInjured", {})
	T.eq(#watcher.seen, 3, "nothing once unwatched")
end)

T.test("a watcher sees a suspension and the Done that ends it", function()
	local me = Setup()
	local B = Probe("B", { Update = function(self) return self:Done("finished") end })
	local suspended = false
	local A = Probe("A", {
		Update = function(self)
			if suspended then return self:Continue() end
			suspended = true
			return self:SuspendFor(B:New(), "interrupt")
		end,
	})
	local b = Behavior:New(A:New(), "Test")
	b:Update(me, 0.1)
	local watcher = Watcher()
	b:Watch(watcher)
	b:Update(me, 0.1)
	b:Update(me, 0.1)
	T.eq(table.concat(watcher.seen, "; "), table.concat({
		N.SUSPEND_FOR .. " A B interrupt false",
		N.DONE .. " B nil finished false",
	}, "; "), "seen")
end)

T.test("an Npc gives its Behavior's name and stack, and passes a watcher on", function()
	local me = Setup()
	local npc = N.Npc.New(Variant(), { health = 50 }, me)
	local watcher = Watcher()
	npc:Watch(watcher)
	npc:Update(0.1)
	local name, frames = npc:Stack()
	T.eq(name, Variant().KIND, "the Behavior is named for the variant's kind")
	T.eq(frames[1].name, "Idle", "its action")
	T.eq(#watcher.seen, 1, "the start was seen")
end)

-- The actor port contract

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("the fake actor implements every actor method", function()
	local fake = Fake.Actor()
	for _, name in ipairs(Actor.METHODS) do
		T.eq(type(fake[name]), "function", "fake_actor " .. name)
	end
end)

T.test("a variant's particle systems are its PARTICLES, and a variant without the list has none", function()
	local listed = { "some_particle" }
	T.eq(N.Particles({ PARTICLES = listed }), listed, "listed")
	T.eq(#N.Particles({}), 0, "none")
	for _, name in ipairs({ "foundation.npc.zombie", "foundation.npc.headless_hatman", "foundation.npc.eyeball_boss" }) do
		T.eq(#N.Particles(T.require(name)) > 0, true, name .. " lists its systems")
	end
end)

T.test("a variant's fake actor dispatches only the particle systems its variant declares", function()
	local declared, undeclared = "declared_particle", "undeclared_particle"
	local fake = Fake.Actor({ variant = { PARTICLES = { declared } } })
	fake:DispatchParticleEffect(declared, Fake.Vector(0, 0, 0))
	T.eq(#fake:Called("DispatchParticleEffect"), 1, "a declared system plays")
	local ok, err = pcall(fake.DispatchParticleEffect, fake, undeclared, Fake.Vector(0, 0, 0))
	T.eq(ok, false, "an undeclared system is refused")
	T.eq(err:find(undeclared, 1, true) ~= nil, true, "the refusal names it: " .. tostring(err))
	local listless = Fake.Actor({ variant = {} })
	T.eq(pcall(listless.DispatchParticleEffect, listless, declared, Fake.Vector(0, 0, 0)), false, "a variant with no PARTICLES refuses all")
	local plain = Fake.Actor()
	plain:DispatchParticleEffect(undeclared, Fake.Vector(0, 0, 0))
	T.eq(#plain:Called("DispatchParticleEffect"), 1, "an actor with no variant checks nothing")
end)

T.test("wetsand_nextbot defines every actor method the engine does not already provide", function()
	local text = ReadFile("addon/gamemodes/sandcastle/entities/entities/wetsand_nextbot.lua")
	for _, name in ipairs(Actor.METHODS) do
		local defined = text:find("function ENT:" .. name .. "(", 1, true) ~= nil
		T.eq(defined or Actor.ENGINE[name] == true, true, "wetsand_nextbot " .. name)
		-- GMod looks up the engine's metatable before the entity's table, so
		-- an ENT function of an engine method's name would never run.
		T.eq(defined and Actor.ENGINE[name] == true, false, "no shadowed definition of " .. name)
	end
end)

T.test("the damage types keep Source's bits", function()
	T.eq(Actor.DMG_GENERIC, 0, "generic")
	T.eq(Actor.DMG_CRUSH, 1, "crush")
	T.eq(Actor.DMG_SLASH, 4, "slash")
	T.eq(Actor.DMG_BURN, 8, "burn")
	T.eq(Actor.DMG_BLAST, 64, "blast")
	T.eq(Actor.DMG_CLUB, 128, "club")
end)

T.finish()
