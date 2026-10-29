-- Transactions: every exchange between a user and the system, or between
-- modules, as a value that settles once, now or later, as one of
--   COMMITTED  with a value: it happened
--   DECLINED   with a refusal: the caller's mistake, theirs to hear
--   FAILED     with an error: our bug, ours to log; a client learns only
--              that it failed
--
-- Refusals. A refusal is a plain table { refusal = true, kind, detail }, so
-- it is told apart from our own bugs by value. The marker is only ever set
-- here, and a kind is a string, so a refusal raised by code loaded before a
-- reload of any module is still recognised after it; nothing is compared
-- by table identity.
--   Refuse(kind, detail)      raises one: the domain declines the request
--   IsRefusal(err, kinds)     whether err is a refusal of one of kinds, a
--                             set of kind strings
--   Message(err)              "kind: detail"
--   Explain(err, kinds), Detail(err, kinds)   the message or the detail of
--                             a refusal of one of kinds; anything else, our
--                             bug, is rethrown unchanged
--
-- Transactions.
--   New() -> tx, pending: tx:Commit(value), tx:Decline(kind, detail),
--     tx:Fail(err) settle it (twice is our bug); tx:State(), tx:Value(),
--     tx:Refusal(), tx:Error(); tx:OnSettle(fn(tx)) runs fn once settled
--     (at once if it is); tx:Await(scheduler), in a scheduler task, parks it
--     until tx settles, then returns its value, raises its refusal, or
--     raises its error, so awaiting work reads straight down
--   Run(fn, ...) -> tx: fn(work, ...) now; its return commits, a refusal
--     declines, anything else fails
--   Spawn(scheduler, fn, ...) -> tx: the same as a task of a
--     foundation.list.schedule, so it may await other transactions
--
-- A spawned transaction is a coroutine object: its task is the coroutine,
-- and the systems that need not run every tick, or rapidly (admin
-- operations, the game rules, the tactics engine, anti-cheat), run as
-- transactions that yield, so combat, pathfinding and the player's feedback
-- keep the tick to run synchronously.
--   tx:Within(countdown) -> tx: gives it a time to settle in, a started
--     timer.countdown (anything with IsElapsed, GetRemainingTime and
--     HasStarted); one unfinished when it elapses is ended at its next turn
--     on the scheduler, its steps undone, and declined as TIMED_OUT. Only a
--     pending spawned transaction has a task to limit, and one deadline
--   tx:Remaining() the seconds left to it, math.huge with no deadline
--   work:Yield(), work:CheckYield() (yields once the scheduler's slice is
--     spent; whether it did), work:Wait(ready) (parks until ready() holds),
--     work:WaitFor(countdown) (parks until it has elapsed: a slow system's
--     sleep between passes), work:Await(tx) (parks until tx settles, then
--     its value, or its refusal or error raised: this one is ended), and
--     work:Remaining() give the task up to the scheduler, and are the
--     work's own: a transaction run at once has no scheduler, so yielding
--     is our bug. A deadline is read at the task's turns, never mid-step
--   work:Undo(fn) registers a compensation for a step just done: a
--     transaction that declines or fails runs them newest first (one that
--     breaks fails the transaction, naming both errors)
--   All(list) -> tx committing with the list's values in order once every
--     one commits, or settling as the first that declines or fails
--
-- Over the wire, a requester keeps a Ledger(): ledger:Open(now, timeout) ->
-- id, tx; ledger:Settle(id, reply) -> whether it was open; ledger:Expire(now)
-- declines what has no reply by its deadline (TIMED_OUT); ledger:Count().
-- The other side answers with Reply(tx[, kinds]) -> { state, kind, detail };
-- given the kinds that are the caller's mistake, a decline of any other kind
-- (our bug) is told as failed. A
-- scheduler is handed to Await and Spawn, never required here.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, huge, ipairs, pairs, pcall, setmetatable, tostring, type = error, math.huge, ipairs, pairs, pcall, setmetatable, tostring, type
module(...)

PENDING, COMMITTED, DECLINED, FAILED = "pending", "committed", "declined", "failed"

-- A request whose reply never came.
TIMED_OUT = "timed out"
TIMED_OUT_DETAIL = "The server did not answer in time."
-- A spawned transaction that did not settle within its countdown.
RAN_OUT_DETAIL = "The transaction ran out of time."

