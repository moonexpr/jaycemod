-- TF2's HUD as cooler-hud v2.6 lays it out (tf/custom/cooler-hud-v2.6's
-- resource/ui and scripts/hudlayout.res), in TF2's proportional units of a
-- 480-tall screen (Unit): scalable images (ScalableImagePanel and the
-- scalable_image borders, nine pieces), the team scores centred above the
-- round timer, the timer panel (HudObjectiveTimePanel.res) and its progress
-- pie, KOTH's clocks, the respawn label (spectator.res), the win panel
-- (winpanel.res, at hudlayout.res's WinPanel) and the boss meter. Rects are
-- { x, y, w, h } in pixels; text anchors { x, y } are where a centred line's
-- middle goes.
local abs, cos, floor, ipairs, max, min, pi, sin = math.abs, math.cos, math.floor, ipairs, math.max, math.min, math.pi, math.sin
module(...)

local RED, BLUE = 2, 3

-- ClientScheme.res's TanLight, every label's colour.
TAN_LIGHT = { r = 235, g = 226, b = 202 }

-- TF2's fonts by their scheme names: "TF2" is TF2 Build.
FONT_BUILD, FONT_SECONDARY, FONT_SMALL = "TF2 Build", "TF2 Secondary", "Verdana"

function Unit(screenTall) return screenTall / 480 end

local function Rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

-- The nine pieces of an image srcW x srcH whose corners are srcCorner
-- pixels, drawn into the rect with corners drawCorner pixels (shrunk to
-- fit a rect smaller than two corners): each { x, y, w, h, u0, v0, u1, v1 },
-- row by row from the top left. No seams: the pieces' edges are rounded to
-- whole pixels, so neighbours meet without a gap, and each samples half a
-- texel inside its own part of the image, so filtering never blends in its
-- neighbour's.
local function Round(v) return floor(v + 0.5) end

function Slices(x, y, w, h, srcW, srcH, srcCorner, drawCorner)
	local cx, cy = min(drawCorner, w / 2), min(drawCorner, h / 2)
	local cu, cv = srcCorner / srcW, srcCorner / srcH
	local hu, hv = 0.5 / srcW, 0.5 / srcH
	local xs = { Round(x), Round(x + cx), Round(x + w - cx), Round(x + w) }
	local ys = { Round(y), Round(y + cy), Round(y + h - cy), Round(y + h) }
	local us = { { hu, cu - hu }, { cu + hu, 1 - cu - hu }, { 1 - cu + hu, 1 - hu } }
	local vs = { { hv, cv - hv }, { cv + hv, 1 - cv - hv }, { 1 - cv + hv, 1 - hv } }
	local pieces = {}
	for row = 1, 3 do
		for col = 1, 3 do
			pieces[#pieces + 1] = {
				x = xs[col],
				y = ys[row],
				w = xs[col + 1] - xs[col],
				h = ys[row + 1] - ys[row],
				u0 = us[col][1],
				v0 = vs[row][1],
				u1 = us[col][2],
				v1 = vs[row][2],
			}
		end
	end
	return pieces
end

-- The color_panel images' corners (ClientScheme.res's TFFatLineBorder*),
-- and how big they draw.
PANEL_SRC_CORNER, PANEL_DRAW_CORNER = 23, 5

local PANEL_IMAGES = {
	[RED] = "hud/color_panel_red",
	[BLUE] = "hud/color_panel_blu",
}
-- TFFatLineBorderRedBG and its kin: a team's panel, brown for no team.
function PanelImage(team) return PANEL_IMAGES[team] or "hud/color_panel_brown" end
-- TFFatLineBorder*BGMoreOpaque: a team's score box.
function ScoreImage(team) return (PANEL_IMAGES[team] or "hud/color_panel_brown") .. "_more_opaque" end

-- The team scores ----------------------------------------------------------------

-- Two boxes side by side, BLU's left of the centre and RED's right.
SCORE_W, SCORE_H, SCORE_GAP = 40, 20, 4
SCORE_FONT_TALL = 16
-- Between the scores and the timer.
SCORE_BELOW = 2

function ScoreBoxes(centre, top, unit)
	local w, h, gap = SCORE_W * unit, SCORE_H * unit, SCORE_GAP * unit
	return {
		[BLUE] = Rect(centre - gap / 2 - w, top, w, h),
		[RED] = Rect(centre + gap / 2, top, w, h),
	}
