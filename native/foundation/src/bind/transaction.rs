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
use crate::lua::{api, push_str, raise_where, set_function, tostring, CFunction, GLOBALSINDEX, L, TNIL, TTABLE};
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
const ID_BITS: f64 = 16.0;

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

unsafe fn metatable(l: L, name: &CStr, methods: &[(&CStr, CFunction)]) {
    let api = api();
    if (api.newmetatable)(l, name.as_ptr()) != 0 {
        (api.pushvalue)(l, -1);
        (api.setfield)(l, -2, c"__index".as_ptr());
        for (n, f) in methods {
            set_function(l, n, *f);
        }
    }
}

// Refusals -----------------------------------------------------------------------

/// Pushes { refusal = true, kind, detail } of the values at `kind`, `detail`.
unsafe fn push_refusal(l: L, kind: c_int, detail: c_int) {
    let api = api();
    (api.createtable)(l, 0, 3);
    (api.pushboolean)(l, 1);
    (api.setfield)(l, -2, c"refusal".as_ptr());
    (api.pushvalue)(l, kind);
    (api.setfield)(l, -2, c"kind".as_ptr());
    (api.pushvalue)(l, detail);
    (api.setfield)(l, -2, c"detail".as_ptr());
}

unsafe extern "C-unwind" fn refuse(l: L) -> c_int {
    (api().settop)(l, 2);
    push_refusal(l, 1, 2);
    (api().error)(l);
    0
}

/// Whether the value at `index` is any refusal.
unsafe fn is_any_refusal(l: L, index: c_int) -> bool {
    let api = api();
    if (api.type_of)(l, index) != TTABLE {
        return false;
    }
    (api.getfield)(l, index, c"refusal".as_ptr());
    let yes = (api.type_of)(l, -1) == crate::lua::TBOOLEAN && (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    yes
}

/// Whether the value at `err` is a refusal of one of the kinds at `kinds`.
unsafe fn is_refusal_of(l: L, err: c_int, kinds: c_int) -> bool {
    let api = api();
    if !is_any_refusal(l, err) {
        return false;
    }
    (api.getfield)(l, err, c"kind".as_ptr());
    (api.gettable)(l, kinds);
    let yes = (api.type_of)(l, -1) == crate::lua::TBOOLEAN && (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    yes
}

unsafe extern "C-unwind" fn is_refusal(l: L) -> c_int {
    (api().settop)(l, 2);
    boolean(l, is_refusal_of(l, 1, 2))
}

/// Pushes err.kind .. ": " .. err.detail.
unsafe fn push_message(l: L, err: c_int) {
    let api = api();
    (api.getfield)(l, err, c"kind".as_ptr());
    push_str(l, ": ");
    (api.getfield)(l, err, c"detail".as_ptr());
    (api.concat)(l, 3);
}

unsafe extern "C-unwind" fn message(l: L) -> c_int {
    push_message(l, 1);
    1
}

/// Rethrows the value at 1 unless it is a refusal of the kinds at 2.
unsafe fn refusal_or_rethrow(l: L) {
    let api = api();
    (api.settop)(l, 2);
    if !is_refusal_of(l, 1, 2) {
        (api.pushvalue)(l, 1);
        (api.error)(l);
    }
}

unsafe extern "C-unwind" fn explain(l: L) -> c_int {
    refusal_or_rethrow(l);
    push_message(l, 1);
    1
}

unsafe extern "C-unwind" fn detail(l: L) -> c_int {
    refusal_or_rethrow(l);
    (api().getfield)(l, 1, c"detail".as_ptr());
    1
}

// Transactions ----------------------------------------------------------------------

/// Pushes a new pending transaction.
unsafe fn push_tx(l: L) {
    let api = api();
    (api.createtable)(l, 0, 3);
    push_str(l, PENDING);
    (api.setfield)(l, -2, c"state".as_ptr());
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, c"callbacks".as_ptr());
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
        ],
    );
    (api.setmetatable)(l, -2);
}

unsafe extern "C-unwind" fn new(l: L) -> c_int {
    push_tx(l);
    1
}

