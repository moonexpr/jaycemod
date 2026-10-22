local T = dofile("tests/harness.lua")
local L = T.require("games.gameplay.teams")

local STATE = T.require("games.gameplay.rounds.state")

local UNASSIGNED, SPEC, RED, BLU = L.UNASSIGNED, L.SPECTATOR, L.RED, L.BLUE

-- TF2's configuration: BLU left, RED right (Teammenu.res).
local function Teams(blu, red)
	return {
		{ index = BLU, name = "BLU", color = "blue", count = blu, command = "blue" },
		{ index = RED, name = "RED", color = "red", count = red, command = "red" },
	}
end

local EXTRAS = {
	auto = { name = "Auto-assign", command = "auto" },
	spectate = { index = SPEC, name = "Spectate", command = "spectate", count = 0 },
}

-- CTFTeamMenu: the teams, in the order given

T.test("team choices keep the given order, names, colours, commands and counts", function()
	local menu = L.TeamMenu(Teams(4, 5), UNASSIGNED, 1, EXTRAS)
	T.eq(#menu.teams, 2, "two teams")
	local blu, red = menu.teams[1], menu.teams[2]
	T.eq(blu.index, BLU, "left")
	T.eq(blu.label, "BLU", "label")
	T.eq(blu.color, "blue", "color")
	T.eq(blu.command, "blue", "command")
	T.eq(blu.count, 4, "count")
	T.eq(red.index, RED, "right")
	T.eq(red.count, 5, "red count")
end)

T.test("hotkeys follow Teammenu.res: auto 1, spectate 2, then the teams", function()
	local menu = L.TeamMenu(Teams(0, 0), UNASSIGNED, 1, EXTRAS)
	T.eq(menu.auto.hotkey, 1, "auto")
	T.eq(menu.spectate.hotkey, 2, "spectate")
	T.eq(menu.teams[1].hotkey, 3, "BLU")
	T.eq(menu.teams[2].hotkey, 4, "RED")
	T.eq(#menu.choices, 4, "every choice")
	for i, c in ipairs(menu.choices) do T.eq(c.hotkey, i, "choices in hotkey order") end
end)

T.test("without auto-assign or spectate the teams take the first hotkeys", function()
	local menu = L.TeamMenu(Teams(0, 0), UNASSIGNED, 1, {})
	T.eq(menu.auto, nil, "no auto")
	T.eq(menu.spectate, nil, "no spectate")
	T.eq(menu.teams[1].hotkey, 1, "first team")
	T.eq(#menu.choices, 2, "teams only")
end)

T.test("auto-assign and spectate are offered with their commands", function()
	local menu = L.TeamMenu(Teams(0, 0), UNASSIGNED, 1, EXTRAS)
	T.eq(menu.auto.command, "auto", "auto command")
	T.eq(menu.auto.label, "Auto-assign", "auto label")
	T.eq(menu.auto.enabled, true, "auto enabled")
	T.eq(menu.spectate.command, "spectate", "spectate command")
	T.eq(menu.spectate.index, SPEC, "spectate team")
	T.eq(menu.spectate.enabled, true, "spectate enabled")
end)

-- CTFTeamMenu::Update: Cancel only once the player has a team

T.test("an unassigned player cannot cancel", function()
	T.eq(L.TeamMenu(Teams(0, 0), UNASSIGNED, 1, EXTRAS).cancel, false)
end)

T.test("a player with a team, spectators included, can cancel", function()
	T.eq(L.TeamMenu(Teams(1, 0), BLU, 1, EXTRAS).cancel, true, "BLU")
	T.eq(L.TeamMenu(Teams(0, 0), SPEC, 1, EXTRAS).cancel, true, "spectator")
end)

T.test("the player's own team is marked", function()
	local menu = L.TeamMenu(Teams(1, 0), BLU, 1, EXTRAS)
	T.eq(menu.teams[1].current, true, "BLU")
	T.eq(menu.teams[2].current, false, "RED")
	T.eq(menu.spectate.current, false, "spectate")
	T.eq(L.TeamMenu(Teams(0, 0), SPEC, 1, EXTRAS).spectate.current, true, "spectator")
end)

-- CTFTeamMenu::OnTick: a team is disabled when it is the heavy team or joining it would unbalance

T.test("a team joining would unbalance is disabled with a reason", function()
	local menu = L.TeamMenu(Teams(0, 1), UNASSIGNED, 1, EXTRAS)
	local blu, red = menu.teams[1], menu.teams[2]
	T.eq(red.enabled, false, "RED 2 vs 0")
	T.eq(red.reason, "Team is full", "reason")
	T.eq(blu.enabled, true, "BLU 1 vs 1")
	T.eq(blu.reason, nil, "no reason")
end)

T.test("leaving your team counts against it", function()
	-- a BLU player: RED 2 vs BLU 1 is within limit 1
	local menu = L.TeamMenu(Teams(2, 1), BLU, 1, EXTRAS)
	T.eq(menu.teams[2].enabled, true)
end)

T.test("the heavy team is disabled even for its own players", function()
	local menu = L.TeamMenu(Teams(1, 3), RED, 1, EXTRAS)
	T.eq(menu.teams[2].enabled, false, "RED is heavy")
	T.eq(menu.teams[1].enabled, true, "BLU")
end)

T.test("limit 0 disables no team", function()
	local menu = L.TeamMenu(Teams(0, 9), UNASSIGNED, 0, EXTRAS)
	T.eq(menu.teams[2].enabled, true)
end)

T.test("any number of teams is laid out and checked", function()
	local A, B, C = 2, 3, 4 -- any game's team numbers
	local teams = {
		{ index = A, name = "A", color = "a", count = 2, command = "a" },
		{ index = B, name = "B", color = "b", count = 1, command = "b" },
		{ index = C, name = "C", color = "c", count = 0, command = "c" },
	}
	local menu = L.TeamMenu(teams, UNASSIGNED, 1, {})
	T.eq(#menu.teams, 3, "three teams")
	T.eq(menu.teams[1].enabled, false, "A: 3 vs 0")
	T.eq(menu.teams[2].enabled, false, "B: 2 vs 0")
	T.eq(menu.teams[3].enabled, true, "C: 1 vs 1")
end)

-- CTFTeamMenu::ShowPanel: when the menu may open

T.test("the menu opens during a round and for anyone before a team win", function()
	T.eq(L.TeamMenuAllowed(STATE.RND_RUNNING, RED, UNASSIGNED), true, "running")
	T.eq(L.TeamMenuAllowed(STATE.RND_RUNNING, UNASSIGNED, UNASSIGNED), true, "new player")
end)

T.test("during a team win only the winners, spectators and the unassigned may open it", function()
	T.eq(L.TeamMenuAllowed(STATE.TEAM_WIN, RED, BLU), false, "loser")
	T.eq(L.TeamMenuAllowed(STATE.TEAM_WIN, BLU, BLU), true, "winner")
	T.eq(L.TeamMenuAllowed(STATE.TEAM_WIN, SPEC, BLU), true, "spectator")
	T.eq(L.TeamMenuAllowed(STATE.TEAM_WIN, UNASSIGNED, BLU), true, "unassigned")
end)

T.test("nobody opens it once the game is over", function()
	T.eq(L.TeamMenuAllowed(STATE.GAME_OVER, UNASSIGNED, UNASSIGNED), false)
end)

-- The client's own reaction to its team (TeamMenuReaction): an unassigned
-- player in team play (L.TeamPlay) sees the menu, as a fresh join does.

-- A loaded client in team play, its menu closed, mid-round.
local function View(t)
	local view = {
		teamPlay = true,
		ready = true,
		team = UNASSIGNED,
		openedOn = nil,
		state = STATE.RND_RUNNING,
		winner = UNASSIGNED,
	}
	for k, v in pairs(t or {}) do view[k] = v end
	return view
end

T.test("a loaded, unassigned client in team play opens the menu", function()
	T.eq(L.TeamMenuReaction(View()), L.MENU_OPEN, "open")
end)

T.test("the menu waits for the client to load and for team play", function()
	T.eq(L.TeamMenuReaction(View({ ready = false })), L.MENU_STAY, "still loading")
	T.eq(L.TeamMenuReaction(View({ teamPlay = false })), L.MENU_STAY, "no team play: Sandbox mode, or no rounds")
end)

T.test("a player on a team or spectating is left alone", function()
	T.eq(L.TeamMenuReaction(View({ team = RED })), L.MENU_STAY, "on RED")
	T.eq(L.TeamMenuReaction(View({ team = SPEC })), L.MENU_STAY, "spectating")
end)

T.test("an unassigned player does not get the menu once the game is over", function()
	T.eq(L.TeamMenuReaction(View({ state = STATE.GAME_OVER })), L.MENU_STAY, "game over")
end)

T.test("the open menu closes when the player gets a team", function()
	T.eq(L.TeamMenuReaction(View({ openedOn = UNASSIGNED, team = BLU })), L.MENU_CLOSE, "joined BLU")
	T.eq(L.TeamMenuReaction(View({ openedOn = UNASSIGNED, team = SPEC })), L.MENU_CLOSE, "spectating")
	T.eq(L.TeamMenuReaction(View({ openedOn = UNASSIGNED })), L.MENU_STAY, "still choosing")
end)

T.test("a menu opened on a team (F2) closes when the team changes, and stays when it becomes unassigned", function()
	T.eq(L.TeamMenuReaction(View({ openedOn = RED, team = RED })), L.MENU_STAY, "same team")
	T.eq(L.TeamMenuReaction(View({ openedOn = RED, team = BLU })), L.MENU_CLOSE, "balanced to BLU")
	T.eq(L.TeamMenuReaction(View({ openedOn = RED, team = UNASSIGNED })), L.MENU_STAY, "a new game: now choosing")
end)

-- mp_forceautoteam and mp_allowspectators

T.test("mp_forceautoteam leaves only auto-assign (and spectating) in the menu", function()
	local extras = { auto = EXTRAS.auto, spectate = EXTRAS.spectate, forceAuto = true }
	local menu = L.TeamMenu(Teams(0, 0), UNASSIGNED, 1, extras)
	T.eq(menu.auto.enabled, true, "auto-assign")
	T.eq(menu.spectate.enabled, true, "spectate")
	for _, c in ipairs(menu.teams) do
		T.eq(c.enabled, false, c.label .. " disabled")
		T.eq(c.reason, "Teams are auto-assigned", c.label .. " says why")
	end
end)

T.test("mp_allowspectators 0 disables spectating in the menu", function()
	local extras = { auto = EXTRAS.auto, spectate = EXTRAS.spectate, noSpectators = true }
	local menu = L.TeamMenu(Teams(0, 0), UNASSIGNED, 1, extras)
	T.eq(menu.spectate.enabled, false, "spectate disabled")
	T.eq(menu.spectate.reason, "Spectating is off", "and says why")
	T.eq(menu.teams[1].enabled, true, "the teams stay open")
end)

T.finish()
