-- The round HUD, drawn through SandcastleHUDPaint: a small panel with the
-- stage of a multi-stage map, the team scores and the local team's goal
-- (CTFGameRules::ShouldShowTeamGoal); TF2's win panel (tf_hud_winpanel.cpp);
-- the sudden death panel (tf_hud_stalemate.cpp); the game-over reason; and
-- round notices such as a blocked capture.
local L = WETSAND.RoundsLib
local S = WETSAND.STATE

surface.CreateFont("Sandcastle.Rounds.Title", { font = "Roboto", size = 34, weight = 900 })
surface.CreateFont("Sandcastle.Rounds.Text", { font = "Roboto", size = 18, weight = 600 })
surface.CreateFont("Sandcastle.Rounds.Small", { font = "Roboto", size = 15, weight = 600 })

local STALEMATE_PANEL_SECONDS = 15
local NOTICE_SECONDS = 5
local PANEL_BG = Color(0, 0, 0, 170)
local GOLD = Color(255, 210, 90)

-- Localization -----------------------------------------------------------------------

-- Goal strings arrive as TF2 tokens ("#Goldrush_blue_setup_goal"), whose text
-- is in the mounted TF2's resource/tf_english.txt.
local english
local localized = {}

local function Localize(token)
	if token == "" then return nil end
	if localized[token] == nil then
		english = english or file.Read("resource/tf_english.txt", "tf") or ""
		localized[token] = L.Localize(english, token) or false
	end
	return localized[token] or nil
end

-- Round panel ------------------------------------------------------------------------------

local function ShowGoal(state)
	return state == S.PREROUND or state == S.RND_RUNNING or GetGlobal2Bool("wetsand_round_in_setup", false)
end

local function DrawRoundPanel(w, h)
	local x, y = 16, math.floor(h * 0.08)
	local lines = {}
	local stages = GetGlobal2Int("wetsand_mini_round_count", 0)
	if stages > 1 then
		lines[#lines + 1] = { string.format("Stage %d of %d", GetGlobal2Int("wetsand_mini_round_stage", 0), stages), GOLD }
	end
	lines[#lines + 1] = {
		string.format("RED %d  :  %d BLU", team.GetScore(WETSAND.TEAM_RED), team.GetScore(WETSAND.TEAM_BLUE)), color_white,
	}
	local myTeam = WETSAND.TeamOf(LocalPlayer())
	if myTeam ~= WETSAND.TEAM_UNASSIGNED and ShowGoal(WETSAND.State()) then
		local goal = Localize(GetGlobal2String("wetsand_round_goal_" .. myTeam, ""))
		if goal then lines[#lines + 1] = { goal, WETSAND.TeamColor[myTeam] } end
	end

	surface.SetFont("Sandcastle.Rounds.Small")
	local width = 0
	for _, line in ipairs(lines) do width = math.max(width, (surface.GetTextSize(line[1]))) end
	draw.RoundedBox(6, x, y, width + 16, #lines * 20 + 8, PANEL_BG)
	for i, line in ipairs(lines) do
		draw.SimpleText(line[1], "Sandcastle.Rounds.Small", x + 8, y + 4 + (i - 1) * 20, line[2])
	end
end

-- Centre panels -----------------------------------------------------------------------------

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

local function DrawWinPanel(w, h)
	local panel = L.WinPanel({
		winner = GetGlobal2Int("wetsand_round_winner", WETSAND.TEAM_UNASSIGNED),
		reason = GetGlobal2Int("wetsand_round_win_reason", 0),
		fullRound = GetGlobal2Bool("wetsand_round_full_round", true),
		remaining = GetGlobal2Int("wetsand_rounds_remaining", 0),
	})
	local rows = {}
	if panel.reason then rows[#rows + 1] = panel.reason end
	if panel.details then rows[#rows + 1] = panel.details end
	DrawCentrePanel(w, h, panel.title, WETSAND.TeamColor[GetGlobal2Int("wetsand_round_winner", WETSAND.TEAM_UNASSIGNED)] or color_white, rows)
end

local stalemateSince
local function DrawStalematePanel(w, h)
	if CurTime() - stalemateSince > STALEMATE_PANEL_SECONDS then return end
	local panel = L.StalematePanel(GetGlobal2Int("wetsand_stalemate_reason", L.STALEMATE.TIMER))
	DrawCentrePanel(w, h, panel.title, GOLD, { panel.reason })
end

local function DrawGameOver(w, h)
	DrawCentrePanel(w, h, "GAME OVER", GOLD, { GetGlobal2String("wetsand_game_over_reason", "") })
end

-- Notices ------------------------------------------------------------------------------------

local notices = {}

net.Receive("wetsand_round_notice_show", function()
	notices[#notices + 1] = { text = net.ReadString(), team = net.ReadUInt(2), expires = CurTime() + NOTICE_SECONDS }
end)

local function DrawNotices(w, h)
	local y = math.floor(h * 0.08)
	for i = #notices, 1, -1 do
		if CurTime() > notices[i].expires then table.remove(notices, i) end
	end
	for i, n in ipairs(notices) do
		draw.SimpleTextOutlined(n.text, "Sandcastle.Rounds.Small", w - 16, y + (i - 1) * 20, WETSAND.TeamColor[n.team] or color_white,
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
	end
end

-- Painting -----------------------------------------------------------------------------------

local lastState
hook.Add("SandcastleHUDPaint", "wetsand_rounds", function(w, h)
	local state = WETSAND.State()
	if state == S.STALEMATE and lastState ~= S.STALEMATE then stalemateSince = CurTime() end
	lastState = state

	DrawRoundPanel(w, h)
	DrawNotices(w, h)
	if state == S.TEAM_WIN then
		DrawWinPanel(w, h)
	elseif state == S.STALEMATE then
		DrawStalematePanel(w, h)
	elseif state == S.GAME_OVER then
		DrawGameOver(w, h)
	end
end)
