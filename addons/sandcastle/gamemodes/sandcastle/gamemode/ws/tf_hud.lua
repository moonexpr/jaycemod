-- TF2's HUD look, in its proportional units of a 480-tall screen (Unit):
-- scalable images (ScalableImagePanel and the scalable_image borders, nine
-- pieces), the team scores centred above the round timer, the timer panel
-- (HudObjectiveTimePanel.res) and the win panel (winpanel.res, at
-- hudlayout.res's WinPanel). Rects are { x, y, w, h } in pixels; text
-- anchors { x, y } are where a centred line's middle goes.
local floor, min = math.floor, math.min
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

-- HudObjectiveTimePanel.res, from TimePanelBG's top: the background 78 x 33;
-- TimePanelValue (HudFontMediumSmall) 2 below its top, 31 tall; the label
-- strip (objectives_timepanel_suddendeath) 22 down, 20 tall, behind it, the
-- label (ClockSubText) 24 down, 19 tall.
TIMER_W, TIMER_H = 78, 33
TIMER_VALUE_Y, TIMER_VALUE_TALL, TIMER_FONT_TALL = 2, 31, 18
TIMER_STRIP_Y, TIMER_STRIP_H = 22, 20
TIMER_LABEL_Y, TIMER_LABEL_TALL, TIMER_LABEL_FONT_TALL = 24, 19, 9
TIMER_STRIP = "hud/objectives_timepanel_suddendeath"

function TimerPanel(centre, top, unit)
	local x = centre - TIMER_W / 2 * unit
	return {
		bg = Rect(x, top, TIMER_W * unit, TIMER_H * unit),
		value = { x = centre, y = top + (TIMER_VALUE_Y + TIMER_VALUE_TALL / 2) * unit },
		label = {
			strip = Rect(x, top + TIMER_STRIP_Y * unit, TIMER_W * unit, TIMER_STRIP_H * unit),
			x = centre,
			y = top + (TIMER_LABEL_Y + TIMER_LABEL_TALL / 2) * unit,
		},
	}
end

-- CTFHudTimeStatus::SetTeamBackground: the local team's, BLU's for anyone else.
function TimerBackground(team)
	return team == RED and "hud/objectives_timepanel_red_bg" or "hud/objectives_timepanel_blue_bg"
end

-- The win panel -------------------------------------------------------------------

-- hudlayout.res's WinPanel: 300 wide at c-150, 215 down. winpanel.res's
-- TeamScoresPanel puts the score boxes (135 x 40) at 9 and 156, 28 down,
-- the scores (ScoreboardTeamScore, TF2 52) against the panel's middle, the
-- team names (ScoreboardTeamName) at their outer ends; WinPanelBGBorder at
-- 70 down, 282 wide, under them; the winning team (ScoreboardTeamName) at
-- 72, the reason and details (ScoreboardVerySmall) at 89 and 101. Without
-- TF2's top players the border ends under the details.
WIN_W, WIN_Y = 300, 215
WIN_BOX_W, WIN_BOX_H, WIN_BOX_Y, WIN_BLUE_BOX_X, WIN_RED_BOX_X = 135, 40, 28, 9, 156
WIN_SCORE_BLUE_X, WIN_SCORE_RED_X, WIN_SCORE_Y, WIN_SCORE_FONT_TALL = 139, 161, 38, 52
WIN_NAME_BLUE_X, WIN_NAME_RED_X, WIN_NAME_Y, WIN_NAME_FONT_TALL = 15, 285, 48, 20
WIN_BORDER_Y, WIN_BORDER_W, WIN_BORDER_H = 70, 282, 58
WIN_TITLE_Y, WIN_REASON_Y, WIN_DETAILS_Y = 84, 101, 114
WIN_TEXT_FONT_TALL = 8

function WinPanel(screenW, screenH, unit)
	local left, top = screenW / 2 - WIN_W / 2 * unit, WIN_Y * unit
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
