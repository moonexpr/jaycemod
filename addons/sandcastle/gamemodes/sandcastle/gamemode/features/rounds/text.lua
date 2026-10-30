-- What the round HUD says: the win panel (CTFWinPanel::FireGameEvent), the
-- sudden death panel (CHudStalemate::SetupStalematePanel), the time-added
-- flash. TF2's "#Token" strings are worded by ws.localization.
local math, string, table = math, string, table
local Rounds = gameplay.rounds
local State = require("games.gameplay.rounds.state")
local Teams = gameplay.teams
module(...)

-- The states whose centre panel shows the teams' scores itself (the win
-- panel, the match's end), so the top scores and koth's team clocks go.
local WIN_PANELS = {
	[State.TEAM_WIN] = true,
	[State.GAME_OVER] = true,
}

-- Whether the bar at the top (the team scores, koth's team clocks) shows in
-- state.
function ShowsTeamBar(state)
	return not WIN_PANELS[state]
end

local RED, BLUE = Teams.RED, Teams.BLUE
local FIRST_GAME_TEAM = Teams.FIRST_GAME_TEAM
local WINREASON, STALEMATE = Rounds.WINREASON, Rounds.STALEMATE
local SECONDS_PER_MINUTE = 60

local TEAM_LABEL = {
	[RED] = "RED",
	[BLUE] = "BLU",
}
local REASON_TEXT = {
	[WINREASON.ALL_POINTS_CAPTURED] = "%s captured all control points",
	[WINREASON.OPPONENTS_DEAD] = "%s killed all opponents during sudden death",
	[WINREASON.DEFEND_UNTIL_TIME_LIMIT] = "%s successfully defended until time ran out",
	[WINREASON.STALEMATE] = "You're all losers",
	[WINREASON.TIMELIMIT] = "%s had more points when the time limit was reached",
	[WINREASON.WINLIMIT] = "%s had more points when the win limit was reached",
	[WINREASON.WINDIFFLIMIT] = "%s was ahead by the required difference to win",
	[WINREASON.FRAGLIMIT] = "%s reached the frag limit",
	[WINREASON.CASHLIMIT] = "%s reached the cash limit",
	[WINREASON.ENDED_EARLY] = "The match ended early",
}
-- Winreason_FlagCaptureLimit(_One): a CTF win, at the capture limit or by
-- the most captures at the time limit, counts them.
local CAPTURES_TEXT = "%s captured the enemy intelligence %d times"
local CAPTURE_TEXT = "%s captured the enemy intelligence %d time"
local BY_CAPTURES = {
	[WINREASON.FLAG_CAPTURE_LIMIT] = true,
	[WINREASON.MOST_CAPTURES] = true,
}
-- Winreason_Arena: an arena round's elimination is no sudden death.
local ARENA_ELIMINATION = "%s killed all opponents"

-- info = { winner, reason, fullRound, remaining (areas left for the winner),
-- arena (the round was arena's), captures (the winner's, for a CTF win) }
function WinPanel(info)
	if info.winner < FIRST_GAME_TEAM then
		return {
			title = "STALEMATE",
			reason = REASON_TEXT[WINREASON.STALEMATE],
		}
	end
	local team = TEAM_LABEL[info.winner]
	local areaDefense = info.reason == WINREASON.DEFEND_UNTIL_TIME_LIMIT and not info.fullRound
	local title
	if info.fullRound then
		title = team .. " TEAM WINS!"
	elseif areaDefense then
		title = team .. " TEAM DEFENDS!"
	else
		title = team .. " TEAM SEIZES AREA"
	end
	local text = REASON_TEXT[info.reason]
	if info.arena and info.reason == WINREASON.OPPONENTS_DEAD then text = ARENA_ELIMINATION end
	local reason = text and string.format(text, team) or nil
	if BY_CAPTURES[info.reason] then
		reason = string.format(info.captures == 1 and CAPTURE_TEXT or CAPTURES_TEXT, team, info.captures)
	end
	local panel = {
		title = title,
		reason = reason,
	}
	if not info.fullRound and info.reason ~= WINREASON.STALEMATE then
		panel.details = info.remaining .. (info.remaining == 1 and " more area to win" or " more areas to win")
	end
	return panel
end

local STALEMATE_REASON = {
	[STALEMATE.JOIN_MID] = "Sit back and relax while you wait for this petty conflict to end.",
	[STALEMATE.TIMER] = "You've run out of time. Watch your back and finish 'em off. No more spawning.",
	[STALEMATE.SERVER_TIMELIMIT] = "Map time limit reached. No more spawning, so make this count.",
	[STALEMATE.MATCH_TIED] = "The match is tied. No more spawning: the next team to win takes the match.",
	[STALEMATE.ADMIN] = "The Administrator has called sudden death. No more spawning.",
	[STALEMATE.BOTH_DEAD] = "Both teams fell at once. Again: no more spawning, the last team standing wins.",
	[STALEMATE.LIMIT_TIED] = "Both teams reached the limit together. No more spawning, the last team standing wins.",
	[STALEMATE.ENDED_EARLY] = "The match is ending early. No more spawning, the last team standing wins.",
}

function StalematePanel(reason)
	return {
		title = "SUDDEN DEATH!",
		reason = STALEMATE_REASON[reason],
	}
end

-- Sudden death's notification card: its panel's title and reason.
function SuddenDeathNote(reason)
	local panel = StalematePanel(reason)
	return string.format("%s %s", panel.title, panel.reason)
end

-- Deathmatch's start (games.gameplay.rounds' Deathmatch): the tied match's
-- bonus round, won at fraglimit frags.
function DeathmatchNote(fraglimit)
	return string.format("DEATHMATCH! The match is tied: the first team to %d frags wins it.", fraglimit)
