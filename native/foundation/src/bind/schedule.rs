//! list.schedule, native: cooperative tasks in a time slice, the Lua twin's
//! contract (foundation/list/schedule.lua). Each task is a Lua coroutine,
//! resumed through coroutine.resume; CheckYield, Yield and Wait suspend the
//! running task by returning lua_yield from inside it. The order, the
//! parked tasks and the deadline are the scheduler's; the coroutines, their
//! arguments and their conditions live in its environment (env.threads,
//! env.args, env.waiting, keyed by task number), beside env.clock.
//!
//! Nothing here holds a reference to the scheduler across a call into Lua:
//! a task may call its own scheduler, so each step looks it up again.

use super::slots::fresh_environment;
use super::util::{boolean, env_field, number};
use crate::lua::{raise_where, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TTABLE, TUSERDATA};
use crate::module;
use crate::userdata::{self, Native};
use std::collections::{HashSet, VecDeque};
use std::ffi::{c_int, CStr};

#[derive(Default)]
pub struct Scheduler {
    tasks: VecDeque<u32>,
    started: HashSet<u32>,
    next: u32,
    current: Option<u32>,
    deadline: f64,
}

impl Native for Scheduler {
    const NAME: &'static CStr = c"foundation.list.schedule";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Spawn", spawn),
        (c"Run", run),
        (c"CheckYield", check_yield),
        (c"Yield", yield_turn),
        (c"Wait", wait),
        (c"Limit", limit),
        (c"Count", count),
    ];
}

/// list.schedule.New(clock) -> a scheduler
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    l.settop(1);
    userdata::push(l, Scheduler::default());
    fresh_environment(l, -1);
    l.getfenv(-1);
    l.pushvalue(1);
    l.setfield(-2, c"clock");
    for name in [c"threads", c"args", c"waiting", c"finish", c"awaiting", c"limit", c"expire"] {
        l.createtable(0, 0);
        l.setfield(-2, name);
    }
    l.settop(-2);
    1
}

/// clock:Now(), the clock in the environment of the scheduler at 1.
unsafe fn now(l: L) -> f64 {
    env_field(l, 1, c"clock");
    l.getfield(-1, c"Now");
    l.pushvalue(-2);
    l.call(1, 1);
    let t = l.tonumber(-1);
    l.settop(-3);
    t
}

/// env[table][task] = the value at the top (popped).
unsafe fn store(l: L, table: &CStr, task: u32) {
    env_field(l, 1, table);
    l.insert(-2);
    l.rawseti(-2, task as c_int);
    l.settop(-2);
}

/// Pushes env[table][task].
unsafe fn fetch(l: L, table: &CStr, task: u32) {
    env_field(l, 1, table);
    l.rawgeti(-1, task as c_int);
    l.remove(-2);
}

/// env[table][task] = nil.
unsafe fn forget(l: L, table: &CStr, task: u32) {
    l.pushnil();
    store(l, table, task);
}

/// scheduler:Spawn(fn, ...) -> the task (its coroutine), run from the next Run
unsafe extern "C-unwind" fn spawn(l: L) -> c_int {
    spawn_frame(l, l.gettop())
}

/// Spawns the task of the scheduler at 1, the function at 2 and its
/// arguments at 3..n; values above n are left alone. Pushes the task.
unsafe fn spawn_frame(l: L, n: c_int) -> c_int {
    let s = userdata::check::<Scheduler>(l, 1);
    s.next += 1;
    let task = s.next;
    s.tasks.push_back(task);
    l.getfield(GLOBALSINDEX, c"coroutine");
    l.getfield(-1, c"create");
    l.pushvalue(2);
    l.call(1, 1);
    let thread = l.gettop();
    l.pushvalue(thread);
    store(l, c"threads", task);
    l.createtable(n.max(2) - 2, 1);
    for i in 3..=n {
        l.pushvalue(i);
        l.rawseti(-2, i - 2);
    }
    l.pushnumber((n.max(2) - 2) as f64);
    l.setfield(-2, c"n");
    store(l, c"args", task);
    l.pushvalue(thread);
    1
}

