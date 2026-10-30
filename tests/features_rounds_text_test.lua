-- features.rounds.text: the win panel's wording (CTFWinPanel::FireGameEvent) and the
-- lookup of TF2 localization tokens in tf_english.txt (UTF-16LE).
local T = dofile("tests/harness.lua")
local R = gameplay.rounds
local Text = T.require("features.rounds.text")

local W = R.WINREASON
local Teams = gameplay.teams
local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE

local function Panel(winner, reason, fullRound, remaining)
	return Text.WinPanel({
		winner = winner,
		reason = reason,
		fullRound = fullRound,
		remaining = remaining,
	})
end

T.test("a full round win says the team wins", function()
	local p = Panel(BLU, W.ALL_POINTS_CAPTURED, true, 0)
	T.eq(p.title, "BLU TEAM WINS!")
	T.eq(p.reason, "BLU captured all control points")
	T.eq(p.details, nil)
end)

-- Winreason_FlagCaptureLimit(_One), for the capture limit and for the most
-- captures at the time limit.
T.test("a CTF win says how many times the team captured the intelligence", function()
	local function Ctf(reason, captures)
		return Text.WinPanel({ winner = BLU, reason = reason, fullRound = true, remaining = 0, captures = captures }).reason
	end
	T.eq(Ctf(W.FLAG_CAPTURE_LIMIT, 3), "BLU captured the enemy intelligence 3 times", "the capture limit")
	T.eq(Ctf(W.MOST_CAPTURES, 1), "BLU captured the enemy intelligence 1 time", "the most, one")
end)

T.test("a round won at a round limit says which", function()
	T.eq(Panel(RED, W.FRAGLIMIT, true, 0).reason, "RED reached the frag limit")
	T.eq(Panel(BLU, W.CASHLIMIT, true, 0).reason, "BLU reached the cash limit")
end)

T.test("a mini-round win seizes the area and counts what is left", function()
	local p = Panel(BLU, W.ALL_POINTS_CAPTURED, false, 2)
	T.eq(p.title, "BLU TEAM SEIZES AREA")
	T.eq(p.details, "2 more areas to win")
	p = Panel(BLU, W.ALL_POINTS_CAPTURED, false, 1)
	T.eq(p.details, "1 more area to win")
end)

T.test("defending a mini-round until time runs out defends", function()
	local p = Panel(RED, W.DEFEND_UNTIL_TIME_LIMIT, false, 1)
	T.eq(p.title, "RED TEAM DEFENDS!")
	T.eq(p.reason, "RED successfully defended until time ran out")
end)

T.test("a stalemate has everyone lose", function()
	local p = Panel(NOBODY, W.STALEMATE, true, 0)
	T.eq(p.title, "STALEMATE")
	T.eq(p.reason, "You're all losers")
end)

T.test("sudden death wins by killing everyone", function()
	local p = Panel(RED, W.OPPONENTS_DEAD, true, 0)
	T.eq(p.reason, "RED killed all opponents during sudden death")
end)

T.test("sudden death explains why it started", function()
	local p = Text.StalematePanel(R.STALEMATE.TIMER)
	T.eq(p.title, "SUDDEN DEATH!")
	T.eq(p.reason, "You've run out of time. Watch your back and finish 'em off. No more spawning.")
	T.eq(Text.StalematePanel(R.STALEMATE.SERVER_TIMELIMIT).reason, "Map time limit reached. No more spawning, so make this count.")
	T.eq(Text.StalematePanel(R.STALEMATE.MATCH_TIED).reason, "The match is tied. No more spawning: the next team to win takes the match.")
	T.eq(Text.StalematePanel(R.STALEMATE.ADMIN).reason, "The Administrator has called sudden death. No more spawning.")
	T.eq(Text.StalematePanel(R.STALEMATE.LIMIT_TIED).reason, "Both teams reached the limit together. No more spawning, the last team standing wins.")
	T.eq(Text.StalematePanel(R.STALEMATE.BOTH_DEAD).reason, "Both teams fell at once. Again: no more spawning, the last team standing wins.")
end)

T.test("time added reads as the flash beside the timer shows it", function()
	T.eq(Text.TimeAdded(180), "+3:00", "three minutes")
	T.eq(Text.TimeAdded(45), "+0:45", "seconds")
	T.eq(Text.TimeAdded(-30), "-0:30", "taken away")
end)

-- The timer box: the gamemode's countdown to Gameplay mode, or the round's timer.
local NOW = 500
local NO_TRANSITION = 0
local ROUND_LEFT = 42

-- A round timer running in normal time, overridden by fields.
local function Display(fields)
	local q = {
		now = NOW,
		transitionEnd = NO_TRANSITION,
		shown = true,
		halted = false,
		koth = false,
		preround = false,
		setup = false,
		overtime = false,
		gameOverEnd = 0,
		capUnlockEnd = 0,
		setupEnd = 0,
		matchEnd = 0,
		waitingHave = 0,
		waitingNeed = 0,
		kothUnlockEnd = 0,
		left = ROUND_LEFT,
	}
	for k, v in pairs(fields) do q[k] = v end
	return Text.TimerDisplay(q)