/// The state of the transaction at `tx`, as text.
unsafe fn state_of(l: L, tx: c_int) -> String {
    let api = api();
    (api.getfield)(l, tx, c"state".as_ptr());
    let s = tostring(l, -1);
    (api.settop)(l, -2);
    s
}

/// Settles the transaction at `tx` as `state`, tx[field] = the value at
/// `value`, then runs its callbacks; settling twice is the caller's bug.
unsafe fn settle(l: L, tx: c_int, state: &str, field: &CStr, value: c_int) {
    let api = api();
    let now = state_of(l, tx);
    if now != PENDING {
        raise_where(l, format!("a {now} transaction cannot settle again"));
    }
    push_str(l, state);
    (api.setfield)(l, tx, c"state".as_ptr());
    (api.pushvalue)(l, value);
    (api.setfield)(l, tx, field.as_ptr());
    (api.getfield)(l, tx, c"callbacks".as_ptr());
    let callbacks = (api.gettop)(l);
    (api.pushnil)(l);
    (api.setfield)(l, tx, c"callbacks".as_ptr());
    let mut i = 1;
    loop {
        (api.rawgeti)(l, callbacks, i);
        if (api.type_of)(l, -1) == TNIL {
            break;
        }
        (api.pushvalue)(l, tx);
        (api.call)(l, 1, 0);
        i += 1;
    }
    (api.settop)(l, callbacks - 1);
}

unsafe extern "C-unwind" fn commit(l: L) -> c_int {
    (api().settop)(l, 2);
    settle(l, 1, COMMITTED, c"value", 2);
    0
}

unsafe extern "C-unwind" fn decline(l: L) -> c_int {
    (api().settop)(l, 3);
    push_refusal(l, 2, 3);
    settle(l, 1, DECLINED, c"refusal", 4);
    0
}

unsafe extern "C-unwind" fn fail(l: L) -> c_int {
    (api().settop)(l, 2);
    settle(l, 1, FAILED, c"err", 2);
    0
}

unsafe fn field(l: L, name: &CStr) -> c_int {
    (api().getfield)(l, 1, name.as_ptr());
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
    let api = api();
    (api.settop)(l, 2);
    if state_of(l, 1) == PENDING {
        (api.getfield)(l, 1, c"callbacks".as_ptr());
        let n = (api.objlen)(l, -1) as c_int;
        (api.pushvalue)(l, 2);
        (api.rawseti)(l, -2, n + 1);
    } else {
        (api.pushvalue)(l, 2);
        (api.pushvalue)(l, 1);
        (api.call)(l, 1, 0);
    }
    0
}

/// The settled transaction at 1's outcome: its value returned, or its
/// refusal or error raised.
unsafe fn outcome(l: L) -> c_int {
    let api = api();
    match state_of(l, 1).as_str() {
        COMMITTED => field(l, c"value"),
        DECLINED => {
            (api.getfield)(l, 1, c"refusal".as_ptr());
            (api.error)(l);
            0
        }
        _ => {
            (api.getfield)(l, 1, c"err".as_ptr());
            (api.error)(l);
            0
        }
    }
}

/// tx:Await(scheduler), in a task of the native list.schedule
unsafe extern "C-unwind" fn await_tx(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if state_of(l, 1) != PENDING {
        return outcome(l);
    }
    // the scheduler at 1 and the transaction at 2, as park_on reads them
    (api.insert)(l, 1);
    schedule::park_on(l)
}

// Work -----------------------------------------------------------------------------

unsafe fn push_work(l: L) {
    let api = api();
    (api.createtable)(l, 0, 1);
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, c"undos".as_ptr());
    metatable(l, WORK, &[(c"Undo", undo)]);
    (api.setmetatable)(l, -2);
}

unsafe extern "C-unwind" fn undo(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.getfield)(l, 1, c"undos".as_ptr());
    let n = (api.objlen)(l, -1) as c_int;
    (api.pushvalue)(l, 2);
    (api.rawseti)(l, -2, n + 1);
    0
}

