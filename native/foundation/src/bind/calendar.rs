//! list.calendar, native: recurring jobs run a budget at a time, fair across
//! systems and earliest due first within one, the Lua twin's contract
//! (foundation/list/calendar.lua). The systems, the jobs, their standings,
//! heaps and counts are the calendar's; the job functions live in its
//! environment (env.fns, keyed by job number), beside env.clock and env.timer.
//!
//! Nothing here holds a reference to the calendar across a call into Lua: a
//! job may call its own calendar (Wake, Cancel, Every), so each step looks it
//! up again.

use super::slots::fresh_environment;
use super::util::{absent, env_field, nothing, number};
use crate::heap::Heap;
use crate::lua::{api, push_str, raise_where, tostring, CFunction, L, TBOOLEAN, TFUNCTION, TNUMBER, TSTRING};
use crate::module;
use crate::userdata::{self, Native};
use std::collections::HashMap;
use std::ffi::{c_int, CStr, CString};

#[derive(Default)]
struct Counts {
    runs: u32,
    spent: f64,
    late: f64,
    late_max: f64,
}

impl Counts {
    fn add(&mut self, spent: f64, late: f64) {
        self.runs += 1;
        self.spent += spent;
        self.late += late;
        if late > self.late_max {
            self.late_max = late;
        }
    }
}

struct System {
    name: CString,
    weight: f64,
    standing: f64,
    heap: Heap,
    jobs: u32,
    behind: u32,
    counts: Counts,
}

struct Job {
    system: usize,
    period: f64,
    at: f64,
    ticket: u64,
    runs: u32,
    late: f64,
    late_max: f64,
    woken: Option<f64>,
}

#[derive(Default)]
pub struct Calendar {
    systems: Vec<System>,
    jobs: HashMap<u32, Job>,
    tickets: HashMap<u64, u32>,
    next_job: u32,
    next_ticket: u64,
    floor: f64,
    running: Option<u32>,
}

impl Native for Calendar {
    const NAME: &'static CStr = c"foundation.list.calendar";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"System", system),
        (c"Every", every),
        (c"Wake", wake),
        (c"Cancel", cancel),
        (c"Run", run),
        (c"Report", report),
        (c"Job", job),
        (c"Size", size),
        (c"__len", size),
    ];
}

impl Calendar {
    fn system_named(&self, name: &[u8]) -> Option<usize> {
        self.systems.iter().position(|s| s.name.as_bytes() == name)
    }

    /// Queues `id` at `at` under a new ticket, its old one let go.
    fn queue(&mut self, id: u32, at: f64) {
        self.next_ticket += 1;
        let ticket = self.next_ticket;
        let job = self.jobs.get_mut(&id).expect("a queued job is known");
        self.tickets.remove(&job.ticket);
        self.tickets.insert(ticket, id);
        job.ticket = ticket;
        job.at = at;
        self.systems[job.system].heap.push(at, ticket as f64);
    }

    /// The ticket and time of system `s`'s job due first, past its stale entries.
    fn top(&mut self, s: usize) -> Option<(u64, f64)> {
        let heap = &mut self.systems[s].heap;
        while let Some((ticket, at)) = heap.peek() {
            let ticket = ticket as u64;
            if self.tickets.contains_key(&ticket) {
                return Some((ticket, at));
            }
            heap.pop();
        }
        None
    }

    /// Of the systems with a job due at `now`, the lowest standing, a tie to
    /// the one made first; a system's standing raised to the floor first.
    fn pick(&mut self, now: f64) -> Option<usize> {
        let mut best: Option<usize> = None;
        for s in 0..self.systems.len() {
            let Some((_, at)) = self.top(s) else { continue };
            if at > now {
                continue;
            }
            let standing = self.systems[s].standing.max(self.floor);
            self.systems[s].standing = standing;
            if best.map_or(true, |b| standing < self.systems[b].standing) {
                best = Some(s);
            }
        }
        best
    }