/// Whether the code calling is the running task itself (not a coroutine of
/// its own inside it, which a yield here would suspend instead).
unsafe fn in_task(l: L) -> bool {
    let Some(task) = userdata::check::<Scheduler>(l, 1).current else { return false };
    fetch(l, c"threads", task);
    l.pushthread();
    let same = l.rawequal(-1, -2) != 0;
    l.settop(-3);
    same
}

pub(super) unsafe extern "C-unwind" fn yield_turn(l: L) -> c_int {
    if !in_task(l) {
        return boolean(l, false);
    }
    l.settop(0);
    l.yield_(0)
}

pub(super) unsafe extern "C-unwind" fn check_yield(l: L) -> c_int {
    if !in_task(l) || now(l) < userdata::check::<Scheduler>(l, 1).deadline {
        return boolean(l, false);
    }
    l.settop(0);
    l.yield_(0)
}

pub(super) unsafe extern "C-unwind" fn wait(l: L) -> c_int {
    l.settop(2);
    if !in_task(l) {
        raise_where(l, "only a running task can wait".into());
    }
    l.pushvalue(2);
    l.call(0, 1);
    let ready = l.toboolean(-1) != 0;
    l.settop(2);
    if ready {
        return 0;
    }
    let task = userdata::check::<Scheduler>(l, 1).current.unwrap_or_default();
    l.pushvalue(2);
    store(l, c"waiting", task);
    l.settop(0);
    l.yield_(0)
}

/// scheduler:Limit(task, countdown, onExpire): gives the task a time to
/// finish in. The task is found among the live ones (the queue and the one
/// running) by its coroutine, which is what Spawn returns.
unsafe extern "C-unwind" fn limit(l: L) -> c_int {
    l.settop(4);
    let kind = l.type_of(3);
    if kind != TTABLE && kind != TUSERDATA {
        raise_where(l, "a task's countdown must say whether it has elapsed (IsElapsed)".into());
    }
    l.getfield(3, c"IsElapsed");
    let says = l.type_of(-1) == TFUNCTION;
    l.settop(4);
    if !says {
        raise_where(l, "a task's countdown must say whether it has elapsed (IsElapsed)".into());
    }
    let live: Vec<u32> = {
        let s = userdata::check::<Scheduler>(l, 1);
        s.tasks.iter().copied().chain(s.current).collect()
    };
    let mut found = None;
    for task in live {
        fetch(l, c"threads", task);
        let same = l.rawequal(-1, 2) != 0;
        l.settop(4);
        if same {
            found = Some(task);
            break;
        }
    }
    let Some(task) = found else { raise_where(l, "no such task to limit".into()) };
    fetch(l, c"limit", task);
    let has = l.type_of(-1) != TNIL;
    l.settop(4);
    if has {
        raise_where(l, "a task has one countdown".into());
    }
    l.pushvalue(3);
    store(l, c"limit", task);
    l.pushvalue(4);
    store(l, c"expire", task);
    0
}

/// Whether the task's countdown, if it has one, has elapsed.
unsafe fn limit_elapsed(l: L, task: u32) -> bool {
    fetch(l, c"limit", task);
    if l.type_of(-1) == TNIL {
        l.settop(-2);
        return false;
    }
    l.getfield(-1, c"IsElapsed");
    l.pushvalue(-2);
    l.call(1, 1);
    let elapsed = l.toboolean(-1) != 0;
    l.settop(-3);
    elapsed
}

/// Whether the transaction at `tx` has settled (its state is not pending).
unsafe fn settled(l: L, tx: c_int) -> bool {
    l.getfield(tx, c"state");
    let pending = crate::lua::string_at(l, -1) == Some(b"pending".as_slice());
    l.settop(-2);
    !pending
}

