-- foundation.kill_feed: GMod's death notices name an NPC "#<class>" with
-- team -1 (an NPC's colour); the AI war's soldiers are shown in their
-- team's colour.
local T = dofile("tests/harness.lua")
local Feed = T.require("foundation.kill_feed")
local AiWar = T.require("foundation.aiwar")
local RED, BLUE = 2, 3

T.test("a soldier's notice takes the team its faction fights for: its home without a war", function()
	T.eq(Feed.Team("#ws_drg_rebel", -1), RED)
	T.eq(Feed.Team("#ws_drg_vortigaunt", -1), RED)
	T.eq(Feed.Team("#ws_drg_combine", -1), BLUE)
	T.eq(Feed.Team("ws_drg_rebel", -1), RED, "the class as GMod's feed passes it, without the #")
end)

T.test("once the sides trade, a soldier's notice follows its faction", function()
	local sides = AiWar.Sides(RED) -- the Combine on RED
	T.eq(Feed.Team("#ws_drg_combine", -1, sides), RED, "the Combine")
	T.eq(Feed.Team("#ws_drg_vortigaunt", -1, sides), BLUE, "the Resistance")
	T.eq(Feed.Team("Some Player", BLUE, sides), BLUE, "a player keeps the notice's")
end)

T.test("players and other NPCs keep the team the notice has", function()
	T.eq(Feed.Team("Some Player", RED), RED, "a player")
	T.eq(Feed.Team("#npc_zombie", -1), -1, "another NPC")
end)

-- GMod's feed gives no attacker name for a death nobody caused (a fall, a
-- suicide): it keeps the team it has.
T.test("a notice without a name keeps its team", function()
	T.eq(Feed.Team(nil, -1), -1)
	T.eq(Feed.Team(nil, RED), RED)
end)

-- A kill the player took part in is marked as theirs. A client still
-- loading has no player yet (me nil), and no kill is theirs: not even a
-- death with no killer, whose attacker is nil too.
T.test("a kill is mine when I am its killer or its victim", function()
	T.eq(Feed.Mine("Alice", "Alice", "Bob"), true, "my kill")
	T.eq(Feed.Mine("Bob", "Alice", "Bob"), true, "my death")
	T.eq(Feed.Mine("Carol", "Alice", "Bob"), false, "theirs")
end)

T.test("before my player exists no kill is mine", function()
	T.eq(Feed.Mine(nil, "Alice", "Bob"), false, "a kill")
	T.eq(Feed.Mine(nil, nil, "Bob"), false, "a death with no killer")
end)

-- TF2's capture and defense rows (CTFHudDeathNotice): who did it in their
-- team's colour, the team's capture or defend icon, the word, the point.
T.test("a capture names its cappers, joined, with the team's capture icon", function()
	local row = Feed.Objective(Feed.CAPTURED, RED, { "Alice", "Combine Soldier" }, "RED", "the Granary", "Carol")
	T.eq(row.killer, "Alice, Combine Soldier", "the cappers")
	T.eq(row.killerTeam, RED, "in their team's colour")
	T.eq(row.icon, "redcapture", "RED's capture icon")
	T.eq(row.info, "captured", "the word")
	T.eq(row.victim, "the Granary", "the point")
	T.eq(row.mine, false, "not mine")
end)

T.test("a defense names its defender, with the team's defend icon", function()
	local row = Feed.Objective(Feed.DEFENDED, BLUE, { "Bob" }, "BLU", "the Granary", "Bob")
	T.eq(row.killer, "Bob", "the defender")
	T.eq(row.icon, "bluedefend", "BLU's defend icon")
	T.eq(row.info, "defended", "the word")
	T.eq(row.mine, true, "mine: I defended it")
end)

T.test("a capture no one is named for is the team's; before my player exists it is not mine", function()
	local row = Feed.Objective(Feed.CAPTURED, BLUE, {}, "BLU", "the Granary", nil)
	T.eq(row.killer, "BLU", "the team's name")
	T.eq(row.mine, false, "not mine")
	T.eq(Feed.Objective(Feed.CAPTURED, RED, { "Alice" }, "RED", "A", "Alice").mine, true, "I capped it")
end)

T.test("every soldier class has a faction, so each gets a name", function()
	local n = 0
	for class, faction in pairs(Feed.SOLDIERS) do
		n = n + 1
		T.eq(AiWar.FACTIONS[faction] ~= nil, true, class)
	end
	T.eq(n, 3)
end)

T.finish()
