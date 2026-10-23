-- games.gameplay.arrivals: the players expected from the previous map, and the
-- file that carries them across the map change.
local T = dofile("tests/harness.lua")
local Arrivals = gameplay.arrivals

local NOW = 1000000
local ALICE, BOB, CAROL = "76561197960265729", "76561197960265730", "76561197960265731"

T.test("the tuning is defined", function()
	T.defined(Arrivals.MAX_AGE, "MAX_AGE")
end)

T.test("players written at a map's end are read back on the next", function()
	local ids = Arrivals.Read(Arrivals.Write({ ALICE, BOB }, NOW), NOW + 1)
	T.eq(table.concat(ids, " "), ALICE .. " " .. BOB, "read back")
end)

T.test("a file older than MAX_AGE expects nobody: the server stopped between maps", function()
	local text = Arrivals.Write({ ALICE }, NOW)
	T.eq(#Arrivals.Read(text, NOW + Arrivals.MAX_AGE), 1, "fresh")
	T.eq(#Arrivals.Read(text, NOW + Arrivals.MAX_AGE + 1), 0, "stale")
end)

T.test("no file, or one not written here, expects nobody", function()
	T.eq(#Arrivals.Read("", NOW), 0, "none")
	T.eq(#Arrivals.Read("hello\n" .. ALICE, NOW), 0, "not ours")
end)

T.test("nobody expected: everyone has arrived", function()
	T.eq(Arrivals.New({}):Done(), true)
end)

T.test("done once every expected player has arrived or left", function()
	local arrivals = Arrivals.New({ ALICE, BOB, CAROL })
	arrivals:Arrived(ALICE)
	T.eq(arrivals:Done(), false, "two to come")
	arrivals:Left(BOB)
	T.eq(arrivals:Done(), false, "one to come")
	arrivals:Arrived(CAROL)
	T.eq(arrivals:Done(), true, "all in")
end)

T.test("a newcomer is not waited for, and arriving twice counts once", function()
	local arrivals = Arrivals.New({ ALICE, BOB })
	arrivals:Arrived("76561197960265799")
	arrivals:Arrived(ALICE)
	arrivals:Arrived(ALICE)
	T.eq(arrivals:Done(), false, "Bob still to come")
end)

T.finish()
