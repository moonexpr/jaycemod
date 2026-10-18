-- What the round HUD says: the win panel (CTFWinPanel::FireGameEvent), the
-- sudden death panel (CHudStalemate::SetupStalematePanel), the time-added
-- flash. TF2's "#Token" strings are worded by foundation.localization.
local math, string, table = math, string, table
local Rounds = require("foundation.rounds")
local Teams = require("foundation.teams")
module(...)

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
}
-- Winreason_Arena: an arena round's elimination is no sudden death.
local ARENA_ELIMINATION = "%s killed all opponents"

-- info = { winner, reason, fullRound, remaining (areas left for the winner),
-- arena (the round was arena's) }
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
	local panel = {
		title = title,
		reason = text and string.format(text, team) or nil,
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

-- The flash beside the timer when time is added (game_teamplay_timer_time_added).
function TimeAdded(seconds)
	local sign = seconds < 0 and "-" or "+"
	local s = math.abs(seconds)
	return string.format("%s%d:%02d", sign, math.floor(s / SECONDS_PER_MINUTE), s % SECONDS_PER_MINUTE)
end

-- The timer box ----------------------------------------------------------------------

-- mp_scrambleteams_auto's card, with the round won that made a scramble due.
SCRAMBLE_NOTE = "Teams will be scrambled next round!"

-- The note everyone gets as mp_chattime begins: the map that comes next.
function NextMapNote(map)
	return string.format("Next map: %s", map)
end

-- Which clock the timer box shows.
DISPLAY_TRANSITION = "transition" -- the gamemode's countdown to Gameplay mode
DISPLAY_ROUND = "round" -- the round's own timer
DISPLAY_GAME_OVER = "game_over" -- the match won: the countdown to the next map
DISPLAY_CAP_UNLOCK = "cap_unlock" -- arena: the countdown to the point unlocking
DISPLAY_SETUP = "setup" -- arena: its setup's countdown (no team_round_timer has it)

-- The label under the clock. The transition's is the operator's word as
-- written; the round's are TF2's, in capitals.
LABEL_TRANSITION = "Prepare"
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

-- What the timer box shows, or nil for nothing. q = { now, transitionEnd
-- (the gamemode's ws_gamemode_transition_end, 0 outside a transition),
-- shown (a HUD timer exists), halted (the rounds stand still: Sandbox mode
-- or its transition), koth (the koth HUD draws its own clocks), preround,
-- setup, overtime, gameOverEnd (ws_game_over_end: when the won
-- match's map changes, 0 before), setupEnd (arena: when its setup ends,
-- else 0), capUnlockEnd (arena: when the point unlocks while the round waits
-- for it, else 0), left (the round timer's seconds) }. The countdown to
-- Gameplay mode wins while it runs, then the won match's to its map
-- change, on any map; then, while the rounds run, an arena's setup, then
-- its countdown to the point unlocking (with or without a round timer of
-- its own), else the round's timer. Returns { kind, left, label }.
function TimerDisplay(q)
	if q.transitionEnd > q.now then
		return {
			kind = DISPLAY_TRANSITION,
			left = q.transitionEnd - q.now,
			label = LABEL_TRANSITION,
		}
	end
	if q.gameOverEnd > q.now then
		return {
			kind = DISPLAY_GAME_OVER,
			left = q.gameOverEnd - q.now,
			label = LABEL_GAME_OVER,
		}
	end
	if q.halted then return nil end
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
	if not q.shown or q.koth then return nil end
	return {
		kind = DISPLAY_ROUND,
		left = q.left,
		label = RoundLabel(q),
	}
end
