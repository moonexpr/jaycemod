-- The rounds feature's view, drawn from what the rounds controller networks
-- (the ws_round_* and ws_timer_* keys and its net messages):
--   - the team scores, centred above the round timer, and the timer as
--     cooler-hud's time panel (ws.tf_hud): the clock and the progress pie
--     on the team's outlined background, its PREPARE, SETUP, OVERTIME and
--     GAME OVER labels in a box under it, and the "+m:ss" flash beside it
--     when time is added (game_teamplay_timer_time_added);
--     the koth HUD replaces the timer; before a game (Sandbox mode, the
--     wait for players, the countdown to Gameplay mode) the pregame panel
--     (features/gamemode/cl.lua) takes the scores' and the timer's place;
--   - the pre-round and respawn countdowns and the announcement line;
--   - the round limits' counters (games.gameplay.rounds.limits), as TF2's Player
--     Destruction panel (HudObjectivePlayerDestruction.res), in cl_limits;
--   - a small panel with the stage of a multi-stage map and the local
--     team's goal (CTFGameRules::ShouldShowTeamGoal); TF2's win panel
--     (tf_hud_winpanel.cpp, ws.tf_hud) for a round's and the match's end,
--     with the match's reason, and round notices
--     (sudden death and the next map come as notification cards);
--   - the announcer as each TF2 client plays it: the timer's countdown
--     (CTeamRoundTimer::ClientThink), "Mission begins in 60 seconds"... "1"
--     through setup and "Mission ends in..." through normal time, the siren
--     when setup gives way to the round, and the overtime line
--     (CTFGameRules::HandleOvertimeBegin). Only the timer shown in the HUD
--     speaks, and only while it runs with auto_countdown on.
local Rounds = gameplay.rounds
local Timer = WS.require("games.gameplay.rounds.timer")
local Text = WS.require("features.rounds.text")
local Hud = WS.require("ws.tf_hud")

local S = WS.STATE
local UNASSIGNED = WS.TEAM_UNASSIGNED

