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
use crate::lua::{api, raise_where, CFunction, GLOBALSINDEX, L, TNIL};
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
        (c"Count", count),
    ];
}

/// list.schedule.New(clock) -> a scheduler
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    userdata::push(l, Scheduler::default());
    fresh_environment(l, -1);
    (api.getfenv)(l, -1);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"clock".as_ptr());
    for name in [c"threads", c"args", c"waiting", c"finish", c"awaiting"] {
        (api.createtable)(l, 0, 0);
        (api.setfield)(l, -2, name.as_ptr());
    }
    (api.settop)(l, -2);
    1
}

/// clock:Now(), the clock in the environment of the scheduler at 1.
unsafe fn now(l: L) -> f64 {
    let api = api();
    env_field(l, 1, c"clock");
    (api.getfield)(l, -1, c"Now".as_ptr());
    (api.pushvalue)(l, -2);
    (api.call)(l, 1, 1);
    let t = (api.tonumber)(l, -1);
    (api.settop)(l, -3);
    t
}

/// env[table][task] = the value at the top (popped).
unsafe fn store(l: L, table: &CStr, task: u32) {
    let api = api();
    env_field(l, 1, table);
    (api.insert)(l, -2);
    (api.rawseti)(l, -2, task as c_int);
    (api.settop)(l, -2);
}

/// Pushes env[table][task].
unsafe fn fetch(l: L, table: &CStr, task: u32) {
    let api = api();
    env_field(l, 1, table);
    (api.rawgeti)(l, -1, task as c_int);
    (api.remove)(l, -2);
}

/// env[table][task] = nil.
unsafe fn forget(l: L, table: &CStr, task: u32) {
    (api().pushnil)(l);
    store(l, table, task);
}

/// scheduler:Spawn(fn, ...) -> the task (its coroutine), run from the next Run
unsafe extern "C-unwind" fn spawn(l: L) -> c_int {
    spawn_frame(l, (api().gettop)(l))
}

/// Spawns the task of the scheduler at 1, the function at 2 and its
/// arguments at 3..n; values above n are left alone. Pushes the task.
unsafe fn spawn_frame(l: L, n: c_int) -> c_int {
    let api = api();
    let s = userdata::check::<Scheduler>(l, 1);
    s.next += 1;
    let task = s.next;
    s.tasks.push_back(task);
    (api.getfield)(l, GLOBALSINDEX, c"coroutine".as_ptr());
    (api.getfield)(l, -1, c"create".as_ptr());
    (api.pushvalue)(l, 2);
    (api.call)(l, 1, 1);
    let thread = (api.gettop)(l);
    (api.pushvalue)(l, thread);
    store(l, c"threads", task);
    (api.createtable)(l, n.max(2) - 2, 1);
    for i in 3..=n {
        (api.pushvalue)(l, i);
        (api.rawseti)(l, -2, i - 2);
    }
    (api.pushnumber)(l, (n.max(2) - 2) as f64);
    (api.setfield)(l, -2, c"n".as_ptr());
    store(l, c"args", task);
    (api.pushvalue)(l, thread);
    1
}

/// Whether the code calling is the running task itself (not a coroutine of
/// its own inside it, which a yield here would suspend instead).
unsafe fn in_task(l: L) -> bool {
    let api = api();
    let Some(task) = userdata::check::<Scheduler>(l, 1).current else { return false };
    fetch(l, c"threads", task);
    (api.pushthread)(l);
    let same = (api.rawequal)(l, -1, -2) != 0;
    (api.settop)(l, -3);
    same
}

unsafe extern "C-unwind" fn yield_turn(l: L) -> c_int {
    if !in_task(l) {
        return boolean(l, false);
    }
    (api().settop)(l, 0);
    (api().yield_)(l, 0)
}

unsafe extern "C-unwind" fn check_yield(l: L) -> c_int {
    if !in_task(l) || now(l) < userdata::check::<Scheduler>(l, 1).deadline {
        return boolean(l, false);
    }
    (api().settop)(l, 0);
    (api().yield_)(l, 0)
}

