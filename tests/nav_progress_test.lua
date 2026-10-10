-- foundation.nav_progress: what the nav mesh progress box says while
-- mp_nav_generate runs (ws/sh_nav_progress.lua). GMod reports no
-- progress, so it tells the stage and the time it has taken, and the areas
-- made at the end.
local T = dofile("tests/harness.lua")
local P = T.require("foundation.nav_progress")

T.test("each stage says what is happening, with the time taken", function()
	T.eq(P.Body(P.OPENING, 5, 0), "Opening doors and laying bridges... 0:05")
	T.eq(P.Body(P.GENERATING, 83, 0), "Generating... 1:23")
	T.eq(P.Body(P.DONE, 125, 2426), "Done in 2:05: 2426 areas, saved")
end)

T.test("the bar runs until it is done, then is full", function()
	T.eq(P.Fraction(P.OPENING), nil, "running: no fraction to show")
	T.eq(P.Fraction(P.GENERATING), nil)
	T.eq(P.Fraction(P.DONE), 1)
end)

T.test("the box stays up a moment after it is done, then goes", function()
	T.eq(P.Showing(P.GENERATING, 0, 999), true, "while it runs")
	T.eq(P.Showing(P.DONE, 10, 10 + P.LINGER - 1), true, "just done")
	T.eq(P.Showing(P.DONE, 10, 10 + P.LINGER + 1), false, "gone")
	T.eq(P.Showing(P.IDLE, 0, 0), false, "nothing running")
end)

T.finish()
