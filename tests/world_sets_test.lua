-- foundation.world.sets: named sets, closed vocabularies parsed once.
local T = dofile("tests/harness.lua")
local Sets = world.sets

local PATH, COST, NAV = "PATH", "COST", "NAV"

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

T.test("a named set holds its members, in the order given", function()
	local layers = Sets.Named("layers", { PATH, COST, NAV })
	T.eq(layers:Has(COST), true, "a member")
	T.eq(layers:Has("VISION"), false, "not a member")
	T.eq(layers:Has(nil), false, "nil is never a member")
	local members = layers:Members()
	T.eq(table.concat(members, ","), "PATH,COST,NAV", "in order")
	members[1] = "changed"
	T.eq(layers:Members()[1], PATH, "the list handed out is a copy")
	T.eq(layers:Name(), "layers", "its name")
end)

T.test("a set is parsed once: no name, no members, or a repeat is refused", function()
	T.eq(Raises(Sets.Named, "", { PATH }):find("needs a name", 1, true) ~= nil, true, "no name")
	T.eq(Raises(Sets.Named, "layers", {}):find("layers: lists no members", 1, true) ~= nil, true, "no members")
	T.eq(Raises(Sets.Named, "layers", { PATH, COST, PATH }):find("layers: lists PATH twice", 1, true) ~= nil, true, "a repeat")
end)

T.test("the members the caller gave are copied, so later edits do not reach the set", function()
	local list = { PATH, COST }
	local layers = Sets.Named("layers", list)
	list[3] = NAV
	T.eq(layers:Has(NAV), false, "not added")
end)

T.test("checking a value outside the set is the caller's bug, blamed on its caller", function()
	local reasons = Sets.Named("reports: reason", { "cheating", "idle" })
	T.eq(reasons:Check("idle"), "idle", "a member passes through")
	local function File(reason) reasons:Check(reason) end
	local function Caller() File("rude") end
	local err = Raises(Caller)
	T.eq(err:find("reports: reason: unknown rude", 1, true) ~= nil, true, "named")
	T.eq(err:find("world_sets_test.lua:", 1, true) ~= nil, true, "points into the caller's file")
	local line = debug.getinfo(Caller, "S").linedefined
	T.eq(err:find(":" .. line .. ":", 1, true) ~= nil, true, "at File's caller")
end)

T.test("a token names the first member it is a prefix of, ignoring case", function()
	local layers = Sets.Named("layers", { PATH, COST, NAV })
	T.eq(layers:Match("p"), PATH, "a prefix")
	T.eq(layers:Match("cost"), COST, "the whole name, lower case")
	T.eq(layers:Match("vision"), nil, "no member")
	T.eq(layers:Match(""), nil, "an empty token names nothing")
end)

-- Plain sets: value -> true tables.

local function Listed(set)
	return table.concat(Sets.Sorted(set), " ")
end

T.test("a plain set from a list, each value once", function()
	T.eq(Listed(Sets.Of({ "b", "a", "b" })), "a b", "a and b")
	T.eq(Sets.Count(Sets.Of({ "b", "a", "b" })), 2, "two")
	T.eq(Sets.Count({}), 0, "empty")
end)

T.test("union, intersection and difference make new sets", function()
	local a, b = Sets.Of({ 1, 2, 3 }), Sets.Of({ 3, 4 })
	T.eq(Listed(Sets.Union(a, b)), "1 2 3 4", "union")
	T.eq(Listed(Sets.Union(a, b, Sets.Of({ 9 }))), "1 2 3 4 9", "union of three")
	T.eq(Listed(Sets.Intersect(a, b)), "3", "intersection")
	T.eq(Listed(Sets.Subtract(a, b)), "1 2", "difference")
	T.eq(Listed(a), "1 2 3", "the operands are untouched")
end)

T.test("a copy is a new set with the same members", function()
	local a = Sets.Of({ "x" })
	local copy = Sets.Copy(a)
	copy.y = true
	T.eq(Listed(a), "x", "the original")
	T.eq(Listed(copy), "x y", "the copy")
end)

T.finish()
