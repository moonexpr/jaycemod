-- What the nav mesh progress box says while mp_nav_generate runs
-- (wetsand/sh_nav_progress.lua). GMod reports no progress, so it tells the
-- stage and the time it has taken, the bar runs until it is done, and the
-- areas made show at the end, LINGER seconds.
local floor, format = math.floor, string.format
module(...)

IDLE, OPENING, GENERATING, DONE = 0, 1, 2, 3
LINGER = 8

local function Clock(seconds)
	seconds = floor(seconds)
	return format("%d:%02d", floor(seconds / 60), seconds % 60)
end

function Body(stage, elapsed, areas)
	if stage == OPENING then return "Opening doors and laying bridges... " .. Clock(elapsed) end
	if stage == GENERATING then return "Generating... " .. Clock(elapsed) end
	return format("Done in %s: %d areas, saved", Clock(elapsed), areas)
end

-- 1 when done; nil while it runs, the bar showing only that it runs.
function Fraction(stage)
	if stage == DONE then return 1 end
	return nil
end

-- Whether the box shows at now: while it runs, and LINGER after it is done
-- (doneAt).
function Showing(stage, doneAt, now)
	if stage == IDLE then return false end
	if stage == DONE then return now - doneAt <= LINGER end
	return true
end
