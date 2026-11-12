-- foundation.list.calendar: recurring jobs, a budget a tick, fair across
-- systems and earliest due first within one, lateness as output.
local T = dofile ("tests/harness.lua")
local Calendar = list.calendar

-- A clock the test sets: the game's time, which jobs are due by.
local function Clock ()
	local clock = { t = 0 }
	function clock:Now () return self.t end
	return clock
end

-- A calendar on a clock and a timer the test moves; a job spends by moving
-- the timer.
local function Fixture ()
	local clock, timer = Clock (), Clock ()
	return Calendar.New (clock, timer), clock, timer
end

local function Raises (fn, ...)
	local ok, err = pcall (fn, ...)
	T.eq (ok, false, "raises")
	return tostring (err)
end

T.test ("a job runs when it is due and again a period after it was due", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local runs = {}
	calendar:Every ("war", 2, function (_, now) runs [#runs + 1] = now end, 1)
	calendar:Run (1)
	T.eq (#runs, 0, "not due at 0")
	clock.t = 1
	calendar:Run (1)
	T.eq (#runs, 1, "due at 1")
	calendar:Run (1)
	T.eq (#runs, 1, "once a time it is due")
	clock.t = 2.5
	calendar:Run (1)
	T.eq (#runs, 1, "next due at 3")
	clock.t = 3
	calendar:Run (1)
	T.eq (runs [2], 3, "at 3")
end)

T.test ("a job first due now when no time is given", function ()
	local calendar, clock = Fixture ()
	clock.t = 7
	calendar:System ("war", 1)
	local ran = 0
	calendar:Every ("war", 1, function () ran = ran + 1 end)
	calendar:Run (1)
	T.eq (ran, 1, "ran at once")
end)

T.test ("a job late by more than its period skips the runs it missed and keeps its phase", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local runs = {}
	local job = calendar:Every ("war", 1, function (_, now) runs [#runs + 1] = now end, 0)
	clock.t = 3.5
	calendar:Run (1)
	T.eq (#runs,                 1, "one run for the missed ones")
	T.eq (calendar:Job (job).at, 4, "next due on its phase, after now")
	calendar:Run (1)
	T.eq (#runs, 1, "not again at 3.5")
end)

T.test ("a job's answer sets when it is next due: seconds from now, or false to leave", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local spans = { 0.5, false }
	local runs = 0
	local job = calendar:Every ("war", 10, function ()
		runs = runs + 1
		return spans [runs]
	end, 2)
	clock.t = 3
	calendar:Run (1)
	T.eq (calendar:Job (job).at, 3.5, "an attention span from when it ran, not from when it was due")
	clock.t = 3.5
	calendar:Run (1)
	T.eq (runs,               2,   "ran again")
	T.eq (calendar:Size (),   0,   "and left")
	T.eq (calendar:Job (job), nil, "known no more")
end)

T.test ("within a system the earliest due runs first, a tie in the order added", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local order = {}
	local function Job (name) return function () order [#order + 1] = name end end
	calendar:Every ("war", 10, Job ("c"),  3)
	calendar:Every ("war", 10, Job ("a"),  1)
	calendar:Every ("war", 10, Job ("b1"), 2)
	calendar:Every ("war", 10, Job ("b2"), 2)
	clock.t = 5
	calendar:Run (1)
	T.eq (table.concat (order, " "), "a b1 b2 c", "earliest deadline first")
end)

T.test ("a run stops once its time is spent, and the rest run next, the most overdue first", function ()
	local calendar, clock, timer = Fixture ()
	calendar:System ("war", 1)
	local order = {}
	for i = 1, 4 do
		calendar:Every ("war", 10, function ()
			order [#order + 1] = i
			timer.t = timer.t + 0.002
		end, i)
	end
	clock.t = 5
	T.eq (calendar:Run (0.003),      2,         "two of 2 ms fit 3 ms: the second overruns, charged after")
	T.eq (table.concat (order, " "), "1 2",     "the first two")
	T.eq (calendar:Run (0.003),      2,         "the rest")
	T.eq (table.concat (order, " "), "1 2 3 4", "in their order")
end)

T.test ("a run takes no more jobs than its count", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local ran = 0
	for i = 1, 5 do calendar:Every ("war", 10, function () ran = ran + 1 end, i) end
	clock.t = 5
	T.eq (calendar:Run (1, 2), 2, "two")
	T.eq (ran,                 2, "ran two")
	T.eq (calendar:Run (1),    3, "and the rest when uncounted")
end)

-- Two systems, each with more due than a run takes: each job costs 1 ms.
local function Contend (weights, runs)
	local calendar, clock, timer = Fixture ()
	local spent = {}
	for name, weight in pairs (weights) do
		calendar:System (name, weight)
		spent [name] = 0
		for _ = 1, 50 do
			calendar:Every (name, 0.001, function ()
				timer.t = timer.t + 0.001
				spent [name] = spent [name] + 0.001
			end, 0)
		end
	end
	for _ = 1, runs do
		calendar:Run (0.010)
		clock.t = clock.t + 0.015
	end
	return spent, calendar
end

T.test ("systems with work share the time by their weights", function ()
	local spent = Contend ({ war = 1, searches = 3 }, 100)
	T.near (spent.searches / spent.war, 3, 0.1, "three to one")
end)

T.test ("a system is served after another furthest behind it, so neither starves", function ()
	local calendar, clock, timer = Fixture ()
	calendar:System ("war",          1)
	calendar:System ("transactions", 1)
	local order = {}
	for _, name in ipairs ({ "war", "transactions" }) do
		for _ = 1, 3 do
			calendar:Every (name, 10, function ()
				order [#order + 1] = name:sub (1, 1)
				timer.t = timer.t + 0.001
			end, 0)
		end
	end
	calendar:Run (1)
	T.eq (table.concat (order), "wtwtwt", "taking turns, the one added first on a tie")
end)

T.test ("a system idle a while banks no credit: it joins at the others' standing", function ()
	local calendar, clock, timer = Fixture ()
	calendar:System ("war",      1)
	calendar:System ("searches", 1)
	for _ = 1, 20 do
		calendar:Every ("war", 0.001, function () timer.t = timer.t + 0.001 end, 0)
	end
	for _ = 1, 50 do calendar:Run (0.010) clock.t = clock.t + 0.015 end
	local before = calendar:Report ().war.spent
	local searched = 0
	for _ = 1, 20 do
		calendar:Every ("searches", 0.001, function ()
			timer.t = timer.t + 0.001
			searched = searched + 0.001
		end, clock.t)
	end
	for _ = 1, 10 do calendar:Run (0.010) clock.t = clock.t + 0.015 end
	local war = calendar:Report ().war.spent - before
	T.near (searched / (searched + war), 0.5, 0.1, "half each since it joined, not all of it to catch up")
end)

T.test ("Wake brings a job sooner, once; a later time leaves it as it was", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local ran = 0
	local job = calendar:Every ("war", 5, function () ran = ran + 1 end, 10)
	calendar:Wake (job, 20)
	T.eq (calendar:Job (job).at, 10, "not later")
	clock.t = 5
	calendar:Wake (job)
	T.eq (calendar:Job (job).at, 5, "now")
	calendar:Run (1)
	T.eq (ran,                   1,  "ran when woken")
	T.eq (calendar:Job (job).at, 10, "next a period after it was due: the time it was first due")
	clock.t = 10
	calendar:Run (1)
	T.eq (ran, 2, "once at 10, though it was due there twice")
end)

T.test ("a job woken while it runs is due no later than the wake", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local job
	job = calendar:Every ("war", 5, function (self, now) calendar:Wake (self, now + 1) end, 0)
	calendar:Run (1)
	T.eq (calendar:Job (job).at, 1, "the wake, before its period")
end)

T.test ("Cancel takes a job out, from outside or from within its own run", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local ran = 0
	local other = calendar:Every ("war", 1, function () ran = ran + 100 end, 0)
	calendar:Every ("war", 1, function (self) ran = ran + 1 calendar:Cancel (self) end, 0)
	calendar:Cancel (other)
	T.eq (calendar:Size (), 1, "one left")
	calendar:Run (1)
	clock.t = 5
	calendar:Run (1)
	T.eq (ran,              1, "the cancelled never ran, the other once")
	T.eq (calendar:Size (), 0, "none left")
	T.eq (#calendar,        0, "__len")
end)

T.test ("lateness is reported a job and a system, and a report can start the counts again", function ()
	local calendar, clock, timer = Fixture ()
	calendar:System ("war", 2)
	local slow = calendar:Every ("war", 10, function () timer.t = timer.t + 0.004 end, 1)
	local quick = calendar:Every ("war", 10, function () timer.t = timer.t + 0.001 end, 2)
	clock.t = 3
	calendar:Run (0.002)
	local report = calendar:Report ()
	T.eq (report.war.runs, 1, "the slow one ran, overrunning")
	T.near (report.war.spent, 0.004, 1e-12, "what it spent")
	T.eq (report.war.late,          2, "2 s late")
	T.eq (report.war.lateMax,       2, "the worst")
	T.eq (report.war.behind,        1, "one due and not run")
	T.eq (report.war.weight,        2, "its weight")
	T.eq (report.war.jobs,          2, "its jobs")
	T.eq (calendar:Job (slow).late, 2, "the job's own")
	clock.t = 4
	calendar:Run (1)
	report = calendar:Report (true)
	T.eq (report.war.runs,             2, "both")
	T.eq (report.war.late,             4, "2 and 2")
	T.eq (report.war.lateMax,          2, "the worst")
	T.eq (report.war.behind,           0, "none behind")
	T.eq (calendar:Job (quick).runs,   1, "its runs")
	T.eq (calendar:Report ().war.runs, 0, "counted from the reset")
end)

T.test ("a job's error is raised from the run, the job taken out first", function ()
	local calendar, clock = Fixture ()
	calendar:System ("war", 1)
	local ran = 0
	calendar:Every ("war", 1, function () error ("broken job") end, 0)
	calendar:Every ("war", 1, function () ran = ran + 1 end,        0)
	T.eq (Raises (calendar.Run, calendar, 1):find ("broken job", 1, true) ~= nil, true, "its message")
	T.eq (calendar:Size (),                                                       1,    "the broken one gone")
	calendar:Run (1)
	T.eq (ran, 1, "the rest go on")
end)

T.test ("systems and jobs refuse what is not one", function ()
	local calendar = Fixture ()
	Raises (calendar.System, calendar, 1,     1)
	Raises (calendar.System, calendar, "war", 0)
	Raises (calendar.System, calendar, "war", -1)
	calendar:System ("war", 1)
	Raises (calendar.System, calendar, "war", 1)
	Raises (calendar.Every, calendar, "nobody", 1, function () end)
	Raises (calendar.Every, calendar, "war",    0, function () end)
	Raises (calendar.Every, calendar, "war",    1, "not a function")
end)

-- The AI war's looks: a wave of soldiers enlisted in one tick all due at once, each look a job
-- that answers its interval (an attention span from when it ran), a run a tick on a budget.
T.test ("jobs all due at once that answer their span are spread over the ticks, and stay spread", function ()
	local INTERVAL, TICK, COST, BUDGET, COUNT = 0.2, 0.015, 0.001, 0.003, 16
	local calendar, clock, timer = Fixture ()
	calendar:System ("looks", 1)
	local last, longest, most, ran = {}, 0, 0, 0
	for i = 1, COUNT do
		calendar:Every ("looks", INTERVAL, function (_, now)
			if last [i] then longest = math.max (longest, now - last [i]) end
			last [i] = now
			ran = ran + 1
			timer.t = timer.t + COST
			return INTERVAL
		end, 0)
	end
	local perTick = math.ceil (BUDGET / COST)
	for _ = 1, 400 do
		ran = 0
		calendar:Run (BUDGET)
		most = math.max (most, ran)
		clock.t = clock.t + TICK
	end
	T.eq (most <= perTick, true, "never more than the budget takes in one tick")
	for i = 1, COUNT do T.eq (last [i] ~= nil, true, "everyone ran: " .. i) end
	-- a job waits its span, to the tick after, and at worst for everyone before it once
	T.eq (longest <= INTERVAL + TICK * (1 + math.ceil (COUNT / perTick)), true, "no one waits much past its span")
	local behind = 0
	for _ = 1, 200 do
		calendar:Run (BUDGET)
		behind = behind + calendar:Report ().looks.behind
		clock.t = clock.t + TICK
	end
	T.eq (behind, 0, "none is left behind once they are spread")
end)

T.finish ()
