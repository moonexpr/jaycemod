-- The rounds feature's view, drawn from what the rounds controller networks
-- (the wetsand_round_* and wetsand_timer_* keys and its net messages):
--   - the round timer with its PREPARE, SETUP and OVERTIME labels, and the
--     "+m:ss" flash beside it when time is added (teamplay_timer_time_added);
--     the koth HUD replaces the timer; during the gamemode's countdown to
--     Gameplay mode (wetsand_gamemode_transition_end) the timer shows that
--     countdown labelled "Prepare";
--   - the pre-round and respawn countdowns and the announcement line;
--   - a small panel with the stage of a multi-stage map, the team scores and
--     the local team's goal (CTFGameRules::ShouldShowTeamGoal); TF2's win
--     panel (tf_hud_winpanel.cpp), the sudden death panel
--     (tf_hud_stalemate.cpp), the game-over reason, and round notices;
--   - the announcer as each TF2 client plays it: the timer's countdown
--     (CTeamRoundTimer::ClientThink), "Mission begins in 60 seconds"... "1"
--     through setup and "Mission ends in..." through normal time, the siren
--     when setup gives way to the round, and the overtime line
--     (CTFGameRules::HandleOvertimeBegin). Only the timer shown in the HUD
--     speaks, and only while it runs with auto_countdown on.
local Rounds = WETSAND.require("foundation.rounds")
local Timer = WETSAND.require("foundation.rounds.timer")
local Text = WETSAND.require("foundation.rounds.text")

local S = WETSAND.STATE
local UNASSIGNED = WETSAND.TEAM_UNASSIGNED

surface.CreateFont("Sandcastle.Hud.Timer", {
	font = "Roboto",
	size = 34,
	weight = 800,
})
surface.CreateFont("Sandcastle.Hud.Label", {
	font = "Roboto",
	size = 18,
	weight = 700,
})
surface.CreateFont("Sandcastle.Hud.Announce", {
	font = "Roboto",
	size = 42,
	weight = 900,
})
surface.CreateFont("Sandcastle.Rounds.Title", {
	font = "Roboto",
	size = 34,
	weight = 900,
})
surface.CreateFont("Sandcastle.Rounds.Text", {
	font = "Roboto",
	size = 18,
	weight = 600,
})
surface.CreateFont("Sandcastle.Rounds.Small", {
	font = "Roboto",
	size = 15,
	weight = 600,
})

-- The top-centre of the screen can sit under a display notch (MacBook), so
-- the timer is pushed down by a fraction of the screen height, at most
-- TIMER_Y_MAX so the timer stays on screen (a saved 2 put it off it).
local TIMER_Y_MAX = 0.9
local timerY = CreateClientConVar("cl_hud_round_timer_y", "0.08", true, false,
	"Round timer top, as a fraction of screen height (clears display notches).", 0, TIMER_Y_MAX)

local ANNOUNCE_SECONDS = 4
local TIME_ADDED_SECONDS = 2
local STALEMATE_PANEL_SECONDS = 15
local NOTICE_SECONDS = 5
local PANEL_BG = Color(0, 0, 0, 170)
local GOLD = Color(255, 210, 90)
local TIMER_WIDTH, TIMER_HEIGHT, TIMER_LABELLED_HEIGHT = 140, 46, 64

local OVERTIME = "Game.Overtime"

local View = {
	announcement = nil,
	timeAdded = nil,
	notices = {},
	stalemateSince = 0,
	lastState = nil,
	serial = nil,
	wasSetup = nil,
	wasOvertime = false,
	armed = {},
}

local function PlayPA(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name, 100, 100, 1, CHAN_VOICE2) end
end

local function Play(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name) end
end

local function Clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The top of the timer row, which other views line up under.
function View:TimerTop(h)
	return math.floor(h * timerY:GetFloat())
end