end

-- The flash beside the timer when time is added (game_teamplay_timer_time_added).
function TimeAdded(seconds)
	local sign = seconds < 0 and "-" or "+"
	local s = math.abs(seconds)
	return string.format("%s%d:%02d", sign, math.floor(s / SECONDS_PER_MINUTE), s % SECONDS_PER_MINUTE)
end

-- The timer box ----------------------------------------------------------------------

-- mp_scrambleteams_auto's card, with the round won that made a scramble due.
SCRAMBLE_NOTE = "Teams will be scrambled next round!"

-- A restart asked (gameplay.rounds' RestartRequest), as every player's
-- centre and console print it: tf_english.txt's #round_restart_in_sec(s) and
-- #game_switch_in_sec(s), by the announcement CheckRestartRound chose.
local RESTART_NOTES = {
	[Rounds.RESTART_ROUND] = { "The round will restart in %d second", "The round will restart in %d seconds" },
	[Rounds.RESTART_SWITCH] = { "Switching teams!\nThe game will restart in %d second", "Switching teams!\nThe game will restart in %d seconds" },
}

function RestartNote(announce, seconds)
	local forms = RESTART_NOTES[announce]
	return string.format(seconds > 1 and forms[2] or forms[1], seconds)
end

-- The note everyone gets as mp_chattime begins: the map that comes next.
function NextMapNote(map)
	return string.format("Next map: %s", map)
end

-- Before a game, the pregame (tournament) panel shows in place of the top
-- timer and scores (features.gamemode.tournament): the wait for players,
-- the countdown to Gameplay mode, or Sandbox mode.
PREGAME_WAITING, PREGAME_COUNTDOWN, PREGAME_SANDBOX = "waiting", "countdown", "sandbox"

-- The pregame now, or nil in Gameplay mode. q = { now, transitionEnd (the
-- gamemode's ws_gamemode_transition_end, 0 outside a transition),
-- waitingNeed (how many players the gamemode's wait needs; 0 outside it),
-- halted (the rounds stand still) }: the wait first, then the countdown
-- (which runs on once its pre-round lets the rounds run), then Sandbox mode.
function Pregame(q)
	if q.waitingNeed > 0 then return PREGAME_WAITING end
	if q.transitionEnd > q.now then return PREGAME_COUNTDOWN end
	if q.halted then return PREGAME_SANDBOX end
	return nil
end

-- Which clock the timer box shows.
DISPLAY_ROUND = "round" -- the round's own timer
DISPLAY_GAME_OVER = "game_over" -- the match won: the countdown to the next map
DISPLAY_CAP_UNLOCK = "cap_unlock" -- arena: the countdown to the point unlocking
DISPLAY_SETUP = "setup" -- arena: its setup's countdown (no team_round_timer has it)
DISPLAY_MAP = "map" -- no round timer: the map's time left under mp_timelimit (CTFHudTimeStatus)

-- The wait's words, on the pregame panel.
LABEL_WAITING = "Waiting for players"
-- The label under the clock: TF2's, in capitals.
LABEL_PREROUND = "PREPARE"
LABEL_SETUP = "SETUP"
LABEL_OVERTIME = "OVERTIME"
LABEL_GAME_OVER = "GAME OVER"
LABEL_CAP_UNLOCK = "POINT UNLOCKS" -- CHudArenaCapPointCountdown's, on the timer

local function RoundLabel(q)
	if q.preround then return LABEL_PREROUND end
	if q.setup then return LABEL_SETUP end
	if q.overtime then return LABEL_OVERTIME end
	return nil
end

-- What the timer box shows, or nil for nothing. q = { now, transitionEnd,
-- waitingNeed and halted (as Pregame takes them), shown (a HUD timer
-- exists), koth (the koth HUD draws its own clocks), preround, setup,
-- overtime, gameOverEnd (ws_game_over_end: when the won match's map
-- changes, 0 before), setupEnd (arena: when its setup ends, else 0),
-- capUnlockEnd (arena: when the point unlocks while the round waits for
-- it, else 0), kothUnlockEnd (koth: when tf_logic_koth's lock on the hill
-- at the round's start ends, else 0), matchEnd (ws_match_time_end: when mp_timelimit runs out, 0
-- without one), left (the round timer's seconds) }. Nothing before a game
-- (Pregame: its panel shows the wait and the countdown); then the won
-- match's countdown to its map change, on any map; then, while the rounds
-- run, an arena's setup, then its countdown to the point unlocking (with or
-- without a round timer of its own), a koth hill's lock as SETUP (the team
-- clocks greyed meanwhile: KothClocksLive), else the round's timer, else (a map
-- without one, as ctf_2fort) the map's time left. Returns { kind, left,
-- label }.
function TimerDisplay(q)
	if Pregame(q) then return nil end
	if q.gameOverEnd > q.now then
		return {
			kind = DISPLAY_GAME_OVER,
			left = q.gameOverEnd - q.now,
			label = LABEL_GAME_OVER,
		}
	end
	if q.setupEnd > q.now then
		return {
			kind = DISPLAY_SETUP,
			left = q.setupEnd - q.now,
			label = LABEL_SETUP,
		}
	end
	if q.capUnlockEnd > q.now then
		return {
			kind = DISPLAY_CAP_UNLOCK,
			left = q.capUnlockEnd - q.now,
			label = LABEL_CAP_UNLOCK,
		}
	end
	if q.koth then
		if q.kothUnlockEnd <= q.now then return nil end
		return {
			kind = DISPLAY_SETUP,
			left = q.kothUnlockEnd - q.now,
			label = LABEL_SETUP,
		}
	end
	if not q.shown then
		if q.matchEnd <= q.now then return nil end
		return {
			kind = DISPLAY_MAP,
			left = q.matchEnd - q.now,
		}
	end
	return {
		kind = DISPLAY_ROUND,
		left = q.left,
		label = RoundLabel(q),
	}
end

-- Whether koth's team clocks run yet: greyed, as disabled, while the hill's
-- lock at the round's start (q = { now, kothUnlockEnd }) counts down as
-- SETUP on the timer.
function KothClocksLive(q)
	return q.kothUnlockEnd <= q.now
end
