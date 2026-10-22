-- The dev workbench's scenario format (sandcastle_dev_scenario): a named,
-- described state of one map at one schema, refused or migrated on load,
-- never applied silently.
local T = dofile("tests/harness.lua")
local Scenario = T.require("sandcastle_dev_scenario")

local MAP = "cp_altitude"
local STATE = {
	schema = 2,
	map = MAP,
	sections = { rounds = { active = true } },
}

local function Raises(fn, pattern, what)
	local ok, err = pcall(fn)
	T.eq(ok, false, what .. " raises")
	T.eq(tostring(err):find(pattern, 1, true) ~= nil, true, what .. " says " .. pattern .. ": " .. tostring(err))
end

T.test("a scenario holds its name, description, map, schema and state", function()
	local s = Scenario.New("mid_push", "BLU on the last point", STATE, "2026-10-22 10:00")
	T.eq(s.name, "mid_push", "name")
	T.eq(s.description, "BLU on the last point", "description")
	T.eq(s.map, MAP, "the state's map")
	T.eq(s.schema, 2, "the state's schema")
	T.eq(s.saved_at, "2026-10-22 10:00", "when")
	T.eq(s.state, STATE, "state")
	T.eq(s.format, Scenario.FORMAT, "the file format")
end)

T.test("a name is lower-case letters, digits, _ and -, so it is a safe file name", function()
	for _, bad in ipairs({ "", "Mid", "a b", "../x", "a.json", string.rep("a", Scenario.MAX_NAME + 1) }) do
		Raises(function() Scenario.New(bad, "", STATE, "") end, "name", "name " .. bad)
	end
	T.eq(Scenario.New("quick_1", "", STATE, "").name, "quick_1", "a quick slot's")
end)

T.test("Path puts a scenario under its map", function()
	T.eq(Scenario.Path("base/", MAP, "mid_push"), "base/cp_altitude/mid_push.json", "path")
end)

T.test("Load gives the state of a scenario of this map and schema", function()
	local s = Scenario.New("a", "", STATE, "")
	local state, notes = Scenario.Load(s, MAP, 2, {})
	T.eq(state.sections.rounds.active, true, "the state's contents")
	T.eq(state ~= STATE, true, "a copy, which applying or migrating leaves the scenario's own intact")
	T.eq(#notes, 0, "nothing to say")
end)

T.test("a scenario of another map is refused, naming both and the fix", function()
	local s = Scenario.New("a", "", STATE, "")
	Raises(function() Scenario.Load(s, "ctf_2fort", 2, {}) end, "changelevel cp_altitude", "another map")
end)

T.test("an older schema migrates step by step, and says so", function()
	local old = Scenario.New("a", "", {
		schema = 1,
		map = MAP,
		sections = { round = { active = true } },
	}, "")
	local migrations = {
		[1] = function(state)
			state.sections.rounds = state.sections.round
			state.sections.round = nil
			return state
		end,
	}
	local state, notes = Scenario.Load(old, MAP, 2, migrations)
	T.eq(state.schema, 2, "now schema 2")
	T.eq(state.sections.rounds.active, true, "moved")
	T.eq(#notes, 1, "one note")
	T.eq(notes[1]:find("1 to 2", 1, true) ~= nil, true, "says from and to: " .. notes[1])
	T.eq(old.state.sections.round ~= nil, true, "the scenario itself is left as it was")
end)

T.test("an older schema with no migration is refused", function()
	local old = Scenario.New("a", "", {
		schema = 1,
		map = MAP,
		sections = {},
	}, "")
	Raises(function() Scenario.Load(old, MAP, 3, { [1] = function(s) return s end }) end, "no migration from schema 2", "a gap")
end)

T.test("a newer schema is refused: this workbench cannot read it", function()
	local new = Scenario.New("a", "", {
		schema = 9,
		map = MAP,
		sections = {},
	}, "")
	Raises(function() Scenario.Load(new, MAP, 2, {}) end, "newer", "newer")
end)

T.test("Parse checks a decoded file's fields", function()
	local s = Scenario.New("a", "d", STATE, "t")
	T.eq(Scenario.Parse(s, "a.json").name, "a", "a good one")
	Raises(function() Scenario.Parse({ name = "a" }, "a.json") end, "a.json", "a bad one names its file")
	Raises(function() Scenario.Parse(nil, "b.json") end, "b.json", "an unreadable one")
end)

T.finish()