end

-- The top of the timer row (the round timer, or KOTH's clocks), under the
-- scores that start at top.
function TimerTop(top, unit)
	return top + (SCORE_H + SCORE_BELOW) * unit
end

-- The timer panel -----------------------------------------------------------------

-- HudObjectiveTimePanel.res in cooler-hud's ObjectiveStatusTimePanel (c-55,
-- 110 wide), from the panel's left and TimePanelBG's top (9 down in it):
-- TimePanelBG 78x33 at 16, BetterOutline over it; TimePanelValue
-- (HudFontMediumSmall: TF2 Build 18) 45x31 at 22,2; TimePanelProgressBar
-- 20x20 at 67,6; the labels (SetupLabel, OvertimeLabel and their kin) 90x19
-- at 10,34 in TFFatLineBorder, in HudFontSmallest (TF2 Secondary 11) and
-- the overtime and sudden death ones in HudFontSmallestBold (TF2 Build 11).
TIMER_PANEL_W, TIMER_BG_X = 110, 16
TIMER_W, TIMER_H = 78, 33
TIMER_VALUE_X, TIMER_VALUE_Y, TIMER_VALUE_W, TIMER_VALUE_TALL, TIMER_FONT_TALL = 22, 2, 45, 31, 18
TIMER_PIE_X, TIMER_PIE_Y, TIMER_PIE_SIZE = 67, 6, 20
TIMER_LABEL_X, TIMER_LABEL_Y, TIMER_LABEL_W, TIMER_LABEL_TALL, TIMER_LABEL_FONT_TALL = 10, 34, 90, 19, 11
TIMER_LABEL_BORDER = "hud/color_panel_brown"
TIMER_PIE = "hud/objectives_timepanel_progressbar"
-- cooler-hud's objectives_timepanel_bg_outline: TF2's clock_area_mask as a
-- distance field, outlined light tan with a soft edge (UnlitGeneric's keys).
TIMER_OUTLINE = {
	["$translucent"] = 1,
	["$basetexture"] = "hud/null_texture",
	["$detail"] = "hud/clock_area_mask",
	["$detailscale"] = 1,
	["$detailblendmode"] = 8,
	["$distancealphafromdetail"] = 1,
	["$softedges"] = 1,
	["$edgesoftnessstart"] = 0.4,
	["$edgesoftnessend"] = 0.2,
	["$scaleedgesoftnessbasedonscreenres"] = 1,
	["$outline"] = 1,
	["$outlinecolor"] = "[0.7 0.7 0.5]",
	["$outlinestart0"] = 1.5,
	["$outlinestart1"] = 1.7,
	["$outlineend0"] = 0.5,
	["$outlineend1"] = 0.7,
	["$scaleoutlinesoftnessbasedonscreenres"] = 1,
}

function TimerPanel(centre, top, unit)
	local left = centre - TIMER_PANEL_W / 2 * unit
	return {
		bg = Rect(left + TIMER_BG_X * unit, top, TIMER_W * unit, TIMER_H * unit),
		value = {
			x = left + (TIMER_VALUE_X + TIMER_VALUE_W / 2) * unit,
			y = top + (TIMER_VALUE_Y + TIMER_VALUE_TALL / 2) * unit,
		},
		pie = Rect(left + TIMER_PIE_X * unit, top + TIMER_PIE_Y * unit, TIMER_PIE_SIZE * unit, TIMER_PIE_SIZE * unit),
		label = {
			box = Rect(left + TIMER_LABEL_X * unit, top + TIMER_LABEL_Y * unit, TIMER_LABEL_W * unit, TIMER_LABEL_TALL * unit),
			x = centre,
			y = top + (TIMER_LABEL_Y + TIMER_LABEL_TALL / 2) * unit,
		},
	}
end

-- The progress pie (CTFProgressBar) ------------------------------------------------

-- ClientScheme.res's TimerProgress colours and the panel's percent_warning.
PIE_ACTIVE = { r = 251, g = 235, b = 202 }
PIE_INACTIVE = { r = 52, g = 48, b = 45 }
PIE_WARNING = { r = 240, g = 30, b = 30 }
PIE_PERCENT_WARNING = 0.75

-- CTFHudTimeStatus::OnThink: the share of the timer's full length gone, 0
-- to 1; none for a timer without one.
function TimerElapsed(left, fullLength)
	if fullLength <= 0 then return 0 end
	return min(1, max(0, (fullLength - left) / fullLength))
end

function PieColor(elapsed)
	return elapsed < PIE_PERCENT_WARNING and PIE_ACTIVE or PIE_WARNING
end

-- Where a ray from the square's middle at angle (clockwise from up) leaves
-- the unit square.
local function OnSquare(angle)
	local dx, dy = sin(angle), -cos(angle)
	local t = 0.5 / max(abs(dx), abs(dy))
	return { x = 0.5 + dx * t, y = 0.5 + dy * t }
end

local CORNERS = { { x = 1, y = 0 }, { x = 1, y = 1 }, { x = 0, y = 1 }, { x = 0, y = 0 } }

-- CTFProgressBar::Paint's active part: the time left as a wedge of the unit
-- square, from twelve o'clock clockwise, cut to the square; a fan from its
-- first point (the middle), each point { x, y } its own texture coordinates
-- too. Empty with nothing left.
function PieWedge(left)
	if left <= 0 then return {} end
	local wedge = { { x = 0.5, y = 0.5 }, { x = 0.5, y = 0 } }
	local stop = 2 * pi * min(left, 1)
	for i, corner in ipairs(CORNERS) do
		if (2 * i - 1) * pi / 4 > stop then break end
		wedge[#wedge + 1] = corner
	end
	local last, final = wedge[#wedge], OnSquare(stop)
	if abs(final.x - last.x) + abs(final.y - last.y) > 1e-9 then wedge[#wedge + 1] = final end
	return wedge
end

-- KOTH's clocks ----------------------------------------------------------------------

-- hudlayout.res's HudKothTimeStatus (c-100, 200 wide) and
-- hudobjectivekothtimepanel.res: BlueTimer at 0 and RedTimer at 90, each a
-- time panel 110 wide, so their backgrounds are at c-84 and c+6; the
-- ActiveTimerBG (objectives_timepanel_active_bg) over the running one
-- (blue_active_xpos 16, red_active_xpos 106).
KOTH_W, KOTH_BLUE_X, KOTH_RED_X = 200, 0, 90
KOTH_ACTIVE_FRAME = "hud/objectives_timepanel_active_bg"

function KothPanels(centre, top, unit)
	local left = centre - KOTH_W / 2 * unit
	local function At(x) return TimerPanel(left + (x + TIMER_PANEL_W / 2) * unit, top, unit) end
	return { [BLUE] = At(KOTH_BLUE_X), [RED] = At(KOTH_RED_X) }
end

-- The top of the timer panel counting down the hill's lock at a koth
-- round's start (Sandcastle's own: TF2 shows it only on the point's icon),
-- KOTH_SETUP_GAP under the clocks' backgrounds, over the label row an
-- overtime box takes (no overtime runs in setup).
KOTH_SETUP_GAP = 3

function KothSetupTop(top, unit)
	return top + (TIMER_H + KOTH_SETUP_GAP) * unit
end

-- The objective HUDs at the foot of the screen, each laid out from it as
-- its .res places it, stack when several show: bottom first, frags (the
-- round limits' panels), the bomb defusal's panel (on its maps the points'
-- and flags' panels are hidden, above it), payload's track, the control
-- points' icons, then the flag or MvM's bomb on top. spans: by key, each shown one's content
-- { bottom, top }, in units above the screen's foot where it would sit
-- alone. Returns by key how many units each is lifted: just clear of the
-- one below it, OBJECTIVE_GAP apart; the lowest, never.
OBJECTIVE_ORDER = { "frags", "defuse", "payload", "points", "flags" }
OBJECTIVE_GAP = 2

function ObjectiveLifts(spans)
	local lifts, stackTop = {}, nil
	for _, key in ipairs(OBJECTIVE_ORDER) do
		local span = spans[key]
		if span then
			local lift = stackTop and max(0, stackTop + OBJECTIVE_GAP - span.bottom) or 0
			lifts[key] = lift
			stackTop = span.top + lift
		end
	end
	return lifts
end

function KothActiveFrame(panels, team)
	return panels[team].bg
end

-- The respawn label ----------------------------------------------------------------

-- cooler-hud's spectator.res ReinforcementsLabel: -8, r91, 292x28, its text
-- centred in HudFontMediumSmallSecondary (TF2 Secondary 18), in
-- TFThinLineBorder (tournament_panel_brown, corners 23 drawn 8).
RESPAWN_X, RESPAWN_BOTTOM, RESPAWN_W, RESPAWN_H, RESPAWN_FONT_TALL = -8, 91, 292, 28, 18
RESPAWN_BORDER, RESPAWN_SRC_CORNER, RESPAWN_DRAW_CORNER = "hud/tournament_panel_brown", 23, 8

function RespawnLabel(screenTall, unit)
	return Rect(RESPAWN_X * unit, screenTall - RESPAWN_BOTTOM * unit, RESPAWN_W * unit, RESPAWN_H * unit)
end

-- What moved the respawn (games.gameplay.respawn_modifiers), a line a
-- reason in a panel of its own REASONS_GAP under the label, as wide and as
-- far off the screen's left, in TFFatLineBorder's brown: each line's
-- seconds right-aligned in a column REASON_SECONDS_W wide from the screen's
-- edge, its words REASON_WORDS_GAP after. REASON_TALL lines, so the most a
-- respawn can have (five reasons and the limited total) fit in the 63 units
-- under the label.
REASONS_PANEL = "hud/color_panel_brown"
REASONS_GAP, REASONS_PAD, REASON_TALL = 2, 3, 9
REASON_SECONDS_W, REASON_WORDS_GAP = 28, 5

-- count lines -> { panel, lines }: the panel's rect and each line's
-- { seconds, words } anchors, the seconds' right edge and the words' left
-- edge, at the line's middle.
function RespawnReasons(screenTall, unit, count)
	local label = RespawnLabel(screenTall, unit)
	local top = label.y + label.h + REASONS_GAP * unit
	local panel = Rect(label.x, top, label.w, (2 * REASONS_PAD + count * REASON_TALL) * unit)
	local edge = label.x - RESPAWN_X * unit -- the screen's left edge, where the label hangs off it
	local secondsX = edge + (REASONS_PAD + REASON_SECONDS_W) * unit
	local lines = {}
	for i = 1, count do
		local y = top + (REASONS_PAD + (i - 0.5) * REASON_TALL) * unit
		lines[i] = {
			seconds = { x = secondsX, y = y },
			words = { x = secondsX + REASON_WORDS_GAP * unit, y = y },
		}
	end
	return { panel = panel, lines = lines }
end

-- CTFHudTimeStatus::SetTeamBackground: the local team's, BLU's for anyone else.
function TimerBackground(team)
	return team == RED and "hud/objectives_timepanel_red_bg" or "hud/objectives_timepanel_blue_bg"
end

-- The win panel -------------------------------------------------------------------

-- Cooler-hud's hudlayout.res WinPanel: 300 wide at c-150, c-10 (10 above
-- the screen's middle). Its winpanel.res TeamScoresPanel (-41,13) puts the
-- score boxes (140x39, TFFatLineBorder*BGMoreOpaque) at 9 and 151, 29 down;
-- the scores (ScoreboardTeamScore, TF2 Build 52, north-aligned 13 down) end
-- at 139 and start at 161, against the panel's middle; the team names
-- (HudFontMediumBold, TF2 Build 24) at 17 and up to 283, their middle 48
-- down; WinPanelBGBorder at 69 down, 282 wide; the winning team
-- (HudFontMediumBold) centred 84 down, the reason (ScoreboardVerySmallBold)
-- 102 and the details (ScoreboardVerySmall, TF2 Secondary 8) 110. Without
-- TF2's top players the border ends 4 under the details label.
WIN_W, WIN_Y_FROM_MIDDLE = 300, -10
WIN_BOX_W, WIN_BOX_H, WIN_BOX_Y, WIN_BLUE_BOX_X, WIN_RED_BOX_X = 140, 39, 29, 9, 151
WIN_SCORE_BLUE_X, WIN_SCORE_RED_X, WIN_SCORE_Y, WIN_SCORE_FONT_TALL = 139, 161, 39, 52
WIN_NAME_BLUE_X, WIN_NAME_RED_X, WIN_NAME_Y, WIN_NAME_FONT_TALL = 17, 283, 48, 24
WIN_BORDER_Y, WIN_BORDER_W, WIN_BORDER_H = 69, 282, 55
WIN_TITLE_Y, WIN_REASON_Y, WIN_DETAILS_Y = 84, 102, 110
WIN_TEXT_FONT_TALL = 8

function WinPanel(screenW, screenH, unit)
	local left, top = screenW / 2 - WIN_W / 2 * unit, screenH / 2 + WIN_Y_FROM_MIDDLE * unit
	local centre = screenW / 2
	local function At(x, y) return { x = left + x * unit, y = top + y * unit } end
	local function Box(x) return Rect(left + x * unit, top + WIN_BOX_Y * unit, WIN_BOX_W * unit, WIN_BOX_H * unit) end
	return {
		boxes = { [BLUE] = Box(WIN_BLUE_BOX_X), [RED] = Box(WIN_RED_BOX_X) },
		scores = { [BLUE] = At(WIN_SCORE_BLUE_X, WIN_SCORE_Y), [RED] = At(WIN_SCORE_RED_X, WIN_SCORE_Y) },
		names = { [BLUE] = At(WIN_NAME_BLUE_X, WIN_NAME_Y), [RED] = At(WIN_NAME_RED_X, WIN_NAME_Y) },
		border = Rect(centre - WIN_BORDER_W / 2 * unit, top + WIN_BORDER_Y * unit, WIN_BORDER_W * unit, WIN_BORDER_H * unit),
		title = { x = centre, y = top + WIN_TITLE_Y * unit },
		reason = { x = centre, y = top + WIN_REASON_Y * unit },
		details = { x = centre, y = top + WIN_DETAILS_Y * unit },
	}
end

-- The boss meter (CHudBossHealthMeter, cooler-hud's HudBossHealth.res at
-- hudlayout.res's HudBossHealth): the panel centred (c-100, 200 wide)
-- health_alive_pos_y (42) down while you play and health_dead_pos_y (90)
-- while you are dead or watching; its BorderImage (bar_surround_krampus)
-- 200x51 at 0,-11; the bar 168x10 at 15,10 (HealthBarPanel at 15,6, its
-- BarImage 4 down), its panel's width the boss's health, which cuts the
-- image (u: how much of it) rather than squashing it.
BOSS_BAR = "hud/halloween_bar"
local BOSS_W, BOSS_ALIVE_Y, BOSS_DEAD_Y = 200, 42, 90
local BOSS_BORDER_Y, BOSS_BORDER_H = -11, 51
local BOSS_BAR_X, BOSS_BAR_Y, BOSS_BAR_W, BOSS_BAR_H = 15, 10, 168, 10

-- bar_surround_krampus, cooler-hud's own texture, drawn instead of shipped:
-- in its 512x128 image a dark translucent band (31,40 to 476,88) round a
-- thin tan line (38,49 to 469,79), clear inside; each a share of the border
-- image's rect.
BOSS_BAND_COLOR = { r = 38, g = 34, b = 32, a = 179 }
BOSS_LINE_COLOR = { r = 222, g = 203, b = 156, a = 255 }
BOSS_LINE_THICK = 0.8 -- 2 of the image's 512 pixels, in HUD units
local KRAMPUS_W, KRAMPUS_H = 512, 128
local KRAMPUS_BAND = { 31, 40, 476, 88 }
local KRAMPUS_LINE = { 38, 49, 469, 79 }

local function Within(r, box)
	local sx, sy = r.w / KRAMPUS_W, r.h / KRAMPUS_H
	return Rect(r.x + box[1] * sx, r.y + box[2] * sy, (box[3] - box[1]) * sx, (box[4] - box[2]) * sy)
end

-- watching: dead or observing; fraction: the boss's health, 0 to 1.
-- Returns { surround, frame = { band, line }, bar, u }.
function BossMeter(screenW, unit, watching, fraction)
	local x, y = screenW / 2 - BOSS_W / 2 * unit, (watching and BOSS_DEAD_Y or BOSS_ALIVE_Y) * unit
	local surround = Rect(x, y + BOSS_BORDER_Y * unit, BOSS_W * unit, BOSS_BORDER_H * unit)
	return {
		surround = surround,
		frame = { band = Within(surround, KRAMPUS_BAND), line = Within(surround, KRAMPUS_LINE) },
		bar = Rect(x + BOSS_BAR_X * unit, y + BOSS_BAR_Y * unit, BOSS_BAR_W * unit * fraction, BOSS_BAR_H * unit),
		u = fraction,
	}
end
