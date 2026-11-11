-- Looks: which of the war's bot soldiers take their look this tick. A look is dear (its sight
-- traces, its route planned anew), and soldiers enlisted or respawned in one wave come due in one
-- tick and, left alone, in every same tick after: a team of eight looking at once fills a tick.
-- So a tick takes only its share of the looks an interval holds, the most overdue first; the rest
-- stay due and look in the ticks after, from when each is next due apart, so a wave is spread
-- within one interval and stays spread.
--   Share(count, interval, tick) -> how many of count lookers may look in a tick of that length
--     for each to look once an interval: the fewest that an interval's ticks take them all by.
--   Due(lookers, now, share, dueAt) -> the lookers due (dueAt(looker) <= now), the most overdue
--     first and a tie in the order given, no more than share of them.
--   Roster(term) -> the fighters a look is shown that seldom change (buildings, monsters), found
--     by a walk too dear for every tick: roster:Of(now, find, fit) -> find()'s list, found again
--     once term has passed since it was, those of it fit(fighter) now, as a list of the caller's.
--     So one that dies is gone at once, and a new one is seen by the next walk.
local ceil, floor, ipairs, max, setmetatable = math.ceil, math.floor, ipairs, math.max, setmetatable
local TopK = list.select.TopK
module (...)

-- Over the whole ticks an interval holds: part of a tick takes no look.
function Share (count, interval, tick)
	return ceil (count / max (1, floor (interval / tick)))
end

function Due (lookers, now, share, dueAt)
	local due = {}
	for _, looker in ipairs (lookers) do
		if dueAt (looker) <= now then due [#due + 1] = looker end
	end
	return TopK (due, share, function (a, b) return dueAt (a) < dueAt (b) end)
end

local Roster_ = {}
Roster_.__index = Roster_

function Roster (term)
	return setmetatable ({ term = term, found = nil, foundAt = nil }, Roster_)
end

function Roster_:Of (now, find, fit)
	if not self.found or now - self.foundAt >= self.term then self.found, self.foundAt = find (), now end
	local fitting = {}
	for _, fighter in ipairs (self.found) do
		if fit (fighter) then fitting [#fitting + 1] = fighter end
	end
	return fitting
end