    fn cancel(&mut self, id: u32) -> bool {
        let Some(job) = self.jobs.remove(&id) else { return false };
        self.tickets.remove(&job.ticket);
        self.systems[job.system].jobs -= 1;
        true
    }
}

/// field:Now() of the calendar at 1's environment.
unsafe fn now_of(l: L, field: &CStr) -> f64 {
    let api = api();
    env_field(l, 1, field);
    (api.getfield)(l, -1, c"Now".as_ptr());
    (api.pushvalue)(l, -2);
    (api.call)(l, 1, 1);
    let t = (api.tonumber)(l, -1);
    (api.settop)(l, -3);
    t
}

/// env.fns[id] = the value at `index` (absolute), or nil when `index` is 0.
unsafe fn set_fn(l: L, id: u32, index: c_int) {
    let api = api();
    env_field(l, 1, c"fns");
    if index == 0 {
        (api.pushnil)(l);
    } else {
        (api.pushvalue)(l, index);
    }
    (api.rawseti)(l, -2, id as c_int);
    (api.settop)(l, -2);
}

/// list.calendar.New(clock, timer) -> a calendar
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    userdata::push(l, Calendar::default());
    fresh_environment(l, -1);
    (api.getfenv)(l, -1);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"clock".as_ptr());
    (api.pushvalue)(l, 2);
    (api.setfield)(l, -2, c"timer".as_ptr());
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, c"fns".as_ptr());
    (api.settop)(l, -2);
    1
}

/// The string at `index`, as bytes, or None for any other value.
unsafe fn string_at(l: L, index: c_int) -> Option<Vec<u8>> {
    let api = api();
    if (api.type_of)(l, index) != TSTRING {
        return None;
    }
    Some(CStr::from_ptr((api.tolstring)(l, index, std::ptr::null_mut())).to_bytes().to_vec())
}

/// calendar:System(name, weight)
unsafe extern "C-unwind" fn system(l: L) -> c_int {
    let api = api();
    let Some(name) = string_at(l, 2) else {
        raise_where(l, format!("a system's name is a string, not {}", tostring(l, 2)))
    };
    let weight = ((api.type_of)(l, 3) == TNUMBER).then(|| (api.tonumber)(l, 3)).filter(|w| *w > 0.0);
    let Some(weight) = weight else {
        raise_where(l, format!("a system's weight is a number above 0, not {}", tostring(l, 3)))
    };
    let calendar = userdata::check::<Calendar>(l, 1);
    if calendar.system_named(&name).is_some() {
        raise_where(l, format!("a system is already named {}", tostring(l, 2)));
    }
    let standing = calendar.floor;
    calendar.systems.push(System {
        name: CString::new(name).unwrap_or_default(),
        weight,
        standing,
        heap: Heap::default(),
        jobs: 0,
        behind: 0,
        counts: Counts::default(),
    });
    0
}

/// calendar:Every(system, period, fn[, at]) -> the job
unsafe extern "C-unwind" fn every(l: L) -> c_int {
    let api = api();
    let found = string_at(l, 2).and_then(|name| userdata::check::<Calendar>(l, 1).system_named(&name));
    let Some(s) = found else { raise_where(l, format!("no system is named {}", tostring(l, 2))) };
    let period = ((api.type_of)(l, 3) == TNUMBER).then(|| (api.tonumber)(l, 3)).filter(|p| *p > 0.0);
    let Some(period) = period else {
        raise_where(l, format!("a job's period is a number above 0, not {}", tostring(l, 3)))
    };
    if (api.type_of)(l, 4) != TFUNCTION {
        raise_where(l, format!("a job is a function, not {}", tostring(l, 4)));
    }
    let at = if absent(l, 5) { now_of(l, c"clock") } else { (api.checknumber)(l, 5) };
    let calendar = userdata::check::<Calendar>(l, 1);
    calendar.next_job += 1;
    let id = calendar.next_job;
    calendar.jobs.insert(id, Job { system: s, period, at, ticket: 0, runs: 0, late: 0.0, late_max: 0.0, woken: None });
    calendar.systems[s].jobs += 1;
    calendar.queue(id, at);
    set_fn(l, id, 4);
    number(l, id as f64)
}