unsafe extern "C-unwind" fn wait(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if !in_task(l) {
        raise_where(l, "only a running task can wait".into());
    }
    (api.pushvalue)(l, 2);
    (api.call)(l, 0, 1);
    let ready = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, 2);
    if ready {
        return 0;
    }
    let task = userdata::check::<Scheduler>(l, 1).current.unwrap_or_default();
    (api.pushvalue)(l, 2);
    store(l, c"waiting", task);
    (api.settop)(l, 0);
    (api.yield_)(l, 0)
}

/// Whether the transaction at `tx` has settled (its state is not pending).
unsafe fn settled(l: L, tx: c_int) -> bool {
    let api = api();
    (api.getfield)(l, tx, c"state".as_ptr());
    let pending = crate::lua::string_at(l, -1) == Some(b"pending".as_slice());
    (api.settop)(l, -2);
    !pending
}

/// Whether the task may run: not parked, or its condition now holds (its
/// condition function, or the transaction it awaits settled).
unsafe fn may_run(l: L, task: u32) -> bool {
    let api = api();
    fetch(l, c"awaiting", task);
    if (api.type_of)(l, -1) != TNIL {
        let ready = settled(l, (api.gettop)(l));
        (api.settop)(l, -2);
        return ready;
    }
    (api.settop)(l, -2);
    fetch(l, c"waiting", task);
    if (api.type_of)(l, -1) == TNIL {
        (api.settop)(l, -2);
        return true;
    }
    (api.call)(l, 0, 1);
    let ready = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    ready
}

/// Resumes the task with the value at `with` (else true, or its arguments
/// on its first run): the coroutine, then (ok, results...) left on the stack.
unsafe fn resume(l: L, task: u32, with: Option<c_int>) {
    let api = api();
    let started = !userdata::check::<Scheduler>(l, 1).started.insert(task);
    (api.getfield)(l, GLOBALSINDEX, c"coroutine".as_ptr());
    (api.getfield)(l, -1, c"resume".as_ptr());
    (api.remove)(l, -2);
    fetch(l, c"threads", task);
    (api.pushvalue)(l, -1);
    (api.insert)(l, -3);
    let mut nargs = 1;
    if started {
        match with {
            // what CheckYield and Yield return to the task, as the Lua twin's do
            None => (api.pushboolean)(l, 1),
            Some(value) => (api.pushvalue)(l, value),
        }
        nargs += 1;
    } else {
        fetch(l, c"args", task);
        let args = (api.gettop)(l);
        (api.getfield)(l, args, c"n".as_ptr());
        let n = (api.tonumber)(l, -1) as c_int;
        (api.settop)(l, -2);
        for i in 1..=n {
            (api.rawgeti)(l, args, i);
        }
        (api.remove)(l, args);
        nargs += n;
        forget(l, c"args", task);
    }
    (api.call)(l, nargs, -1);
}

/// Whether the coroutine at `index` has finished.
unsafe fn dead(l: L, index: c_int) -> bool {
    let api = api();
    let index = if index < 0 { (api.gettop)(l) + index + 1 } else { index };
    (api.getfield)(l, GLOBALSINDEX, c"coroutine".as_ptr());
    (api.getfield)(l, -1, c"status".as_ptr());
    (api.pushvalue)(l, index);
    (api.call)(l, 1, 1);
    let status = crate::lua::string_at(l, -1) == Some(b"dead".as_slice());
    (api.settop)(l, -3);
    status
}

/// Forgets a task that has ended.
unsafe fn finish(l: L, task: u32) {
    for table in [c"threads", c"waiting", c"args", c"finish", c"awaiting"] {
        forget(l, table, task);
    }
    userdata::check::<Scheduler>(l, 1).started.remove(&task);
}

