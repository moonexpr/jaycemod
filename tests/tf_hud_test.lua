-- ws.tf_hud: TF2's HUD as cooler-hud v2.6 lays it out, in TF2's
-- proportional units of a 480-tall screen: scalable images
-- (ScalableImagePanel's nine pieces), the team scores centred above the
-- round timer, the timer panel (HudObjectiveTimePanel.res) with its
-- progress pie (CTFProgressBar), KOTH's two clocks, the respawn label
-- (spectator.res), the win panel (winpanel.res) and the boss meter.
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

-- HudObjectiveTimePanel.res in cooler-hud's ObjectiveStatusTimePanel (c-55,
-- 110 wide): TimePanelBG 78x33 at 16,9; TimePanelValue 22,11 45x31;
-- TimePanelProgressBar 20x20 at 67,15; the labels (SetupLabel and kin)
-- 90x19 at 10,43, in TFFatLineBorder.
T.test("the timer panel: the clock left of the pie, both in the background, the label under it", function()
	local unit = 2
	local panel = Hud.TimerPanel(240, 50, unit)
	T.eq(panel.bg.x .. "," .. panel.bg.y .. " " .. panel.bg.w .. "x" .. panel.bg.h, "162,50 156x66", "TimePanelBG, centred")
	T.eq(panel.value.x, 240 - 10.5 * unit, "the clock centred in its 45 from 22")
	T.eq(panel.value.y, 50 + 17.5 * unit, "and in its 31 from 11")
	T.eq(panel.pie.x .. "," .. panel.pie.y .. " " .. panel.pie.w .. "x" .. panel.pie.h, "264,62 40x40", "the pie at 67,15")
	T.eq(panel.pie.x > panel.value.x, true, "right of the clock")
	T.eq(panel.pie.x + panel.pie.w <= panel.bg.x + panel.bg.w, true, "inside the background")
	local box = panel.label.box
	T.eq(box.x .. "," .. box.y .. " " .. box.w .. "x" .. box.h, "150,118 180x38", "the label's box at 10,43")
	T.eq(box.y >= panel.bg.y + panel.bg.h, true, "under the background")
	T.eq(panel.label.x, 240, "the label centred")
	T.eq(panel.label.y, box.y + box.h / 2, "in its box")
end)

-- CTFHudTimeStatus::OnThink: the pie shows the share of the timer's full
-- length gone, none for a timer without one.
T.test("the pie's share is the time gone of the timer's full length", function()
	T.eq(Hud.TimerElapsed(45, 180), 0.75, "45 of 180 left")
	T.eq(Hud.TimerElapsed(180, 180), 0, "none gone")
	T.eq(Hud.TimerElapsed(30, 0), 0, "no full length: none")
	T.eq(Hud.TimerElapsed(200, 180), 0, "never below none")
	T.eq(Hud.TimerElapsed(-1, 180), 1, "nor above all")
end)

-- CTFProgressBar::Paint: the whole image in the inactive colour, then the
-- time left in the active one (the warning one from 75% gone), a wedge
-- from twelve o'clock clockwise, cut to the square.
T.test("the pie's wedge runs clockwise from twelve o'clock to the time left, cut to its square", function()
	local function Points(wedge)
		local out = {}
		for i, p in ipairs(wedge) do out[i] = string.format("%.2f,%.2f", p.x, p.y) end
		return table.concat(out, " ")
	end
	T.eq(#Hud.PieWedge(0), 0, "nothing left: no wedge")
	T.eq(Points(Hud.PieWedge(0.25)), "0.50,0.50 0.50,0.00 1.00,0.00 1.00,0.50", "a quarter: to three o'clock")
	T.eq(Points(Hud.PieWedge(0.125)), "0.50,0.50 0.50,0.00 1.00,0.00", "an eighth: to the corner")
	T.eq(Points(Hud.PieWedge(0.5)), "0.50,0.50 0.50,0.00 1.00,0.00 1.00,1.00 0.50,1.00", "a half: to six")
	T.eq(Points(Hud.PieWedge(1)), "0.50,0.50 0.50,0.00 1.00,0.00 1.00,1.00 0.00,1.00 0.00,0.00 0.50,0.00", "all: round to twelve")
	local p = Hud.PieWedge(1 / 12)[3]
	T.eq(string.format("%.3f,%.3f", p.x, p.y), string.format("%.3f,0.000", 0.5 + math.tan(math.pi / 6) / 2), "30 degrees on the top edge")
	T.eq(Hud.PieColor(0.5), Hud.PIE_ACTIVE, "under 75% gone: active")
	T.eq(Hud.PieColor(0.75), Hud.PIE_WARNING, "from 75%: the warning colour")
end)

-- hudobjectivekothtimepanel.res in hudlayout.res's HudKothTimeStatus (c-100,
-- 200 wide): BlueTimer at 0 and RedTimer at 90, each a time panel; the
-- ActiveTimerBG over the running one (blue_active_xpos 16, red 106).
T.test("KOTH's clocks: BLU's left and RED's right of the centre, the active frame on the running one", function()
	local unit = 1
	local clocks = Hud.KothPanels(320, 50, unit)
	T.eq(clocks[BLUE].bg.x, 320 - 84, "BLU's background at c-84")
	T.eq(clocks[RED].bg.x, 320 + 6, "RED's at c+6")
	T.eq(clocks[BLUE].bg.y, 50, "on the timer row")
	T.eq(Hud.KothActiveFrame(clocks, RED).x, clocks[RED].bg.x, "the frame over RED's")
	T.eq(Hud.KothActiveFrame(clocks, BLUE).w, 78, "as big as a background")
end)

