//! transaction, native: exchanges that settle once, the Lua twin's contract
//! (foundation/transaction.lua). A transaction, a work object and a ledger
//! are tables, as the Lua twin's are (tx: state, value, refusal, err,
//! callbacks), with native metatables; a refusal is the same plain table
//! { refusal = true, kind, detail }, told apart by value.
//!
//! A C function on a coroutine's stack cannot be yielded through, so a
//! spawned transaction's task is the caller's function itself, run as the
//! coroutine's body, and the native list.schedule hands its outcome back
//! (schedule::spawn_finishing): its return commits, a refusal declines, any
//! other error fails, its undos run first. Await parks the task on the
//! transaction (schedule::park_on): resumed with the value once it commits,
//! or, if it declines or fails, ended with that refusal or error as an
//! uncaught raise would end it.

use super::schedule;
use super::util::boolean;
use crate::lua::{push_str, raise_where, set_function, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TTABLE, TUSERDATA};
use std::ffi::{c_int, CStr};

const TX: &CStr = c"foundation.transaction.tx";
const WORK: &CStr = c"foundation.transaction.work";
const LEDGER: &CStr = c"foundation.transaction.ledger";
const PENDING: &str = "pending";
const COMMITTED: &str = "committed";
const DECLINED: &str = "declined";
const FAILED: &str = "failed";
const TIMED_OUT: &str = "timed out";
const TIMED_OUT_DETAIL: &str = "The server did not answer in time.";
const RAN_OUT_DETAIL: &str = "The transaction ran out of time.";
const ID_BITS: f64 = 16.0;

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

unsafe fn metatable(l: L, name: &CStr, methods: &[(&CStr, CFunction)]) {
    if l.newmetatable(name) != 0 {
        l.pushvalue(-1);
        l.setfield(-2, c"__index");
        for (n, f) in methods {
            set_function(l, n, *f);
        }
    }
}

// Refusals -----------------------------------------------------------------------

/// Pushes { refusal = true, kind, detail } of the values at `kind`, `detail`.
unsafe fn push_refusal(l: L, kind: c_int, detail: c_int) {
    l.createtable(0, 3);
    l.pushboolean(1);
    l.setfield(-2, c"refusal");
    l.pushvalue(kind);
    l.setfield(-2, c"kind");
    l.pushvalue(detail);
    l.setfield(-2, c"detail");
}

unsafe extern "C-unwind" fn refuse(l: L) -> c_int {
    l.settop(2);
    push_refusal(l, 1, 2);
    l.error();
    0
}

/// Whether the value at `index` is any refusal.
unsafe fn is_any_refusal(l: L, index: c_int) -> bool {
    if l.type_of(index) != TTABLE {
        return false;
    }
    l.getfield(index, c"refusal");
    let yes = l.type_of(-1) == crate::lua::TBOOLEAN && l.toboolean(-1) != 0;
    l.settop(-2);
    yes
}

/// Whether the value at `err` is a refusal of one of the kinds at `kinds`.
unsafe fn is_refusal_of(l: L, err: c_int, kinds: c_int) -> bool {
    if !is_any_refusal(l, err) {
        return false;
    }
    l.getfield(err, c"kind");
    l.gettable(kinds);
    let yes = l.type_of(-1) == crate::lua::TBOOLEAN && l.toboolean(-1) != 0;
    l.settop(-2);
    yes
}

unsafe extern "C-unwind" fn is_refusal(l: L) -> c_int {
    l.settop(2);
    boolean(l, is_refusal_of(l, 1, 2))
}

/// Pushes err.kind .. ": " .. err.detail.
unsafe fn push_message(l: L, err: c_int) {
    l.getfield(err, c"kind");
    push_str(l, ": ");
    l.getfield(err, c"detail");
    l.concat(3);
}

unsafe extern "C-unwind" fn message(l: L) -> c_int {
    push_message(l, 1);
    1
}

