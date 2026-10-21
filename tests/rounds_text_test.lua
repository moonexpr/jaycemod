-- foundation.rounds.text: the win panel's wording (CTFWinPanel::FireGameEvent) and the
-- lookup of TF2 localization tokens in tf_english.txt (UTF-16LE).
local T = dofile("tests/harness.lua")
local R = T.require("foundation.rounds")
local Text = T.require("foundation.rounds.text")

local W = R.WINREASON
local Teams = T.require("foundation.teams")
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

T.test("the countdown to Gameplay mode shows on the timer as Prepare while the rounds are halted", function()
	local d = Display({
		transitionEnd = NOW + 9,
		halted = true,
	})
	T.eq(d.kind, Text.DISPLAY_TRANSITION, "the transition's clock")
	T.eq(d.left, 9, "seconds until Gameplay mode")
	T.eq(d.label, Text.LABEL_TRANSITION, "labelled")
	T.eq(Text.LABEL_TRANSITION, "Prepare", "the operator's word")
end)

T.test("the countdown shows even without a HUD timer or on a koth map", function()
	local plain = Display({
		transitionEnd = NOW + 3,
		halted = true,
		shown = false,
	})
	T.eq(plain.kind, Text.DISPLAY_TRANSITION, "no team_round_timer")
	local koth = Display({
		transitionEnd = NOW + 3,
		halted = true,
		koth = true,
	})
	T.eq(koth.kind, Text.DISPLAY_TRANSITION, "koth")
end)

T.test("a game waiting for players shows how many are here of how many it needs, in place of a clock", function()
	local d = Display({ halted = true, waitingHave = 1, waitingNeed = 2 })
	T.eq(d.kind, Text.DISPLAY_WAITING, "the wait")
	T.eq(d.text, "1/2", "here of needed")
	T.eq(d.label, Text.LABEL_WAITING, "labelled")
	T.eq(Display({ halted = true, waitingHave = 0, waitingNeed = 0 }), nil, "no wait")
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
	T.eq(Display({ capUnlockEnd = NOW + 16, transitionEnd = NOW + 5 }).kind, Text.DISPLAY_TRANSITION)
	T.eq(Display({ capUnlockEnd = NOW + 16, gameOverEnd = NOW + 5 }).kind, Text.DISPLAY_GAME_OVER)
end)

T.test("a deathmatch says the match is tied and how many frags win it", function()
	T.eq(Text.DeathmatchNote(30), "DEATHMATCH! The match is tied: the first team to 30 frags wins it.")
end)

T.test("the top scores and koth's team clocks give way to the win panel", function()
	local State = T.require("foundation.rounds.state")
	T.eq(Text.ShowsTeamBar(State.RND_RUNNING), true, "while the round runs")
	T.eq(Text.ShowsTeamBar(State.STALEMATE), true, "in sudden death")
	T.eq(Text.ShowsTeamBar(State.TEAM_WIN), false, "under a round's win panel")
	T.eq(Text.ShowsTeamBar(State.GAME_OVER), false, "under the match's")
end)

T.finish()
