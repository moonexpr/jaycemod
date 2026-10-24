-- Part of the rounds view (cl.lua): the round limits' counters
-- (games.gameplay.rounds.limits), as TF2's Player Destruction panel, the
-- lowest of the objectives at the foot of the screen.
local Limits = WS.require("games.gameplay.rounds.limits")
local Rounds = gameplay.rounds
local Shadowed = WS.TFHud.Shadowed

-- The round limits ---------------------------------------------------------------------

-- TF2's Player Destruction panel (cooler-hud's
-- HudObjectivePlayerDestruction.res), in its 480-tall units: the
-- ProgressBarContainer, a 240x48 bar centred at the screen's foot, its
-- bottom 24 up (ScoreContainer c-200 r131, the bar 59 down in it); BLU's
-- fill (-2, 122 wide) growing from the middle out to the left and RED's
-- (120, 121 wide) to the right; each team's icon (FlagImageBlue/Red, 10x10)
-- 15 in from its outer end, 8 down; each count (Blue/RedScoreValueContainer's
-- Score, HudFontMediumBold) 15 in from BLU's end and 14 from RED's, its
-- middle 32.5 down; the limit on the "Playing to" tab (PlayingToBG
-- 150x38 at 26 down, PlayingTo in HudFontSmall centred 44 down). A panel
-- per limit, the next above.
local LIMIT_BAR_W, LIMIT_BAR_H, LIMIT_BAR_BOTTOM, LIMIT_STEP = 240, 48, 24, 52
local LIMIT_BLUE_FILL_X, LIMIT_BLUE_FILL_W, LIMIT_RED_FILL_X, LIMIT_RED_FILL_W = -2, 122, 120, 121
local LIMIT_ICON, LIMIT_ICON_Y, LIMIT_BLUE_ICON_X, LIMIT_RED_ICON_X = 10, 8, 15, 215
local LIMIT_BLUE_VALUE_X, LIMIT_RED_VALUE_X, LIMIT_VALUE_Y = 15, 14, 32.5 -- from each end, from the top
local LIMIT_TAB_W, LIMIT_TAB_H, LIMIT_TAB_Y, LIMIT_LABEL_Y = 150, 38, 26, 44
local LIMIT_VALUE_FONT, LIMIT_LABEL_FONT = "Sandcastle.Hud.LimitValue", "Sandcastle.Hud.LimitLabel"
local LIMIT_VALUE_TALL, LIMIT_LABEL_TALL = 24, 14
local LIMIT_OUTLINE = Material("hud/objectives_corepanel_bg")
local LIMIT_TAB = Material("hud/objectives_flagpanel_bg_playingto")
local LIMIT_FILL = {
	[WS.TEAM_BLUE] = { material = Material("hud/objectives_corepanel_meter_solid"), color = Color(84, 111, 127) },
	[WS.TEAM_RED] = { material = Material("hud/objectives_corepanel_meter_solid_right"), color = Color(171, 59, 59) },
}
local LIMIT_ICONS = {
	[Rounds.WINREASON.FRAGLIMIT] = Material("hud/hud_obj_status_kill_64"),
	[Rounds.WINREASON.CASHLIMIT] = Material("hud/mvm_cash"),
}
local limitFontsFor

local function LimitFonts(unit)
	if limitFontsFor == unit then return end
	surface.CreateFont(LIMIT_VALUE_FONT, { font = "TF2 Build", size = math.Round(LIMIT_VALUE_TALL * unit), weight = 500 })
	surface.CreateFont(LIMIT_LABEL_FONT, { font = "TF2 Secondary", size = math.Round(LIMIT_LABEL_TALL * unit), weight = 500 })
	limitFontsFor = unit
end