/// Rethrows the value at 1 unless it is a refusal of the kinds at 2.
unsafe fn refusal_or_rethrow(l: L) {
    l.settop(2);
    if !is_refusal_of(l, 1, 2) {
        l.pushvalue(1);
        l.error();
    }
}

unsafe extern "C-unwind" fn explain(l: L) -> c_int {
    refusal_or_rethrow(l);
    push_message(l, 1);
    1
}

unsafe extern "C-unwind" fn detail(l: L) -> c_int {
    refusal_or_rethrow(l);
    l.getfield(1, c"detail");
    1
}

// Transactions ----------------------------------------------------------------------

/// Pushes a new pending transaction.
unsafe fn push_tx(l: L) {
    l.createtable(0, 3);
    push_str(l, PENDING);
    l.setfield(-2, c"state");
    l.createtable(0, 0);
    l.setfield(-2, c"callbacks");
    metatable(
        l,
        TX,
        &[
            (c"Commit", commit),
            (c"Decline", decline),
            (c"Fail", fail),
            (c"State", state),
            (c"Value", value),
            (c"Refusal", refusal),
            (c"Error", error_of),
            (c"OnSettle", on_settle),
            (c"Await", await_tx),
            (c"Within", within),
            (c"Remaining", remaining),
        ],
    );
    l.setmetatable(-2);
}

unsafe extern "C-unwind" fn new(l: L) -> c_int {
    push_tx(l);
    1
}

/// The state of the transaction at `tx`, as text.
unsafe fn state_of(l: L, tx: c_int) -> String {
    l.getfield(tx, c"state");
    let s = tostring(l, -1);
    l.settop(-2);
    s
}

/// Settles the transaction at `tx` as `state`, tx[field] = the value at
/// `value`, then runs its callbacks; settling twice is the caller's bug.
unsafe fn settle(l: L, tx: c_int, state: &str, field: &CStr, value: c_int) {
    let now = state_of(l, tx);
    if now != PENDING {
        raise_where(l, format!("a {now} transaction cannot settle again"));
    }
    push_str(l, state);
    l.setfield(tx, c"state");
    l.pushvalue(value);
    l.setfield(tx, field);
    l.getfield(tx, c"callbacks");
    let callbacks = l.gettop();
    l.pushnil();
    l.setfield(tx, c"callbacks");
    let mut i = 1;
    loop {
        l.rawgeti(callbacks, i);
        if l.type_of(-1) == TNIL {
            break;
        }
        l.pushvalue(tx);
        l.call(1, 0);
        i += 1;
    }
    l.settop(callbacks - 1);
}

unsafe extern "C-unwind" fn commit(l: L) -> c_int {
    l.settop(2);
    settle(l, 1, COMMITTED, c"value", 2);
    0
}

unsafe extern "C-unwind" fn decline(l: L) -> c_int {
    l.settop(3);
    push_refusal(l, 2, 3);
    settle(l, 1, DECLINED, c"refusal", 4);
    0
}

unsafe extern "C-unwind" fn fail(l: L) -> c_int {
    l.settop(2);
    settle(l, 1, FAILED, c"err", 2);
    0
}

unsafe fn field(l: L, name: &CStr) -> c_int {
    l.getfield(1, name);
    1
}

unsafe extern "C-unwind" fn state(l: L) -> c_int {
    field(l, c"state")
}

unsafe extern "C-unwind" fn value(l: L) -> c_int {
    field(l, c"value")
}

unsafe extern "C-unwind" fn refusal(l: L) -> c_int {
    field(l, c"refusal")
}

unsafe extern "C-unwind" fn error_of(l: L) -> c_int {
    field(l, c"err")
}

unsafe extern "C-unwind" fn on_settle(l: L) -> c_int {
    l.settop(2);
    if state_of(l, 1) == PENDING {
        l.getfield(1, c"callbacks");
        let n = l.objlen(-1) as c_int;
        l.pushvalue(2);
        l.rawseti(-2, n + 1);
    } else {
        l.pushvalue(2);
        l.pushvalue(1);
        l.call(1, 0);
    }
    0
}