-- Wire ids are whole numbers below 2^ID_BITS, reused once they wrap.
ID_BITS = 16

-------------------------------------------------------------------------------
-- Refusals

local function NewRefusal(kind, detail)
	return {
		refusal = true,
		kind = kind,
		detail = detail,
	}
end

function Refuse(kind, detail)
	error(NewRefusal(kind, detail), 0)
end

local function IsAnyRefusal(err)
	return type(err) == "table" and err.refusal == true
end

function IsRefusal(err, kinds)
	return IsAnyRefusal(err) and kinds[err.kind] == true
end

function Message(err)
	return err.kind .. ": " .. err.detail
end

function Explain(err, kinds)
	if not IsRefusal(err, kinds) then error(err, 0) end
	return Message(err)
end

function Detail(err, kinds)
	if not IsRefusal(err, kinds) then error(err, 0) end
	return err.detail
end

-------------------------------------------------------------------------------
-- Transactions

local Tx = {}
Tx.__index = Tx

function New()
	return setmetatable({
		state = PENDING,
		callbacks = {},
	}, Tx)
end

local function Settle(tx, state, field, value)
	if tx.state ~= PENDING then error("a " .. tx.state .. " transaction cannot settle again", 3) end
	tx.state = state
	tx[field] = value
	local callbacks = tx.callbacks
	tx.callbacks = nil
	for _, fn in ipairs(callbacks) do fn(tx) end
end

function Tx:Commit(value) Settle(self, COMMITTED, "value", value) end
function Tx:Decline(kind, detail) Settle(self, DECLINED, "refusal", NewRefusal(kind, detail)) end
function Tx:Fail(err) Settle(self, FAILED, "err", err) end

function Tx:State() return self.state end
function Tx:Value() return self.value end
function Tx:Refusal() return self.refusal end
function Tx:Error() return self.err end

-- Whether the value is a started countdown, as a deadline is read.
local function IsStartedCountdown(countdown)
	return (type(countdown) == "table" or type(countdown) == "userdata")
		and type(countdown.IsElapsed) == "function" and type(countdown.GetRemainingTime) == "function"
		and type(countdown.HasStarted) == "function" and countdown:HasStarted()
end