end

-- CTFHudTimeStatus: a map with no round timer (ctf_2fort) shows the map's
-- time left under mp_timelimit; with no time limit, nothing.
T.test("with no round timer the box shows the map's time left", function()
	local d = Display({ shown = false, matchEnd = NOW + 600 })
	T.eq(d.kind, Text.DISPLAY_MAP, "the map's clock")
	T.eq(d.left, 600, "its time left")
	T.eq(d.label, nil, "no label")
	T.eq(Display({ shown = false, matchEnd = 0 }), nil, "no time limit: nothing")
	T.eq(Display({ shown = true, matchEnd = NOW + 600 }).kind, Text.DISPLAY_ROUND, "a round timer first")
	T.eq(Display({ shown = false, matchEnd = NOW + 600, halted = true }), nil, "nothing while halted")
end)

T.test("mp_chattime's note names the next map", function()
	T.eq(Text.NextMapNote("pl_upward"), "Next map: pl_upward")
	-- tf_english.txt's #round_restart_in_sec(s) and #game_switch_in_sec(s),
	-- the singular for a second or less, as CheckRestartRound picks them
	T.eq(Text.RestartNote(R.RESTART_ROUND, 5), "The round will restart in 5 seconds")
	T.eq(Text.RestartNote(R.RESTART_ROUND, 1), "The round will restart in 1 second")
	T.eq(Text.RestartNote(R.RESTART_ROUND, 0), "The round will restart in 0 second")
	T.eq(Text.RestartNote(R.RESTART_SWITCH, 3), "Switching teams!\nThe game will restart in 3 seconds")
end)

T.test("sudden death's card says why, as its panel did", function()
	T.eq(Text.SuddenDeathNote(R.STALEMATE.ADMIN),
		"SUDDEN DEATH! The Administrator has called sudden death. No more spawning.")
end)

T.test("the match won, the timer counts down to the map change as GAME OVER", function()
	local d = Display({ gameOverEnd = NOW + 25, overtime = true })
	T.eq(d.kind, Text.DISPLAY_GAME_OVER, "the match's clock")
	T.eq(d.left, 25, "seconds until the next map")
	T.eq(d.label, "GAME OVER")
	T.eq(Display({ gameOverEnd = NOW + 25, shown = false, koth = true }).kind, Text.DISPLAY_GAME_OVER,
		"with no round timer, or on a koth map")
	T.eq(Display({ gameOverEnd = NOW }).kind, Text.DISPLAY_ROUND, "run out: the round's clock again")
end)

-- Before a game: Sandbox mode, the wait for players and the countdown to
-- Gameplay mode show on the pregame (tournament) panel in place of the top
-- timer and scores, never both.
local function Pregame(fields)
	local q = { now = NOW, transitionEnd = NO_TRANSITION, waitingNeed = 0, halted = false }
	for k, v in pairs(fields) do q[k] = v end
	return Text.Pregame(q)
end

T.test("the pregame is the wait, then the countdown, then Sandbox mode", function()
	T.eq(Pregame({ waitingNeed = 2, transitionEnd = NOW + 5, halted = true }), Text.PREGAME_WAITING, "the wait first")
	T.eq(Pregame({ transitionEnd = NOW + 5, halted = true }), Text.PREGAME_COUNTDOWN, "the countdown")
	T.eq(Pregame({ transitionEnd = NOW + 5 }), Text.PREGAME_COUNTDOWN, "the countdown past its pre-round")
	T.eq(Pregame({ halted = true }), Text.PREGAME_SANDBOX, "Sandbox mode")
	T.eq(Pregame({}), nil, "Gameplay mode: no pregame")
	T.eq(Pregame({ transitionEnd = NOW }), nil, "a countdown run out")
end)

T.test("the timer shows nothing while the pregame panel is up", function()
	T.eq(Display({ transitionEnd = NOW + 9, halted = true }), nil, "the countdown")
	T.eq(Display({ transitionEnd = NOW + 9, preround = true }), nil, "the countdown past its pre-round")
	T.eq(Display({ transitionEnd = NOW + 3, shown = false, koth = true }), nil, "on any map")
	T.eq(Display({ halted = true, waitingHave = 1, waitingNeed = 2 }), nil, "the wait")
end)

T.test("Sandbox mode outside a transition shows no timer", function()
	T.eq(Display({ halted = true }), nil, "no transition")
	T.eq(Display({
		transitionEnd = NOW,
		halted = true,
	}), nil, "a countdown that has run out while the rounds are still halted")
end)

