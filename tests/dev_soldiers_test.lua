-- sandcastle_dev_soldiers: which live bot player stands in for each bot soldier a scenario saved, so a
-- scenario saved in one session loads in another, whose bots were given other names.
local T = dofile ("tests/harness.lua")
local Soldiers = T.require ("sandcastle_dev_soldiers")

local function Names (chosen, count)
	local names = {}
	for i = 1, count do names [i] = chosen [i] and chosen [i].name or "-" end
	return table.concat (names, " ")
end

T.test ("a saved bot is the live bot of its name", function ()
	local saved = { { name = "Sans", team = 2 }, { name = "Kris", team = 3 } }
	local bots = { { name = "Kris", team = 3 }, { name = "Sans", team = 2 } }
	T.eq (Names (Soldiers.Pair (saved, bots), 2), "Sans Kris", "each by its name")
end)

T.test ("a saved bot no live bot is named for takes a free one of its team, in the order given", function ()
	local saved = { { name = "Sans", team = 2 }, { name = "Kris", team = 3 }, { name = "Toriel", team = 2 } }
	local bots = { { name = "Engie", team = 3 }, { name = "Toriel", team = 2 }, { name = "Pearl", team = 2 } }
	T.eq (Names (Soldiers.Pair (saved, bots), 3), "Pearl Engie Toriel", "names first, then the team's free bots")
end)

T.test ("a live bot stands in for one saved bot at most, and a team short of bots leaves the rest unpaired", function ()
	local saved = { { name = "A", team = 2 }, { name = "B", team = 2 }, { name = "C", team = 3 } }
	local bots = { { name = "X", team = 2 }, { name = "Y", team = 2 } }
	T.eq (Names (Soldiers.Pair (saved, bots), 3), "X Y -", "no bot of its team left for C")
	local named = { { name = "X", team = 2 }, { name = "A", team = 2 } }
	T.eq (Names (Soldiers.Pair (named, { { name = "X", team = 2 } }), 2), "X -", "the named one is not taken twice")
end)

T.test ("a bot of the right name on the other team is not that soldier", function ()
	local saved = { { name = "Sans", team = 2 } }
	local bots = { { name = "Sans", team = 3 }, { name = "Kris", team = 2 } }
	T.eq (Names (Soldiers.Pair (saved, bots), 1), "Kris", "its team decides, not its name alone")
end)

T.finish ()
