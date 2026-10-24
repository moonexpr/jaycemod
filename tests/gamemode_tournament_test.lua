-- features.gamemode.tournament: TF2's tournament panel (CHudTournament,
-- hudtournament.res as cooler-hud v2.6 lays it out) over Sandcastle's own
-- ready-up, Sandbox mode, the wait for players and the countdown to
-- Gameplay mode: the state in the gamemode's own words, each team's name
-- and players, TF2's win conditions from the match's limits, and how to
-- begin a game for a player who may.
local T = dofile("tests/harness.lua")
local Tournament = T.require("features.gamemode.tournament")
local Teams = gameplay.teams
local Text = T.require("features.rounds.text")

local RED, BLUE = Teams.RED, Teams.BLUE
local NOW = 100

local function Q(over)
	local q = {
		now = NOW,
		transitionEnd = 0,
		waitingHave = 0,
		waitingNeed = 0,
		halted = true,
		winPanel = false,
		players = { [RED] = 2, [BLUE] = 1 },
		names = { [RED] = "RED", [BLUE] = "BLU" },
		limits = { timelimit = 0, winlimit = 0, maxrounds = 0 },
		mayBegin = false,
		humans = { [RED] = 2, [BLUE] = 1 },
		teamReady = { [RED] = false, [BLUE] = false },
		localTeam = BLUE,
		readyKey = "F4",
		teamKey = "F2",
	}
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

T.test("Gameplay mode shows no panel", function()
	T.eq(Tournament.Panel(Q({ halted = false })), nil, "the rounds run")
end)

T.test("Sandbox mode says so", function()
	T.eq(Tournament.Panel(Q()).state, "Sandbox mode", "state")
end)

T.test("a game waiting for players counts them, in the round timer's words", function()
	local panel = Tournament.Panel(Q({ waitingHave = 1, waitingNeed = 2 }))
	T.eq(panel.state, Text.LABEL_WAITING .. " (1/2)", "have of need")
end)

T.test("the countdown to Gameplay mode gives the whole seconds left", function()
	T.eq(Tournament.Panel(Q({ transitionEnd = NOW + 9.2 })).state, "Gameplay mode begins in 10 seconds", "rounded up")
	T.eq(Tournament.Panel(Q({ transitionEnd = NOW + 0.5 })).state, "Gameplay mode begins in 1 second", "one")
end)

T.test("the countdown shows on after its first pre-round lets the rounds run", function()
	T.eq(Tournament.Panel(Q({ halted = false, transitionEnd = NOW + 3 })).state, "Gameplay mode begins in 3 seconds", "not halted")
end)

T.test("a countdown that has ended is no countdown", function()
	T.eq(Tournament.Panel(Q({ halted = false, transitionEnd = NOW })), nil, "Gameplay mode")
	T.eq(Tournament.Panel(Q({ transitionEnd = NOW - 1 })).state, "Sandbox mode", "a stale end in Sandbox mode")
end)

T.test("a win panel hides it", function()
	T.eq(Tournament.Panel(Q({ winPanel = true })), nil, "Sandbox mode")
	T.eq(Tournament.Panel(Q({ winPanel = true, transitionEnd = NOW + 5 })), nil, "counting down")
end)

T.test("each team's strip names it and counts its players", function()
	local panel = Tournament.Panel(Q())
	T.eq(panel.teams[BLUE].name, "BLU", "BLU's name")
	T.eq(panel.teams[RED].name, "RED", "RED's name")
	T.eq(panel.teams[RED].state, "2 players", "RED's players")
	T.eq(panel.teams[BLUE].state, "1 player", "one")
	T.eq(Tournament.Panel(Q({ players = { [RED] = 0, [BLUE] = 0 } })).teams[RED].state, "0 players", "none")
end)

T.test("the win conditions are the match's limits, in TF2's words", function()
	local function Conditions(limits) return Tournament.Panel(Q({ limits = limits })).conditions end
	T.eq(Conditions({ timelimit = 0, winlimit = 0, maxrounds = 0 }), "Win Conditions: None", "none")
	T.eq(Conditions({ timelimit = 30, winlimit = 0, maxrounds = 0 }), "Win Conditions: 30 minutes", "the time limit")
	T.eq(Conditions({ timelimit = 1, winlimit = 1, maxrounds = 1 }), "Win Conditions: 1 minute, 1 win, 1 round", "ones")
	T.eq(Conditions({ timelimit = 30, winlimit = 3, maxrounds = 5 }), "Win Conditions: 30 minutes, 3 wins, 5 rounds", "all")
	T.eq(Conditions({ timelimit = 0, winlimit = 3, maxrounds = 5 }), "Win Conditions: 3 wins, 5 rounds", "no time limit")
end)

