-- foundation.core.constants: a closed, fixed set of named constants.
local T = dofile("tests/harness.lua")
local Constants = core.constants
local Class = core.class

local function Layout()
	return Constants.New("inventory layout", {
		GAP = 8,
		TILE = 112,
		PAD = 4,
		BADGE = 4,
	})
end

T.test("a constant set reads its constants as fields", function()
	local layout = Layout()
	T.eq(layout.GAP, 8, "a constant")
	T.eq(layout.PAD, layout.BADGE, "two constants may share a value")
	T.eq(layout:Name(), "inventory layout", "its name")
	T.eq(Class.IsA(layout, Constants.ConstantSet), true, "a constant set")
end)

T.test("reading a constant it lacks is refused, naming the set", function()
	local layout = Layout()
	local ok, why = pcall(function() return layout.GAPP end)
	T.eq(ok, false, "refused")
	T.eq(why:find("inventory layout: no constant GAPP", 1, true) ~= nil, true, "named: " .. tostring(why))
	T.eq(layout:Has("GAPP"), false, "Has asks without refusing")
	T.eq(layout:Has("GAP"), true, "a constant it has")
end)

T.test("a constant set takes no new constants", function()
	local layout = Layout()
	T.eq(pcall(function() layout.MARGIN = 2 end), false, "refused")
end)

T.test("iterating a constant set gives exactly its constants", function()
	local seen = {}
	for name, value in pairs(Layout()) do seen[#seen + 1] = name .. "=" .. value end
	table.sort(seen)
	T.eq(table.concat(seen, " "), "BADGE=4 GAP=8 PAD=4 TILE=112", "constants only")
	T.eq(table.concat(Layout():Names(), " "), "BADGE GAP PAD TILE", "Names, sorted")
end)

T.test("a constant set needs a name, constants, and upper-case names", function()
	T.eq(pcall(Constants.New, nil, { A = 1 }), false, "no name")
	T.eq(pcall(Constants.New, "x", {}), false, "no constants")
	T.eq(pcall(Constants.New, "x", { gap = 1 }), false, "a lower-case name")
	T.eq(pcall(Constants.New, "x", { [1] = 1 }), false, "a number for a name")
end)

T.test("calling a constant set parses a name into its constant", function()
	local layout = Layout()
	T.eq(layout("TILE"), 112, "a name it has")
	T.eq(layout("MARGIN"), nil, "nil for one it lacks, unrefused")
	T.eq(tostring(layout), "inventory layout", "its name")
	T.eq(getmetatable(layout).__len(layout), 4, "__len counts the constants")
end)

T.finish()