/// Whether the task may run: not parked, or its condition now holds (its
/// condition function, or the transaction it awaits settled).
unsafe fn may_run(l: L, task: u32) -> bool {
    // one out of time is ended, parked or not
    if limit_elapsed(l, task) {
        return true;
    }
    fetch(l, c"awaiting", task);
    if l.type_of(-1) != TNIL {
        let ready = settled(l, l.gettop());
        l.settop(-2);
        return ready;
    }
    l.settop(-2);
    fetch(l, c"waiting", task);
    if l.type_of(-1) == TNIL {
        l.settop(-2);
        return true;
    }
    l.call(0, 1);
    let ready = l.toboolean(-1) != 0;
    l.settop(-2);
    ready
}

/// Resumes the task with the value at `with` (else true, or its arguments
/// on its first run): the coroutine, then (ok, results...) left on the stack.
unsafe fn resume(l: L, task: u32, with: Option<c_int>) {
    let started = !userdata::check::<Scheduler>(l, 1).started.insert(task);
    l.getfield(GLOBALSINDEX, c"coroutine");
    l.getfield(-1, c"resume");
    l.remove(-2);
    fetch(l, c"threads", task);
    l.pushvalue(-1);
    l.insert(-3);
    let mut nargs = 1;
    if started {
        match with {
            // what CheckYield and Yield return to the task, as the Lua twin's do
            None => l.pushboolean(1),
            Some(value) => l.pushvalue(value),
        }
        nargs += 1;
    } else {
        fetch(l, c"args", task);
        let args = l.gettop();
        l.getfield(args, c"n");
        let n = l.tonumber(-1) as c_int;
        l.settop(-2);
        for i in 1..=n {
            l.rawgeti(args, i);
        }
        l.remove(args);
        nargs += n;
        forget(l, c"args", task);
    }
    l.call(nargs, -1);
}

/// Whether the coroutine at `index` has finished.
unsafe fn dead(l: L, index: c_int) -> bool {
    let index = if index < 0 { l.gettop() + index + 1 } else { index };
    l.getfield(GLOBALSINDEX, c"coroutine");
    l.getfield(-1, c"status");
    l.pushvalue(index);
    l.call(1, 1);
    let status = crate::lua::string_at(l, -1) == Some(b"dead".as_slice());
    l.settop(-3);
    status
}

/// Forgets a task that has ended.
unsafe fn finish(l: L, task: u32) {
    for table in [c"threads", c"waiting", c"args", c"finish", c"awaiting", c"limit", c"expire"] {
        forget(l, table, task);
    }
    userdata::check::<Scheduler>(l, 1).started.remove(&task);
}

/// Hands a task's outcome (ok, then the values from `first` to the top) to
/// its finish handler, when it has one; whether it had.
unsafe fn hand_over(l: L, task: u32, ok: bool, first: c_int) -> bool {
    let top = l.gettop();
    fetch(l, c"finish", task);
    if l.type_of(-1) == TNIL {
        l.settop(top);
        return false;
    }
    l.pushboolean(ok as c_int);
    for i in first..=top {
        l.pushvalue(i);
    }
    finish(l, task);
    l.call(top - first + 2, 0);
    l.settop(top);
    true
}

/// A task's error raised from Run, as the Lua twin raises it (a traceback
/// of the coroutine at `thread`, the error at `err`).
unsafe fn raise_task_error(l: L, thread: c_int, err: c_int) -> ! {
    l.getfield(GLOBALSINDEX, c"debug");
    l.getfield(-1, c"traceback");
    l.pushvalue(thread);
    crate::lua::push_tostring(l, err);
    l.call(2, 1);
    l.error();
    unreachable!("lua_error does not return")
}