local function DrawLimitPanel(panel, x, y, unit)
	local blue, red = WS.TEAM_BLUE, WS.TEAM_RED
	-- each fill's image spans its panel; BLU's shows from the middle to the
	-- left, RED's from the middle to the right, as far as the team's share
	local blueShare, redShare = panel.fills[blue], panel.fills[red]
	local blueW, redW = LIMIT_BLUE_FILL_W * blueShare, LIMIT_RED_FILL_W * redShare
	surface.SetMaterial(LIMIT_FILL[blue].material)
	surface.SetDrawColor(LIMIT_FILL[blue].color)
	surface.DrawTexturedRectUV(x + (LIMIT_BLUE_FILL_X + LIMIT_BLUE_FILL_W - blueW) * unit, y, blueW * unit, LIMIT_BAR_H * unit,
		1 - blueShare, 0, 1, 1)
	surface.SetMaterial(LIMIT_FILL[red].material)
	surface.SetDrawColor(LIMIT_FILL[red].color)
	surface.DrawTexturedRectUV(x + LIMIT_RED_FILL_X * unit, y, redW * unit, LIMIT_BAR_H * unit, 0, 0, redShare, 1)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(LIMIT_OUTLINE)
	surface.DrawTexturedRect(x, y, LIMIT_BAR_W * unit, LIMIT_BAR_H * unit)
	surface.SetMaterial(LIMIT_ICONS[panel.reason])
	surface.DrawTexturedRect(x + LIMIT_BLUE_ICON_X * unit, y + LIMIT_ICON_Y * unit, LIMIT_ICON * unit, LIMIT_ICON * unit)
	surface.DrawTexturedRect(x + LIMIT_RED_ICON_X * unit, y + LIMIT_ICON_Y * unit, LIMIT_ICON * unit, LIMIT_ICON * unit)
	Shadowed(panel.values[blue], LIMIT_VALUE_FONT, x + LIMIT_BLUE_VALUE_X * unit, y + LIMIT_VALUE_Y * unit, TEXT_ALIGN_LEFT)
	Shadowed(panel.values[red], LIMIT_VALUE_FONT, x + (LIMIT_BAR_W - LIMIT_RED_VALUE_X) * unit, y + LIMIT_VALUE_Y * unit, TEXT_ALIGN_RIGHT)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(LIMIT_TAB)
	surface.DrawTexturedRect(x + (LIMIT_BAR_W - LIMIT_TAB_W) / 2 * unit, y + LIMIT_TAB_Y * unit, LIMIT_TAB_W * unit, LIMIT_TAB_H * unit)
	Shadowed(panel.label, LIMIT_LABEL_FONT, x + LIMIT_BAR_W / 2 * unit, y + LIMIT_LABEL_Y * unit, TEXT_ALIGN_CENTER)
end

local function Counts(key)
	return { [WS.TEAM_RED] = GetGlobal2Int(key .. WS.TEAM_RED, 0), [WS.TEAM_BLUE] = GetGlobal2Int(key .. WS.TEAM_BLUE, 0) }
end

-- The limits' panels shown: none on an MvM map, where the bomb's panel is
-- the only objective. For now the frags panel alone (operator, 2026-10-10):
-- nothing earns money yet, so the cash panel waits; the cash limit still
-- decides a round.
local function LimitPanels()
	if GetGlobal2Bool("ws_mvm", false) then return {} end
	return Limits.Panels({ frags = GetGlobal2Int("ws_round_fraglimit", 0), cash = 0 },
		Counts("ws_round_frags_"), Counts("ws_round_earned_"))
end

-- The objectives' stack (ws.tf_hud's ObjectiveLifts): the lowest, from the
-- "Playing to" tab hanging under the lowest bar to the top bar's top.
WS.TFHud.ObjectiveSpan("frags", function()
	local n = #LimitPanels()
	if n == 0 then return nil end
	return {
		bottom = LIMIT_BAR_BOTTOM - (LIMIT_TAB_Y + LIMIT_TAB_H - LIMIT_BAR_H),
		top = LIMIT_BAR_BOTTOM + LIMIT_BAR_H + (n - 1) * LIMIT_STEP,
	}
end)

local function Draw(w, h)
	local panels = LimitPanels()
	if #panels == 0 then return end
	local unit = h / 480
	LimitFonts(unit)
	local x = w / 2 - LIMIT_BAR_W / 2 * unit
	for i, panel in ipairs(panels) do
		local y = h - (LIMIT_BAR_BOTTOM + LIMIT_BAR_H + (i - 1) * LIMIT_STEP) * unit
		DrawLimitPanel(panel, x, y, unit)
	end
end

return { Draw = Draw }
