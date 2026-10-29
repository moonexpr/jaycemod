-- foundation.transaction: refusals (a request the domain declines, the
-- caller's mistake, told apart from our own bugs by a marker compared by
-- value so it survives any reload), and transactions, which settle once as
-- committed, declined or failed, now or later.
local T = dofile("tests/harness.lua")
local Transaction = transaction

local KIND = "unknown weapon"
local OTHER_KIND = "bad catalog"
local KINDS = { [KIND] = true }

local function Raised(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raised")
	return err
end

T.test("a raised refusal carries its kind and detail and is recognised", function()
	local err = Raised(Transaction.Refuse, KIND, "bfg")
	T.eq(err.kind, KIND)
	T.eq(err.detail, "bfg")
	T.eq(Transaction.IsRefusal(err, KINDS), true)
end)

T.test("a refusal of a kind not asked about is not recognised", function()
	T.eq(Transaction.IsRefusal(Raised(Transaction.Refuse, OTHER_KIND, "x"), KINDS), false)
end)

T.test("our bugs are never refusals", function()
	local events_style = {
		kind = KIND,
		message = "an events.lua error with a kind the caller would accept",
	}
	T.eq(Transaction.IsRefusal(events_style, KINDS), false, "an events-style error")
	T.eq(Transaction.IsRefusal({
		refusal = KIND,
		kind = KIND,
		detail = "x",
	}, KINDS), false, "a marker that is not this module's value")
	T.eq(Transaction.IsRefusal("attempt to index a nil value", KINDS), false, "a runtime error")
	T.eq(Transaction.IsRefusal(nil, KINDS), false, "error(nil)")
end)

T.test("a refusal reads as its kind and detail", function()
	T.eq(Transaction.Message(Raised(Transaction.Refuse, KIND, "bfg")), "unknown weapon: bfg")
end)

T.test("explaining a refusal of an accepted kind gives its message", function()
	T.eq(Transaction.Explain(Raised(Transaction.Refuse, KIND, "bfg"), KINDS), "unknown weapon: bfg")
end)

T.test("explaining anything else rethrows it unchanged", function()
	local events_style = {
		kind = KIND,
		message = "ours",
	}
	T.eq(rawequal(Raised(Transaction.Explain, events_style, KINDS), events_style), true, "an events-style error")
	local other = Raised(Transaction.Refuse, OTHER_KIND, "x")
	T.eq(rawequal(Raised(Transaction.Explain, other, KINDS), other), true, "a refusal of another kind")
	T.eq(Raised(Transaction.Explain, "boom", KINDS), "boom", "a runtime error, without a position added")
end)

T.test("Detail is the refusal's words for the player, and rethrows anything else", function()
	local err = Raised(Transaction.Refuse, KIND, "You cannot do that.")
	T.eq(Transaction.Detail(err, KINDS), "You cannot do that.")
	local other = Raised(Transaction.Refuse, OTHER_KIND, "x")
	T.eq(rawequal(Raised(Transaction.Detail, other, KINDS), other), true, "a refusal of another kind")
	T.eq(Raised(Transaction.Detail, "boom", KINDS), "boom", "a runtime error")
end)

T.test("a refusal raised before a rerun of transaction.lua is recognised by the new code", function()
	local err = Raised(Transaction.Refuse, KIND, "bfg")
	package.loaded["foundation.transaction"] = nil
	local Rerun = transaction
	T.eq(Rerun.IsRefusal(err, KINDS), true)
end)

-- Transactions -------------------------------------------------------------------

local Scheduler = list.schedule

local function Clock()
	return { Now = function() return 0 end }
end

T.test("a transaction settles once: committed with a value", function()
	local tx = Transaction.New()
	T.eq(tx:State(), Transaction.PENDING, "pending")
	tx:Commit(42)
	T.eq(tx:State(), Transaction.COMMITTED, "committed")
	T.eq(tx:Value(), 42, "its value")
	T.eq(pcall(tx.Commit, tx, 1), false, "settling again is our bug")
	T.eq(pcall(tx.Decline, tx, KIND, "x"), false, "so is declining it after")
end)

T.test("declined carries the refusal; failed carries our error", function()
	local declined = Transaction.New()
	declined:Decline(KIND, "bfg")
	T.eq(declined:State(), Transaction.DECLINED, "declined")
	T.eq(Transaction.IsRefusal(declined:Refusal(), KINDS), true, "a refusal of its kind")
	T.eq(declined:Refusal().detail, "bfg", "its detail")
	local failed = Transaction.New()
	failed:Fail("boom")
	T.eq(failed:State(), Transaction.FAILED, "failed")
	T.eq(failed:Error(), "boom", "our error")
end)

T.test("settle callbacks run once each, in order, before or after settling", function()
	local tx, log = Transaction.New(), {}
	tx:OnSettle(function(t) log[#log + 1] = "first " .. t:State() end)
	tx:OnSettle(function() log[#log + 1] = "second" end)
	tx:Commit()
	tx:OnSettle(function() log[#log + 1] = "late" end)
	T.eq(table.concat(log, ", "), "first committed, second, late", "in order")
end)

T.test("running work commits its result, declines its refusal, fails on our bug", function()
	T.eq(Transaction.Run(function(work, a, b) return a + b end, 2, 3):Value(), 5, "committed")
	local declined = Transaction.Run(function() Transaction.Refuse(KIND, "no") end)
	T.eq(declined:State(), Transaction.DECLINED, "declined")
	T.eq(declined:Refusal().kind, KIND, "the refusal")
	local failed = Transaction.Run(function() error("broken") end)
	T.eq(failed:State(), Transaction.FAILED, "failed")
	T.eq(tostring(failed:Error()):find("broken", 1, true) ~= nil, true, "the error")
end)

T.test("a declined or failed transaction undoes its done steps, newest first", function()
	local log = {}
	local tx = Transaction.Run(function(work)
		log[#log + 1] = "pay"
		work:Undo(function() log[#log + 1] = "refund" end)
		log[#log + 1] = "reserve"
		work:Undo(function() log[#log + 1] = "release" end)
		Transaction.Refuse(KIND, "out of stock")
	end)
	T.eq(tx:State(), Transaction.DECLINED, "declined")
	T.eq(table.concat(log, ", "), "pay, reserve, release, refund", "undone in reverse")
	log = {}
	Transaction.Run(function(work)
		work:Undo(function() log[#log + 1] = "undo" end)
		error("bug")
	end)
	T.eq(log[1], "undo", "a failure undoes too")
	log = {}
	Transaction.Run(function(work) work:Undo(function() log[#log + 1] = "undo" end) end)
	T.eq(#log, 0, "a commit keeps its steps")
end)

T.test("an undo that breaks fails the transaction, naming both errors", function()
	local tx = Transaction.Run(function(work)
		work:Undo(function() error("refund broke") end)
		Transaction.Refuse(KIND, "no")
	end)
	T.eq(tx:State(), Transaction.FAILED, "failed")
	T.eq(tostring(tx:Error()):find("refund broke", 1, true) ~= nil, true, "the undo's error")
end)

T.test("spawned work runs asynchronously, on the scheduler's runs", function()
	local scheduler = Scheduler.New(Clock())
	local tx = Transaction.Spawn(scheduler, function(work, x) return x * 2 end, 21)
	T.eq(tx:State(), Transaction.PENDING, "not yet")
	scheduler:Run(1)
	T.eq(tx:Value(), 42, "committed by the run")
end)

T.test("awaiting a transaction parks the task until it settles, then gives its value", function()
	local scheduler = Scheduler.New(Clock())
	local inner = Transaction.New()
	local outer = Transaction.Spawn(scheduler, function() return inner:Await(scheduler) + 1 end)
	scheduler:Run(1)
	T.eq(outer:State(), Transaction.PENDING, "waiting on the inner one")
	inner:Commit(9)
	scheduler:Run(1)
	T.eq(outer:Value(), 10, "went on with its value")
end)

T.test("awaiting a declined transaction declines the awaiting one with the same refusal", function()
	local scheduler = Scheduler.New(Clock())
	local inner = Transaction.New()
	local log = {}
	local outer = Transaction.Spawn(scheduler, function(work)
		work:Undo(function() log[#log + 1] = "undone" end)
		inner:Await(scheduler)
	end)
	scheduler:Run(1)
	inner:Decline(KIND, "sold out")
	scheduler:Run(1)
	T.eq(outer:State(), Transaction.DECLINED, "declined")
	T.eq(outer:Refusal().detail, "sold out", "the same refusal")
	T.eq(log[1], "undone", "its steps undone")
	local failing = Transaction.New()
	local after = Transaction.Spawn(scheduler, function() failing:Await(scheduler) end)
	failing:Fail("ours")
	scheduler:Run(1)
	T.eq(after:State(), Transaction.FAILED, "a failure fails it")
end)

T.test("awaiting outside a task is our bug", function()
	T.eq(pcall(Transaction.New().Await, Transaction.New(), Scheduler.New(Clock())), false, "refused")
end)

T.test("all of several commits with their values in order, or settles as the first that does not", function()
	local a, b = Transaction.New(), Transaction.New()
	local both = Transaction.All({ a, b })
	b:Commit("b")
	T.eq(both:State(), Transaction.PENDING, "waits for every one")
	a:Commit("a")
	T.eq(table.concat(both:Value(), " "), "a b", "values in the given order")
	local c, d = Transaction.New(), Transaction.New()
	local either = Transaction.All({ c, d })
	d:Decline(KIND, "no")
	T.eq(either:State(), Transaction.DECLINED, "the first decline")
	c:Commit()
	T.eq(either:State(), Transaction.DECLINED, "and stays so")
	T.eq(Transaction.All({}):State(), Transaction.COMMITTED, "all of none")
end)

-- Over the wire -----------------------------------------------------------------

T.test("a reply tells the outcome; a failure tells nothing of ours", function()
	local committed = Transaction.Run(function() return 1 end)
	local reply = Transaction.Reply(committed)
	T.eq(reply.state, Transaction.COMMITTED, "committed")
	local declined = Transaction.Run(function() Transaction.Refuse(KIND, "bfg") end)
	reply = Transaction.Reply(declined)
	T.eq(reply.kind, KIND, "the refusal's kind")
	T.eq(reply.detail, "bfg", "its detail")
	reply = Transaction.Reply(Transaction.Run(function() error("secret path") end))
	T.eq(reply.state, Transaction.FAILED, "failed")
	T.eq(reply.detail, nil, "no detail")
	T.eq(pcall(Transaction.Reply, Transaction.New()), false, "a pending one has no reply")
end)

T.test("given the caller's kinds, a reply tells a decline of any other kind as failed", function()
	local declined = Transaction.Run(function() Transaction.Refuse(OTHER_KIND, "internal") end)
	T.eq(Transaction.Reply(declined, KINDS).state, Transaction.FAILED, "not the caller's mistake")
	T.eq(Transaction.Reply(declined, KINDS).detail, nil, "nothing of it told")
	local theirs = Transaction.Run(function() Transaction.Refuse(KIND, "bfg") end)
	T.eq(Transaction.Reply(theirs, KINDS).kind, KIND, "the caller's own")
end)

T.test("a ledger settles the transactions it opened from their replies", function()
	local ledger = Transaction.Ledger()
	local id, tx = ledger:Open(0, 5)
	local id2, tx2 = ledger:Open(0, 5)
	T.eq(id ~= id2, true, "each its own id")
	T.eq(ledger:Settle(id, { state = Transaction.COMMITTED }), true, "settled")
	T.eq(tx:State(), Transaction.COMMITTED, "committed")
	ledger:Settle(id2, { state = Transaction.DECLINED, kind = KIND, detail = "no" })
	T.eq(tx2:Refusal().detail, "no", "declined with the refusal")
	T.eq(ledger:Settle(id, { state = Transaction.COMMITTED }), false, "a reply for no open transaction")
	local id3, tx3 = ledger:Open(0, 5)
	ledger:Settle(id3, { state = Transaction.FAILED })
	T.eq(tx3:State(), Transaction.FAILED, "failed")
	T.eq(ledger:Count(), 0, "none open")
end)

T.test("a ledger declines a transaction with no reply by its deadline", function()
	local ledger = Transaction.Ledger()
	local id, tx = ledger:Open(10, 5)
	ledger:Expire(14)
	T.eq(tx:State(), Transaction.PENDING, "not yet")
	ledger:Expire(15)
	T.eq(tx:State(), Transaction.DECLINED, "timed out")
	T.eq(tx:Refusal().kind, Transaction.TIMED_OUT, "the timeout's kind")
	T.eq(ledger:Settle(id, { state = Transaction.COMMITTED }), false, "a late reply is dropped")
end)

T.test("ledger ids wrap within the wire's bits", function()
	local ledger = Transaction.Ledger()
	local seen = {}
	for _ = 1, 2 ^ Transaction.ID_BITS + 3 do
		local id = ledger:Open(0, 1)
		T.eq(id >= 0 and id < 2 ^ Transaction.ID_BITS, true, "in range")
		seen[id] = true
		ledger:Expire(1)
	end
end)

-- A transaction is a coroutine object ---------------------------------------------------
-- A spawned transaction's task is its coroutine: it yields (work:Yield,
-- CheckYield, Wait, WaitFor, Await) to give the rest of the tick to
-- synchronous systems, and carries a deadline, a timer.countdown
-- (tx:Within): one unfinished when it elapses is ended at its next turn,
-- its steps undone, and declined as TIMED_OUT.
local Countdown = timer.countdown

-- A clock the test sets by hand.
local function Moving()
	return { t = 0, Now = function(self) return self.t end }
end

local function Started(clock, seconds)
	local countdown = Countdown.New(clock)
	countdown:Start(seconds)
	return countdown
end

T.test("a spawned transaction past its countdown is ended, its steps undone, and declined as timed out", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local log, never = {}, Transaction.New()
	local tx = Transaction.Spawn(scheduler, function(work)
		work:Undo(function() log[#log + 1] = "undone" end)
		return never:Await(scheduler)
	end):Within(Started(clock, 5))
	scheduler:Run(1)
	T.eq(tx:State(), Transaction.PENDING, "waiting, within its time")
	T.near(tx:Remaining(), 5, 1e-9, "five seconds left")
	clock.t = 6
	scheduler:Run(1)
	T.eq(tx:State(), Transaction.DECLINED, "declined")
	T.eq(tx:Refusal().kind, Transaction.TIMED_OUT, "as timed out")
	T.eq(log[1], "undone", "its steps undone")
	T.eq(scheduler:Count(), 0, "its task gone")
end)

T.test("a transaction that settles in its time is not touched by the countdown", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local tx = Transaction.Spawn(scheduler, function() return "done" end):Within(Started(clock, 5))
	scheduler:Run(1)
	clock.t = 60
	scheduler:Run(1)
	T.eq(tx:Value(), "done", "committed")
end)

T.test("a transaction not yet started whose time is up never runs", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local ran = false
	local tx = Transaction.Spawn(scheduler, function() ran = true end):Within(Started(clock, 1))
	clock.t = 2
	scheduler:Run(1)
	T.eq(ran, false, "its work never ran")
	T.eq(tx:Refusal().kind, Transaction.TIMED_OUT, "timed out")
end)

T.test("a deadline is held to a pending transaction with a task, once, and a started countdown", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local countdown = Started(clock, 5)
	T.eq(pcall(Transaction.New().Within, Transaction.New(), countdown), false, "no task to limit")
	T.eq(pcall(Transaction.Run(function() end).Within, Transaction.Run(function() end), countdown), false, "settled")
	local tx = Transaction.Spawn(scheduler, function() end)
	T.eq(pcall(tx.Within, tx, {}), false, "not a countdown")
	T.eq(pcall(tx.Within, tx, Countdown.New(clock)), false, "not started: an unstarted countdown has elapsed")
	T.eq(tx:Within(countdown), tx, "chained")
	T.eq(pcall(tx.Within, tx, Started(clock, 9)), false, "one deadline")
end)

T.test("with no deadline a transaction has unlimited time", function()
	T.eq(Transaction.New():Remaining(), math.huge, "no deadline")
end)

T.test("work yields its turn: tasks interleave, a transaction a step at a time", function()
	local scheduler = Scheduler.New(Moving())
	local log = {}
	local function Steps(name)
		return function(work)
			for i = 1, 2 do
				log[#log + 1] = name .. i
				work:Yield()
			end
			return name
		end
	end
	local a, b = Transaction.Spawn(scheduler, Steps("a")), Transaction.Spawn(scheduler, Steps("b"))
	scheduler:Run(1)
	T.eq(table.concat(log, " "), "a1 b1 a2 b2", "interleaved")
	T.eq(a:Value() .. b:Value(), "ab", "both committed")
end)

T.test("work's CheckYield gives up the turn once the slice is spent", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local steps = 0
	local tx = Transaction.Spawn(scheduler, function(work)
		for _ = 1, 3 do
			steps = steps + 1
			clock.t = clock.t + 1
			work:CheckYield()
		end
	end)
	scheduler:Run(1)
	T.eq(steps, 1, "one step in the slice")
	for _ = 1, 3 do scheduler:Run(1) end
	T.eq(steps, 3, "a step a run")
	T.eq(tx:State(), Transaction.COMMITTED, "done over four runs")
end)

T.test("work waits for a condition, or for a countdown of its own: a slow system's sleep", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local ready, passes = false, 0
	local tx = Transaction.Spawn(scheduler, function(work)
		work:Wait(function() return ready end)
		passes = passes + 1
		local nap = Started(clock, 10)
		work:WaitFor(nap)
		passes = passes + 1
	end)
	scheduler:Run(1)
	T.eq(passes, 0, "waiting for the condition")
	ready = true
	scheduler:Run(1)
	T.eq(passes, 1, "past it, asleep")
	clock.t = 5
	scheduler:Run(1)
	T.eq(passes, 1, "still asleep")
	clock.t = 11
	scheduler:Run(1)
	T.eq(passes, 2, "woke")
	T.eq(tx:State(), Transaction.COMMITTED, "done")
end)

T.test("work awaits a transaction, and a deadline cuts the wait short", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local inner = Transaction.New()
	local outer = Transaction.Spawn(scheduler, function(work) return work:Await(inner) + 1 end)
	scheduler:Run(1)
	inner:Commit(41)
	scheduler:Run(1)
	T.eq(outer:Value(), 42, "went on with its value")
	local slow = Transaction.Spawn(scheduler, function(work) return work:Await(Transaction.New()) end):Within(Started(clock, 3))
	scheduler:Run(1)
	clock.t = 4
	scheduler:Run(1)
	T.eq(slow:Refusal().kind, Transaction.TIMED_OUT, "timed out waiting")
end)

T.test("work says how long it has left, a second countdown asleep within a deadline times out first", function()
	local clock = Moving()
	local scheduler = Scheduler.New(clock)
	local left
	local tx = Transaction.Spawn(scheduler, function(work)
		left = work:Remaining()
		work:WaitFor(Started(clock, 100))
	end):Within(Started(clock, 5))
	scheduler:Run(1)
	T.near(left, 5, 1e-9, "its deadline's")
	clock.t = 6
	scheduler:Run(1)
	T.eq(tx:Refusal().kind, Transaction.TIMED_OUT, "the deadline first")
	T.eq(Transaction.Spawn(scheduler, function(work) left = work:Remaining() end) ~= nil, true)
	scheduler:Run(1)
	T.eq(left, math.huge, "no deadline: unlimited")
end)

T.test("work of a transaction run at once has no scheduler to yield on (our bug)", function()
	local tx = Transaction.Run(function(work) work:Yield() end)
	T.eq(tx:State(), Transaction.FAILED, "failed")
end)

T.finish()
