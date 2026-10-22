-- games.world.snapshot: a model's state as plain data and back.
local T = dofile("tests/harness.lua")
local Snapshot = T.require("games.world.snapshot")
local Cfsm = T.require("foundation.generator.state_machine")

local IDLE, BUSY = "idle", "busy"
local LIGHT = Cfsm.Define({
	name = "light",
	states = { IDLE, BUSY },
	transitions = { [IDLE] = { BUSY } },
})

local Thing = {}
Thing.__index = Thing

local SPEC = Snapshot.Spec({
	name = "thing",
	skip = { "settings" },
	times = { "dueAt", "waves.*" },
	machines = { "states" },
})

local function NewThing(now)
	return setmetatable({
		settings = { fromConvars = true },
		states = LIGHT:New(IDLE),
		dueAt = now + 5,
		waves = {
			[2] = now + 1,
			[3] = now + 2,
		},
		count = 4,
		label = "a",
		list = { 1, 2, 3 },
		nested = { deeper = { yes = true } },
		gone = nil,
	}, Thing)
end

local function Raises(fn, pattern, what)
	local ok, err = pcall(fn)
	T.eq(ok, false, what .. " raises")
	T.eq(tostring(err):find(pattern, 1, true) ~= nil, true, what .. " names " .. pattern .. ": " .. tostring(err))
end

T.test("times are taken as seconds from now and put back from the new now", function()
	local thing = NewThing(100)
	local snap = Snapshot.Take(thing, SPEC, 100)
	T.eq(snap.dueAt, 5, "due in 5 s")
	T.eq(snap.waves[2], 1, "wave in 1 s")
	local other = NewThing(0)
	Snapshot.Apply(other, snap, SPEC, 1000)
	T.eq(other.dueAt, 1005, "due 5 s after the new now")
	T.eq(other.waves[3], 1002, "wave 2 s after the new now")
end)

T.test("a machine is kept as its state and restored without running handlers", function()
	local thing = NewThing(0)
	thing.states:Transition(BUSY)
	local snap = Snapshot.Take(thing, SPEC, 0)
	T.eq(snap.states, BUSY, "state kept")
	local other = NewThing(0)
	Snapshot.Apply(other, snap, SPEC, 0)
	T.eq(other.states:State(), BUSY, "state restored")
end)

T.test("Machine:Restore sets any declared state, even one no edge reaches", function()
	local machine = LIGHT:New(BUSY)
	machine:Restore(IDLE)
	T.eq(machine:State(), IDLE, "restored")
	Raises(function() machine:Restore("broken") end, "undeclared", "an undeclared state")
end)

T.test("skipped fields are neither taken nor touched", function()
	local thing = NewThing(0)
	local snap = Snapshot.Take(thing, SPEC, 0)
	T.eq(snap.settings, nil, "skipped")
	local other = NewThing(0)
	other.settings.fromConvars = "kept"
	Snapshot.Apply(other, snap, SPEC, 0)
	T.eq(other.settings.fromConvars, "kept", "untouched")
end)

T.test("taken values are copies, and applied values are copies again", function()
	local thing = NewThing(0)
	local snap = Snapshot.Take(thing, SPEC, 0)
	thing.list[1] = 99
	T.eq(snap.list[1], 1, "the snapshot does not follow the model")
	local other = NewThing(0)
	Snapshot.Apply(other, snap, SPEC, 0)
	snap.nested.deeper.yes = false
	T.eq(other.nested.deeper.yes, true, "the model does not follow the snapshot")
end)

T.test("a field the snapshot lacks is cleared, so a pending time does not survive", function()
	local thing = NewThing(0)
	thing.dueAt = nil
	local snap = Snapshot.Take(thing, SPEC, 0)
	local other = NewThing(0)
	other.extra = "stale"
	Snapshot.Apply(other, snap, SPEC, 0)
	T.eq(other.dueAt, nil, "cleared")
	T.eq(other.extra, nil, "a field added since is cleared too")
end)

T.test("a value that is not plain data needs the refs port, or is refused with its path", function()
	local thing = NewThing(0)
	thing.owner = setmetatable({ id = 7 }, { __tostring = function() return "entity 7" end })
	Raises(function() Snapshot.Take(thing, SPEC, 0) end, "thing.owner", "no refs")
	thing.owner = function() end
	Raises(function() Snapshot.Take(thing, SPEC, 0) end, "thing.owner", "a function")
end)

