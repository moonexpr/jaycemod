-- TF2's tournament panel (CHudTournament, tf_hud_tournament.cpp) as
-- cooler-hud v2.6 lays it out (resource/ui/hudtournament.res), in TF2's
-- proportional units of a 480-tall screen, over Sandcastle's stand-in for
-- TF2's tournament ready-up: Sandbox mode, a game waiting for players and
-- the countdown to Gameplay mode (games.system.gamemode). There is no
-- per-team ready-up, so each team's state slot counts its players; the
-- state line is in the gamemode's own words, the win conditions TF2's
-- from the match's limits, and the instructions line names the one action
-- there is, beginning a game, for a player who may. Rects are { x, y, w, h }
-- in pixels.
local ceil, concat, format, ipairs = math.ceil, table.concat, string.format, ipairs
local Teams = gameplay.teams
local Text = require("features.rounds.text")
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE

-- HudTournament: c-125, 250 wide. HudTournamentBG 0,0 250x55,
-- tournament_panel_brown, src_corner_width 23, draw_corner_width 8.
W, BG_H = 250, 55
BG_IMAGE, BG_SRC_CORNER, BG_DRAW_CORNER = "hud/tournament_panel_brown", 23, 8
-- TournamentLabel 5,3 240x19, centred, HudFontSmall (TF2 Secondary 14).
STATE_Y, STATE_TALL, STATE_FONT_TALL = 3, 19, 14
-- HudTournamentBLUEBG 5,23 and HudTournamentREDBG 125,23, 120x16,
-- tournament_panel_blu and _red, src_corner_width 15, draw_corner_width 4.
STRIP_Y, STRIP_W, STRIP_H, BLUE_STRIP_X, RED_STRIP_X = 23, 120, 16, 5, 125
STRIP_IMAGES = {
	[BLUE] = "hud/tournament_panel_blu",
	[RED] = "hud/tournament_panel_red",
}
STRIP_SRC_CORNER, STRIP_DRAW_CORNER = 15, 4
-- The team labels, 24 down, 65x15: TournamentBLUELabel 12 west and
-- TournamentREDLabel 175 east, HudFontSmallest (TF2 Secondary 11);
-- TournamentBLUEStateLabel 56 east and TournamentREDStateLabel 130 west,
-- HudFontSmallestBold (TF2 Build 11).
TEAM_LABEL_Y, TEAM_LABEL_W, TEAM_LABEL_TALL, NAME_FONT_TALL, TEAM_STATE_FONT_TALL = 24, 65, 15, 11, 11
BLUE_NAME_X, BLUE_STATE_X, RED_NAME_X, RED_STATE_X = 12, 56, 175, 130
-- TournamentConditionLabel 8,42, north-west, TFFontSmall (TF2 Secondary 8)
-- in TanLight.
CONDITION_X, CONDITION_Y, CONDITION_FONT_TALL = 8, 42, 8
-- TournamentInstructionsLabel 0,50 250x20, centred, HudFontSmallBold (TF2
-- Build 14), over TournamentInstructionsLabelShadow in black at 1,51.
INSTRUCTIONS_Y, INSTRUCTIONS_TALL, INSTRUCTIONS_FONT_TALL, SHADOW_OFFSET = 50, 20, 14, 1

-- The state line: Sandbox mode as the gamemode's notices name it, the
-- wait in the round timer's words (features.rounds.text), the countdown
-- as the transition's opening line words it (features/gamemode/sv.lua).
local SANDBOX = "Sandbox mode"
local WAITING = Text.LABEL_WAITING .. " (%d/%d)"
local COUNTDOWN, COUNTDOWN_ONE = "Gameplay mode begins in %d seconds", "Gameplay mode begins in %d second"

-- Each team's state slot: its players.
local PLAYERS, PLAYER = "%d players", "%d player"

-- CHudTournament::PreparePanel's win conditions (#Tournament_WinConditions
-- and its kin), from mp_timelimit, mp_winlimit and mp_maxrounds.
local CONDITIONS, NO_CONDITIONS = "Win Conditions: ", "None"
local CONDITION_WORDS = {
	{ key = "timelimit", one = "minute", many = "minutes" },
	{ key = "winlimit", one = "win", many = "wins" },
	{ key = "maxrounds", one = "round", many = "rounds" },
}