-- The hill's lock at a koth round's start counts down on a timer panel of
-- its own, under the (greyed) clocks, where the overtime box would be.
T.test("KOTH's setup timer hangs centred under the clocks, clear of them", function()
	local unit = 2
	local clocks = Hud.KothPanels(320, 50, unit)
	local setup = Hud.TimerPanel(320, Hud.KothSetupTop(50, unit), unit)
	T.eq(setup.bg.y > clocks[BLUE].bg.y + clocks[BLUE].bg.h, true, "below the clocks' backgrounds")
	T.eq(setup.bg.x + setup.bg.w / 2, 320 + (Hud.TIMER_BG_X + Hud.TIMER_W / 2 - Hud.TIMER_PANEL_W / 2) * unit, "centred as the round timer is")
end)

-- spectator.res's ReinforcementsLabel: -8, r91, 292x28, in TFThinLineBorder.
T.test("the respawn label sits at the bottom left, its left edge off the screen", function()
	local label = Hud.RespawnLabel(960, 2)
	T.eq(label.x .. "," .. label.y .. " " .. label.w .. "x" .. label.h, "-16,778 584x56", "-8, r91, 292x28")
	T.eq(Hud.RESPAWN_BORDER, "hud/tournament_panel_brown", "TFThinLineBorder's image")
end)

-- What moved the respawn, in a panel of its own under the label.
local SCREENS = { { 480, 1 }, { 1080, 1080 / 480 }, { 720, 1.5 } }

T.test("the respawn reasons' panel hangs under the label, as wide and as far off the screen", function()
	for _, s in ipairs(SCREENS) do
		local label = Hud.RespawnLabel(s[1], s[2])
		local panel = Hud.RespawnReasons(s[1], s[2], 2).panel
		T.eq(Near(panel.x, label.x) and Near(panel.w, label.w), true, "the label's left and width")
		T.eq(Near(panel.y, label.y + label.h + Hud.REASONS_GAP * s[2]), true, "a gap under the label")
	end
	T.eq(Hud.REASONS_PANEL, "hud/color_panel_brown", "TFFatLineBorder's brown, apart from the label's thin line")
end)

T.test("the most reasons a respawn can have, and its limited total, fit above the screen's bottom", function()
	local M = gameplay.respawn_modifiers
	local every = M.For({ kills = M.MOST_KILLS, captures = 1, defenses = 1, finishedOff = true, suicide = true })
	local lines = #every + 1 -- the total, when a limit cut it
	for _, s in ipairs(SCREENS) do
		local panel = Hud.RespawnReasons(s[1], s[2], lines).panel
		T.eq(panel.y + panel.h <= s[1], true, lines .. " lines on a " .. s[1] .. "-tall screen")
	end
end)

