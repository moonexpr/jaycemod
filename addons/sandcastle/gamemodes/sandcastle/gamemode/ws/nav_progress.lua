-- What the nav mesh progress box says while mp_nav_generate runs
-- (ws/sh_nav_progress.lua). It tells the stage and the time it has taken;
-- generating, the engine's latest step and its progress through it, read
-- by each client from the engine's own progress box (the server learns
-- neither), the bar running until the engine reports; and the areas made
-- show at the end, LINGER seconds. While it runs, MvM's upgrade
-- station music plays, silent for MUSIC_DELAY seconds, then fading in over
-- MUSIC_FADE.
local floor, format = math.floor, string.format
local Scalar = math.scalar
module(...)

IDLE, OPENING, GENERATING, DONE = 0, 1, 2, 3
LINGER = 8
TITLE = "Calculating navigation mesh, please wait..."
-- Below the title and the stage, what the player is to do, a line each.
DESCRIPTION = {
	"Stay connected: this runs once for this map and takes a few minutes.",
	"When it is done, the map restarts by itself and play begins.",
}
MUSIC = "items/tf_music_upgrade_machine.wav"
MUSIC_DELAY, MUSIC_FADE = 10, 15

local function Clock(seconds)
	seconds = floor(seconds)
	return format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- step: the engine's latest, "" before it reports one.
function Body(stage, elapsed, areas, step)
	if stage == OPENING then return "Opening doors and laying bridges... " .. Clock(elapsed) end
	if stage == GENERATING then return (step ~= "" and step or "Generating...") .. " " .. Clock(elapsed) end
	return format("Done in %s: %d areas, saved", Clock(elapsed), areas)
end

-- 1 when done; generating, the engine's progress through its step
-- (stepFraction, nil before it reports); otherwise nil, the bar showing
-- only that it runs.
function Fraction(stage, stepFraction)
	if stage == DONE then return 1 end
	if stage == GENERATING then return stepFraction end
	return nil
end

-- The music's volume, 0 to 1, elapsed seconds after the client's box
-- first showed (its own clock, so no two clocks disagree): none until
-- MUSIC_DELAY, rising to full over MUSIC_FADE, none once done.
function MusicVolume(stage, elapsed)
	if stage ~= OPENING and stage ~= GENERATING then return 0 end
	return Scalar.Saturate((elapsed - MUSIC_DELAY) / MUSIC_FADE)
end

-- Whether the box shows at now: while it runs, and LINGER after it is done
-- (doneAt).
function Showing(stage, doneAt, now)
	if stage == IDLE then return false end
	if stage == DONE then return now - doneAt <= LINGER end
	return true
end
