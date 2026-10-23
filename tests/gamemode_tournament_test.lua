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

T.test("a player who may begin a game is told how, in Sandbox mode only", function()
	T.eq(Tournament.Panel(Q({ mayBegin = true })).instructions, Tournament.BEGIN_INSTRUCTIONS, "Sandbox mode")
	T.eq(Tournament.Panel(Q()).instructions, nil, "a player who may not")
	T.eq(Tournament.Panel(Q({ mayBegin = true, waitingHave = 1, waitingNeed = 2 })).instructions, nil, "waiting")
	T.eq(Tournament.Panel(Q({ mayBegin = true, transitionEnd = NOW + 5 })).instructions, nil, "counting down")
end)

T.test("the panel is centred, BLU's strip left of RED's and meeting it", function()
	local layout = Tournament.Layout(500, 40, 2)
	T.eq(layout.bg.x + layout.bg.w / 2, 500, "centred")
	T.eq(layout.bg.y, 40, "from the top given")
	local blue, red = layout.strips[BLUE], layout.strips[RED]
	T.eq(blue.x + blue.w, red.x, "BLU's strip ends where RED's begins")
	T.eq(blue.x + blue.w, 500, "at the middle")
end)

T.finish()