-- Goal strings arrive as TF2 tokens ("#Goldrush_blue_setup_goal"), worded in
-- the player's language (WETSAND.Localize). nil when unknown or empty.
function View:Localize(token)
	if token == "" then return nil end
	return WETSAND.Localize(token)
end

-- The HUD timer's seconds left, paused or running.
local function TimerLeft()
	if GetGlobal2Bool("wetsand_timer_paused", true) then return GetGlobal2Float("wetsand_timer_time_left", 0) end
	return GetGlobal2Float("wetsand_timer_end_time", 0) - CurTime()
end

-- Game events ---------------------------------------------------------------------

-- The announcement line (wetsand/sh_announcer.lua), from the server or
-- another view; with an icon, drawn as TF2's notification card.
function View:Announce(text, team, icon)
	self.announcement = {
		text = text,
		team = team,
		icon = icon ~= "" and icon or nil,
		expires = CurTime() + ANNOUNCE_SECONDS,
	}
end

WETSAND.Events.Listen("announcement", "wetsand_rounds_view", function(fields)
	if not WETSAND.TeamRules.HearsBroadcast(fields.audience, false, LocalPlayer():Team()) then return end
	View:Announce(fields.text, fields.team, fields.icon)
	-- a card (an admin's notice) is kept in the console too
	if fields.icon ~= "" then MsgC(WETSAND.TeamColor[fields.team] or color_white, "[Sandcastle] " .. fields.text .. "\n") end
end)

-- A round notice under the timer, in the team's colour (the capture view's
-- "defended" notices).
function View:Notice(text, team)
	self.notices[#self.notices + 1] = {
		text = text,
		team = team,
		expires = CurTime() + NOTICE_SECONDS,
	}
end

-- "+points" beside a team's score when an admin awards it points
-- (wetsand/sh_announcer.lua), as "+time" beside the timer.
WETSAND.Events.Listen("points_awarded", "wetsand_rounds_view", function(fields)
	View.pointsAwarded = {
		text = "+" .. fields.points,
		team = fields.team,
		expires = CurTime() + TIME_ADDED_SECONDS,
	}
end)

-- The timer's "+time" beside the clock (sh.lua).
WETSAND.Events.Listen("teamplay_timer_time_added", "wetsand_rounds_view", function(fields)
	if fields.seconds_added == 0 then return end
	View.timeAdded = {
		text = Text.TimeAdded(fields.seconds_added),
		team = fields.team,
		expires = CurTime() + TIME_ADDED_SECONDS,
	}
end)

-- The timer -----------------------------------------------------------------------

