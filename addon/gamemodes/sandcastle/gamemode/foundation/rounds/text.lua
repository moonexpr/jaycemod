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
}

-- info = { winner, reason, fullRound, remaining (areas left for the winner) }
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

-- The flash beside the timer when time is added (teamplay_timer_time_added).
function TimeAdded(seconds)
	local sign = seconds < 0 and "-" or "+"
	local s = math.abs(seconds)
	return string.format("%s%d:%02d", sign, math.floor(s / SECONDS_PER_MINUTE), s % SECONDS_PER_MINUTE)
end

-- The timer box ----------------------------------------------------------------------

-- The note everyone gets as mp_chattime begins: the map that comes next.
function NextMapNote(map)
	return string.format("Next map: %s", map)
end

-- Which clock the timer box shows.
DISPLAY_TRANSITION = "transition" -- the gamemode's countdown to Gameplay mode
DISPLAY_ROUND = "round" -- the round's own timer
DISPLAY_GAME_OVER = "game_over" -- the match won: the countdown to the next map

-- The label under the clock. The transition's is the operator's word as
-- written; the round's are TF2's, in capitals.
LABEL_TRANSITION = "Prepare"
LABEL_PREROUND = "PREPARE"
LABEL_SETUP = "SETUP"
LABEL_OVERTIME = "OVERTIME"
LABEL_GAME_OVER = "GAME OVER"

local function RoundLabel(q)
	if q.preround then return LABEL_PREROUND end
	if q.setup then return LABEL_SETUP end
	if q.overtime then return LABEL_OVERTIME end
	return nil
end

-- What the timer box shows, or nil for nothing. q = { now, transitionEnd
-- (the gamemode's wetsand_gamemode_transition_end, 0 outside a transition),
-- shown (a HUD timer exists), halted (the rounds stand still: Sandbox mode
-- or its transition), koth (the koth HUD draws its own clocks), preround,
-- setup, overtime, gameOverEnd (wetsand_game_over_end: when the won
-- match's map changes, 0 before), left (the round timer's seconds) }. The
-- countdown to Gameplay mode wins while it runs, then the won match's to
-- its map change, on any map; the round's timer shows only while the rounds
-- run. Returns { kind, left, label }.
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
	if q.halted or not q.shown or q.koth then return nil end
	return {
		kind = DISPLAY_ROUND,
		left = q.left,
		label = RoundLabel(q),
	}
end