/// Runs the work at `work`'s undos newest first; pushes the first error
/// one raised, or nil.
unsafe fn rollback(l: L, work: c_int) {
    let api = api();
    (api.getfield)(l, work, c"undos".as_ptr());
    let undos = (api.gettop)(l);
    let n = (api.objlen)(l, undos) as c_int;
    for i in (1..=n).rev() {
        (api.rawgeti)(l, undos, i);
        if (api.pcall)(l, 0, 0, 0) != 0 {
            (api.remove)(l, undos);
            return;
        }
    }
    (api.settop)(l, undos - 1);
    (api.pushnil)(l);
}

/// Settles the transaction at `tx` by the work's outcome: ok with the
/// value at `result`, else the error at `result` after the undos.
unsafe fn conclude(l: L, tx: c_int, work: c_int, ok: bool, result: c_int) {
    let api = api();
    if ok {
        settle(l, tx, COMMITTED, c"value", result);
        return;
    }
    rollback(l, work);
    let broken = (api.gettop)(l);
    if (api.type_of)(l, broken) != TNIL {
        let text = format!("{}; then undoing failed: {}", tostring(l, result), tostring(l, broken));
        push_str(l, &text);
        let msg = (api.gettop)(l);
        settle(l, tx, FAILED, c"err", msg);
    } else if is_any_refusal(l, result) {
        settle(l, tx, DECLINED, c"refusal", result);
    } else {
        settle(l, tx, FAILED, c"err", result);
    }
    (api.settop)(l, broken - 1);
}

/// transaction.Run(fn, ...) -> tx: fn(work, ...) now
unsafe extern "C-unwind" fn run(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l);
    push_tx(l);
    let tx = (api.gettop)(l);
    push_work(l);
    let work = (api.gettop)(l);
    (api.pushvalue)(l, 1);
    (api.pushvalue)(l, work);
    for i in 2..=n {
        (api.pushvalue)(l, i);
    }
    let ok = (api.pcall)(l, n, 1, 0) == 0;
    let result = (api.gettop)(l);
    conclude(l, tx, work, ok, result);
    (api.settop)(l, tx);
    1
}

/// A spawned transaction's finish handler: upvalue 1 the transaction, 2 its
/// work; called with (ok, results or error).
unsafe extern "C-unwind" fn finished(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let ok = (api.toboolean)(l, 1) != 0;
    (api.pushvalue)(l, upvalue(1));
    let tx = (api.gettop)(l);
    (api.pushvalue)(l, upvalue(2));
    let work = (api.gettop)(l);
    conclude(l, tx, work, ok, 2);
    0
}

/// transaction.Spawn(scheduler, fn, ...) -> tx: the same as a task
unsafe extern "C-unwind" fn spawn(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l);
    push_tx(l);
    push_work(l);
    // scheduler, fn, work, args..., then tx and work above
    (api.pushvalue)(l, n + 2);
    (api.insert)(l, 3);
    let tx = n + 2;
    (api.pushvalue)(l, tx);
    (api.pushvalue)(l, tx + 1);
    (api.pushcclosure)(l, finished, 2);
    // the handler right after the task's values: tx moves up to n + 3
    (api.insert)(l, n + 2);
    schedule::spawn_finishing(l, n + 1);
    (api.pushvalue)(l, n + 3);
    1
}

// All -------------------------------------------------------------------------------

/// The callback each transaction of All runs: upvalue 1 the combined one,
/// 2 its state { values, left }, 3 the transaction's place.
unsafe extern "C-unwind" fn all_step(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.pushvalue)(l, upvalue(1));
    let all = (api.gettop)(l);
    if state_of(l, all) != PENDING {
        return 0;
    }
    match state_of(l, 1).as_str() {
        COMMITTED => {
            (api.pushvalue)(l, upvalue(2));
            let own = (api.gettop)(l);
            (api.getfield)(l, own, c"values".as_ptr());
            let values = (api.gettop)(l);
            (api.getfield)(l, 1, c"value".as_ptr());
            (api.rawseti)(l, values, (api.tonumber)(l, upvalue(3)) as c_int);
            (api.getfield)(l, own, c"left".as_ptr());
            let left = (api.tonumber)(l, -1) - 1.0;
            (api.settop)(l, -2);
            (api.pushnumber)(l, left);
            (api.setfield)(l, own, c"left".as_ptr());
            if left == 0.0 {
                settle(l, all, COMMITTED, c"value", values);
            }
        }
        DECLINED => {
            (api.getfield)(l, 1, c"refusal".as_ptr());
            let r = (api.gettop)(l);
            settle(l, all, DECLINED, c"refusal", r);
        }
        _ => {
            (api.getfield)(l, 1, c"err".as_ptr());
            let e = (api.gettop)(l);
            settle(l, all, FAILED, c"err", e);
        }
    }
    0
}

