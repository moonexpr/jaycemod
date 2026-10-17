-- Where the capture HUD's control point icons sit, as TF2 places them
-- (CHudControlPointIcons::PerformLayout, hud_controlpointicons.cpp): the
-- master's caplayout rows centred at the bottom of the screen, the panel
-- ending a separator above the bottom edge (height_offset 0 on PC). Sizes
-- are TF2's proportional HUD units from scripts/hudlayout.res
-- (HudControlPointIcons) and resource/ui/ControlPointIcon.res, a unit being
-- 1/UNITS_TALL of the screen's height, so the layout scales with any
-- resolution. TF2 shows the icons for every round but payload's, whose
-- escort HUD takes the same bottom centre (CTFHudObjectiveStatus::
-- SetVisiblePanels).
local cos, floor, ipairs, pi = math.cos, math.floor, ipairs, math.pi
local Rounds = require("foundation.rounds")
module(...)

UNITS_TALL = 480 -- a proportional screen's height in HUD units
ICON = 33 -- ControlPointIcon.res wide and tall
GAP_X = 9 -- HudControlPointIcons separator_width
GAP_Y = 7 -- HudControlPointIcons separator_height
BOTTOM_OFFSET = 0 -- HudControlPointIcons height_offset [$WIN32]
LABEL = 11 -- the cappers line under each row's icons (TF2 draws it inside the icon)
-- The capture panel's reason text, in TF2's target ID font (targetid.res's
-- HudFontSmall: TF2 Secondary, 14 units tall, weight 500), outlined black,
-- fading white -> red -> white once every REASON_PULSE seconds.
REASON_FONT = "TF2 Secondary"
REASON_TALL = 14
REASON_WEIGHT = 500
REASON_PULSE = 3

-- How red the reason text is at time now: 0 white, 1 red, smoothly between.
function ReasonRedness(now)
	return (1 - cos(2 * pi * now / REASON_PULSE)) / 2
end

-- Whether the icons show in a round with HUD type hudType (a Rounds.HUD_*).
function Shown(hudType)
	return hudType ~= Rounds.HUD_PAYLOAD
end

-- rowSizes: how many icons each caplayout row shows, top row first; w, h:
-- the screen in pixels. Returns { size, label, top, rows }: the icon's and
-- the cappers line's height, the panel's top, and each row's icons' { x, y }
-- in pixels, left to right.
function Layout(rowSizes, w, h)
	local unit = h / UNITS_TALL
	local size, label = floor(ICON * unit), floor(LABEL * unit)
	local gapX, gapY = floor(GAP_X * unit), floor(GAP_Y * unit)
	local pitch = size + label + gapY
	local top = h - floor(BOTTOM_OFFSET * unit) - gapY - #rowSizes * pitch
	local rows = {}
	for line, count in ipairs(rowSizes) do
		local x = floor((w - (count * size + (count - 1) * gapX)) / 2)
		local y = top + gapY + (line - 1) * pitch
		local icons = {}
		for i = 1, count do
			icons[i] = {
				x = x + (i - 1) * (size + gapX),
				y = y,
			}
		end
		rows[line] = icons
	end
	return {
		size = size,
		label = label,
		top = top,
		rows = rows,
	}
end