T.test("the reasons stack down the panel, the seconds in a column before the words", function()
	local unit = 2
	local reasons = Hud.RespawnReasons(960, unit, 3)
	local panel = reasons.panel
	T.eq(#reasons.lines, 3, "a line a reason")
	for i, line in ipairs(reasons.lines) do
		T.eq(Near(line.seconds.y, line.words.y), true, "the seconds and words on one line")
		T.eq(line.seconds.x < line.words.x, true, "the seconds' right edge before the words")
		T.eq(line.seconds.x > 0, true, "the seconds on the screen, though the panel hangs off it")
		T.eq(line.seconds.y > panel.y and line.seconds.y < panel.y + panel.h, true, "inside the panel")
		if i > 1 then
			T.eq(Near(line.seconds.y - reasons.lines[i - 1].seconds.y, Hud.REASON_TALL * unit), true, "a line apart")
			T.eq(Near(line.seconds.x, reasons.lines[1].seconds.x), true, "one column")
		end
	end
	T.eq(Near(reasons.lines[1].seconds.y - panel.y, panel.y + panel.h - reasons.lines[3].seconds.y), true, "as much room above as below")
end)

T.test("the timer's background is the local team's, BLU's for anyone else", function()
	T.eq(Hud.TimerBackground(RED), "hud/objectives_timepanel_red_bg", "RED's")
	T.eq(Hud.TimerBackground(BLUE), "hud/objectives_timepanel_blue_bg", "BLU's")
	T.eq(Hud.TimerBackground(1), "hud/objectives_timepanel_blue_bg", "a spectator's")
end)

T.test("the win panel: the scores over its border, coloured for the winner", function()
	local unit = 1
	local panel = Hud.WinPanel(640, 480, unit)
	T.eq(panel.boxes[BLUE].y, 240 - 10 + 29, "hudlayout.res's WinPanel at c-10; the score boxes 29 down")
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

-- CHudBossHealthMeter (cooler-hud's HudBossHealth.res at hudlayout.res's
-- HudBossHealth): the panel centred at the top (c-100, 200 wide), 42 down
-- while you play and 90 while you are dead or watching; its BorderImage
-- 200x51 at 0,-11; the bar 168x10 at 15,10 (HealthBarPanel 15,6, BarImage
-- 4 down in it), cut (not squashed) to the boss's health, as SetWide clips
-- its image.
T.test("the boss meter is centred, 42 down while you play and 90 while you watch", function()
	local playing = Hud.BossMeter(1280, 2, false, 1)
	T.eq(playing.surround.x, 640 - 200, "centred: c-100")
	T.eq(playing.surround.y, 84 - 22, "the border 11 above the panel's 42")
	T.eq(playing.surround.w .. "x" .. playing.surround.h, "400x102", "200x51")
	T.eq(Hud.BossMeter(1280, 2, true, 1).surround.y, 180 - 22, "90 down while watching")
end)

T.test("the boss meter's bar is cut to the health left, its image with it", function()
	local meter = Hud.BossMeter(1280, 2, false, 0.25)
	T.eq(meter.bar.x, 640 - 200 + 30, "15 in")
	T.eq(meter.bar.y, 84 + 20, "10 down")
	T.eq(meter.bar.w, 168 * 2 * 0.25, "a quarter of 168")
	T.eq(meter.bar.h, 20, "10 tall")
	T.eq(meter.u, 0.25, "a quarter of the image")
	T.eq(Hud.BOSS_BAR, "hud/halloween_bar")
end)

-- Cooler-hud's bar_surround_krampus: a dark translucent band round the bar
-- with a thin tan line inside it and nothing in the middle, drawn from its
-- measured rects so the texture need not ship.
T.test("the boss meter's frame: the dark band round the tan line, both round the bar", function()
	local meter = Hud.BossMeter(1280, 2, false, 1)
	local band, line, bar = meter.frame.band, meter.frame.line, meter.bar
	T.eq(band.x < line.x and band.y < line.y, true, "the band outside the line")
	T.eq(band.x + band.w > line.x + line.w and band.y + band.h > line.y + line.h, true, "on every side")
	T.eq(line.x <= bar.x + 1 and line.x + line.w >= bar.x + bar.w - 1, true, "the line round the bar's width")
	T.eq(line.y <= bar.y and line.y + line.h >= bar.y + bar.h - 1, true, "and its height")
	T.eq(band.x >= meter.surround.x and band.x + band.w <= meter.surround.x + meter.surround.w, true, "inside the border image's rect")
end)

T.finish()