unsafe extern "C-unwind" fn all(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.checktype)(l, 1, TTABLE);
    push_tx(l);
    let combined = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let values = (api.gettop)(l);
    let n = (api.objlen)(l, 1);
    if n == 0 {
        settle(l, combined, COMMITTED, c"value", values);
        (api.settop)(l, combined);
        return 1;
    }
    (api.createtable)(l, 0, 2);
    let own = (api.gettop)(l);
    (api.pushvalue)(l, values);
    (api.setfield)(l, own, c"values".as_ptr());
    (api.pushnumber)(l, n as f64);
    (api.setfield)(l, own, c"left".as_ptr());
    for i in 1..=n as c_int {
        (api.rawgeti)(l, 1, i);
        let tx = (api.gettop)(l);
        (api.getfield)(l, tx, c"OnSettle".as_ptr());
        (api.pushvalue)(l, tx);
        (api.pushvalue)(l, combined);
        (api.pushvalue)(l, own);
        (api.pushnumber)(l, i as f64);
        (api.pushcclosure)(l, all_step, 3);
        (api.call)(l, 2, 0);
        (api.settop)(l, own);
    }
    (api.settop)(l, combined);
    1
}

// Over the wire -------------------------------------------------------------------

unsafe extern "C-unwind" fn reply(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let state = state_of(l, 1);
    if state == PENDING {
        raise_where(l, "a pending transaction has no reply yet".into());
    }
    (api.createtable)(l, 0, 3);
    let out = (api.gettop)(l);
    if state == DECLINED {
        (api.getfield)(l, 1, c"refusal".as_ptr());
        let r = (api.gettop)(l);
        let theirs = (api.type_of)(l, 2) == TNIL || is_refusal_of(l, r, 2);
        if !theirs {
            push_str(l, FAILED);
            (api.setfield)(l, out, c"state".as_ptr());
            (api.settop)(l, out);
            return 1;
        }
        push_str(l, DECLINED);
        (api.setfield)(l, out, c"state".as_ptr());
        (api.getfield)(l, r, c"kind".as_ptr());
        (api.setfield)(l, out, c"kind".as_ptr());
        (api.getfield)(l, r, c"detail".as_ptr());
        (api.setfield)(l, out, c"detail".as_ptr());
        (api.settop)(l, out);
        return 1;
    }
    push_str(l, &state);
    (api.setfield)(l, out, c"state".as_ptr());
    1
}

unsafe extern "C-unwind" fn ledger(l: L) -> c_int {
    let api = api();
    (api.createtable)(l, 0, 3);
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, c"open".as_ptr());
    (api.pushnumber)(l, 0.0);
    (api.setfield)(l, -2, c"count".as_ptr());
    (api.pushnumber)(l, 0.0);
    (api.setfield)(l, -2, c"nextId".as_ptr());
    metatable(l, LEDGER, &[(c"Open", ledger_open), (c"Settle", ledger_settle), (c"Expire", ledger_expire), (c"Count", ledger_count)]);
    (api.setmetatable)(l, -2);
    1
}

unsafe fn add_count(l: L, by: f64) {
    let api = api();
    (api.getfield)(l, 1, c"count".as_ptr());
    let n = (api.tonumber)(l, -1) + by;
    (api.settop)(l, -2);
    (api.pushnumber)(l, n);
    (api.setfield)(l, 1, c"count".as_ptr());
}