T.test("once the countdown has run out the round's own timer takes over", function()
	local d = Display({
		transitionEnd = NOW - 1,
		preround = true,
	})
	T.eq(d.kind, Text.DISPLAY_ROUND, "the round's clock")
	T.eq(d.left, ROUND_LEFT, "its time")
	T.eq(d.label, Text.LABEL_PREROUND, "pre-round")
end)

T.test("the round's timer carries its phase's label", function()
	T.eq(Display({}).label, nil, "normal time")
	T.eq(Display({ setup = true }).label, Text.LABEL_SETUP, "setup")
	T.eq(Display({ overtime = true }).label, Text.LABEL_OVERTIME, "overtime")
	T.eq(Display({
		preround = true,
		setup = true,
	}).label, Text.LABEL_PREROUND, "pre-round before setup")
end)

-- tf_logic_koth locks the hill for unlock_point seconds at each round's
-- start: the timer box counts it down as SETUP, and the team clocks are
-- greyed, disabled, until the point unlocks.
T.test("on a koth map the hill's unlock counts down on the timer as SETUP", function()
	local d = Display({ koth = true, kothUnlockEnd = NOW + 25 })
	T.eq(d.kind, Text.DISPLAY_SETUP, "setup")
	T.eq(d.left, 25, "seconds to the unlock")
	T.eq(d.label, Text.LABEL_SETUP, "labelled")
	T.eq(Display({ koth = true, kothUnlockEnd = NOW - 1 }), nil, "unlocked: the team clocks")
	T.eq(Text.KothClocksLive({ now = NOW, kothUnlockEnd = NOW + 25 }), false, "the clocks greyed meanwhile")
	T.eq(Text.KothClocksLive({ now = NOW, kothUnlockEnd = NOW - 1 }), true, "then live")
end)

T.test("no round timer without a HUD timer or on a koth map", function()
	T.eq(Display({ shown = false }), nil, "no team_round_timer")
	T.eq(Display({ koth = true }), nil, "koth draws its own clocks")
end)

-- Arena: the point unlocks a while into the round (ws_arena_cap_enable_time);
-- until then the timer box counts down to it.
T.test("in arena the timer counts down to the point unlocking, labelled so", function()
	local display = Display({ capUnlockEnd = NOW + 16 })
	T.eq(display.kind, Text.DISPLAY_CAP_UNLOCK)
	T.eq(display.left, 16, "seconds to the unlock")
	T.eq(display.label, Text.LABEL_CAP_UNLOCK)
end)

T.test("the unlock countdown shows on an arena map with no round timer of its own", function()
	T.eq(Display({ capUnlockEnd = NOW + 16, shown = false }).kind, Text.DISPLAY_CAP_UNLOCK)
end)

T.test("once the point is unlocked the round's own timer is back, and nothing shows while gameplay is halted", function()
	T.eq(Display({ capUnlockEnd = NOW - 1 }).kind, Text.DISPLAY_ROUND, "unlocked")
	T.eq(Display({ capUnlockEnd = NOW + 16, halted = true }), nil, "halted")
end)

-- Arena's setup (mp_arena_preround_time) has no team_round_timer: the timer
-- box counts it down as SETUP, then the point's unlock.
T.test("an arena's setup counts down on the timer as SETUP, before the unlock countdown", function()
	local display = Display({ setupEnd = NOW + 9, capUnlockEnd = NOW + 40, shown = false })
	T.eq(display.kind, Text.DISPLAY_SETUP)
	T.eq(display.left, 9, "seconds of setup left")
	T.eq(display.label, Text.LABEL_SETUP, "SETUP, as a setup timer's")
	T.eq(Display({ setupEnd = NOW - 1, capUnlockEnd = NOW + 40 }).kind, Text.DISPLAY_CAP_UNLOCK, "then the unlock")
	T.eq(Display({ setupEnd = NOW + 9, halted = true }), nil, "nothing while halted")
end)

T.test("the game-mode countdown and game over still come before the unlock countdown", function()
	T.eq(Display({ capUnlockEnd = NOW + 16, transitionEnd = NOW + 5 }), nil, "the countdown's panel")
	T.eq(Display({ capUnlockEnd = NOW + 16, gameOverEnd = NOW + 5 }).kind, Text.DISPLAY_GAME_OVER)
end)

T.test("a deathmatch says the match is tied and how many frags win it", function()
	T.eq(Text.DeathmatchNote(30), "DEATHMATCH! The match is tied: the first team to 30 frags wins it.")
end)

T.test("the top scores and koth's team clocks give way to the win panel", function()
	local State = T.require("games.gameplay.rounds.state")
	T.eq(Text.ShowsTeamBar(State.RND_RUNNING), true, "while the round runs")
	T.eq(Text.ShowsTeamBar(State.STALEMATE), true, "in sudden death")
	T.eq(Text.ShowsTeamBar(State.TEAM_WIN), false, "under a round's win panel")
	T.eq(Text.ShowsTeamBar(State.GAME_OVER), false, "under the match's")
end)

T.finish()