/// A job number at `index`, or None.
unsafe fn id_at(l: L, index: c_int) -> Option<u32> {
    let api = api();
    if (api.type_of)(l, index) != TNUMBER {
        return None;
    }
    let n = (api.tonumber)(l, index);
    (n >= 1.0 && n.fract() == 0.0 && n <= u32::MAX as f64).then_some(n as u32)
}

/// calendar:Wake(job[, at])
unsafe extern "C-unwind" fn wake(l: L) -> c_int {
    let api = api();
    let Some(id) = id_at(l, 2) else { return 0 };
    if !userdata::check::<Calendar>(l, 1).jobs.contains_key(&id) {
        return 0;
    }
    let at = if absent(l, 3) { now_of(l, c"clock") } else { (api.checknumber)(l, 3) };
    let calendar = userdata::check::<Calendar>(l, 1);
    if calendar.running == Some(id) {
        let job = calendar.jobs.get_mut(&id).expect("known");
        if job.woken.map_or(true, |w| at < w) {
            job.woken = Some(at);
        }
    } else if at < calendar.jobs[&id].at {
        calendar.queue(id, at);
    }
    0
}

/// calendar:Cancel(job)
unsafe extern "C-unwind" fn cancel(l: L) -> c_int {
    let Some(id) = id_at(l, 2) else { return 0 };
    if userdata::check::<Calendar>(l, 1).cancel(id) {
        set_fn(l, id, 0);
    }
    0
}

/// When a job due at `at` that ran at `now` is due next, by its answer at
/// `answer`: None, it leaves.
unsafe fn next_at(l: L, answer: c_int, period: f64, at: f64, now: f64) -> Option<f64> {
    let api = api();
    match (api.type_of)(l, answer) {
        TBOOLEAN if (api.toboolean)(l, answer) == 0 => None,
        TNUMBER => Some(now + (api.tonumber)(l, answer)),
        _ => {
            let next = at + period;
            Some(if next <= now { at + period * (((now - at) / period).floor() + 1.0) } else { next })
        }
    }
}