/// The settled transaction at 1's outcome: its value returned, or its
/// refusal or error raised.
unsafe fn outcome(l: L) -> c_int {
    match state_of(l, 1).as_str() {
        COMMITTED => field(l, c"value"),
        DECLINED => {
            l.getfield(1, c"refusal");
            l.error();
            0
        }
        _ => {
            l.getfield(1, c"err");
            l.error();
            0
        }
    }
}

/// tx:Await(scheduler), in a task of the native list.schedule
unsafe extern "C-unwind" fn await_tx(l: L) -> c_int {
    l.settop(2);
    if state_of(l, 1) != PENDING {
        return outcome(l);
    }
    // the scheduler at 1 and the transaction at 2, as park_on reads them
    l.insert(1);
    schedule::park_on(l)
}

// Work -----------------------------------------------------------------------------

unsafe fn push_work(l: L) {
    l.createtable(0, 1);
    l.createtable(0, 0);
    l.setfield(-2, c"undos");
    metatable(
        l,
        WORK,
        &[
            (c"Undo", undo),
            (c"Yield", work_yield),
            (c"CheckYield", work_check_yield),
            (c"Wait", work_wait),
            (c"WaitFor", work_wait_for),
            (c"Await", work_await),
            (c"Remaining", work_remaining),
        ],
    );
    l.setmetatable(-2);
}

unsafe extern "C-unwind" fn undo(l: L) -> c_int {
    l.settop(2);
    l.getfield(1, c"undos");
    let n = l.objlen(-1) as c_int;
    l.pushvalue(2);
    l.rawseti(-2, n + 1);
    0
}

/// Replaces the work at 1 with its scheduler; a transaction run at once
/// has none, which is our bug.
unsafe fn scheduler_for_work(l: L) {
    l.getfield(1, c"scheduler");
    if l.type_of(-1) == TNIL {
        raise_where(l, "this transaction runs at once: it has no scheduler to yield on".into());
    }
    l.replace(1);
}

/// work:Yield(): the running task gives up its turn.
unsafe extern "C-unwind" fn work_yield(l: L) -> c_int {
    l.settop(1);
    scheduler_for_work(l);
    schedule::yield_turn(l)
}

/// work:CheckYield(): yields once the scheduler's slice is spent.
unsafe extern "C-unwind" fn work_check_yield(l: L) -> c_int {
    l.settop(1);
    scheduler_for_work(l);
    schedule::check_yield(l)
}

/// work:Wait(ready): parks until ready() holds.
unsafe extern "C-unwind" fn work_wait(l: L) -> c_int {
    l.settop(2);
    scheduler_for_work(l);
    schedule::wait(l)
}

/// The condition of work:WaitFor: upvalue 1 the countdown; whether it has
/// elapsed.
unsafe extern "C-unwind" fn elapsed(l: L) -> c_int {
    l.pushvalue(upvalue(1));
    l.getfield(-1, c"IsElapsed");
    l.pushvalue(-2);
    l.call(1, 1);
    1
}

/// work:WaitFor(countdown): parks until the countdown has elapsed.
unsafe extern "C-unwind" fn work_wait_for(l: L) -> c_int {
    l.settop(2);
    l.pushvalue(2);
    l.pushcclosure(elapsed, 1);
    scheduler_for_work(l);
    // scheduler, countdown, condition: the countdown is not wanted
    l.remove(2);
    schedule::wait(l)
}

/// work:Await(tx): parks until tx settles, then its value; its refusal or
/// error ends this task.
unsafe extern "C-unwind" fn work_await(l: L) -> c_int {
    l.settop(2);
    scheduler_for_work(l);
    if state_of(l, 2) != PENDING {
        l.remove(1);
        return outcome(l);
    }
    schedule::park_on(l)
}