T.test("a player who may begin a game is told how in Sandbox mode, not once a game is asked for", function()
	T.eq(Tournament.Panel(Q({ mayBegin = true })).instructions, Tournament.BEGIN_INSTRUCTIONS, "Sandbox mode")
	T.eq(Tournament.Panel(Q()).instructions, nil, "a player who may not")
	T.eq(Tournament.Panel(Q({ mayBegin = true, waitingHave = 1, waitingNeed = 2 })).instructions, "F4 = Toggle Team Ready",
		"waiting: the ready key instead")
	T.eq(Tournament.Panel(Q({ mayBegin = true, transitionEnd = NOW + 5 })).instructions, nil, "counting down")
end)

-- The ready-up (features.gamemode.ready): while the game waits, each team
-- with players says whether it is ready, in TF2's words, and the line
-- under the panel names the key that toggles it.
T.test("while the game waits, a team with players says whether it is ready", function()
	local panel = Tournament.Panel(Q({ waitingHave = 1, waitingNeed = 6, teamReady = { [RED] = false, [BLUE] = true } }))
	T.eq(panel.teams[BLUE].state, "Ready", "BLU ready")
	T.eq(panel.teams[RED].state, "Not Ready", "RED not")
	local empty = Tournament.Panel(Q({ waitingHave = 1, waitingNeed = 6, humans = { [RED] = 0, [BLUE] = 1 },
		players = { [RED] = 0, [BLUE] = 1 } }))
	T.eq(empty.teams[RED].state, "0 players", "a team nobody plays on has nothing to ready")
	T.eq(Tournament.Panel(Q()).teams[BLUE].state, "1 player", "Sandbox mode: the count")
end)

T.test("while the game waits, the line under the panel names the ready key, or how to pick a team", function()
	local function Instructions(over)
		over.waitingHave, over.waitingNeed = 1, 6
		return Tournament.Panel(Q(over)).instructions
	end
	T.eq(Instructions({}), "F4 = Toggle Team Ready", "on a team")
	T.eq(Instructions({ readyKey = false }), "Toggle Team Ready: bind a key to player_ready_toggle", "no key bound")
	T.eq(Instructions({ localTeam = Teams.UNASSIGNED }), "F2 = Pick a Team", "on no team")
	T.eq(Instructions({ localTeam = Teams.UNASSIGNED, teamKey = false }), "Pick a Team: bind a key to changeteam", "no team key")
end)

T.test("in Sandbox mode a player on no team is told how to pick one", function()
	T.eq(Tournament.Panel(Q({ localTeam = Teams.UNASSIGNED })).instructions, "F2 = Pick a Team", "on no team")
	T.eq(Tournament.Panel(Q({ localTeam = Teams.UNASSIGNED, mayBegin = true })).instructions,
		Tournament.BEGIN_INSTRUCTIONS, "how to begin a game first")
end)

T.test("the line sits on TF2's help strip under the panel, inside its width", function()
	local layout = Tournament.Layout(500, 40, 2)
	T.eq(layout.help.y > layout.bg.y and layout.help.y < layout.bg.y + layout.bg.h, true, "overlapping the panel's foot")
	T.eq(layout.help.x, layout.bg.x, "as wide as the panel")
	T.eq(layout.help.w, layout.bg.w, "as wide as the panel")
	T.eq(layout.instructions.y > layout.help.y and layout.instructions.y < layout.help.y + layout.help.h, true, "in it")
	T.eq(layout.instructions.x, 500, "centred")
end)

T.test("the panel is centred, BLU's strip left of RED's and meeting it", function()
	local layout = Tournament.Layout(500, 40, 2)
	T.eq(layout.bg.x + layout.bg.w / 2, 500, "centred")
	T.eq(layout.bg.y, 40, "from the top given")
	local blue, red = layout.strips[BLUE], layout.strips[RED]
	T.eq(blue.x + blue.w, red.x, "BLU's strip ends where RED's begins")
	T.eq(blue.x + blue.w, 500, "at the middle")
end)

