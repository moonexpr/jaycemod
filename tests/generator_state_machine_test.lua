-- foundation.generator.state_machine: a classical, flat finite state machine.
local T = dofile("tests/harness.lua")
local Cfsm = T.require("foundation.generator.state_machine")

local CLOSED, OPENING, OPEN = "closed", "opening", "open"
local LOCKED = "locked"

-- A door: closed -> opening -> open -> closed, and nothing else.
local function Door(log)
	local function Note(entry) return function(...) log[#log + 1] = entry .. ":" .. table.concat({ ... }, ",") end end
	return Cfsm.Define({
		name = "door",
		states = { CLOSED, OPENING, OPEN },
		transitions = {
			[CLOSED] = { OPENING },
			[OPENING] = { OPEN },
			[OPEN] = { CLOSED },
		},
		enter = {
			[OPENING] = Note("enter opening"),
			[OPEN] = Note("enter open"),
		},
		leave = { [OPENING] = Note("leave opening") },
		think = { [OPENING] = Note("think opening") },
	})
end

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

T.test("a machine starts in its initial state and moves along declared edges, as a scenario", function()
	local log = {}
	local door = Door(log):New(CLOSED)
	T.eq(door:State(), CLOSED, "starts closed")
	door:Transition(OPENING, "a")
	door:Think("t")
	door:Transition(OPEN, "b")
	T.eq(door:State(), OPEN, "open")
	T.eq(table.concat(log, " "), "enter opening:a think opening:t leave opening:b enter open:b", "handlers in order")
end)

T.test("a transition along an undeclared edge is refused, and the state stays", function()
	local door = Door({}):New(CLOSED)
	local err = Raises(door.Transition, door, OPEN)
	T.eq(err:find("closed", 1, true) ~= nil and err:find("open", 1, true) ~= nil, true, "names both: " .. err)
	T.eq(door:State(), CLOSED, "still closed")
	T.eq(door:Can(OPENING), true, "a declared edge")
	T.eq(door:Can(OPEN), false, "an undeclared edge")
end)

T.test("Enter skips the state left's leave handler, as Source's State_Enter", function()
	local log = {}
	local door = Door(log):New(OPENING)
	door:Enter(OPEN)
	T.eq(table.concat(log, " "), "enter open:", "no leave")
end)

T.test("an undeclared state is refused wherever it appears", function()
	Raises(Door({}).New, Door({}), LOCKED)
	local door = Door({}):New(CLOSED)
	Raises(door.Transition, door, LOCKED)
	Raises(Cfsm.Define, {
		name = "bad",
		states = { CLOSED },
		enter = { [LOCKED] = function() end },
	})
	Raises(Cfsm.Define, {
		name = "bad",
		states = { CLOSED },
		transitions = { [CLOSED] = { LOCKED } },
	})
end)

T.test("a definition needs a name, states without repeats, and functions for handlers", function()
	Raises(Cfsm.Define, { states = { CLOSED } })
	Raises(Cfsm.Define, {
		name = "empty",
		states = {},
	})
	Raises(Cfsm.Define, {
		name = "twice",
		states = { CLOSED, CLOSED },
	})
	Raises(Cfsm.Define, {
		name = "not a function",
		states = { CLOSED },
		think = { [CLOSED] = true },
	})
end)

T.test("without a transition table every declared state may follow any other", function()
	local free = Cfsm.Define({
		name = "free",
		states = { CLOSED, OPEN },
	}):New(CLOSED)
	free:Transition(OPEN)
	free:Transition(OPEN)
	free:Enter(CLOSED)
	T.eq(free:State(), CLOSED, "closed")
end)

T.test("a state without a think handler thinks nothing", function()
	local door = Door({}):New(CLOSED)
	door:Think()
	T.eq(door:State(), CLOSED, "unchanged")
end)

T.test("a definition is its own copy: changing the spec after does not change it", function()
	local enter = {}
	local def = Cfsm.Define({
		name = "copy",
		states = { CLOSED, OPEN },
		enter = enter,
	})
	local entered = false
	enter[OPEN] = function() entered = true end
	def:New(CLOSED):Transition(OPEN)
	T.eq(entered, false, "the later handler is not seen")
end)

T.test("a transition action runs on every move, after the leave and before the enter", function()
	local log = {}
	local function Note(entry) return function() log[#log + 1] = entry end end
	local machine = Cfsm.Define({
		name = "acted",
		states = { CLOSED, OPEN },
		changing = function(from, to, tag) log[#log + 1] = from .. ">" .. to .. ":" .. tag end,
		enter = { [OPEN] = Note("enter open") },
		leave = { [CLOSED] = Note("leave closed") },
	}):New(CLOSED)
	machine:Transition(OPEN, "t")
	machine:Enter(CLOSED, "e")
	T.eq(table.concat(log, " "), "leave closed closed>open:t enter open open>closed:e", "order")
end)

T.test("a transition action must be a function", function()
	Raises(Cfsm.Define, {
		name = "bad",
		states = { CLOSED },
		changing = "yes",
	})
end)

T.test("machines of one definition keep their own state", function()
	local def = Door({})
	local a, b = def:New(CLOSED), def:New(CLOSED)
	a:Transition(OPENING)
	T.eq(b:State(), CLOSED, "b untouched")
	T.eq(a:Is(OPENING), true, "Is")
end)

T.finish()
