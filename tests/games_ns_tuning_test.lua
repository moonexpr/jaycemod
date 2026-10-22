-- games.ns.tuning: changing NextSoldier's tactics constants while
-- they run (ns_tactics_tune), within bounds, and putting them back.
local T = dofile("tests/harness.lua")
local Tuning = T.require("games.ns.tuning")
local Tactics = T.require("games.ns.tactics")
local Lanes = T.require("games.ns.lanes")
local Orders = T.require("foundation.aiwar.orders")
local Squad = T.require("games.ns.squad")

local MODULES = {
	tactics = Tactics,
	lanes = Lanes,
	orders = Orders,
	squad = Squad,
}

local function Has(text, fragment)
	T.eq(text:find(fragment, 1, true) ~= nil, true, fragment .. " in: " .. text)
end

T.test("every tunable is a number its module has, within the range it may take", function()
	T.eq(#Tuning.TUNABLES >= 20, true, "the tactics' constants are listed")
	for _, tunable in ipairs(Tuning.TUNABLES) do
		local value = MODULES[tunable.module][tunable.key]
		T.eq(type(value), "number", tunable.name)
		T.eq(value >= tunable.min and value <= tunable.max, true, tunable.name .. " in range")
		T.eq(tunable.name, tunable.module .. "." .. tunable.key, "named module.KEY")
	end
end)

T.test("a value set takes effect at the next call, and reset puts the default back", function()
	local tuner = Tuning.Tuner.New(MODULES)
	local default = Tactics.FLANK_OFFSET
	local ok = tuner:Set("tactics.FLANK_OFFSET", "100")
	T.eq(ok, true, "set")
	local flank = Tactics.FlankPoint({ x = 0, y = 0 }, { x = 1000, y = 0, z = 0 }, 1)
	T.eq(flank.y, 100, "the flank point is 100 beside the enemy now")
	T.eq(tuner:Reset("tactics.FLANK_OFFSET"), true, "reset")
	T.eq(Tactics.FLANK_OFFSET, default, "back to its default")
end)

T.test("names are found whatever their case", function()
	local tuner = Tuning.Tuner.New(MODULES)
	T.eq(tuner:Set("lanes.flank_radius", "250"), true, "lower case")
	T.eq(Lanes.FLANK_RADIUS, 250, "set")
	local left = Lanes.FixedFlanks({ x = 0, y = 0, z = 0 }, { x = 1000, y = 0, z = 0 })
	T.eq(left.y, 250, "a fixed flank stands 250 beside the objective now")
	tuner:ResetAll()
	T.eq(Lanes.FLANK_RADIUS ~= 250, true, "every one reset")
end)

T.test("a value is refused when the name is unknown, it is no number, out of range, or not whole where it must be", function()
	local tuner = Tuning.Tuner.New(MODULES)
	local before = Tactics.BOUND_DISTANCE
	local ok, why = tuner:Set("tactics.NOPE", "1")
	T.eq(ok, false, "unknown")
	Has(why, "no tunable")
	ok, why = tuner:Set("tactics.BOUND_DISTANCE", "far")
	T.eq(ok, false, "no number")
	Has(why, "not a number")
	ok, why = tuner:Set("tactics.BOUND_DISTANCE", "-5")
	T.eq(ok, false, "below its range")
	Has(why, "between")
	ok, why = tuner:Set("tactics.FALLBACK_STEPS", "2.5")
	T.eq(ok, false, "not whole")
	Has(why, "whole")
	T.eq(Tactics.BOUND_DISTANCE, before, "nothing changed")
	ok, why = tuner:Reset("tactics.NOPE")
	T.eq(ok, false, "no reset for an unknown name")
end)

T.test("the listing shows each value and its default, the changed ones first, and filters by name", function()
	local tuner = Tuning.Tuner.New(MODULES)
	tuner:Set("orders.SQUAD_SPACING", "128")
	local lines = tuner:Lines("")
	Has(lines[1], "orders.SQUAD_SPACING = 128 (default " .. tuner.defaults["orders.SQUAD_SPACING"] .. ")")
	local filtered = tuner:Lines("bound")
	for _, line in ipairs(filtered) do Has(line:lower(), "bound") end
	T.eq(#filtered >= 2, true, "BOUND_DISTANCE and BOUND_TIME at least")
	Has(tuner:Lines("tactics.CONTACT_MEMORY")[1], "(default)")
	T.eq(#tuner:Lines("zzz"), 0, "nothing matches")
	tuner:ResetAll()
end)

T.test("changing a lanes constant asks for new lanes; the others do not", function()
	T.eq(Tuning.Replans(Tuning.Find("lanes.LANE_PENALTY")), true, "lanes")
	T.eq(Tuning.Replans(Tuning.Find("tactics.BOUND_TIME")), false, "tactics")
end)

T.finish()
