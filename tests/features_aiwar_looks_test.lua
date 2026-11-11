-- features.aiwar.looks: which of the soldiers due a look take it this tick, so that the looks of an
-- interval are spread over its ticks and never land in one.
local T = dofile ("tests/harness.lua")
local Looks = T.require ("features.aiwar.looks")

local INTERVAL, TICK = 0.2, 0.015

local function At (looker) return looker.nextLook end

local function Lookers (count, due)
	local lookers = {}
	for i = 1, count do lookers [i] = { name = i, nextLook = due } end
	return lookers
end

T.test ("a tick's share is enough for every looker to look once an interval, and no more than they are", function ()
	local ticks = math.floor (INTERVAL / TICK)
	for count = 1, 64 do
		local share = Looks.Share (count, INTERVAL, TICK)
		T.eq (share >= 1,                  true, "at least one a tick: " .. count)
		T.eq (share * ticks >= count,      true, "an interval's ticks take them all: " .. count)
		T.eq (share <= count,              true, "never more than there are: " .. count)
		T.eq ((share - 1) * ticks < count, true, "no larger than it needs to be: " .. count)
	end
	T.eq (Looks.Share (0, INTERVAL, TICK), 0, "no lookers, no looks")
end)

T.test ("only the lookers due look, the most overdue first, and a tie in the order given", function ()
	local lookers =
	{
		{ name = "later", nextLook = 5 },
		{ name = "due", nextLook = 2 },
		{ name = "overdue", nextLook = 1 },
		{ name = "tied", nextLook = 2 },
		{ name = "new", nextLook = 0 }
	}
	local due = Looks.Due (lookers, 2, #lookers, At)
	local names = {}
	for i, looker in ipairs (due) do names [i] = looker.name end
	T.eq (table.concat (names, " "), "new overdue due tied", "who looks, in order")
end)

T.test ("no more look in a tick than its share; the rest stay due", function ()
	local lookers = Lookers (5, 0)
	lookers [4].nextLook = -1
	local due = Looks.Due (lookers, 0, 2, At)
	T.eq (#due,                           2, "the share")
	T.eq (due [1].name,                   4, "the most overdue is not the one left waiting")
	T.eq (#Looks.Due (lookers, 0, 0, At), 0, "no share, no looks")
end)

T.test ("lookers all due at once are spread over the ticks, and each still looks about once an interval", function ()
	local count = 16
	local lookers = Lookers (count, 0)
	local share = Looks.Share (count, INTERVAL, TICK)
	local last, longest, most = {}, 0, 0
	local now = 0
	for _ = 1, 400 do
		local due = Looks.Due (lookers, now, share, At)
		most = math.max (most, #due)
		for _, looker in ipairs (due) do
			if last [looker] then longest = math.max (longest, now - last [looker]) end
			last [looker] = now
			looker.nextLook = now + INTERVAL
		end
		now = now + TICK
	end
	T.eq (most <= share, true, "never more than the share in one tick")
	for _, looker in ipairs (lookers) do T.eq (last [looker] ~= nil, true, "everyone looked: " .. looker.name) end
	-- a looker waits its interval, to the tick after, and at worst for everyone before it once
	T.eq (longest <= INTERVAL + TICK * (1 + math.ceil (count / share)), true, "no one waits much past its interval")
	-- once spread they stay spread: the steady state needs no waiting at all
	local waited = 0
	for _ = 1, 200 do
		for _, looker in ipairs (lookers) do
			if looker.nextLook <= now - TICK then waited = waited + 1 end
		end
		for _, looker in ipairs (Looks.Due (lookers, now, share, At)) do looker.nextLook = now + INTERVAL end
		now = now + TICK
	end
	T.eq (waited, 0, "no looker is left waiting once they are spread")
end)

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
