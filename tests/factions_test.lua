-- foundation.factions: the DrGBase factions of TF2's two teams, "Team RED"
-- and "Team BLU": which a team's members join, and which they leave.
local T = dofile("tests/harness.lua")
local Factions = T.require("foundation.factions")
local Teams = T.require("games.gameplay.teams")

T.test("each playing team has a faction of its own, named as the team", function()
	T.eq(Factions.Of(Teams.RED), Factions.RED, "RED")
	T.eq(Factions.Of(Teams.BLUE), Factions.BLU, "BLU")
	T.eq(Factions.RED ~= Factions.BLU, true, "two factions")
	T.eq(Factions.LABEL[Factions.RED], "Team RED")
	T.eq(Factions.LABEL[Factions.BLU], "Team BLU")
end)

T.test("no other team has one", function()
	for _, team in ipairs({ Teams.UNASSIGNED, Teams.SPECTATOR, Teams.HALLOWEEN }) do
		T.eq(Factions.Of(team), nil, tostring(team))
	end
end)

T.test("DrGBase upper-cases faction names, so ours are upper case already", function()
	T.eq(Factions.RED, Factions.RED:upper())
	T.eq(Factions.BLU, Factions.BLU:upper())
end)

T.test("joining a team leaves the other team's faction and joins its own", function()
	local leave, join = Factions.Change(Teams.RED)
	T.eq(#leave, 1)
	T.eq(leave[1], Factions.BLU, "leaves BLU")
	T.eq(join, Factions.RED, "joins RED")
end)

T.test("leaving the playing teams leaves both factions and joins none", function()
	local leave, join = Factions.Change(Teams.SPECTATOR)
	T.eq(#leave, 2, "both")
	T.eq(join, nil)
end)

T.test("every playing team's faction, for relating to each", function()
	local all = Factions.ALL
	T.eq(#all, 2)
	T.eq(all[1].team, Teams.RED)
	T.eq(all[1].faction, Factions.RED)
	T.eq(all[2].team, Teams.BLUE)
	T.eq(all[2].faction, Factions.BLU)
end)

T.finish()
