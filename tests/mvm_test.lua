-- The MvM mode (features.mvm.model): tf_logic_mann_vs_machine makes the
-- game Mann vs. Machine over every other game type its maps carry (their
-- bombs are item_teamflags, mvm_mannhattan's gates control points). BLU
-- carries its own bomb, a delivery scores nothing (the map's relays end the
-- round), and owning every gate wins nothing.
local T = dofile("tests/harness.lua")
local Mvm = T.require("features.mvm.model")
local Flag = T.require("features.flag.model")
local Teams = T.require("foundation.teams")

T.test("MvM outranks the game types its maps also carry", function()
	T.eq(Mvm.Mode.NAME, "mvm", "named")
	for _, path in ipairs({ "foundation.rounds.control_points", "foundation.rounds.payload", "features.koth.model" }) do
		T.eq(Mvm.Mode.PRIORITY > T.require(path).Mode.PRIORITY, true, "over " .. path)
	end
	T.eq(Mvm.Mode.PRIORITY > Flag.Mode.PRIORITY, true, "over CTF")
end)

T.test("the bomb is BLU's to carry, and a delivery scores no capture", function()
	T.eq(Mvm.Mode.FLAG_OWNERS_CARRY, true, "owners carry")
	T.eq(Mvm.Mode.FLAG_CAPS_SCORE, false, "no tally")
	T.eq(Mvm.Mode.OBJECTIVE, true, "no round limits")
end)

T.test("capturing every gate wins nothing: the map decides", function()
	T.eq(Mvm.Mode:MayWinByPoints(Teams.BLUE, { timerMayExpire = true }), false, "BLU owning every gate")
end)

T.finish()