function Tx:OnSettle(fn)
	if self.state == PENDING then
		self.callbacks[#self.callbacks + 1] = fn
	else
		fn(self)
	end
end

-- The settled transaction's outcome, as a return or a raise.
local function Outcome(tx)
	if tx.state == COMMITTED then return tx.value end
	if tx.state == DECLINED then error(tx.refusal, 0) end
	error(tx.err, 0)
end

function Tx:Await(scheduler)
	if self.state == PENDING then scheduler:Wait(function() return self.state ~= PENDING end) end
	return Outcome(self)
end

-- The work object handed to a transaction's function.
local Work = {}
Work.__index = Work

function Work:Undo(fn)
	self.undos[#self.undos + 1] = fn
end

-- The scheduler a spawned transaction's work yields on.
local function Scheduler(work)
	if not work.scheduler then error("this transaction runs at once: it has no scheduler to yield on", 3) end
	return work.scheduler
end

function Work:Yield()
	Scheduler(self):Yield()
end

function Work:CheckYield()
	return Scheduler(self):CheckYield()
end

function Work:Wait(ready)
	Scheduler(self):Wait(ready)
end

function Work:WaitFor(countdown)
	Scheduler(self):Wait(function() return countdown:IsElapsed() end)
end

function Work:Await(tx)
	local scheduler = Scheduler(self)
	if tx.state == PENDING then scheduler:Wait(function() return tx.state ~= PENDING end) end
	return Outcome(tx)
end

function Work:Remaining()
	local countdown = self.tx and self.tx.countdown
	return countdown and countdown:GetRemainingTime() or huge
end

-- Runs the undos newest first; the first that breaks, or nil.
local function Rollback(work)
	local undos = work.undos
	for i = #undos, 1, -1 do
		local ok, err = pcall(undos[i])
		if not ok then return err end
	end
	return nil
end

-- Settles tx by what its work did: ok with the value at result, else the
-- error (or refusal) result after the undos, newest first.
local function Conclude(tx, work, ok, result)
	if ok then
		tx:Commit(result)
		return
	end
	local broken = Rollback(work)
	if broken ~= nil then
		tx:Fail(tostring(result) .. "; then undoing failed: " .. tostring(broken))
	elseif IsAnyRefusal(result) then
		Settle(tx, DECLINED, "refusal", result)
	else
		tx:Fail(result)
	end
end

-- Settles tx by fn(work, ...), called the way `call` calls it.
local function Execute(tx, work, call, fn, ...)
	Conclude(tx, work, call(fn, work, ...))
end

local function NewWork(tx, scheduler)
	return setmetatable({ undos = {}, tx = tx, scheduler = scheduler }, Work)
end

function Run(fn, ...)
	local tx = New()
	Execute(tx, NewWork(tx), pcall, fn, ...)
	return tx
end

function Spawn(scheduler, fn, ...)
	local tx = New()
	local work = NewWork(tx, scheduler)
	tx.scheduler, tx.work = scheduler, work
	tx.task = scheduler:Spawn(Execute, tx, work, pcall, fn, ...)
	return tx
end

-- A task the scheduler ended for want of time: the work undone, the
-- transaction declined.
local function RanOut(tx)
	if tx.state == PENDING then Conclude(tx, tx.work, false, NewRefusal(TIMED_OUT, RAN_OUT_DETAIL)) end
end

function Tx:Within(countdown)
	if self.state ~= PENDING then error("a " .. self.state .. " transaction has no time left to limit", 2) end
	if not self.task then error("only a spawned transaction has a task to limit", 2) end
	if self.countdown then error("a transaction has one deadline", 2) end
	if not IsStartedCountdown(countdown) then
		error("a deadline is a started countdown (an unstarted one has elapsed)", 2)
	end
	self.countdown = countdown
	self.scheduler:Limit(self.task, countdown, function() RanOut(self) end)
	return self
end

function Tx:Remaining()
	local countdown = self.countdown
	return countdown and countdown:GetRemainingTime() or huge
end

function All(list)
	local all = New()
	local values, left = {}, #list
	if left == 0 then
		all:Commit(values)
		return all
	end
	for i, tx in ipairs(list) do
		tx:OnSettle(function(settled)
			if all.state ~= PENDING then return end
			if settled.state == COMMITTED then
				values[i] = settled.value
				left = left - 1
				if left == 0 then all:Commit(values) end
			elseif settled.state == DECLINED then
				Settle(all, DECLINED, "refusal", settled.refusal)
			else
				all:Fail(settled.err)
			end
		end)
	end
	return all
end

-------------------------------------------------------------------------------
-- Over the wire

function Reply(tx, kinds)
	if tx.state == PENDING then error("a pending transaction has no reply yet", 2) end
	if tx.state == DECLINED and kinds and not IsRefusal(tx.refusal, kinds) then return { state = FAILED } end
	if tx.state == DECLINED then
		return {
			state = DECLINED,
			kind = tx.refusal.kind,
			detail = tx.refusal.detail,
		}
	end
	return { state = tx.state }
end

local LedgerClass = {}
LedgerClass.__index = LedgerClass

function Ledger()
	return setmetatable({
		open = {}, -- id -> { tx, deadline }
		count = 0,
		nextId = 0,
	}, LedgerClass)
end

function LedgerClass:Open(now, timeout)
	local id = self.nextId
	self.nextId = (id + 1) % 2 ^ ID_BITS
	local tx = New()
	self.open[id] = {
		tx = tx,
		deadline = now + timeout,
	}
	self.count = self.count + 1
	return id, tx
end

local function Close(self, id)
	local entry = self.open[id]
	if not entry then return nil end
	self.open[id] = nil
	self.count = self.count - 1
	return entry.tx
end

function LedgerClass:Settle(id, reply)
	local tx = Close(self, id)
	if not tx then return false end
	if reply.state == COMMITTED then
		tx:Commit()
	elseif reply.state == DECLINED then
		tx:Decline(reply.kind, reply.detail)
	else
		tx:Fail(reply.state)
	end
	return true
end

function LedgerClass:Expire(now)
	for id, entry in pairs(self.open) do
		if now >= entry.deadline then Close(self, id):Decline(TIMED_OUT, TIMED_OUT_DETAIL) end
	end
end

function LedgerClass:Count()
	return self.count
end
