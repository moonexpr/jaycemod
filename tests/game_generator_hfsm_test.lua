-- game.generator.hfsm: the Chart seam over the Action/Behavior engine. The
-- engine itself is tested through foundation.npc (npc_test.lua), which runs
-- on it.
local T = dofile("tests/harness.lua")
local Hfsm = T.require("game.generator.hfsm")
local Port = T.require("foundation.core.port")

-- A soldier the port is checked against: more methods than any chart needs.
local function Soldier()
	local soldier = { time = 0, alive = true, shots = 0 }
	function soldier:Now() return self.time end
	function soldier:IsAlive() return self.alive end
	function soldier:Shoot() self.shots = self.shots + 1 end
	function soldier:Secret() return "engine internals" end
	return soldier
end

local SOLDIER_PORT = Port.New("Soldier", { "Now", "IsAlive", "Shoot" })

-- Patrol until stuck, then Unstick, then back; an engagement asks to shoot.
local function PatrolChart()
	local chart = Hfsm.Chart({
		name = "Patrol",
		port = SOLDIER_PORT,
		events = { "OnStuck" },
		queries = { "ShouldShoot" },
		initial = function(state) return state.Patrol:New() end,
	})
	local Patrol = chart:State("Patrol")
	local Unstick = chart:State("Unstick")
	function Patrol:OnStuck(me) return self:TryChangeTo(Unstick:New(), Hfsm.RESULT_IMPORTANT, "stuck") end
	function Patrol:ShouldShoot(me) return Hfsm.ANSWER_YES end
	function Patrol:Update(me)
		me:Shoot()
		return self:Continue()
	end
	function Unstick:Update(me) return self:ChangeTo(Patrol:New(), "free") end
	return chart, { Patrol = Patrol, Unstick = Unstick }
end

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

T.test("a machine runs the chart's states over its actor, as a scenario", function()
	local chart, states = PatrolChart()
	local soldier = Soldier()
	local machine = chart:New(soldier, states)
	machine:Update(0.1)
	machine:Update(0.1) -- the first tick starts the state, the second updates it
	T.eq(machine:Describe(), "Patrol", "patrolling")
	T.eq(soldier.shots, 1, "patrol shoots through the port")
	machine:Event("OnStuck")
	machine:Update(0.1)
	T.eq(machine:Describe(), "Unstick", "stuck")
	machine:Update(0.1)
	T.eq(machine:Describe(), "Patrol", "free again")
	T.eq(machine:Query("ShouldShoot"), Hfsm.ANSWER_YES, "query answered")
end)

T.test("a state sees only the methods its chart's port declares", function()
	local chart = Hfsm.Chart({
		name = "Nosy",
		port = SOLDIER_PORT,
		initial = function(state) return state.Nosy:New() end,
	})
	local Nosy = chart:State("Nosy")
	local seen
	function Nosy:Update(me)
		seen = { me.Secret, me:Now() }
		return self:Continue()
	end
	local soldier = Soldier()
	soldier.time = 7
	local machine = chart:New(soldier, { Nosy = Nosy })
	machine:Update(0.1)
	machine:Update(0.1)
	T.eq(seen[1], nil, "an undeclared method is out of reach")
	T.eq(seen[2], 7, "a declared method forwards to the actor")
end)

T.test("an actor missing a port method is refused, naming what it lacks", function()
	local chart, states = PatrolChart()
	local soldier = Soldier()
	soldier.Shoot = nil
	local err = Raises(chart.New, chart, soldier, states)
	T.eq(err:find("Shoot", 1, true) ~= nil, true, "names Shoot: " .. err)
end)

T.test("a port needs a name and at least one method", function()
	Raises(Port.New, "Empty", {})
	Raises(Port.New, nil, { "Now" })
end)

T.test("a chart needs a name, a port and an initial state", function()
	Raises(Hfsm.Chart, { port = SOLDIER_PORT, initial = function() end })
	Raises(Hfsm.Chart, { name = "NoPort", initial = function() end })
	Raises(Hfsm.Chart, { name = "NoInitial", port = SOLDIER_PORT })
end)

T.test("a state may not define a handler for an event its chart does not declare", function()
	local chart = PatrolChart()
	local Patrol = chart:State("Typo")
	local err = Raises(function()
		function Patrol:OnStuk(me) return self:TryContinue() end
	end)
	T.eq(err:find("OnStuk", 1, true) ~= nil, true, "names the handler: " .. err)
end)

T.test("lifecycle hooks and declared events may be defined, on states and their subclasses", function()
	local chart = PatrolChart()
	local Base = chart:State("Base")
	local Derived = Base:Extend("Derived")
	function Derived:OnStart(me) return self:Continue() end
	function Derived:OnEnd(me) end
	function Derived:OnStuck(me) return self:TryContinue() end
	T.eq(Raises(function() function Derived:OnInjured() end end):find("OnInjured", 1, true) ~= nil, true,
		"a subclass is held to the chart too")
end)

T.test("sending or asking what the chart does not declare is refused", function()
	local chart, states = PatrolChart()
	local machine = chart:New(Soldier(), states)
	machine:Update(0.1)
	Raises(machine.Event, machine, "OnStuk")
	Raises(machine.Query, machine, "ShouldShot")
end)

T.test("the initial state must be one of the chart's own", function()
	local _, states = PatrolChart()
	local other = Hfsm.Chart({
		name = "Other",
		port = SOLDIER_PORT,
		initial = function(state) return state.Patrol:New() end,
	})
	Raises(other.New, other, Soldier(), states)
end)

T.test("a destroyed machine ends its states", function()
	local chart = Hfsm.Chart({
		name = "Ends",
		port = SOLDIER_PORT,
		initial = function(state) return state.Idle:New() end,
	})
	local Idle = chart:State("Idle")
	local ended = false
	function Idle:OnEnd() ended = true end
	local machine = chart:New(Soldier(), { Idle = Idle })
	machine:Update(0.1)
	machine:Destroy()
	T.eq(ended, true, "ended")
	T.eq(machine:IsEmpty(), true, "empty")
end)

T.finish()