/// calendar:Run(seconds[, count]) -> how many jobs ran
unsafe extern "C-unwind" fn run(l: L) -> c_int {
    let api = api();
    let seconds = (api.checknumber)(l, 2);
    let count = if absent(l, 3) { None } else { Some((api.checknumber)(l, 3)) };
    (api.settop)(l, 3);
    let now = now_of(l, c"clock");
    let started = now_of(l, c"timer");
    let mut t = started;
    let mut ran = 0u32;
    let mut drained = false;
    while t - started < seconds && count.map_or(true, |c| (ran as f64) < c) {
        let calendar = userdata::check::<Calendar>(l, 1);
        let Some(s) = calendar.pick(now) else {
            drained = true;
            break;
        };
        let (ticket, at) = calendar.top(s).expect("a picked system has a job due");
        calendar.systems[s].heap.pop();
        let id = calendar.tickets.remove(&ticket).expect("a live ticket has its job");
        let standing = calendar.systems[s].standing;
        if calendar.floor < standing {
            calendar.floor = standing;
        }
        calendar.running = Some(id);
        env_field(l, 1, c"fns");
        (api.rawgeti)(l, -1, id as c_int);
        (api.remove)(l, -2);
        (api.pushnumber)(l, id as f64);
        (api.pushnumber)(l, now);
        let failed = (api.pcall)(l, 2, 1, 0) != 0;
        let answer = (api.gettop)(l);
        let after = now_of(l, c"timer");
        let spent = after - t;
        t = after;
        ran += 1;
        let late = now - at;
        let calendar = userdata::check::<Calendar>(l, 1);
        calendar.running = None;
        let system = &mut calendar.systems[s];
        system.standing += spent / system.weight;
        system.counts.add(spent, late);
        let Some(job) = calendar.jobs.get_mut(&id) else {
            if failed {
                (api.error)(l);
            }
            (api.settop)(l, answer - 1);
            continue;
        };
        job.runs += 1;
        job.late = late;
        if late > job.late_max {
            job.late_max = late;
        }
        let woken = job.woken.take();
        let period = job.period;
        if failed {
            calendar.cancel(id);
            set_fn(l, id, 0);
            (api.settop)(l, answer);
            (api.error)(l);
        }
        let next = next_at(l, answer, period, at, now);
        let next = match (next, woken) {
            (Some(n), Some(w)) => Some(n.min(w)),
            (None, Some(w)) => Some(w),
            (n, None) => n,
        };
        (api.settop)(l, answer - 1);
        let calendar = userdata::check::<Calendar>(l, 1);
        match next {
            Some(n) => calendar.queue(id, n),
            None => {
                calendar.cancel(id);
                set_fn(l, id, 0);
            }
        }
    }
    let calendar = userdata::check::<Calendar>(l, 1);
    for system in &mut calendar.systems {
        system.behind = 0;
    }
    if !drained {
        let Calendar { systems, jobs, .. } = calendar;
        for job in jobs.values().filter(|j| j.at <= now) {
            systems[job.system].behind += 1;
        }
    }
    number(l, ran as f64)
}

unsafe fn set_number(l: L, name: &CStr, n: f64) {
    let api = api();
    (api.pushnumber)(l, n);
    (api.setfield)(l, -2, name.as_ptr());
}

/// calendar:Report([reset]) -> { [system] = { weight, jobs, runs, spent, late, lateMax, behind } }
unsafe extern "C-unwind" fn report(l: L) -> c_int {
    let api = api();
    let reset = (api.toboolean)(l, 2) != 0;
    let calendar = userdata::check::<Calendar>(l, 1);
    (api.createtable)(l, 0, calendar.systems.len() as c_int);
    for system in &mut calendar.systems {
        (api.createtable)(l, 0, 7);
        set_number(l, c"weight", system.weight);
        set_number(l, c"jobs", system.jobs as f64);
        set_number(l, c"runs", system.counts.runs as f64);
        set_number(l, c"spent", system.counts.spent);
        set_number(l, c"late", system.counts.late);
        set_number(l, c"lateMax", system.counts.late_max);
        set_number(l, c"behind", system.behind as f64);
        (api.setfield)(l, -2, system.name.as_ptr());
        if reset {
            system.counts = Counts::default();
        }
    }
    1
}

/// calendar:Job(job) -> { system, period, at, runs, late, lateMax }, or nil
unsafe extern "C-unwind" fn job(l: L) -> c_int {
    let api = api();
    let calendar = userdata::check::<Calendar>(l, 1);
    let Some(job) = id_at(l, 2).and_then(|id| calendar.jobs.get(&id)) else { return nothing(l) };
    (api.createtable)(l, 0, 6);
    push_str(l, &calendar.systems[job.system].name.to_string_lossy());
    (api.setfield)(l, -2, c"system".as_ptr());
    set_number(l, c"period", job.period);
    set_number(l, c"at", job.at);
    set_number(l, c"runs", job.runs as f64);
    set_number(l, c"late", job.late);
    set_number(l, c"lateMax", job.late_max);
    1
}

/// calendar:Size(), #calendar
unsafe extern "C-unwind" fn size(l: L) -> c_int {
    number(l, userdata::check::<Calendar>(l, 1).jobs.len() as f64)
}

/// Pushes the list.calendar module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], None);
}
