-- ws.nav_progress: what the nav mesh progress box says while
-- mp_nav_generate runs (ws/sh_nav_progress.lua). GMod reports no
-- progress, so it tells the stage and the time it has taken, and the areas
-- made at the end.
local T = dofile("tests/harness.lua")
local P = T.require("ws.nav_progress")

T.test("each stage says what is happening, with the time taken", function()
	T.eq(P.Body(P.OPENING, 5, 0), "Opening doors and laying bridges... 0:05")
	T.eq(P.Body(P.GENERATING, 83, 0), "Generating... 1:23")
	T.eq(P.Body(P.DONE, 125, 2426), "Done in 2:05: 2426 areas, saved")
end)

T.test("the title says what is happening and asks to wait", function()
	T.eq(P.TITLE, "Calculating navigation mesh, please wait...")
end)

T.test("below, it tells the player what to do and what happens next", function()
	T.eq(table.concat(P.DESCRIPTION, "\n"), "Stay connected: this runs once for this map and takes a few minutes.\n"
		.. "When it is done, the map restarts by itself and play begins.")
end)

T.test("generating, it says the engine's latest step once the engine reports one", function()
	T.eq(P.Body(P.GENERATING, 83, 0, "Sampling walkable space..."), "Sampling walkable space... 1:23")
	T.eq(P.Body(P.GENERATING, 83, 0, ""), "Generating... 1:23", "nothing reported yet")
	T.eq(P.Body(P.OPENING, 5, 0, "Sampling walkable space..."), "Opening doors and laying bridges... 0:05",
		"an earlier run's step does not show while doors open")
end)

T.test("the bar runs until it is done, then is full", function()
	T.eq(P.Fraction(P.OPENING), nil, "running: no fraction to show")
	T.eq(P.Fraction(P.GENERATING), nil)
	T.eq(P.Fraction(P.DONE), 1)
end)

T.test("generating, the bar shows the engine's progress through its step", function()
	T.eq(P.Fraction(P.GENERATING, 0.4), 0.4)
	T.eq(P.Fraction(P.OPENING, 0.4), nil, "an earlier run's progress does not show while doors open")
	T.eq(P.Fraction(P.DONE, 0.4), 1)
end)

T.test("the box stays up a moment after it is done, then goes", function()
	T.eq(P.Showing(P.GENERATING, 0, 999), true, "while it runs")
	T.eq(P.Showing(P.DONE, 10, 10 + P.LINGER - 1), true, "just done")
	T.eq(P.Showing(P.DONE, 10, 10 + P.LINGER + 1), false, "gone")
	T.eq(P.Showing(P.IDLE, 0, 0), false, "nothing running")
end)

T.test("the upgrade music fades in a while after it starts, and stops when done", function()
	T.defined(P.MUSIC_DELAY, "seconds of silence first")
	T.defined(P.MUSIC_FADE, "seconds to full volume")
	T.eq(P.MusicVolume(P.OPENING, 0), 0, "silent at first")
	T.eq(P.MusicVolume(P.GENERATING, P.MUSIC_DELAY), 0, "silent until the delay is up")
	T.near(P.MusicVolume(P.GENERATING, P.MUSIC_DELAY + P.MUSIC_FADE / 2), 0.5, 1e-9, "half way in")
	T.eq(P.MusicVolume(P.GENERATING, P.MUSIC_DELAY + P.MUSIC_FADE * 3), 1, "full, then held")
	T.eq(P.MusicVolume(P.DONE, P.MUSIC_DELAY + P.MUSIC_FADE * 3), 0, "done: none")
	T.eq(P.MusicVolume(P.IDLE, P.MUSIC_DELAY + P.MUSIC_FADE * 3), 0, "nothing running")
end)

T.finish()