/// Hands a task's outcome (ok, then the values from `first` to the top) to
/// its finish handler, when it has one; whether it had.
unsafe fn hand_over(l: L, task: u32, ok: bool, first: c_int) -> bool {
    let api = api();
    let top = (api.gettop)(l);
    fetch(l, c"finish", task);
    if (api.type_of)(l, -1) == TNIL {
        (api.settop)(l, top);
        return false;
    }
    (api.pushboolean)(l, ok as c_int);
    for i in first..=top {
        (api.pushvalue)(l, i);
    }
    finish(l, task);
    (api.call)(l, top - first + 2, 0);
    (api.settop)(l, top);
    true
}

/// A task's error raised from Run, as the Lua twin raises it (a traceback
/// of the coroutine at `thread`, the error at `err`).
unsafe fn raise_task_error(l: L, thread: c_int, err: c_int) -> ! {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"debug".as_ptr());
    (api.getfield)(l, -1, c"traceback".as_ptr());
    (api.pushvalue)(l, thread);
    crate::lua::push_tostring(l, err);
    (api.call)(l, 2, 1);
    (api.error)(l);
    unreachable!("lua_error does not return")
}

/// Runs one task: resumed (or, awaiting a transaction that declined or
/// failed, ended with its refusal or error, as an uncaught raise would end
/// it), then handed over, requeued or forgotten.
unsafe fn step_task(l: L, task: u32) {
    let api = api();
    let base = (api.gettop)(l);
    fetch(l, c"awaiting", task);
    let tx = (api.gettop)(l);
    let mut with = None;
    if (api.type_of)(l, tx) != TNIL {
        forget(l, c"awaiting", task);
        (api.getfield)(l, tx, c"state".as_ptr());
        let committed = crate::lua::string_at(l, -1) == Some(b"committed".as_slice());
        let declined = crate::lua::string_at(l, -1) == Some(b"declined".as_slice());
        (api.settop)(l, tx);
        if committed {
            (api.getfield)(l, tx, c"value".as_ptr());
            with = Some((api.gettop)(l));
        } else {
            (api.getfield)(l, tx, if declined { c"refusal".as_ptr() } else { c"err".as_ptr() });
            let err = (api.gettop)(l);
            if !hand_over(l, task, false, err) {
                fetch(l, c"threads", task);
                let thread = (api.gettop)(l);
                finish(l, task);
                raise_task_error(l, thread, err);
            }
            (api.settop)(l, base);
            return;
        }
    }
    userdata::check::<Scheduler>(l, 1).current = Some(task);
    let before = (api.gettop)(l);
    resume(l, task, with);
    userdata::check::<Scheduler>(l, 1).current = None;
    let thread = before + 1;
    let ok = (api.toboolean)(l, thread + 1) != 0;
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
    (api.settop)(l, base);
}

/// scheduler:Run(seconds): the tasks in turn until the slice is spent or
/// none is left; a task's error raised here, the task removed first
unsafe extern "C-unwind" fn run(l: L) -> c_int {
    let api = api();
    let seconds = (api.checknumber)(l, 2);
    (api.settop)(l, 2);
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
    let api = api();
    let task = userdata::check::<Scheduler>(l, 1).next + 1;
    (api.pushvalue)(l, last + 1);
    store(l, c"finish", task);
    spawn_frame(l, last);
}

/// For transaction's Await: parks the running task of the scheduler at 1
/// until the transaction at 2 settles; the C function calling returns this.
pub(super) unsafe fn park_on(l: L) -> c_int {
    let api = api();
    if !in_task(l) {
        raise_where(l, "only a running task can wait".into());
    }
    let task = userdata::check::<Scheduler>(l, 1).current.unwrap_or_default();
    (api.pushvalue)(l, 2);
    store(l, c"awaiting", task);
    (api.settop)(l, 0);
    (api.yield_)(l, 0)
}

unsafe extern "C-unwind" fn count(l: L) -> c_int {
    number(l, userdata::check::<Scheduler>(l, 1).tasks.len() as f64)
}

/// Pushes the list.schedule module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], None);
}
