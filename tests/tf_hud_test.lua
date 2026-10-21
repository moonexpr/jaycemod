-- ws.tf_hud: TF2's HUD look, in its proportional units of a 480-tall
-- screen: scalable images (ScalableImagePanel's nine pieces), the team
-- scores centred above the round timer, the timer panel
-- (HudObjectiveTimePanel.res) and the win panel (winpanel.res).
local T = dofile("tests/harness.lua")
local Hud = T.require("ws.tf_hud")

local RED, BLUE = 2, 3

local function Near(a, b) return math.abs(a - b) < 1e-6 end

T.test("a unit is the screen's height over 480", function()
	T.eq(Hud.Unit(960), 2, "960 tall")
end)

T.test("a scalable image is nine pieces: fixed corners, stretched sides and middle", function()
	local pieces = Hud.Slices(10, 20, 100, 60, 64, 64, 16, 8)
	T.eq(#pieces, 9, "nine")
	local first, last = pieces[1], pieces[9]
	T.eq(first.x, 10, "top left x")
	T.eq(first.y, 20, "top left y")
	T.eq(first.w, 8, "a corner's drawn width")
	T.eq(Near(first.u1, 16 / 64 - 0.5 / 64), true, "a corner's texture width, half a texel in")
	T.eq(last.x + last.w, 110, "bottom right reaches the right")
	T.eq(last.y + last.h, 80, "and the bottom")
	T.eq(Near(last.u0, 48 / 64 + 0.5 / 64), true, "from the texture's last corner, half a texel in")
	local middle = pieces[5]
	T.eq(middle.w, 84, "the middle stretches across")
	T.eq(middle.h, 44, "and down")
	local area = 0
	for _, p in ipairs(pieces) do area = area + p.w * p.h end
	T.eq(area, 100 * 60, "the pieces tile the rect")
end)

-- The seams between the pieces: a piece on a fractional pixel leaves a gap
-- or overlap, and filtering at a piece's edge samples its neighbour's
-- texels. Edges fall on whole pixels, and each piece samples half a texel
-- inside its own part of the image.
T.test("a scalable image's pieces meet on whole pixels and sample only their own texels", function()
	local pieces = Hud.Slices(10.4, 20.6, 100.3, 60.2, 64, 64, 16, 7.3)
	for i, p in ipairs(pieces) do
		T.eq(p.x % 1 == 0 and p.y % 1 == 0 and p.w % 1 == 0 and p.h % 1 == 0, true, "piece " .. i .. " on whole pixels")
	end
	for row = 0, 2 do
		for col = 1, 2 do
			local a, b = pieces[row * 3 + col], pieces[row * 3 + col + 1]
			T.eq(a.x + a.w, b.x, "row " .. row .. ": pieces " .. col .. " and " .. col + 1 .. " meet")
		end
	end
	local half = 0.5 / 64
	T.eq(Near(pieces[1].u0, half), true, "the first column half a texel in")
	T.eq(Near(pieces[1].u1, 16 / 64 - half), true, "and short of the next")
	T.eq(Near(pieces[2].u0, 16 / 64 + half), true, "the middle from half a texel past the corner")
end)

T.test("a scalable image smaller than its corners shrinks them", function()
	local pieces = Hud.Slices(0, 0, 10, 6, 64, 64, 16, 8)
	T.eq(pieces[1].w, 5, "half the width")
	T.eq(pieces[1].h, 3, "half the height")
	for _, p in ipairs(pieces) do T.eq(p.w >= 0 and p.h >= 0, true, "no negative piece") end
end)

T.test("the team scores sit centred above the timer, BLU left and RED right", function()
	local unit, centre, top = 2, 500, 100
	local boxes = Hud.ScoreBoxes(centre, top, unit)
	local blue, red = boxes[BLUE], boxes[RED]
	T.eq(blue.x + blue.w < red.x, true, "BLU left of RED, a gap between")
	T.eq(Near((blue.x + red.x + red.w) / 2, centre), true, "centred")
	T.eq(blue.y, top, "at the top of the row")
	T.eq(blue.w, red.w, "the same width")
	local timer = Hud.TimerPanel(centre, Hud.TimerTop(top, unit), unit)
	T.eq(timer.bg.y >= blue.y + blue.h, true, "the timer below the scores")
	T.eq(Near(timer.bg.x + timer.bg.w / 2, centre), true, "the timer centred under them")
end)

T.test("the timer panel's clock sits in its background, its label strip under it", function()
	local unit = 1
	local panel = Hud.TimerPanel(240, 50, unit)
	T.eq(panel.bg.w, 78, "TimePanelBG's width")
	T.eq(panel.bg.h, 33, "and height")
	T.eq(panel.value.x, 240, "the clock centred")
	T.eq(panel.value.y > panel.bg.y and panel.value.y < panel.bg.y + panel.bg.h, true, "inside the background")
	T.eq(panel.label.strip.y > panel.bg.y, true, "the label's strip below the background's top")
	T.eq(panel.label.strip.y + panel.label.strip.h > panel.bg.y + panel.bg.h, true, "showing under it")
	T.eq(panel.label.y > panel.bg.y + panel.bg.h, true, "the label in the part that shows")
end)

T.test("the timer's background is the local team's, BLU's for anyone else", function()
	T.eq(Hud.TimerBackground(RED), "hud/objectives_timepanel_red_bg", "RED's")
	T.eq(Hud.TimerBackground(BLUE), "hud/objectives_timepanel_blue_bg", "BLU's")
	T.eq(Hud.TimerBackground(1), "hud/objectives_timepanel_blue_bg", "a spectator's")
end)

T.test("the win panel: the scores over its border, coloured for the winner", function()
	local unit = 1
	local panel = Hud.WinPanel(640, 480, unit)
	T.eq(Near(panel.border.x + panel.border.w / 2, 320), true, "centred")
	T.eq(panel.boxes[BLUE].x < panel.boxes[RED].x, true, "BLU's score left")
	T.eq(panel.boxes[BLUE].y + panel.boxes[BLUE].h <= panel.border.y, true, "the scores above the border")
	T.eq(panel.scores[BLUE].x <= panel.boxes[BLUE].x + panel.boxes[BLUE].w, true, "BLU's score inside its box")
	T.eq(panel.scores[RED].x >= panel.boxes[RED].x, true, "RED's inside its")
	T.eq(panel.title.y > panel.border.y, true, "the title inside the border")
	T.eq(panel.reason.y > panel.title.y, true, "the reason under it")
	T.eq(Hud.PanelImage(RED), "hud/color_panel_red", "RED's border")
	T.eq(Hud.PanelImage(BLUE), "hud/color_panel_blu", "BLU's")
	T.eq(Hud.PanelImage(0), "hud/color_panel_brown", "a stalemate's")
	T.eq(Hud.ScoreImage(BLUE), "hud/color_panel_blu_more_opaque", "a score box")
end)

-- CHudBossHealthMeter (HudBossHealth.res at hudlayout.res's HudBossHealth):
-- a 200x50 surround centred at the top, 42 down while you play and 90 while
-- you are dead or watching; inside it at 15,16 the 168x18 bar, cut (not
-- squashed) to the boss's health, as SetWide clips its image.
T.test("the boss meter is centred, 42 down while you play and 90 while you watch", function()
	local playing = Hud.BossMeter(1280, 2, false, 1)
	T.eq(playing.surround.x, 640 - 200, "centred: c-100")
	T.eq(playing.surround.y, 84, "42 down")
	T.eq(playing.surround.w .. "x" .. playing.surround.h, "400x100", "200x50")
	T.eq(Hud.BossMeter(1280, 2, true, 1).surround.y, 180, "90 down while watching")
end)

T.test("the boss meter's bar is cut to the health left, its image with it", function()
	local meter = Hud.BossMeter(1280, 2, false, 0.25)
	T.eq(meter.bar.x, 640 - 200 + 30, "15 in")
	T.eq(meter.bar.y, 84 + 32, "16 down")
	T.eq(meter.bar.w, 168 * 2 * 0.25, "a quarter of 168")
	T.eq(meter.bar.h, 36, "18 tall")
	T.eq(meter.u, 0.25, "a quarter of the image")
	T.eq(Hud.BOSS_SURROUND, "hud/halloween_bar_surround")
	T.eq(Hud.BOSS_BAR, "hud/halloween_bar")
end)

T.finish()