/// Pushes the seconds left on the countdown of the transaction at `tx`,
/// math.huge with no deadline.
unsafe fn push_remaining(l: L, tx: c_int) {
    l.getfield(tx, c"countdown");
    if l.type_of(-1) == TNIL {
        l.settop(-2);
        l.pushnumber(f64::INFINITY);
        return;
    }
    l.getfield(-1, c"GetRemainingTime");
    l.pushvalue(-2);
    l.call(1, 1);
    l.remove(-2);
}

/// work:Remaining(): the seconds left to its transaction.
unsafe extern "C-unwind" fn work_remaining(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"tx");
    if l.type_of(-1) == TNIL {
        l.pushnumber(f64::INFINITY);
        return 1;
    }
    push_remaining(l, l.gettop());
    1
}

/// tx:Remaining(): the seconds left to it, math.huge with no deadline.
unsafe extern "C-unwind" fn remaining(l: L) -> c_int {
    l.settop(1);
    push_remaining(l, 1);
    1
}

/// Whether the value at `index` is a started countdown, as a deadline is
/// read: it says IsElapsed, GetRemainingTime and HasStarted, and has started.
unsafe fn is_started_countdown(l: L, index: c_int) -> bool {
    let kind = l.type_of(index);
    if kind != TTABLE && kind != TUSERDATA {
        return false;
    }
    for name in [c"IsElapsed", c"GetRemainingTime", c"HasStarted"] {
        l.getfield(index, name);
        let function = l.type_of(-1) == TFUNCTION;
        l.settop(-2);
        if !function {
            return false;
        }
    }
    l.getfield(index, c"HasStarted");
    l.pushvalue(index);
    l.call(1, 1);
    let started = l.toboolean(-1) != 0;
    l.settop(-2);
    started
}

/// A task the scheduler ended for want of time (upvalue 1 the transaction):
/// the work undone, the transaction declined as timed out.
unsafe extern "C-unwind" fn ran_out(l: L) -> c_int {
    l.settop(0);
    l.pushvalue(upvalue(1));
    let tx = l.gettop();
    if state_of(l, tx) != PENDING {
        return 0;
    }
    l.getfield(tx, c"work");
    let work = l.gettop();
    push_str(l, TIMED_OUT);
    push_str(l, RAN_OUT_DETAIL);
    push_refusal(l, work + 1, work + 2);
    let refusal = l.gettop();
    conclude(l, tx, work, false, refusal);
    0
}

/// tx:Within(countdown) -> tx: a time to settle in (see the Lua twin).
unsafe extern "C-unwind" fn within(l: L) -> c_int {
    l.settop(2);
    let now = state_of(l, 1);
    if now != PENDING {
        raise_where(l, format!("a {now} transaction has no time left to limit"));
    }
    l.getfield(1, c"task");
    let task = l.type_of(-1) != TNIL;
    l.settop(2);
    if !task {
        raise_where(l, "only a spawned transaction has a task to limit".into());
    }
    l.getfield(1, c"countdown");
    let limited = l.type_of(-1) != TNIL;
    l.settop(2);
    if limited {
        raise_where(l, "a transaction has one deadline".into());
    }
    if !is_started_countdown(l, 2) {
        raise_where(l, "a deadline is a started countdown (an unstarted one has elapsed)".into());
    }
    l.pushvalue(2);
    l.setfield(1, c"countdown");
    // scheduler:Limit(task, countdown, ran_out)
    l.getfield(1, c"scheduler");
    let scheduler = l.gettop();
    l.getfield(scheduler, c"Limit");
    l.pushvalue(scheduler);
    l.getfield(1, c"task");
    l.pushvalue(2);
    l.pushvalue(1);
    l.pushcclosure(ran_out, 1);
    l.call(4, 0);
    l.settop(1);
    1
}

/// Runs the work at `work`'s undos newest first; pushes the first error
/// one raised, or nil.
unsafe fn rollback(l: L, work: c_int) {
    l.getfield(work, c"undos");
    let undos = l.gettop();
    let n = l.objlen(undos) as c_int;
    for i in (1..=n).rev() {
        l.rawgeti(undos, i);
        if l.pcall(0, 0, 0) != 0 {
            l.remove(undos);
            return;
        }
    }
    l.settop(undos - 1);
    l.pushnil();
}