T.test("refs encode and decode values and keys that are not plain data", function()
	local a, b = { id = "a" }, { id = "b" }
	setmetatable(a, {})
	setmetatable(b, {})
	local byId = {
		a = a,
		b = b,
	}
	local refs = {
		Encode = function(_, value) return { id = value.id } end,
		Decode = function(_, data) return byId[data.id] end,
	}
	local thing = NewThing(0)
	thing.owner = a
	thing.touching = { [a] = true, [b] = 3 }
	local snap = Snapshot.Take(thing, SPEC, 0, refs)
	local other = NewThing(0)
	Snapshot.Apply(other, snap, SPEC, 0, refs)
	T.eq(other.owner, a, "a value decoded")
	T.eq(other.touching[a], true, "a key decoded")
	T.eq(other.touching[b], 3, "another key decoded")
end)

T.test("a time path reaches through a table keyed by refs", function()
	local a = setmetatable({ id = "a" }, {})
	local refs = {
		Encode = function(_, value) return { id = value.id } end,
		Decode = function() return a end,
	}
	local spec = Snapshot.Spec({
		name = "points",
		times = { "byEnt.*.unlockAt" },
	})
	local model = { byEnt = { [a] = { unlockAt = 130 } } }
	local snap = Snapshot.Take(model, spec, 100, refs)
	local other = { byEnt = {} }
	Snapshot.Apply(other, snap, spec, 1000, refs)
	T.eq(other.byEnt[a].unlockAt, 1030, "30 s to go, from the new now")
	T.eq(model.byEnt[a].unlockAt, 130, "the model taken is untouched")
end)

T.test("a ref that no longer resolves is refused with its path", function()
	local gone = setmetatable({ id = "x" }, {})
	local refs = {
		Encode = function(_, value) return { id = value.id } end,
		Decode = function() return nil end,
	}
	local thing = NewThing(0)
	thing.owner = gone
	local snap = Snapshot.Take(thing, SPEC, 0, refs)
	Raises(function() Snapshot.Apply(NewThing(0), snap, SPEC, 0, refs) end, "thing.owner", "unresolved")
end)

T.test("infinite numbers survive as data a JSON encoder can write", function()
	local thing = NewThing(0)
	thing.forever = math.huge
	local snap = Snapshot.Take(thing, SPEC, 0)
	T.eq(type(snap.forever), "table", "encoded")
	local other = NewThing(0)
	Snapshot.Apply(other, snap, SPEC, 0)
	T.eq(other.forever, math.huge, "decoded")
end)

T.test("a time that is infinite stays infinite", function()
	local thing = NewThing(0)
	thing.dueAt = math.huge
	local other = NewThing(0)
	Snapshot.Apply(other, Snapshot.Take(thing, SPEC, 50), SPEC, 900)
	T.eq(other.dueAt, math.huge, "forever")
end)

T.test("Apply writes raw, so a model guarded against new keys takes its own fields back", function()
	local Guarded = { __index = {} }
	Guarded.__newindex = function(_, key) error("no new key " .. tostring(key)) end
	local spec = Snapshot.Spec({
		name = "guarded",
		times = { "dueAt" },
	})
	local model = setmetatable({}, Guarded)
	rawset(model, "dueAt", 130)
	local snap = Snapshot.Take(model, spec, 100)
	rawset(model, "dueAt", nil)
	Snapshot.Apply(model, snap, spec, 200)
	T.eq(rawget(model, "dueAt"), 230, "restored past the guard")
end)

T.test("a weak table is data: its contents are copied and its mode comes back", function()
	local spec = Snapshot.Spec({ name = "weak" })
	local model = { seen = setmetatable({ a = 1 }, { __mode = "k" }) }
	local snap = Snapshot.Take(model, spec, 0)
	local other = {}
	Snapshot.Apply(other, snap, spec, 0)
	T.eq(other.seen.a, 1, "contents")
	T.eq(getmetatable(other.seen).__mode, "k", "mode")
	T.eq(other.seen ~= model.seen, true, "a copy")
end)

T.test("a table whose metatable holds more than a mode is not data", function()
	local spec = Snapshot.Spec({ name = "classy" })
	local model = { obj = setmetatable({}, { __mode = "k", __index = {} }) }
	local ok, err = pcall(Snapshot.Take, model, spec, 0)
	T.eq(ok, false, "refused without refs")
	T.eq(tostring(err):find("classy.obj", 1, true) ~= nil, true, "names the path: " .. tostring(err))
end)

T.test("a cycle is refused with its path", function()
	local thing = NewThing(0)
	thing.nested.back = thing.nested
	Raises(function() Snapshot.Take(thing, SPEC, 0) end, "thing.nested.back", "a cycle")
end)

T.test("a spec naming a time or machine twice, or nothing, is refused", function()
	Raises(function() Snapshot.Spec({ name = "x", times = { "a", "a" } }) end, "a", "a repeat")
	Raises(function() Snapshot.Spec({}) end, "name", "no name")
end)

T.finish()