surface.CreateFont("Sandcastle.Hud.Announce", {
	font = "Roboto",
	size = 42,
	weight = 900,
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
local NOTICE_SECONDS = 5
local PANEL_BG = Color(0, 0, 0, 170)
local GOLD = Color(255, 210, 90)

local OVERTIME = "Game.Overtime"

local View = {
	announcement = nil,
	timeAdded = nil,
	notices = {},
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

-- The top of the team scores, the timer row under them.
local function ScoresTop(h)
	return math.floor(h * timerY:GetFloat())
end

-- The top of the team scores' slot, which the pregame panel takes.
function View:ScoresTop(h)
	return ScoresTop(h)
end

-- features.rounds.text's Pregame: before a game, while the pregame panel
-- has the top of the screen; nil in Gameplay mode.
function View:Pregame()
	return Text.Pregame({
		now = CurTime(),
		transitionEnd = GetGlobal2Float("ws_gamemode_transition_end", 0),
		waitingNeed = GetGlobal2Int("ws_gamemode_waiting_need", 0),
		halted = WS.GameplayStopped(),
	})
end

-- When tf_logic_koth's lock on the hill at a koth round's start ends (the
-- capture controller's ws_point_<rank>_locked and _unlock_time: the soonest
-- timed unlock of a locked point), or 0 once none waits to unlock.
function View:KothUnlockEnd()
	local now, soonest = CurTime(), 0
	for r = 1, GetGlobal2Int("ws_point_count", 0) do
		local at = GetGlobal2Float("ws_point_" .. r .. "_unlock_time", 0)
		if GetGlobal2Bool("ws_point_" .. r .. "_locked", false) and at > now and (soonest == 0 or at < soonest) then soonest = at end
	end
	return soonest
end

-- The top of the timer row, which other views line up under.
function View:TimerTop(h)
	return Hud.TimerTop(ScoresTop(h), Hud.Unit(h))
end

local Font, DrawPanel, Shadowed = WS.TFHud.Font, WS.TFHud.DrawPanel, WS.TFHud.Shadowed

local Part = WS.FeatureParts(getfenv(1), "rounds")
local LimitsPart = Part("cl_limits")
local DrawTimerBackground, DrawPie = WS.TFHud.DrawTimerBackground, WS.TFHud.DrawPie

-- Goal strings arrive as TF2 tokens ("#Goldrush_blue_setup_goal"), worded in
-- the player's language (WS.Localize). nil when unknown or empty.
function View:Localize(token)
	if token == "" then return nil end
	return WS.Localize(token)
end

-- The HUD timer's seconds left, paused or running.
local function TimerLeft()
	if GetGlobal2Bool("ws_timer_paused", true) then return GetGlobal2Float("ws_timer_time_left", 0) end
	return GetGlobal2Float("ws_timer_end_time", 0) - CurTime()
end

-- Game events ---------------------------------------------------------------------

-- The announcement line (ws/sh_announcer.lua), from the server or
-- another view; with an icon, drawn as TF2's notification card.
function View:Announce(text, team, icon)
	self.announcement = {
		text = text,
		team = team,
		icon = icon ~= "" and icon or nil,
		expires = CurTime() + ANNOUNCE_SECONDS,
	}
end

WS.Events.Listen("game_announcement", "ws_rounds_view", function(fields)
	if not WS.TeamRules.HearsBroadcast(fields.audience, false, LocalPlayer():Team()) then return end
	View:Announce(fields.text, fields.team, fields.icon)
	-- a card (an admin's notice) is kept in the console too
	if fields.icon ~= "" then MsgC(WS.TeamColor[fields.team] or color_white, "[Sandcastle] " .. fields.text .. "\n") end
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
-- (ws/sh_announcer.lua), as "+time" beside the timer.
WS.Events.Listen("game_points_awarded", "ws_rounds_view", function(fields)
	View.pointsAwarded = {
		text = "+" .. fields.points,
		team = fields.team,
		expires = CurTime() + TIME_ADDED_SECONDS,
	}
end)

-- The map cleaned up, or a new stage on the kept map (sh.lua): the bodies
-- and blood go.
WS.Events.Listen("game_round_gore_cleared", "ws_rounds_view", function()
	game.RemoveRagdolls()
	RunConsoleCommand("r_cleardecals")
end)

-- The timer's "+time" beside the clock (sh.lua).
WS.Events.Listen("game_teamplay_timer_time_added", "ws_rounds_view", function(fields)
	if fields.seconds_added == 0 then return end
	View.timeAdded = {
		text = Text.TimeAdded(fields.seconds_added),
		team = fields.team,
		expires = CurTime() + TIME_ADDED_SECONDS,
	}
end)

-- The timer -----------------------------------------------------------------------

-- features.rounds.text decides the clock: none before a game (the pregame
-- panel shows the wait and the countdown, as TF2's tournament panel), else
-- the round's timer while the rounds run; the koth HUD draws its own clocks,
-- with the hill's lock at the round's start counted down under them.
function View:DrawTimer(w, h)
	local koth = GetGlobal2Int("ws_round_hud_type", Rounds.HUD_NONE) == Rounds.HUD_KOTH
	local display = Text.TimerDisplay({
		now = CurTime(),
		transitionEnd = GetGlobal2Float("ws_gamemode_transition_end", 0),
		shown = GetGlobal2Bool("ws_timer_shown", false),
		halted = WS.GameplayStopped(),
		koth = koth,
		kothUnlockEnd = koth and self:KothUnlockEnd() or 0,
		preround = WS.State() == S.PREROUND,
		setup = GetGlobal2Bool("ws_timer_in_setup", false),
		overtime = GetGlobal2Bool("ws_round_overtime", false),
		gameOverEnd = GetGlobal2Float("ws_game_over_end", 0),
		-- the arena feature's: its round runs in STALEMATE while the point waits to unlock
		capUnlockEnd = WS.State() == S.STALEMATE and GetGlobal2Float("ws_arena_cap_enable_time", 0) or 0,
		setupEnd = GetGlobal2Float("ws_arena_setup_end", 0),
		matchEnd = GetGlobal2Float("ws_match_time_end", 0),
		waitingNeed = GetGlobal2Int("ws_gamemode_waiting_need", 0),
		left = TimerLeft(),
	})
	if not display then return end
	local unit = Hud.Unit(h)
	local top = self:TimerTop(h)
	local underClocks = koth and display.kind == Text.DISPLAY_SETUP
	local panel = Hud.TimerPanel(w / 2, underClocks and Hud.KothSetupTop(top, unit) or top, unit)
	DrawTimerBackground(panel, WS.TeamOf(LocalPlayer()))
	-- only a round's timer has a full length for the pie to run against
	local full = display.kind == Text.DISPLAY_ROUND and GetGlobal2Float("ws_timer_max_length", 0) or 0
	DrawPie(panel.pie, Hud.TimerElapsed(display.left, full))
	Shadowed(Clock(display.left), Font(Hud.FONT_BUILD, Hud.TIMER_FONT_TALL, unit), panel.value.x, panel.value.y, TEXT_ALIGN_CENTER)
	local label = display.label
	if label then
		DrawPanel(Hud.TIMER_LABEL_BORDER, panel.label.box, unit)
		local face = label == Text.LABEL_OVERTIME and Hud.FONT_BUILD or Hud.FONT_SECONDARY
		Shadowed(label, Font(face, Hud.TIMER_LABEL_FONT_TALL, unit), panel.label.x, panel.label.y, TEXT_ALIGN_CENTER)
	end
	local added = self.timeAdded
	if display.kind == Text.DISPLAY_ROUND and added and CurTime() < added.expires then
		Shadowed(added.text, Font(Hud.FONT_BUILD, Hud.TIMER_FONT_TALL, unit), panel.bg.x + panel.bg.w + 4 * unit, panel.value.y,
			TEXT_ALIGN_LEFT, WS.TeamColor[added.team])
	end
end

-- A team's score: BLU's box left of the centre, RED's right, above the
-- timer row, once a game is on (the pregame panel has their slot before);
-- an admin's "+points" beside its box. The win screens hide them
-- (game.match.team_scores), showing the scores themselves.
function View:DrawScore(t, w, h)
	if self:Pregame() then return end
	local unit = Hud.Unit(h)
	local box = Hud.ScoreBoxes(w / 2, ScoresTop(h), unit)[t]
	local font = Font(Hud.FONT_BUILD, Hud.SCORE_FONT_TALL, unit)
	DrawPanel(Hud.ScoreImage(t), box, unit)
	Shadowed(tostring(team.GetScore(t)), font, box.x + box.w / 2, box.y + box.h / 2, TEXT_ALIGN_CENTER)
	local awarded = self.pointsAwarded
	if awarded and awarded.team == t and CurTime() < awarded.expires then
		local blue = t == WS.TEAM_BLUE
		Shadowed(awarded.text, font, blue and box.x - 4 * unit or box.x + box.w + 4 * unit, box.y + box.h / 2,
			blue and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT, WS.TeamColor[t])
	end
end

-- Countdowns and the announcement line -------------------------------------------------

-- TF2's notification card (base_notification.res, hudlayout.res's
-- NotificationPanel), in HUD units of a 480-tall screen: the team's score
-- panel behind, the icon at the left, the text after it, the card as wide
-- as its text, centred CARD_Y down the screen.
local CARD_Y, CARD_TALL, CARD_ICON, CARD_ICON_X, CARD_ICON_Y, CARD_TEXT_X, CARD_PAD = 300, 44, 20, 7, 9, 30, 10
local CARD_FONT, CARD_FONT_TALL = "Sandcastle.Hud.Card", 13
local CARD_BACKGROUND = {
	[WS.TEAM_RED] = Material("hud/score_panel_red_bg"),
	[WS.TEAM_BLUE] = Material("hud/score_panel_blue_bg"),
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
	draw.SimpleTextOutlined(a.text, "Sandcastle.Hud.Announce", w / 2, h * 0.25, WS.TeamColor[a.team] or color_white,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

-- The round panel ------------------------------------------------------------------

local function ShowGoal(state)
	return state == S.PREROUND or state == S.RND_RUNNING or GetGlobal2Bool("ws_round_in_setup", false)
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
	local stages = GetGlobal2Int("ws_mini_round_count", 0)
	if stages > 1 then
		Line(string.format("Stage %d of %d", GetGlobal2Int("ws_mini_round_stage", 0), stages), GOLD)
	end
	local myTeam = WS.TeamOf(LocalPlayer())
	if myTeam ~= UNASSIGNED and ShowGoal(WS.State()) then
		local goal = self:Localize(GetGlobal2String("ws_round_goal_" .. myTeam, ""))
		if goal then Line(goal, WS.TeamColor[myTeam]) end
	end
	if #lines == 0 then return end

	surface.SetFont("Sandcastle.Rounds.Small")
	local width = 0
	for _, line in ipairs(lines) do width = math.max(width, (surface.GetTextSize(line.text))) end
	draw.RoundedBox(6, x, y, width + 16, #lines * 20 + 8, PANEL_BG)
	for i, line in ipairs(lines) do
		draw.SimpleText(line.text, "Sandcastle.Rounds.Small", x + 8, y + 4 + (i - 1) * 20, line.color)
	end
end

-- Centre panels --------------------------------------------------------------------

-- TF2's win panel (cooler-hud's winpanel.res): the teams' scores in their
-- boxes, then the border in the winner's colour (brown for none) with the
-- title and up to two rows, the reason and the details.
local function DrawCentrePanel(w, h, title, winner, rows)
	local unit = Hud.Unit(h)
	local panel = Hud.WinPanel(w, h, unit)
	local scoreFont, nameFont = Font(Hud.FONT_BUILD, Hud.WIN_SCORE_FONT_TALL, unit), Font(Hud.FONT_BUILD, Hud.WIN_NAME_FONT_TALL, unit)
	for t, box in pairs(panel.boxes) do
		DrawPanel(Hud.ScoreImage(t), box, unit)
		local blue = t == WS.TEAM_BLUE
		local score, name = panel.scores[t], panel.names[t]
		Shadowed(tostring(team.GetScore(t)), scoreFont, score.x, score.y, blue and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT)
		Shadowed(WS.TeamName[t], nameFont, name.x, name.y, blue and TEXT_ALIGN_LEFT or TEXT_ALIGN_RIGHT)
	end
	DrawPanel(Hud.PanelImage(winner), panel.border, unit)
	Shadowed(title, nameFont, panel.title.x, panel.title.y, TEXT_ALIGN_CENTER)
	local textFont = Font(Hud.FONT_SECONDARY, Hud.WIN_TEXT_FONT_TALL, unit)
	local at = { panel.reason, panel.details }
	for i, row in ipairs(rows) do
		if at[i] then Shadowed(row, textFont, at[i].x, at[i].y, TEXT_ALIGN_CENTER) end
	end
end

function View:DrawWinPanel(w, h)
	local winner = GetGlobal2Int("ws_round_winner", UNASSIGNED)
	local panel = Text.WinPanel({
		winner = winner,
		reason = GetGlobal2Int("ws_round_win_reason", Rounds.WINREASON.NONE),
		fullRound = GetGlobal2Bool("ws_round_full_round", true),
		remaining = GetGlobal2Int("ws_rounds_remaining", 0),
		arena = GetGlobal2Bool("ws_round_arena", false), -- the arena feature's
		captures = GetGlobal2Int("ws_flag_caps_" .. winner, 0), -- the flag feature's tally
	})
	local rows = {}
	if panel.reason then rows[#rows + 1] = panel.reason end
	if panel.details then rows[#rows + 1] = panel.details end
	DrawCentrePanel(w, h, panel.title, winner, rows)
end

-- The match's end: who won it (Rounds.MatchWinner; a tied match goes to
-- sudden death instead), or a stalemate nobody won, and why it ended.
function View:DrawGameOver(w, h)
	local winner = GetGlobal2Int("ws_match_winner", Rounds.NOBODY_WON)
	local reason = { GetGlobal2String("ws_game_over_reason", "") }
	if winner == Rounds.NOBODY_WON then return DrawCentrePanel(w, h, "STALEMATE", UNASSIGNED, reason) end
	DrawCentrePanel(w, h, string.format("%s WINS THE MATCH!", WS.TeamName[winner]), winner, reason)
end

-- The round limits' panels (cl_limits.lua).
function View:DrawLimits(w, h)
	LimitsPart.Draw(w, h)
end

function View:DrawNotices(w, h)
	local y = math.floor(h * 0.08)
	local notices = self.notices
	for i = #notices, 1, -1 do
		if CurTime() > notices[i].expires then table.remove(notices, i) end
	end
	for i, n in ipairs(notices) do
		draw.SimpleTextOutlined(n.text, "Sandcastle.Rounds.Small", w - 16, y + (i - 1) * 20,
			WS.TeamColor[n.team] or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
	end
end

-- The HUD's game.match elements (WS.HUD), drawn while the rounds run, in
-- this order; each centre panel only in its state.
local function InState(state, draw)
	return function(w, h)
		if WS.State() == state then draw(View, w, h) end
	end
end

local MATCH = {
	{ "game.match.team_scores.blue_score", function(w, h) View:DrawScore(WS.TEAM_BLUE, w, h) end },
	{ "game.match.team_scores.red_score", function(w, h) View:DrawScore(WS.TEAM_RED, w, h) end },
	{ "game.match.timer", function(w, h) View:DrawTimer(w, h) end },
	{ "game.match.announcement", function(w, h) View:DrawAnnouncement(w, h) end },
	{ "game.match.round_panel", function(w, h) View:DrawRoundPanel(w, h) end },
	{ "game.match.limits", function(w, h) View:DrawLimits(w, h) end },
	{ "game.match.notices", function(w, h) View:DrawNotices(w, h) end },
	{ "game.match.win_panel", InState(S.TEAM_WIN, View.DrawWinPanel) },
	{ "game.match.game_over", InState(S.GAME_OVER, View.DrawGameOver) },
}

for i, element in ipairs(MATCH) do
	WS.HUD:Add(element[1], WS.HUD_ORDER.ROUND + i, element[2], WS.Active)
end

-- A win screen (the round's win panel, the match's end) shows the teams'
-- scores itself: while one is up, the small scores and KOTH's clocks go
-- (features.rounds.text's ShowsTeamBar).
local TEAM_BAR = { "game.match.team_scores", "game.match.team_clocks" }
local teamBarShown = true

local function WinScreenThink()
	local shown = Text.ShowsTeamBar(WS.State())
	if shown == teamBarShown then return end
	teamBarShown = shown
	for _, path in ipairs(TEAM_BAR) do
		if shown then WS.HUD:ShowElements(path) else WS.HUD:HideElements(path) end
	end
end

-- The announcer ----------------------------------------------------------------------

-- OnDataChanged: overtime beginning is announced once.
function View:OvertimeThink()
	local overtime = GetGlobal2Bool("ws_round_overtime", false)
	if overtime and not self.wasOvertime and not WS.GameplayStopped() then Play(OVERTIME) end
	self.wasOvertime = overtime
end

-- The HUD timer's countdown and siren; games.gameplay.rounds.timer says which
-- cue plays when.
function View:CountdownThink()
	if not GetGlobal2Bool("ws_timer_shown", false) then return end
	local setup = GetGlobal2Bool("ws_timer_in_setup", false)
	local paused = GetGlobal2Bool("ws_timer_paused", true)
	local speaks = Timer.Speaks({
		paused = paused,
		autoCountdown = GetGlobal2Bool("ws_timer_auto_countdown", true),
		halted = WS.GameplayStopped(),
		isHud = true,
		koth = GetGlobal2Int("ws_round_hud_type", Rounds.HUD_NONE) == Rounds.HUD_KOTH,
	})
	local left = TimerLeft()

	if Timer.StartsRound(self.wasSetup, setup) and speaks then
		Play(Timer.WarningSound(Timer.WARNING_TIME_START, false))
	end
	self.wasSetup = setup

	-- The warnings are re-armed whenever the timer's length changes.
	local serial = GetGlobal2Int("ws_timer_serial", 0)
	if serial ~= self.serial then
		self.serial = serial
		self.armed = Timer.ArmClientWarnings(left, setup)
	end
	if paused then return end

	local warning = Timer.NextClientWarning(self.armed, left, setup)
	if warning then
		self.armed[warning] = false
		if speaks then Play(Timer.WarningSound(warning, setup)) end
	end
end

-- The match's end (mp_chattime): everyone sees their player from behind,
-- the camera kept out of the walls, their weapon's first-person model hidden.
local THIRD_PERSON_DISTANCE = 100
local CAMERA_HULL = Vector(4, 4, 4)

local function GameOverView(ply)
	return WS.State() == S.GAME_OVER and IsValid(ply) and ply:Alive()
end

hook.Add("CalcView", "ws_rounds_game_over", function(ply, origin, angles, fov)
	if not GameOverView(ply) then return end
	local tr = util.TraceHull({
		start = origin,
		endpos = origin - angles:Forward() * THIRD_PERSON_DISTANCE,
		mins = -CAMERA_HULL,
		maxs = CAMERA_HULL,
		filter = ply,
		mask = MASK_SOLID_BRUSHONLY,
	})
	return { origin = tr.HitPos, angles = angles, fov = fov, drawviewer = true }
end)

hook.Add("PreDrawViewModel", "ws_rounds_game_over", function()
	if GameOverView(LocalPlayer()) then return true end
end)

hook.Add("Think", "ws_rounds_announcer", function()
	if not WS.Active() then return end
	WinScreenThink()
	View:OvertimeThink()
	View:CountdownThink()
end)

return View