/// Settles the transaction at `tx` by the work's outcome: ok with the
/// value at `result`, else the error at `result` after the undos.
unsafe fn conclude(l: L, tx: c_int, work: c_int, ok: bool, result: c_int) {
    if ok {
        settle(l, tx, COMMITTED, c"value", result);
        return;
    }
    rollback(l, work);
    let broken = l.gettop();
    if l.type_of(broken) != TNIL {
        let text = format!("{}; then undoing failed: {}", tostring(l, result), tostring(l, broken));
        push_str(l, &text);
        let msg = l.gettop();
        settle(l, tx, FAILED, c"err", msg);
    } else if is_any_refusal(l, result) {
        settle(l, tx, DECLINED, c"refusal", result);
    } else {
        settle(l, tx, FAILED, c"err", result);
    }
    l.settop(broken - 1);
}

/// transaction.Run(fn, ...) -> tx: fn(work, ...) now
unsafe extern "C-unwind" fn run(l: L) -> c_int {
    let n = l.gettop();
    push_tx(l);
    let tx = l.gettop();
    push_work(l);
    let work = l.gettop();
    l.pushvalue(tx);
    l.setfield(work, c"tx");
    l.pushvalue(1);
    l.pushvalue(work);
    for i in 2..=n {
        l.pushvalue(i);
    }
    let ok = l.pcall(n, 1, 0) == 0;
    let result = l.gettop();
    conclude(l, tx, work, ok, result);
    l.settop(tx);
    1
}

/// A spawned transaction's finish handler: upvalue 1 the transaction, 2 its
/// work; called with (ok, results or error).
unsafe extern "C-unwind" fn finished(l: L) -> c_int {
    l.settop(2);
    let ok = l.toboolean(1) != 0;
    l.pushvalue(upvalue(1));
    let tx = l.gettop();
    l.pushvalue(upvalue(2));
    let work = l.gettop();
    conclude(l, tx, work, ok, 2);
    0
}

/// transaction.Spawn(scheduler, fn, ...) -> tx: the same as a task
unsafe extern "C-unwind" fn spawn(l: L) -> c_int {
    let n = l.gettop();
    push_tx(l);
    push_work(l);
    // scheduler, fn, work, args..., then tx and work above
    l.pushvalue(n + 2);
    l.insert(3);
    let tx = n + 2;
    l.pushvalue(tx);
    l.pushvalue(tx + 1);
    l.pushcclosure(finished, 2);
    // the handler right after the task's values: tx moves up to n + 3
    l.insert(n + 2);
    schedule::spawn_finishing(l, n + 1);
    // the task (spawn_finishing left it on top), the scheduler and the work,
    // kept on the transaction and the other way, as the Lua twin's
    let (tx, work, thread) = (n + 3, n + 4, l.gettop());
    l.pushvalue(thread);
    l.setfield(tx, c"task");
    l.pushvalue(1);
    l.setfield(tx, c"scheduler");
    l.pushvalue(work);
    l.setfield(tx, c"work");
    l.pushvalue(tx);
    l.setfield(work, c"tx");
    l.pushvalue(1);
    l.setfield(work, c"scheduler");
    l.pushvalue(tx);
    1
}

// All -------------------------------------------------------------------------------