-- MvM's ready-up (hudtournament.res's if_mvm): a panel per defender, black
-- or green as they are ready, and under them TF2's instructions line,
-- "Waiting For Players" until there are enough, then the ready key,
-- pulsing while the player is not ready (HudReadyPulse).
local function M(over)
	local q = {
		now = NOW,
		transitionEnd = 0,
		waitingHave = 6,
		waitingNeed = 6,
		halted = true,
		winPanel = false,
		mayBegin = false,
		defenders = { { name = "Ann", ready = true }, { name = "Bo", ready = false } },
		localDefender = true,
		localReady = false,
		readyKey = "F4",
		teamKey = "F2",
	}
	for k, v in pairs(over or {}) do q[k] = v end
	return Tournament.MvMPanel(q)
end

T.test("MvM: each defender's panel says whether they are ready", function()
	local panel = M()
	T.eq(#panel.players, 2, "two defenders")
	T.eq(panel.players[1].name, "Ann", "named")
	T.eq(panel.players[1].ready, true, "ready")
	T.eq(panel.players[2].ready, false, "not ready")
end)

T.test("MvM: Waiting For Players, pulsing, until there are enough", function()
	local panel = M({ waitingHave = 3 })
	T.eq(panel.instructions, "Waiting For Players", "TF2's words")
	T.eq(panel.pulse, true, "pulsing")
end)

T.test("MvM: then the ready key, pulsing until the player readies", function()
	T.eq(M().instructions, "F4 = Toggle Ready", "TF2's words")
	T.eq(M().pulse, true, "not ready")
	T.eq(M({ localReady = true }).pulse, false, "ready")
	T.eq(M({ readyKey = false }).instructions, "Toggle Ready: bind a key to player_ready_toggle", "no key bound")
	T.eq(M({ localDefender = false }).instructions, "F2 = Pick a Team", "not a defender")
	T.eq(M({ localDefender = false }).pulse, false, "not a defender")
end)

T.test("MvM: the countdown and Sandbox mode, in TF2's and the gamemode's words", function()
	T.eq(M({ waitingNeed = 0, transitionEnd = NOW + 4.5 }).instructions, "Starting in 5 seconds...", "counting")
	T.eq(M({ waitingNeed = 0, transitionEnd = NOW + 0.5 }).instructions, "Starting in 1 second...", "one")
	T.eq(M({ waitingNeed = 0 }).instructions, "Sandbox mode", "Sandbox mode")
	T.eq(M({ waitingNeed = 0, mayBegin = true }).instructions, Tournament.BEGIN_INSTRUCTIONS, "how to begin")
	T.eq(M({ waitingNeed = 0, halted = false }), nil, "Gameplay mode")
	T.eq(M({ winPanel = true }), nil, "a win panel")
end)

-- HudReadyPulse: TanLight over 0.1 s, toward RedSolid from 0.3 s over 0.4
-- s, and again every 0.5 s, each restart cutting the last short.
T.test("the pulse runs tan to half red and back every half second", function()
	T.near(Tournament.PulseRedness(0.2), 0, 1e-9, "tan")
	T.near(Tournament.PulseRedness(0.4), 0.25, 1e-9, "reddening")
	T.near(Tournament.PulseRedness(0.5), Tournament.PulseRedness(0), 1e-9, "a cycle")
	T.near(Tournament.PulseRedness(0.49999), 0.5, 1e-3, "half red as it restarts")
	T.near(Tournament.PulseRedness(0.05), 0.25, 1e-9, "back to tan")
end)

T.test("MvM's panels sit in a centred row, the instructions line under them", function()
	local layout = Tournament.MvMLayout(500, 40, 2, 3)
	T.eq(#layout.players, 3, "a panel each")
	local first, last = layout.players[1].bg, layout.players[3].bg
	-- UpdatePlayerPanels centres count deltas, not the panels' own width
	T.near((first.x + last.x + last.w) / 2, 500, (Tournament.MVM_PLAYER_W - Tournament.MVM_PLAYER_DELTA) / 2 * 2, "centred")
	T.eq(first.y, 40, "from the top given")
	T.eq(layout.players[2].bg.x - first.x, Tournament.MVM_PLAYER_DELTA * 2, "a delta apart")
	T.eq(layout.instructions.y > first.y + first.h, true, "under them")
	T.eq(layout.instructions.x, 500, "centred")
	local p = layout.players[1]
	T.eq(p.check.x > p.readyBg.x and p.check.x + p.check.w < p.readyBg.x + p.readyBg.w, true, "the check in its box")
end)

T.finish()
