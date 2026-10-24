-- features.aiwar.kill_feed: GMod's death notices name an NPC "#<class>" with
-- team -1 (an NPC's colour); the AI war's soldiers are shown in their
-- team's colour.
local T = dofile("tests/harness.lua")
local Feed = T.require("features.aiwar.kill_feed")
local AiWar = T.require("features.aiwar.model")
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

-- CTFHudDeathNotice: an assisted suicide (a death to the world credited to
-- the enemy who hurt the victim) reads "finished off", with TF2's skull,
-- since TF2 has no icon for the world.
T.test("a death credited to its killer is finished off, under the skull", function()
	local credited = Feed.Credited(Feed.FINISHED_OFF)
	T.eq(credited.info, "finished off", "TF2's words")
	T.eq(credited.icon, "skull_tf", "the skull")
end)

T.test("a notice without the flag is no credited death, whatever else it carries", function()
	T.eq(Feed.Credited(0), nil, "none")
	T.eq(Feed.Credited(1 + 2), nil, "GMod's friendly flags")
	T.eq(Feed.Credited(Feed.FINISHED_OFF + 2) ~= nil, true, "with another flag")
end)

T.test("the flag is one GMod's notices leave free, within their byte", function()
	T.eq(Feed.FINISHED_OFF < 256, true, "a byte")
	for _, gmod in ipairs({ 1, 2, 4, 8 }) do -- DEATH_NOTICE_FRIENDLY_*, and the HEADSHOT and PENETRATION it reserves
		T.eq(Feed.FINISHED_OFF ~= gmod, true, "not " .. gmod)
	end
end)

-- A victim thrown and slammed dead into a surface (ws/sv_hits.lua's
-- strike) shows the impact's own icon, not its thrower's weapon.
T.test("a death by impact shows the impact's icon", function()
	T.eq(Feed.Icon(Feed.SLAMMED), Feed.IMPACT_ICON, "slammed")
	T.eq(Feed.IMPACT_ICON, "ws_impact", "Sandcastle's own, on its sheet")
	T.eq(Feed.Icon(Feed.SLAMMED + 2), Feed.IMPACT_ICON, "with another flag")
	T.eq(Feed.Icon(0), nil, "any other death: by what struck")
	T.eq(Feed.Icon(Feed.FINISHED_OFF), nil, "a credited death has its own")
end)

T.test("the impact's flag is another GMod leaves free, apart from finished off's", function()
	T.eq(Feed.SLAMMED < 256, true, "a byte")
	for _, taken in ipairs({ 1, 2, 4, 8, Feed.FINISHED_OFF }) do
		T.eq(Feed.SLAMMED ~= taken, true, "not " .. taken)
	end
end)

-- CTFHudDeathNotice: an assisted kill names "killer + assister".
T.test("an assister joins the killer's side of the row, in their own team", function()
	local row = { killer = "Scout", killerTeam = RED, victim = "Heavy", victimTeam = BLUE, mine = false }
	Feed.WithAssister(row, "Medic", RED, nil)
	T.eq(row.assister, "Medic", "named")
	T.eq(row.assisterTeam, RED, "coloured")
	T.eq(row.mine, false, "not mine")
end)

T.test("a kill I assisted is mine too", function()
	local row = { killer = "Scout", killerTeam = RED, victim = "Heavy", victimTeam = BLUE, mine = false }
	Feed.WithAssister(row, "Medic", RED, "Medic")
	T.eq(row.mine, true, "mine")
end)

T.finish()
