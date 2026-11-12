-- features.aiwar.looks: what a bot soldier's look is shown. How the looks are spread over the
-- ticks is the war's calendar's (tests/list_calendar_test.lua).
local T = dofile ("tests/harness.lua")
local Looks = T.require ("features.aiwar.looks")

-- A roster's term, and a tick within it.
local INTERVAL, TICK = 0.2, 0.015

T.test ("a roster finds its fighters once a term, however often it is asked", function ()
	local roster = Looks.Roster (INTERVAL)
	local walks = 0
	local function Find ()
		walks = walks + 1
		return { "sentry", "zombie" }
	end
	local function Fit () return true end
	for step = 0, 9 do roster:Of (step * INTERVAL / 10, Find, Fit) end
	T.eq (walks,                                               1,               "one walk within the term")
	T.eq (table.concat (roster:Of (INTERVAL, Find, Fit), " "), "sentry zombie", "found again once the term has passed")
	T.eq (walks,                                               2,               "a second walk")
end)

T.test ("a fighter no longer fit is left out at once, and back when it is fit again; a new one waits for the next walk", function ()
	local roster = Looks.Roster (INTERVAL)
	local world, dead = { "sentry", "zombie" }, {}
	local function Find ()
		local found = {}
		for i, fighter in ipairs (world) do found [i] = fighter end
		return found
	end
	local function Fit (fighter) return not dead [fighter] end
	T.eq (table.concat (roster:Of (0, Find, Fit), " "), "sentry zombie", "both at first")
	dead.sentry = true
	T.eq (table.concat (roster:Of (TICK, Find, Fit), " "), "zombie", "the dead one is gone within the term")
	dead.sentry = nil
	world [3] = "dispenser"
	T.eq (table.concat (roster:Of (2 * TICK, Find, Fit), " "), "sentry zombie", "fit again; the new one not yet found")
	T.eq (table.concat (roster:Of (INTERVAL, Find, Fit), " "), "sentry zombie dispenser", "found at the next walk")
end)

T.test ("what a roster hands out is the caller's to change", function ()
	local roster = Looks.Roster (INTERVAL)
	local function Find () return { "sentry" } end
	local function Fit () return true end
	local first = roster:Of (0, Find, Fit)
	first [#first + 1] = "added by the caller"
	T.eq (#roster:Of (TICK, Find, Fit), 1, "the roster's own list is untouched")
end)

T.finish ()
