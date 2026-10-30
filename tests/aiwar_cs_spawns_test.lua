-- features.aiwar.spawns on a CS:S map: RED, the terrorists, joins the fight at
-- info_player_terrorist and BLU, the counter-terrorists, at
-- info_player_counterterrorist, whichever faction fights for either.
local T = dofile("tests/harness.lua")
local Spawns = T.require("features.aiwar.spawns")
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE

local function Present(list)
	local set = {}
	for _, class in ipairs(list) do set[class] = true end
	return function(class) return set[class] == true end
end

T.test("each team has the spawn class of its CS:S side", function()
	local present = Present({ "info_player_terrorist", "info_player_counterterrorist" })
	T.eq(table.concat(Spawns.TeamClasses(RED, present), ","), "info_player_terrorist", "RED")
	T.eq(table.concat(Spawns.TeamClasses(BLUE, present), ","), "info_player_counterterrorist", "BLU")
end)

T.test("a map without them gives a team none, and an unassigned team none", function()
	T.eq(#Spawns.TeamClasses(RED, Present({ "info_player_counterterrorist" })), 0, "no terrorists' spawns")
	T.eq(#Spawns.TeamClasses(Teams.UNASSIGNED, Present({ "info_player_terrorist" })), 0, "no team")
end)

T.finish()