-- foundation.rounds.text decides the clock: the gamemode's countdown to
-- Gameplay mode ("Prepare"), else the round's timer while the rounds run.
-- Sandbox mode otherwise shows no timer, as TF2's tournament pre-ready
-- state; the koth HUD draws its own clocks.
function View:DrawTimer(w, h)
	local display = Text.TimerDisplay({
		now = CurTime(),
		transitionEnd = GetGlobal2Float("wetsand_gamemode_transition_end", 0),
		shown = GetGlobal2Bool("wetsand_timer_shown", false),
		halted = WETSAND.GameplayStopped(),
		koth = GetGlobal2Int("wetsand_round_hud_type", Rounds.HUD_NONE) == Rounds.HUD_KOTH,
		preround = WETSAND.State() == S.PREROUND,
		setup = GetGlobal2Bool("wetsand_timer_in_setup", false),
		overtime = GetGlobal2Bool("wetsand_round_overtime", false),
		left = TimerLeft(),
	})
	if not display then return end
	local top = self:TimerTop(h)
	local label = display.label
	draw.RoundedBox(6, w / 2 - TIMER_WIDTH / 2, top, TIMER_WIDTH, label and TIMER_LABELLED_HEIGHT or TIMER_HEIGHT, PANEL_BG)
	draw.SimpleText(Clock(display.left), "Sandcastle.Hud.Timer", w / 2, top + 4, color_white, TEXT_ALIGN_CENTER)
	if label then
		draw.SimpleText(label, "Sandcastle.Hud.Label", w / 2, top + 40, GOLD, TEXT_ALIGN_CENTER)
	end
	local added = self.timeAdded
	if display.kind == Text.DISPLAY_ROUND and added and CurTime() < added.expires then
		draw.SimpleTextOutlined(added.text, "Sandcastle.Hud.Label", w / 2 + TIMER_WIDTH / 2 + 8, top + 12,
			WETSAND.TeamColor[added.team] or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
	end
end

-- Countdowns and the announcement line -------------------------------------------------

function View:DrawPreround(w, h)
	if WETSAND.State() ~= S.PREROUND then return end
	local left = math.max(1, math.ceil(GetGlobal2Float("wetsand_preround_end_time", 0) - CurTime()))
	draw.SimpleTextOutlined("Round begins in " .. left, "Sandcastle.Hud.Announce", w / 2, h * 0.35, color_white,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

function View:DrawRespawn(w, h)
	local ply = LocalPlayer()
	if not IsValid(ply) or ply:Alive() then return end
	local at = ply:GetNW2Float("wetsand_respawn_time", 0)
	if at <= 0 then return end
	local left = math.max(0, math.ceil(at - CurTime()))
	local text = left > 0 and ("Respawn in " .. left .. "s") or "Prepare to respawn"
	draw.SimpleTextOutlined(text, "Sandcastle.Hud.Label", w / 2, h * 0.7, color_white, TEXT_ALIGN_CENTER,
		TEXT_ALIGN_CENTER, 1, color_black)
end

-- TF2's notification card (base_notification.res, hudlayout.res's
-- NotificationPanel), in HUD units of a 480-tall screen: the team's score
-- panel behind, the icon at the left, the text after it, the card as wide
-- as its text, centred CARD_Y down the screen.
local CARD_Y, CARD_TALL, CARD_ICON, CARD_ICON_X, CARD_ICON_Y, CARD_TEXT_X, CARD_PAD = 300, 44, 20, 7, 9, 30, 10
local CARD_FONT, CARD_FONT_TALL = "Sandcastle.Hud.Card", 13
local CARD_BACKGROUND = {
	[WETSAND.TEAM_RED] = Material("hud/score_panel_red_bg"),
	[WETSAND.TEAM_BLUE] = Material("hud/score_panel_blue_bg"),
}
local CARD_NEUTRAL = Material("hud/notification_black")
local cardFontTall

local function DrawCard(a, w, h)
	local unit = h / 480
	local tall = math.Round(CARD_FONT_TALL * unit)
	if tall ~= cardFontTall then
		surface.CreateFont(CARD_FONT, { font = "TF2 Secondary", size = tall, weight = 500 })
		cardFontTall = tall
	end
	surface.SetFont(CARD_FONT)
	local textW = surface.GetTextSize(a.text)
	local cardW = CARD_TEXT_X * unit + textW + CARD_PAD * unit
	local x, y = (w - cardW) / 2, CARD_Y * unit
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(CARD_BACKGROUND[a.team] or CARD_NEUTRAL)
	surface.DrawTexturedRect(x, y, cardW, CARD_TALL * unit)
	surface.SetMaterial(Material(a.icon))
	surface.DrawTexturedRect(x + CARD_ICON_X * unit, y + CARD_ICON_Y * unit, CARD_ICON * unit, CARD_ICON * unit)
	draw.SimpleText(a.text, CARD_FONT, x + CARD_TEXT_X * unit, y + (CARD_ICON_Y + CARD_ICON / 2) * unit, color_white,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

function View:DrawAnnouncement(w, h)
	local a = self.announcement
	if not a or CurTime() > a.expires then return end
	if a.icon then return DrawCard(a, w, h) end
	draw.SimpleTextOutlined(a.text, "Sandcastle.Hud.Announce", w / 2, h * 0.25, WETSAND.TeamColor[a.team] or color_white,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

-- The round panel ------------------------------------------------------------------

local function ShowGoal(state)
	return state == S.PREROUND or state == S.RND_RUNNING or GetGlobal2Bool("wetsand_round_in_setup", false)
end

function View:DrawRoundPanel(w, h)
	local x, y = 16, math.floor(h * 0.08)
	local lines = {}
	local function Line(text, color)
		lines[#lines + 1] = {
			text = text,
			color = color,
		}
	end
	local stages = GetGlobal2Int("wetsand_mini_round_count", 0)
	if stages > 1 then
		Line(string.format("Stage %d of %d", GetGlobal2Int("wetsand_mini_round_stage", 0), stages), GOLD)
	end
	Line(string.format("RED %d  :  %d BLU", team.GetScore(WETSAND.TEAM_RED), team.GetScore(WETSAND.TEAM_BLUE)), color_white)
	local scoreLine = #lines - 1
	local myTeam = WETSAND.TeamOf(LocalPlayer())
	if myTeam ~= UNASSIGNED and ShowGoal(WETSAND.State()) then
		local goal = self:Localize(GetGlobal2String("wetsand_round_goal_" .. myTeam, ""))
		if goal then Line(goal, WETSAND.TeamColor[myTeam]) end
	end

	surface.SetFont("Sandcastle.Rounds.Small")
	local width = 0
	for _, line in ipairs(lines) do width = math.max(width, (surface.GetTextSize(line.text))) end
	draw.RoundedBox(6, x, y, width + 16, #lines * 20 + 8, PANEL_BG)
	for i, line in ipairs(lines) do
		draw.SimpleText(line.text, "Sandcastle.Rounds.Small", x + 8, y + 4 + (i - 1) * 20, line.color)
	end
	-- an admin's points, beside the scores
	local awarded = self.pointsAwarded
	if awarded and CurTime() < awarded.expires then
		draw.SimpleTextOutlined(awarded.text, "Sandcastle.Hud.Label", x + width + 24, y + 4 + scoreLine * 20,
			WETSAND.TeamColor[awarded.team] or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
	end
end

-- Centre panels --------------------------------------------------------------------

local function DrawCentrePanel(w, h, title, titleColor, rows)
	local y = math.floor(h * 0.45)
	surface.SetFont("Sandcastle.Rounds.Title")
	local width = surface.GetTextSize(title)
	surface.SetFont("Sandcastle.Rounds.Text")
	for _, row in ipairs(rows) do width = math.max(width, (surface.GetTextSize(row))) end
	draw.RoundedBox(8, w / 2 - width / 2 - 16, y, width + 32, 48 + #rows * 22, PANEL_BG)
	draw.SimpleText(title, "Sandcastle.Rounds.Title", w / 2, y + 6, titleColor, TEXT_ALIGN_CENTER)
	for i, row in ipairs(rows) do
		draw.SimpleText(row, "Sandcastle.Rounds.Text", w / 2, y + 44 + (i - 1) * 22, color_white, TEXT_ALIGN_CENTER)
	end
end

function View:DrawWinPanel(w, h)
	local winner = GetGlobal2Int("wetsand_round_winner", UNASSIGNED)
	local panel = Text.WinPanel({
		winner = winner,
		reason = GetGlobal2Int("wetsand_round_win_reason", Rounds.WINREASON.NONE),
		fullRound = GetGlobal2Bool("wetsand_round_full_round", true),
		remaining = GetGlobal2Int("wetsand_rounds_remaining", 0),
	})
	local rows = {}
	if panel.reason then rows[#rows + 1] = panel.reason end
	if panel.details then rows[#rows + 1] = panel.details end
	DrawCentrePanel(w, h, panel.title, WETSAND.TeamColor[winner] or color_white, rows)
end

function View:DrawStalematePanel(w, h)
	if CurTime() - self.stalemateSince > STALEMATE_PANEL_SECONDS then return end
	local panel = Text.StalematePanel(GetGlobal2Int("wetsand_stalemate_reason", Rounds.STALEMATE.TIMER))
	DrawCentrePanel(w, h, panel.title, GOLD, { panel.reason })
end

-- The match's end: who won it (Rounds.MatchWinner; a tied match goes to
-- sudden death instead), and why it ended.
function View:DrawGameOver(w, h)
	local winner = GetGlobal2Int("wetsand_match_winner", Rounds.NOBODY_WON)
	DrawCentrePanel(w, h, string.format("%s WINS THE MATCH!", WETSAND.TeamName[winner]), WETSAND.TeamColor[winner],
		{ GetGlobal2String("wetsand_game_over_reason", "") })
end

function View:DrawNotices(w, h)
	local y = math.floor(h * 0.08)
	local notices = self.notices
	for i = #notices, 1, -1 do
		if CurTime() > notices[i].expires then table.remove(notices, i) end
	end
	for i, n in ipairs(notices) do
		draw.SimpleTextOutlined(n.text, "Sandcastle.Rounds.Small", w - 16, y + (i - 1) * 20,
			WETSAND.TeamColor[n.team] or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
	end
end

local CENTRE_PANELS = {
	[S.TEAM_WIN] = View.DrawWinPanel,
	[S.STALEMATE] = View.DrawStalematePanel,
	[S.GAME_OVER] = View.DrawGameOver,
}

function View:Paint(w, h)
	local state = WETSAND.State()
	if state == S.STALEMATE and self.lastState ~= S.STALEMATE then self.stalemateSince = CurTime() end
	self.lastState = state
	self:DrawTimer(w, h)
	self:DrawPreround(w, h)
	self:DrawAnnouncement(w, h)
	self:DrawRespawn(w, h)
	self:DrawRoundPanel(w, h)
	self:DrawNotices(w, h)
	local panel = CENTRE_PANELS[state]
	if panel then panel(self, w, h) end
end

-- The announcer ----------------------------------------------------------------------

-- OnDataChanged: overtime beginning is announced once.
function View:OvertimeThink()
	local overtime = GetGlobal2Bool("wetsand_round_overtime", false)
	if overtime and not self.wasOvertime and not WETSAND.GameplayStopped() then Play(OVERTIME) end
	self.wasOvertime = overtime
end

-- The HUD timer's countdown and siren; foundation.rounds.timer says which
-- cue plays when.
function View:CountdownThink()
	if not GetGlobal2Bool("wetsand_timer_shown", false) then return end
	local setup = GetGlobal2Bool("wetsand_timer_in_setup", false)
	local paused = GetGlobal2Bool("wetsand_timer_paused", true)
	local speaks = Timer.Speaks({
		paused = paused,
		autoCountdown = GetGlobal2Bool("wetsand_timer_auto_countdown", true),
		halted = WETSAND.GameplayStopped(),
		isHud = true,
		koth = GetGlobal2Int("wetsand_round_hud_type", Rounds.HUD_NONE) == Rounds.HUD_KOTH,
	})
	local left = TimerLeft()

	if Timer.StartsRound(self.wasSetup, setup) and speaks then
		Play(Timer.WarningSound(Timer.WARNING_TIME_START, false))
	end
	self.wasSetup = setup

	-- The warnings are re-armed whenever the timer's length changes.
	local serial = GetGlobal2Int("wetsand_timer_serial", 0)
	if serial ~= self.serial then
		self.serial = serial
		self.armed = Timer.ArmClientWarnings(left)
	end
	if paused then return end

	local warning = Timer.NextClientWarning(self.armed, left)
	if warning then
		self.armed[warning] = false
		if speaks then Play(Timer.WarningSound(warning, setup)) end
	end
end

hook.Add("SandcastleHUDPaint", "wetsand_rounds", function(w, h)
	View:Paint(w, h)
end)

hook.Add("Think", "wetsand_rounds_announcer", function()
	if not WETSAND.Active() then return end
	View:OvertimeThink()
	View:CountdownThink()
end)

return View
