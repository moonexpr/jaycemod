-- TF2's tournament panel (CHudTournament, tf_hud_tournament.cpp) as
-- cooler-hud v2.6 lays it out (resource/ui/hudtournament.res), in TF2's
-- proportional units of a 480-tall screen, over Sandcastle's stand-in for
-- TF2's tournament ready-up: Sandbox mode, a game waiting for players and
-- the countdown to Gameplay mode (games.system.gamemode, Pregame in
-- features.rounds.text). While the game waits, each team with players says
-- whether it is ready (features.gamemode.ready), else each counts its
-- players; the state line is in the gamemode's own words, the win
-- conditions TF2's from the match's limits, and the instructions line, on
-- TF2's stock help strip, names the key for what the player may do. MvM
-- shows its own ready-up instead (MvMPanel, hudtournament.res's if_mvm).
-- Rects are { x, y, w, h } in pixels.
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
-- TF2's stock help strip, as cooler-hud's bold line overflows the panel:
-- HudTournamentBGHelp 0,51 250x17 (tournament_panel_brown, corners as the
-- background's), TournamentInstructionsLabel 0,54 250x10, centred,
-- TFFontSmall (TF2 Secondary 8).
HELP_Y, HELP_H = 51, 17
INSTRUCTIONS_Y, INSTRUCTIONS_TALL, INSTRUCTIONS_FONT_TALL = 54, 10, 8

-- The state line: Sandbox mode as the gamemode's notices name it, the
-- wait in the round timer's words (features.rounds.text), the countdown
-- as the transition's opening line words it (features/gamemode/sv.lua).
SANDBOX = "Sandbox mode"
local WAITING = Text.LABEL_WAITING .. " (%d/%d)"
local COUNTDOWN, COUNTDOWN_ONE = "Gameplay mode begins in %d seconds", "Gameplay mode begins in %d second"

-- Each team's state slot: its players, or while the game waits, whether a
-- team with players is ready (#Tournament_TeamReady, _TeamNotReady).
local PLAYERS, PLAYER = "%d players", "%d player"
local TEAM_READY = { [true] = "Ready", [false] = "Not Ready" }

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

-- What the player may do, with the key bound to it (input.LookupBinding),
-- or without one, the command to bind: TF2's "F4 = Toggle Ready" and
-- "F4 = change team name/status" (teams have no names here), and the team
-- keys (gm_showteam, changeteam).
local KEYED, UNBOUND = "%s = %s", "%s: bind a key to %s"
local TOGGLE_TEAM_READY, TOGGLE_READY, PICK_TEAM = "Toggle Team Ready", "Toggle Ready", "Pick a Team"
local READY_COMMAND, TEAM_COMMAND = "player_ready_toggle", "changeteam"

local function Keyed(key, action, command)
	if key then return format(KEYED, key, action) end
	return format(UNBOUND, action, command)
end

local function OnGameTeam(team)
	return team == Teams.RED or team == Teams.BLUE
end

local MODE_SANDBOX, MODE_WAITING, MODE_COUNTDOWN = Text.PREGAME_SANDBOX, Text.PREGAME_WAITING, Text.PREGAME_COUNTDOWN

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

local function TeamState(q, mode, t)
	if mode == MODE_WAITING and q.humans[t] > 0 then return TEAM_READY[q.teamReady[t] == true] end
	return Count(q.players[t], PLAYER, PLAYERS)
end

-- The line under the panel: how to begin a game in Sandbox mode, for a
-- player who may; while the game waits, the ready key for a player on a
-- team; before the countdown, the team key for a player on none.
local function Instructions(q, mode)
	if mode == MODE_COUNTDOWN then return nil end
	if mode == MODE_SANDBOX and q.mayBegin then return BEGIN_INSTRUCTIONS end
	if not OnGameTeam(q.localTeam) then return Keyed(q.teamKey, PICK_TEAM, TEAM_COMMAND) end
	if mode == MODE_WAITING then return Keyed(q.readyKey, TOGGLE_TEAM_READY, READY_COMMAND) end
	return nil
end

local function Pregame(q)
	return Text.Pregame(q)
end

-- q = { now, transitionEnd (ws_gamemode_transition_end, 0 outside the
-- countdown), waitingHave, waitingNeed (ws_gamemode_waiting_have and
-- _need; need 0 outside the wait), halted (WS.GameplayStopped), winPanel (a
-- win panel or the match's end is up), players, humans (the human players),
-- teamReady and names (each by team), limits ({ timelimit, winlimit,
-- maxrounds }: the match's), mayBegin (the player holds the match
-- privilege), localTeam (the player's), readyKey and teamKey (the keys
-- bound to player_ready_toggle or gm_showspare2, and to the team menu; nil
-- unbound) }. Returns nil when no panel shows, else { state, teams (by
-- team: { name, state }), conditions, instructions (nil for none) }.
function Panel(q)
	local mode = Pregame(q)
	if mode == nil or q.winPanel then return nil end
	local teams = {}
	for _, t in ipairs({ BLUE, RED }) do
		teams[t] = {
			name = q.names[t],
			state = TeamState(q, mode, t),
		}
	end
	return {
		state = STATE_LINES[mode](q),
		teams = teams,
		conditions = Conditions(q.limits),
		instructions = Instructions(q, mode),
	}
end

-- MvM's ready-up ---------------------------------------------------------------------

-- The instructions line (#Tournament_Instructions_Waiting, the countdown's
-- #Tournament_Countdown_NoCancel and _Sec_NoCancel).
MVM_WAITING = "Waiting For Players"
local MVM_COUNTDOWN, MVM_COUNTDOWN_ONE = "Starting in %d seconds...", "Starting in %d second..."

local function MvMInstructions(q, mode)
	if mode == MODE_COUNTDOWN then
		local left = ceil(q.transitionEnd - q.now)
		return format(left == 1 and MVM_COUNTDOWN_ONE or MVM_COUNTDOWN, left), false
	end
	if mode == MODE_SANDBOX then return q.mayBegin and BEGIN_INSTRUCTIONS or SANDBOX, false end
	if q.waitingHave < q.waitingNeed then return MVM_WAITING, true end
	if not q.localDefender then return Keyed(q.teamKey, PICK_TEAM, TEAM_COMMAND), false end
	return Keyed(q.readyKey, TOGGLE_READY, READY_COMMAND), not q.localReady
end

-- q = { now, transitionEnd, waitingHave, waitingNeed, halted, winPanel and
-- mayBegin (as Panel takes them), defenders (the human defenders, each
-- { name, ready }), localDefender and localReady (the player is one, and
-- ready), readyKey, teamKey }. Returns nil when no panel shows, else
-- { players (each { name, ready }), instructions, pulse (the line pulses
-- red: CHudTournament's HudReadyPulse while the player is not ready) }.
function MvMPanel(q)
	local mode = Pregame(q)
	if mode == nil or q.winPanel then return nil end
	local players = {}
	for i, d in ipairs(q.defenders) do players[i] = { name = d.name, ready = d.ready } end
	local instructions, pulse = MvMInstructions(q, mode)
	return { players = players, instructions = instructions, pulse = pulse }
end

-- HudReadyPulse (scripts/hudanimations_tf.txt): the line to TanLight over
-- PULSE_TAN seconds, then toward RedSolid from PULSE_RED_AT over
-- PULSE_RED_FOR, run again every PULSE_PERIOD, each restart cutting the
-- last short (vgui's StartAnimationSequence removes the queued commands).
PULSE_PERIOD, PULSE_TAN, PULSE_RED_AT, PULSE_RED_FOR = 0.5, 0.1, 0.3, 0.4
local PULSE_PEAK = (PULSE_PERIOD - PULSE_RED_AT) / PULSE_RED_FOR -- how red it gets as it restarts

-- How red the pulsing line is at time now: 0 TanLight, 1 RedSolid.
function PulseRedness(now)
	local t = now % PULSE_PERIOD
	if t < PULSE_TAN then return PULSE_PEAK * (1 - t / PULSE_TAN) end
	if t < PULSE_RED_AT then return 0 end
	return (t - PULSE_RED_AT) / PULSE_RED_FOR
end

local function Rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

-- Where each part goes, the panel centred on centreX from top (unit:
-- ws.tf_hud's Unit): { bg, state (its centre), strips (by team), names and
-- states (by team: { x, y }, x the left of a west label and the right of an
-- east one, y its middle), conditions (its top left), help (the strip
-- under it), instructions (its centre) }.
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
		help = Rect(left, top + HELP_Y * unit, W * unit, HELP_H * unit),
		instructions = { x = centreX, y = instructionsY },
	}
end

-- hudtournament.res's if_mvm, from the top of its player row (y 66 there):
-- playerpanels_kv 55x35, MVM_PLAYER_DELTA apart (team2_player_delta_x) and
-- centred as one team (UpdatePlayerPanels); in each, the black square for
-- the class image (classimagebg 5,4 20x20; Sandcastle has no classes and
-- shows the player's avatar there), ReadyBG 30,6 16x16
-- (tournament_panel_brown, src corners 22, drawn 3), ReadyImage 32,8 12x12
-- (hud/checkmark), playername 4,25 48x8 centred (PlayerPanelPlayerName,
-- Verdana 6); the panel black (color_notready 0 0 0 220) or green
-- (color_ready 0 255 0 220). The instructions line at 155,105 190x20 of the
-- 500-wide panel, so centred, 39 under the row's top, HudFontSmallishBold
-- (TF2 Build 16), its black shadow a unit right and down.
MVM_PLAYER_W, MVM_PLAYER_H, MVM_PLAYER_DELTA = 55, 35, 52
MVM_AVATAR = { x = 5, y = 4, w = 20, h = 20 }
MVM_READY_BG = { x = 30, y = 6, w = 16, h = 16 }
MVM_READY_BG_IMAGE, MVM_READY_BG_SRC_CORNER, MVM_READY_BG_DRAW_CORNER = "hud/tournament_panel_brown", 22, 3
MVM_CHECK = { x = 32, y = 8, w = 12, h = 12 }
MVM_CHECK_IMAGE = "hud/checkmark"
MVM_NAME = { x = 4, y = 25, w = 48, h = 8 }
MVM_NAME_FONT, MVM_NAME_FONT_TALL = "Verdana", 6
MVM_COLOR_READY, MVM_COLOR_NOT_READY = { 0, 255, 0, 220 }, { 0, 0, 0, 220 }
MVM_INSTRUCTIONS_Y, MVM_INSTRUCTIONS_TALL, MVM_INSTRUCTIONS_FONT_TALL, MVM_SHADOW = 105 - 66, 20, 16, 1

local function Part(box, x, y, unit)
	return Rect(x + box.x * unit, y + box.y * unit, box.w * unit, box.h * unit)
end

-- count players' panels in a row centred on centreX from top: { players
-- (each { bg, avatar, readyBg, check, name (its centre) }), instructions
-- and shadow (their centres) }.
function MvMLayout(centreX, top, unit, count)
	local left = centreX - count * MVM_PLAYER_DELTA * unit / 2
	local players = {}
	for i = 1, count do
		local x = left + (i - 1) * MVM_PLAYER_DELTA * unit
		players[i] = {
			bg = Rect(x, top, MVM_PLAYER_W * unit, MVM_PLAYER_H * unit),
			avatar = Part(MVM_AVATAR, x, top, unit),
			readyBg = Part(MVM_READY_BG, x, top, unit),
			check = Part(MVM_CHECK, x, top, unit),
			name = {
				x = x + (MVM_NAME.x + MVM_NAME.w / 2) * unit,
				y = top + (MVM_NAME.y + MVM_NAME.h / 2) * unit,
			},
		}
	end
	local y = top + (MVM_INSTRUCTIONS_Y + MVM_INSTRUCTIONS_TALL / 2) * unit
	return {
		players = players,
		instructions = { x = centreX, y = y },
		shadow = { x = centreX + MVM_SHADOW * unit, y = y + MVM_SHADOW * unit },
	}
end