/// The callback each transaction of All runs: upvalue 1 the combined one,
/// 2 its state { values, left }, 3 the transaction's place.
unsafe extern "C-unwind" fn all_step(l: L) -> c_int {
    l.settop(1);
    l.pushvalue(upvalue(1));
    let all = l.gettop();
    if state_of(l, all) != PENDING {
        return 0;
    }
    match state_of(l, 1).as_str() {
        COMMITTED => {
            l.pushvalue(upvalue(2));
            let own = l.gettop();
            l.getfield(own, c"values");
            let values = l.gettop();
            l.getfield(1, c"value");
            l.rawseti(values, l.tonumber(upvalue(3)) as c_int);
            l.getfield(own, c"left");
            let left = l.tonumber(-1) - 1.0;
            l.settop(-2);
            l.pushnumber(left);
            l.setfield(own, c"left");
            if left == 0.0 {
                settle(l, all, COMMITTED, c"value", values);
            }
        }
        DECLINED => {
            l.getfield(1, c"refusal");
            let r = l.gettop();
            settle(l, all, DECLINED, c"refusal", r);
        }
        _ => {
            l.getfield(1, c"err");
            let e = l.gettop();
            settle(l, all, FAILED, c"err", e);
        }
    }
    0
}

unsafe extern "C-unwind" fn all(l: L) -> c_int {
    l.settop(1);
    l.checktype(1, TTABLE);
    push_tx(l);
    let combined = l.gettop();
    l.createtable(0, 0);
    let values = l.gettop();
    let n = l.objlen(1);
    if n == 0 {
        settle(l, combined, COMMITTED, c"value", values);
        l.settop(combined);
        return 1;
    }
    l.createtable(0, 2);
    let own = l.gettop();
    l.pushvalue(values);
    l.setfield(own, c"values");
    l.pushnumber(n as f64);
    l.setfield(own, c"left");
    for i in 1..=n as c_int {
        l.rawgeti(1, i);
        let tx = l.gettop();
        l.getfield(tx, c"OnSettle");
        l.pushvalue(tx);
        l.pushvalue(combined);
        l.pushvalue(own);
        l.pushnumber(i as f64);
        l.pushcclosure(all_step, 3);
        l.call(2, 0);
        l.settop(own);
    }
    l.settop(combined);
    1
}

// Over the wire -------------------------------------------------------------------

unsafe extern "C-unwind" fn reply(l: L) -> c_int {
    l.settop(2);
    let state = state_of(l, 1);
    if state == PENDING {
        raise_where(l, "a pending transaction has no reply yet".into());
    }
    l.createtable(0, 3);
    let out = l.gettop();
    if state == DECLINED {
        l.getfield(1, c"refusal");
        let r = l.gettop();
        let theirs = l.type_of(2) == TNIL || is_refusal_of(l, r, 2);
        if !theirs {
            push_str(l, FAILED);
            l.setfield(out, c"state");
            l.settop(out);
            return 1;
        }
        push_str(l, DECLINED);
        l.setfield(out, c"state");
        l.getfield(r, c"kind");
        l.setfield(out, c"kind");
        l.getfield(r, c"detail");
        l.setfield(out, c"detail");
        l.settop(out);
        return 1;
    }
    push_str(l, &state);
    l.setfield(out, c"state");
    1
}

unsafe extern "C-unwind" fn ledger(l: L) -> c_int {
    l.createtable(0, 3);
    l.createtable(0, 0);
    l.setfield(-2, c"open");
    l.pushnumber(0.0);
    l.setfield(-2, c"count");
    l.pushnumber(0.0);
    l.setfield(-2, c"nextId");
    metatable(l, LEDGER, &[(c"Open", ledger_open), (c"Settle", ledger_settle), (c"Expire", ledger_expire), (c"Count", ledger_count)]);
    l.setmetatable(-2);
    1
}

unsafe fn add_count(l: L, by: f64) {
    l.getfield(1, c"count");
    let n = l.tonumber(-1) + by;
    l.settop(-2);
    l.pushnumber(n);
    l.setfield(1, c"count");
}

unsafe extern "C-unwind" fn ledger_open(l: L) -> c_int {
    let (now, timeout) = (l.checknumber(2), l.checknumber(3));
    l.getfield(1, c"nextId");
    let id = l.tonumber(-1);
    l.settop(-2);
    l.pushnumber((id + 1.0) % 2f64.powf(ID_BITS));
    l.setfield(1, c"nextId");
    push_tx(l);
    let tx = l.gettop();
    l.getfield(1, c"open");
    l.pushnumber(id);
    l.createtable(0, 2);
    l.pushvalue(tx);
    l.setfield(-2, c"tx");
    l.pushnumber(now + timeout);
    l.setfield(-2, c"deadline");
    l.rawset(-3);
    l.settop(tx);
    add_count(l, 1.0);
    l.pushnumber(id);
    l.pushvalue(tx);
    2
}

