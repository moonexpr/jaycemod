-- features.capture.hud: where the control point icons sit
-- (CHudControlPointIcons::PerformLayout with cooler-hud's hudlayout.res
-- HudControlPointIcons and ControlPointIcon.res), at real screen sizes.
local T = dofile("tests/harness.lua")
local Hud = T.require("features.capture.hud")
local Rounds = gameplay.rounds

-- TF2's own proportional screen, where a HUD unit is a pixel.
local BASE_W, BASE_H = 640, Hud.UNITS_TALL
local WIDE_W, WIDE_H = 1920, 1080
local SQUARE_W = 1440 -- 4:3 at WIDE_H
local HALF_PIXEL = 0.5

local ROW_TALL = Hud.ICON + Hud.LABEL
local ABOVE_EDGE = Hud.GAP_Y + Hud.BOTTOM_OFFSET

-- cooler-hud v2.6's published layout: hudlayout.res's HudControlPointIcons
-- (separator_width 2, separator_height 1, height_offset 16) and
-- ControlPointIcon.res (24 square, BetterOutline2 at -1,-1 26 square).
T.test("the icons take cooler-hud's sizes and spacing", function()
	T.eq(Hud.ICON, 24, "ControlPointIcon wide and tall")
	T.eq(Hud.GAP_X, 2, "separator_width")
	T.eq(Hud.GAP_Y, 1, "separator_height")
	T.eq(Hud.BOTTOM_OFFSET, 16, "height_offset")
	T.eq(Hud.OUTLINE, 1, "BetterOutline2's margin round the icon")
end)

T.test("the outline is at least a pixel round the icon and scales with the screen", function()
	T.eq(Hud.Layout({ 1 }, BASE_W, BASE_H).outline, Hud.OUTLINE, "a unit on TF2's screen")
	local unit = WIDE_H / Hud.UNITS_TALL
	T.eq(Hud.Layout({ 1 }, WIDE_W, WIDE_H).outline, math.floor(Hud.OUTLINE * unit), "scaled")
	T.eq(Hud.Layout({ 1 }, BASE_W / 2, BASE_H / 2).outline, 1, "never thinner than a pixel")
end)

-- BetterOutline2 is a ring: the world shows through its middle, so through
-- the icons' translucent body (icon_obj_*: alpha 173), and nothing pale
-- shows between the ring and the icon's rounded square.
local SIZES = { Hud.ICON, Hud.Layout({ 1 }, WIDE_W, WIDE_H).size, Hud.Layout({ 1 }, BASE_W / 2, BASE_H / 2).size }

T.test("the outline's ring is the icon and its outline all round", function()
	for _, size in ipairs(SIZES) do
		local ring = Hud.Outline(100, 200, size, 2)
		T.eq(ring.outer.x, 98, "left")
		T.eq(ring.outer.y, 198, "top")
		T.eq(ring.outer.w, size + 4, "wide")
		T.eq(ring.outer.h, size + 4, "tall")
	end
end)

T.test("the ring's hole lies within the icon's visible square, so the icon's rim covers its edge", function()
	for _, size in ipairs(SIZES) do
		local x, y = 100, 200
		local hole = Hud.Outline(x, y, size, 1).hole
		local edge = size * Hud.ICON_INSET
		T.eq(hole.x > x + edge and hole.y > y + edge, true, "inside the square's left and top")
		T.eq(hole.x + hole.w < x + size - edge and hole.y + hole.h < y + size - edge, true, "inside its right and bottom")
		T.eq(hole.x - x, x + size - (hole.x + hole.w), "centred across")
		T.eq(hole.w, hole.h, "square")
		T.eq(hole.corner <= size * Hud.ICON_CORNER, true, "no rounder than the icon's corner")
	end
end)

T.test("the ring is as wide at its corners as along its sides", function()
	for _, size in ipairs(SIZES) do
		local ring = Hud.Outline(100, 200, size, 3)
		T.eq(ring.outer.corner - ring.hole.corner, ring.hole.x - ring.outer.x, "outer corner rounder by the ring's width")
	end
end)

T.test("a rounded box's outline: each corner's arc, clockwise from the top left, on the box", function()
	local box = { x = 10, y = 20, w = 40, h = 30, corner = 5 }
	local segments = 4
	local points = Hud.RoundedRect(box, segments)
	T.eq(#points, 4 * (segments + 1), "an arc of segments a corner")
	local centres = { { 15, 25 }, { 45, 25 }, { 45, 45 }, { 15, 45 } }
	for i, p in ipairs(points) do
		local c = centres[math.floor((i - 1) / (segments + 1)) + 1]
		T.near(math.sqrt((p.x - c[1]) ^ 2 + (p.y - c[2]) ^ 2), box.corner, 1e-9, "on its corner's arc")
		T.eq(p.x >= box.x and p.x <= box.x + box.w and p.y >= box.y and p.y <= box.y + box.h, true, "within the box")
	end
	T.near(points[1].x, box.x, 1e-9, "starts on the left edge")
	T.near(points[segments + 1].y, box.y, 1e-9, "the first arc ends on the top edge")
end)

T.test("a square-cornered box's outline is its four corners", function()
	local points = Hud.RoundedRect({ x = 0, y = 0, w = 4, h = 2, corner = 0 }, 4)
	T.eq(#points, 4, "no arcs")
	T.eq(points[3].x, 4, "bottom right")
	T.eq(points[3].y, 2, "bottom right")
end)

local function Bottom(layout, row)
	return layout.rows[row][1].y + layout.size + layout.label
end

local function Centre(layout, row)
	local icons = layout.rows[row]
	return (icons[1].x + icons[#icons].x + layout.size) / 2
end

T.test("one row sits centred at the bottom, a separator and the offset above the screen's edge", function()
	local layout = Hud.Layout({ 3 }, BASE_W, BASE_H)
	T.eq(layout.size, Hud.ICON, "an icon is its units in pixels")
	T.eq(#layout.rows[1], 3, "three icons")
	T.eq(Bottom(layout, 1), BASE_H - ABOVE_EDGE, "bottom, as TF2 anchors it")
	T.near(Centre(layout, 1), BASE_W / 2, HALF_PIXEL, "centred")
	T.eq(layout.rows[1][2].x - layout.rows[1][1].x, Hud.ICON + Hud.GAP_X, "icons a separator apart")
	T.eq(layout.top, BASE_H - ABOVE_EDGE - ROW_TALL - Hud.GAP_Y, "the panel's top, above its first row")
end)

T.test("the layout scales with the screen's height, as TF2's proportional HUD", function()
	local unit = WIDE_H / Hud.UNITS_TALL
	local wide = Hud.Layout({ 5 }, WIDE_W, WIDE_H)
	T.eq(wide.size, math.floor(Hud.ICON * unit), "icon size")
	T.near(Bottom(wide, 1), WIDE_H - ABOVE_EDGE * unit, 1, "a scaled separator and offset above the edge")
	T.near(Centre(wide, 1), WIDE_W / 2, 1, "centred on a wide screen")
	local square = Hud.Layout({ 5 }, SQUARE_W, WIDE_H)
	T.eq(square.size, wide.size, "the same size at the same height")
	T.eq(square.rows[1][1].y, wide.rows[1][1].y, "the same height from the bottom")
	T.near(Centre(square, 1), SQUARE_W / 2, 1, "centred on a 4:3 screen")
end)

T.test("caplayout's rows stack down to the bottom, each centred", function()
	local layout = Hud.Layout({ 1, 2 }, BASE_W, BASE_H)
	T.eq(Bottom(layout, 2), BASE_H - ABOVE_EDGE, "the last row at the bottom")
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