/// Runs one task: resumed (or, awaiting a transaction that declined or
/// failed, ended with its refusal or error, as an uncaught raise would end
/// it), then handed over, requeued or forgotten.
unsafe fn step_task(l: L, task: u32) {
    let base = l.gettop();
    // out of time: not resumed; its handler told, once, with the task
    if limit_elapsed(l, task) {
        fetch(l, c"expire", task);
        fetch(l, c"threads", task);
        finish(l, task);
        if l.type_of(base + 1) != TNIL {
            l.call(1, 0);
        }
        l.settop(base);
        return;
    }
    fetch(l, c"awaiting", task);
    let tx = l.gettop();
    let mut with = None;
    if l.type_of(tx) != TNIL {
        forget(l, c"awaiting", task);
        l.getfield(tx, c"state");
        let committed = crate::lua::string_at(l, -1) == Some(b"committed".as_slice());
        let declined = crate::lua::string_at(l, -1) == Some(b"declined".as_slice());
        l.settop(tx);
        if committed {
            l.getfield(tx, c"value");
            with = Some(l.gettop());
        } else {
            l.getfield(tx, if declined { c"refusal" } else { c"err" });
            let err = l.gettop();
            if !hand_over(l, task, false, err) {
                fetch(l, c"threads", task);
                let thread = l.gettop();
                finish(l, task);
                raise_task_error(l, thread, err);
            }
            l.settop(base);
            return;
        }
    }
    userdata::check::<Scheduler>(l, 1).current = Some(task);
    let before = l.gettop();
    resume(l, task, with);
    userdata::check::<Scheduler>(l, 1).current = None;
    let thread = before + 1;
    let ok = l.toboolean(thread + 1) != 0;
    if !ok {
        if !hand_over(l, task, false, thread + 2) {
            finish(l, task);
            raise_task_error(l, thread, thread + 2);
        }
    } else if dead(l, thread) {
        if !hand_over(l, task, true, thread + 2) {
            finish(l, task);
        }
    } else {
        userdata::check::<Scheduler>(l, 1).tasks.push_back(task);
    }
    l.settop(base);
}

/// scheduler:Run(seconds): the tasks in turn until the slice is spent or
/// none is left; a task's error raised here, the task removed first
unsafe extern "C-unwind" fn run(l: L) -> c_int {
    let seconds = l.checknumber(2);
    l.settop(2);
    if userdata::check::<Scheduler>(l, 1).tasks.is_empty() {
        return 0;
    }
    let deadline = now(l) + seconds;
    userdata::check::<Scheduler>(l, 1).deadline = deadline;
    let mut parked = 0usize;
    while let Some(task) = userdata::check::<Scheduler>(l, 1).tasks.pop_front() {
        if !may_run(l, task) {
            userdata::check::<Scheduler>(l, 1).tasks.push_back(task);
            parked += 1;
        } else {
            forget(l, c"waiting", task);
            parked = 0;
            step_task(l, task);
        }
        let size = userdata::check::<Scheduler>(l, 1).tasks.len();
        if size == 0 || parked >= size || now(l) >= deadline {
            break;
        }
    }
    0
}

/// For transaction.Spawn: spawns the function at 2 with the arguments from
/// 3 to `last` as a task of the scheduler at 1, whose outcome goes to the
/// handler at `last + 1` (handler(ok, ...)) instead of being raised by Run.
/// Values above `last + 1` are left where they are.
pub(super) unsafe fn spawn_finishing(l: L, last: c_int) {
    let task = userdata::check::<Scheduler>(l, 1).next + 1;
    l.pushvalue(last + 1);
    store(l, c"finish", task);
    spawn_frame(l, last);
}

/// For transaction's Await: parks the running task of the scheduler at 1
/// until the transaction at 2 settles; the C function calling returns this.
pub(super) unsafe fn park_on(l: L) -> c_int {
    if !in_task(l) {
        raise_where(l, "only a running task can wait".into());
    }
    let task = userdata::check::<Scheduler>(l, 1).current.unwrap_or_default();
    l.pushvalue(2);
    store(l, c"awaiting", task);
    l.settop(0);
    l.yield_(0)
}

unsafe extern "C-unwind" fn count(l: L) -> c_int {
    number(l, userdata::check::<Scheduler>(l, 1).tasks.len() as f64)
}

/// Pushes the list.schedule module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], None);
}
