-- foundation.kill_feed: GMod's death notices name an NPC "#<class>" with
-- team -1 (an NPC's colour); the AI war's soldiers are shown in their
-- team's colour.
local T = dofile("tests/harness.lua")
local Feed = T.require("foundation.kill_feed")
local RED, BLUE = 2, 3

T.test("a soldier's notice takes its side's team", function()
	T.eq(Feed.Team("#wetsand_drg_rebel", -1), BLUE)
	T.eq(Feed.Team("#wetsand_drg_vortigaunt", -1), BLUE)
	T.eq(Feed.Team("#wetsand_drg_combine", -1), RED)
end)

T.test("players and other NPCs keep the team the notice has", function()
	T.eq(Feed.Team("Some Player", RED), RED, "a player")
	T.eq(Feed.Team("#npc_zombie", -1), -1, "another NPC")
end)

T.test("every soldier class has a team, so each gets a name", function()
	local n = 0
	for class, team in pairs(Feed.SOLDIERS) do
		n = n + 1
		T.eq(team == RED or team == BLUE, true, class)
	end
	T.eq(n, 3)
end)

T.finish()
