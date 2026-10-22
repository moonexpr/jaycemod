-- foundation.core.meta.enum: named constants numbered in order.
local T = dofile("tests/harness.lua")
local Enum = T.require("foundation.core.meta.enum")
local Constants = T.require("foundation.core.meta.constants")
local Class = T.require("foundation.core.meta.class")

local FIRST = 0

local function Effects()
	return Enum.New("hit sound", FIRST, { "DEFAULT", "ELECTRO", "NOTES", "TEAM_RED" })
end

T.test("an enumeration numbers its names in order from its first value", function()
	local effects = Effects()
	T.eq(effects.DEFAULT, FIRST, "the first")
	T.eq(effects.NOTES, FIRST + 2, "the third")
	T.eq(effects:First(), FIRST, "first value")
	T.eq(effects:Last(), FIRST + 3, "last value")
	T.eq(effects:Count(), 4, "four")
	T.eq(table.concat(effects:Names(), " "), "DEFAULT ELECTRO NOTES TEAM_RED", "Names, in value order")
end)

T.test("an enumeration is a constant set", function()
	local effects = Effects()
	T.eq(Class.IsA(effects, Constants.ConstantSet), true, "of the base")
	T.eq(pcall(function() return effects.VORTEX end), false, "an unknown name refused")
	T.eq(pcall(function() effects.VORTEX = 9 end), false, "no new names")
end)

T.test("an enumeration names its values, and checks them", function()
	local effects = Effects()
	T.eq(effects:NameOf(FIRST + 1), "ELECTRO", "a value's name")
	T.eq(effects:NameOf(FIRST + 9), nil, "no name past the last")
	T.eq(effects:Valid(effects.NOTES), true, "a member")
	T.eq(effects:Valid(FIRST + 0.5), false, "not a member")
	T.eq(effects:Check(effects.NOTES), effects.NOTES, "Check passes a member")
	T.eq(pcall(effects.Check, effects, FIRST - 1), false, "and refuses any other")
end)

T.test("an enumeration describes itself for a help text", function()
	T.eq(Effects():Describe(), "0 Default, 1 Electro, 2 Notes, 3 Team red", "value and name")
end)

T.test("an enumeration needs a whole first value and distinct names", function()
	T.eq(pcall(Enum.New, "x", 0.5, { "A" }), false, "a fraction")
	T.eq(pcall(Enum.New, "x", 0, { "A", "A" }), false, "a name twice")
	T.eq(pcall(Enum.New, "x", 0, {}), false, "no names")
end)

T.test("an enumeration indexed by a value gives its name", function()
	local effects = Effects()
	T.eq(effects[FIRST + 1], "ELECTRO", "a value's name")
	T.eq(effects[FIRST + 9], nil, "none past the last")
end)

T.test("calling an enumeration parses a value or a name into its value", function()
	local effects = Effects()
	T.eq(effects(FIRST + 2), FIRST + 2, "a value it has")
	T.eq(effects("NOTES"), FIRST + 2, "a name it has")
	T.eq(effects(FIRST + 9), nil, "nil for a value it lacks")
	T.eq(effects("VORTEX"), nil, "nil for a name it lacks")
	T.eq(tostring(effects), effects:Describe(), "tostring describes it")
	T.eq(getmetatable(effects).__len(effects), effects:Count(), "__len is Count")
end)

T.finish()