unsafe extern "C-unwind" fn ledger_open(l: L) -> c_int {
    let api = api();
    let (now, timeout) = ((api.checknumber)(l, 2), (api.checknumber)(l, 3));
    (api.getfield)(l, 1, c"nextId".as_ptr());
    let id = (api.tonumber)(l, -1);
    (api.settop)(l, -2);
    (api.pushnumber)(l, (id + 1.0) % 2f64.powf(ID_BITS));
    (api.setfield)(l, 1, c"nextId".as_ptr());
    push_tx(l);
    let tx = (api.gettop)(l);
    (api.getfield)(l, 1, c"open".as_ptr());
    (api.pushnumber)(l, id);
    (api.createtable)(l, 0, 2);
    (api.pushvalue)(l, tx);
    (api.setfield)(l, -2, c"tx".as_ptr());
    (api.pushnumber)(l, now + timeout);
    (api.setfield)(l, -2, c"deadline".as_ptr());
    (api.rawset)(l, -3);
    (api.settop)(l, tx);
    add_count(l, 1.0);
    (api.pushnumber)(l, id);
    (api.pushvalue)(l, tx);
    2
}

/// Closes the entry `id` (the number at `id`), pushing its transaction or nil.
unsafe fn close(l: L, id: c_int) {
    let api = api();
    (api.getfield)(l, 1, c"open".as_ptr());
    let open = (api.gettop)(l);
    (api.pushvalue)(l, id);
    (api.rawget)(l, open);
    if (api.type_of)(l, -1) == TNIL {
        (api.remove)(l, open);
        return;
    }
    (api.getfield)(l, -1, c"tx".as_ptr());
    (api.pushvalue)(l, id);
    (api.pushnil)(l);
    (api.rawset)(l, open);
    (api.replace)(l, open);
    (api.settop)(l, open);
    add_count(l, -1.0);
}

unsafe extern "C-unwind" fn ledger_settle(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    close(l, 2);
    let tx = (api.gettop)(l);
    if (api.type_of)(l, tx) == TNIL {
        return boolean(l, false);
    }
    (api.getfield)(l, 3, c"state".as_ptr());
    let state = tostring(l, -1);
    (api.settop)(l, tx);
    match state.as_str() {
        COMMITTED => {
            (api.pushnil)(l);
            settle(l, tx, COMMITTED, c"value", tx + 1);
        }
        DECLINED => {
            (api.getfield)(l, 3, c"kind".as_ptr());
            (api.getfield)(l, 3, c"detail".as_ptr());
            push_refusal(l, tx + 1, tx + 2);
            settle(l, tx, DECLINED, c"refusal", tx + 3);
        }
        _ => {
            (api.getfield)(l, 3, c"state".as_ptr());
            settle(l, tx, FAILED, c"err", tx + 1);
        }
    }
    boolean(l, true)
}

unsafe extern "C-unwind" fn ledger_expire(l: L) -> c_int {
    let api = api();
    let now = (api.checknumber)(l, 2);
    (api.settop)(l, 2);
    (api.getfield)(l, 1, c"open".as_ptr());
    let open = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let due = (api.gettop)(l);
    let mut n = 0;
    (api.pushnil)(l);
    while (api.next)(l, open) != 0 {
        (api.getfield)(l, -1, c"deadline".as_ptr());
        let deadline = (api.tonumber)(l, -1);
        (api.settop)(l, -2);
        if now >= deadline {
            n += 1;
            (api.pushvalue)(l, -2);
            (api.rawseti)(l, due, n);
        }
        (api.settop)(l, -2);
    }
    for i in 1..=n {
        (api.rawgeti)(l, due, i);
        let id = (api.gettop)(l);
        close(l, id);
        let tx = (api.gettop)(l);
        push_str(l, TIMED_OUT);
        push_str(l, TIMED_OUT_DETAIL);
        push_refusal(l, tx + 1, tx + 2);
        settle(l, tx, DECLINED, c"refusal", tx + 3);
        (api.settop)(l, due);
    }
    0
}

unsafe extern "C-unwind" fn ledger_count(l: L) -> c_int {
    field(l, c"count")
}

/// Pushes the transaction module table.
pub unsafe fn push_module(l: L) {
    let api = api();
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
    ] {
        push_str(l, v);
        (api.setfield)(l, -2, name.as_ptr());
    }
    (api.pushnumber)(l, ID_BITS);
    (api.setfield)(l, -2, c"ID_BITS".as_ptr());
}