-- The Match Control panel's Begin Game button (ws/cl_admin_panels.lua),
-- for a player with the match privilege.
BEGIN_INSTRUCTIONS = "Begin Game: Utilities > Admin > Match Control"

-- The panel's modes, by what the client is told.
local MODE_SANDBOX, MODE_WAITING, MODE_COUNTDOWN = "sandbox", "waiting", "countdown"

-- The wait first, then the countdown (which runs on once its first
-- pre-round lets the rounds run), then Sandbox mode; nil in Gameplay mode.
local function Mode(q)
	if q.waitingNeed > 0 then return MODE_WAITING end
	if q.transitionEnd > q.now then return MODE_COUNTDOWN end
	if q.halted then return MODE_SANDBOX end
	return nil
end

local STATE_LINES = {
	[MODE_SANDBOX] = function() return SANDBOX end,
	[MODE_WAITING] = function(q) return format(WAITING, q.waitingHave, q.waitingNeed) end,
	[MODE_COUNTDOWN] = function(q)
		local left = ceil(q.transitionEnd - q.now)
		return format(left == 1 and COUNTDOWN_ONE or COUNTDOWN, left)
	end,
}

local function Count(n, one, many)
	return format(n == 1 and one or many, n)
end

local function Conditions(limits)
	local parts = {}
	for _, word in ipairs(CONDITION_WORDS) do
		local n = limits[word.key]
		if n > 0 then parts[#parts + 1] = format("%d %s", n, n == 1 and word.one or word.many) end
	end
	return CONDITIONS .. (#parts > 0 and concat(parts, ", ") or NO_CONDITIONS)
end

-- q = { now, transitionEnd (ws_gamemode_transition_end, 0 outside the
-- countdown), waitingHave, waitingNeed (ws_gamemode_waiting_have and
-- _need; need 0 outside the wait), halted (WS.GameplayStopped), winPanel (a
-- win panel or the match's end is up), players and names (by team), limits
-- ({ timelimit, winlimit, maxrounds }: the match's), mayBegin (the player
-- holds the match privilege) }. Returns nil when no panel shows, else
-- { state, teams (by team: { name, state }), conditions, instructions (nil
-- for none) }.
function Panel(q)
	local mode = Mode(q)
	if mode == nil or q.winPanel then return nil end
	local teams = {}
	for _, t in ipairs({ BLUE, RED }) do
		teams[t] = {
			name = q.names[t],
			state = Count(q.players[t], PLAYER, PLAYERS),
		}
	end
	return {
		state = STATE_LINES[mode](q),
		teams = teams,
		conditions = Conditions(q.limits),
		instructions = mode == MODE_SANDBOX and q.mayBegin and BEGIN_INSTRUCTIONS or nil,
	}
end

local function Rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

-- Where each part goes, the panel centred on centreX from top (unit:
-- ws.tf_hud's Unit): { bg, state (its centre), strips (by team), names and
-- states (by team: { x, y }, x the left of a west label and the right of an
-- east one, y its middle), conditions (its top left), instructions and
-- shadow (their centres) }.
function Layout(centreX, top, unit)
	local left = centreX - W / 2 * unit
	local labelY = top + (TEAM_LABEL_Y + TEAM_LABEL_TALL / 2) * unit
	local instructionsY = top + (INSTRUCTIONS_Y + INSTRUCTIONS_TALL / 2) * unit
	local function Strip(x) return Rect(left + x * unit, top + STRIP_Y * unit, STRIP_W * unit, STRIP_H * unit) end
	local function At(x) return { x = left + x * unit, y = labelY } end
	return {
		bg = Rect(left, top, W * unit, BG_H * unit),
		state = { x = centreX, y = top + (STATE_Y + STATE_TALL / 2) * unit },
		strips = {
			[BLUE] = Strip(BLUE_STRIP_X),
			[RED] = Strip(RED_STRIP_X),
		},
		names = {
			[BLUE] = At(BLUE_NAME_X),
			[RED] = At(RED_NAME_X + TEAM_LABEL_W),
		},
		states = {
			[BLUE] = At(BLUE_STATE_X + TEAM_LABEL_W),
			[RED] = At(RED_STATE_X),
		},
		conditions = { x = left + CONDITION_X * unit, y = top + CONDITION_Y * unit },
		instructions = { x = centreX, y = instructionsY },
		shadow = { x = centreX + SHADOW_OFFSET * unit, y = instructionsY + SHADOW_OFFSET * unit },
	}
end