/// Closes the entry `id` (the number at `id`), pushing its transaction or nil.
unsafe fn close(l: L, id: c_int) {
    l.getfield(1, c"open");
    let open = l.gettop();
    l.pushvalue(id);
    l.rawget(open);
    if l.type_of(-1) == TNIL {
        l.remove(open);
        return;
    }
    l.getfield(-1, c"tx");
    l.pushvalue(id);
    l.pushnil();
    l.rawset(open);
    l.replace(open);
    l.settop(open);
    add_count(l, -1.0);
}

unsafe extern "C-unwind" fn ledger_settle(l: L) -> c_int {
    l.settop(3);
    close(l, 2);
    let tx = l.gettop();
    if l.type_of(tx) == TNIL {
        return boolean(l, false);
    }
    l.getfield(3, c"state");
    let state = tostring(l, -1);
    l.settop(tx);
    match state.as_str() {
        COMMITTED => {
            l.pushnil();
            settle(l, tx, COMMITTED, c"value", tx + 1);
        }
        DECLINED => {
            l.getfield(3, c"kind");
            l.getfield(3, c"detail");
            push_refusal(l, tx + 1, tx + 2);
            settle(l, tx, DECLINED, c"refusal", tx + 3);
        }
        _ => {
            l.getfield(3, c"state");
            settle(l, tx, FAILED, c"err", tx + 1);
        }
    }
    boolean(l, true)
}

unsafe extern "C-unwind" fn ledger_expire(l: L) -> c_int {
    let now = l.checknumber(2);
    l.settop(2);
    l.getfield(1, c"open");
    let open = l.gettop();
    l.createtable(0, 0);
    let due = l.gettop();
    let mut n = 0;
    l.pushnil();
    while l.next(open) != 0 {
        l.getfield(-1, c"deadline");
        let deadline = l.tonumber(-1);
        l.settop(-2);
        if now >= deadline {
            n += 1;
            l.pushvalue(-2);
            l.rawseti(due, n);
        }
        l.settop(-2);
    }
    for i in 1..=n {
        l.rawgeti(due, i);
        let id = l.gettop();
        close(l, id);
        let tx = l.gettop();
        push_str(l, TIMED_OUT);
        push_str(l, TIMED_OUT_DETAIL);
        push_refusal(l, tx + 1, tx + 2);
        settle(l, tx, DECLINED, c"refusal", tx + 3);
        l.settop(due);
    }
    0
}

unsafe extern "C-unwind" fn ledger_count(l: L) -> c_int {
    field(l, c"count")
}

/// Pushes the transaction module table.
pub unsafe fn push_module(l: L) {
    crate::module::push(
        l,
        &[
            (c"Refuse", refuse),
            (c"IsRefusal", is_refusal),
            (c"Message", message),
            (c"Explain", explain),
            (c"Detail", detail),
            (c"New", new),
            (c"Run", run),
            (c"Spawn", spawn),
            (c"All", all),
            (c"Reply", reply),
            (c"Ledger", ledger),
        ],
        None,
    );
    for (name, v) in [
        (c"PENDING", PENDING),
        (c"COMMITTED", COMMITTED),
        (c"DECLINED", DECLINED),
        (c"FAILED", FAILED),
        (c"TIMED_OUT", TIMED_OUT),
        (c"TIMED_OUT_DETAIL", TIMED_OUT_DETAIL),
        (c"RAN_OUT_DETAIL", RAN_OUT_DETAIL),
    ] {
        push_str(l, v);
        l.setfield(-2, name);
    }
    l.pushnumber(ID_BITS);
    l.setfield(-2, c"ID_BITS");
}
