-- foundation.capture.hud: where the control point icons sit
-- (CHudControlPointIcons::PerformLayout with hudlayout.res's
-- HudControlPointIcons and ControlPointIcon.res), at real screen sizes.
local T = dofile("tests/harness.lua")
local Hud = T.require("foundation.capture.hud")
local Rounds = T.require("games.gameplay.rounds")

-- TF2's own proportional screen, where a HUD unit is a pixel.
local BASE_W, BASE_H = 640, Hud.UNITS_TALL
local WIDE_W, WIDE_H = 1920, 1080
local SQUARE_W = 1440 -- 4:3 at WIDE_H
local HALF_PIXEL = 0.5

local ROW_TALL = Hud.ICON + Hud.LABEL

local function Bottom(layout, row)
	return layout.rows[row][1].y + layout.size + layout.label
end

local function Centre(layout, row)
	local icons = layout.rows[row]
	return (icons[1].x + icons[#icons].x + layout.size) / 2
end

T.test("one row sits centred at the bottom, a separator above the screen's edge", function()
	local layout = Hud.Layout({ 3 }, BASE_W, BASE_H)
	T.eq(layout.size, Hud.ICON, "an icon is its units in pixels")
	T.eq(#layout.rows[1], 3, "three icons")
	T.eq(Bottom(layout, 1), BASE_H - Hud.GAP_Y - Hud.BOTTOM_OFFSET, "bottom, as TF2 anchors it")
	T.near(Centre(layout, 1), BASE_W / 2, HALF_PIXEL, "centred")
	T.eq(layout.rows[1][2].x - layout.rows[1][1].x, Hud.ICON + Hud.GAP_X, "icons a separator apart")
	T.eq(layout.top, BASE_H - Hud.GAP_Y - ROW_TALL - Hud.GAP_Y, "the panel's top, above its first row")
end)

T.test("the layout scales with the screen's height, as TF2's proportional HUD", function()
	local unit = WIDE_H / Hud.UNITS_TALL
	local wide = Hud.Layout({ 5 }, WIDE_W, WIDE_H)
	T.eq(wide.size, math.floor(Hud.ICON * unit), "icon size")
	T.near(Bottom(wide, 1), WIDE_H - Hud.GAP_Y * unit, 1, "a scaled separator above the edge")
	T.near(Centre(wide, 1), WIDE_W / 2, 1, "centred on a wide screen")
	local square = Hud.Layout({ 5 }, SQUARE_W, WIDE_H)
	T.eq(square.size, wide.size, "the same size at the same height")
	T.eq(square.rows[1][1].y, wide.rows[1][1].y, "the same height from the bottom")
	T.near(Centre(square, 1), SQUARE_W / 2, 1, "centred on a 4:3 screen")
end)

T.test("caplayout's rows stack down to the bottom, each centred", function()
	local layout = Hud.Layout({ 1, 2 }, BASE_W, BASE_H)
	T.eq(Bottom(layout, 2), BASE_H - Hud.GAP_Y, "the last row at the bottom")
	T.eq(layout.rows[2][1].y - layout.rows[1][1].y, ROW_TALL + Hud.GAP_Y, "a row and a separator apart")
	T.near(Centre(layout, 1), BASE_W / 2, HALF_PIXEL, "the pyramid's top centred")
	T.near(Centre(layout, 2), BASE_W / 2, HALF_PIXEL, "its base centred")
end)

T.test("no rows, no icons", function()
	T.eq(#Hud.Layout({}, BASE_W, BASE_H).rows, 0, "empty")
end)

T.test("the icons give the bottom centre to payload's cart HUD, as TF2's escort HUD", function()
	T.eq(Hud.Shown(Rounds.HUD_PAYLOAD), false, "payload")
	T.eq(Hud.Shown(Rounds.HUD_CONTROL_POINTS), true, "control points")
	T.eq(Hud.Shown(Rounds.HUD_KOTH), true, "koth")
	T.eq(Hud.Shown(Rounds.HUD_DEATHMATCH), false, "a deathmatch: frags alone")
	T.eq(Hud.Shown(Rounds.HUD_NONE), true, "a round without a HUD type")
end)

-- The capture panel's reason text fades white -> red -> white, once every
-- REASON_PULSE seconds: 0 is white, 1 red.
T.test("the reason text starts white, is red half a pulse on, and white again after a whole one", function()
	T.near(Hud.ReasonRedness(0), 0, 1e-9, "white")
	T.near(Hud.ReasonRedness(Hud.REASON_PULSE / 2), 1, 1e-9, "red")
	T.near(Hud.ReasonRedness(Hud.REASON_PULSE), 0, 1e-9, "white again")
	T.near(Hud.ReasonRedness(Hud.REASON_PULSE / 4), 0.5, 1e-9, "halfway")
end)

T.test("the reason text fades slowly: a pulse takes seconds", function()
	T.eq(Hud.REASON_PULSE >= 2, true, tostring(Hud.REASON_PULSE))
end)

-- CHudControlPointIcons::InitIcons: an icon for each point in the current
-- mini-round (every point outside mini-rounds) that is not hidden; the
-- layout skips the rest (cp_dustbowl shows its stage's two, not all six).
T.test("only the current round's points that are not hidden have icons", function()
	T.eq(Hud.HasIcon({ inRound = true, hidden = false }), true, "in the round")
	T.eq(Hud.HasIcon({ inRound = false, hidden = false }), false, "another stage's")
	T.eq(Hud.HasIcon({ inRound = true, hidden = true }), false, "hidden")
end)

T.finish()
