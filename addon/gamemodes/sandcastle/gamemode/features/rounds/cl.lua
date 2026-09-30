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
-- the timer is pushed down by a fraction of the screen height.
local timerY = CreateClientConVar("cl_hud_round_timer_y", "0.08", true, false,
	"Round timer top, as a fraction of screen height (clears display notches).")

local TEAM_BITS = 2
local SECONDS_BITS = 32
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
	localized = {},
	english = nil,
	stalemateSince = 0,
	lastState = nil,
	serial = nil,
	wasSetup = nil,
	wasOvertime = false,
	armed = {},
}

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

-- Goal strings arrive as TF2 tokens ("#Goldrush_blue_setup_goal"), whose text
-- is in the mounted TF2's resource/tf_english.txt. nil when unknown or empty.
function View:Localize(token)
	if token == "" then return nil end
	if self.localized[token] == nil then
		self.english = self.english or file.Read("resource/tf_english.txt", "tf") or ""
		self.localized[token] = Text.Localize(self.english, token) or false
	end
	return self.localized[token] or nil
end

-- The HUD timer's seconds left, paused or running.
local function TimerLeft()
	if GetGlobal2Bool("wetsand_timer_paused", true) then return GetGlobal2Float("wetsand_timer_time_left", 0) end
	return GetGlobal2Float("wetsand_timer_end_time", 0) - CurTime()
end

-- Net messages ---------------------------------------------------------------------

net.Receive("wetsand_pa_announce_text", function()
	View.announcement = {
		text = net.ReadString(),
		team = net.ReadUInt(TEAM_BITS),
		expires = CurTime() + ANNOUNCE_SECONDS,
	}
end)

net.Receive("wetsand_timer_time_added", function()
	local t = net.ReadUInt(TEAM_BITS)
	local seconds = net.ReadInt(SECONDS_BITS)
	if seconds == 0 then return end
	View.timeAdded = {
		text = Text.TimeAdded(seconds),
		team = t,
		expires = CurTime() + TIME_ADDED_SECONDS,
	}
end)

net.Receive("wetsand_round_notice_show", function()
	View.notices[#View.notices + 1] = {
		text = net.ReadString(),
		team = net.ReadUInt(TEAM_BITS),
		expires = CurTime() + NOTICE_SECONDS,
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

function View:DrawAnnouncement(w, h)
	local a = self.announcement
	if not a or CurTime() > a.expires then return end
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

function View:DrawGameOver(w, h)
	DrawCentrePanel(w, h, "GAME OVER", GOLD, { GetGlobal2String("wetsand_game_over_reason", "") })
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
