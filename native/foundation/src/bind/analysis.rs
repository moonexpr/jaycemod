//! analysis.memory and analysis.analytics, native: the Lua twins'
//! contracts (foundation/analysis/). memory walks Lua's own objects through
//! the C API (with an explicit stack, so a long chain cannot overflow the C
//! stack); analytics keeps its timers, counters and rings in Rust, its clock
//! and memory the caller's ports.

use super::util::{each_item, number};
use crate::lua::{push_str, raise_where, string_at, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TNUMBER, TSTRING, TTABLE};
use crate::module;
use crate::userdata::{self, Native};
use std::collections::HashMap;
use std::ffi::{c_int, CStr};

// analysis.memory -----------------------------------------------------------

const TABLE: f64 = 64.0;
const ARRAY_SLOT: f64 = 8.0;
const HASH_NODE: f64 = 24.0;
const STRING: f64 = 24.0;
const FUNCTION: f64 = 40.0;
const UPVALUE: f64 = 8.0;

fn hash_nodes(count: f64) -> f64 {
    if count <= 0.0 {
        return 0.0;
    }
    let mut nodes = 1.0;
    while nodes < count {
        nodes *= 2.0;
    }
    nodes
}

/// The number of upvalues of the function at `f` (debug.getinfo's nups).
unsafe fn upvalues(l: L, f: c_int) -> f64 {
    l.getfield(GLOBALSINDEX, c"debug");
    l.getfield(-1, c"getinfo");
    l.pushvalue(f);
    push_str(l, "u");
    l.call(2, 1);
    l.getfield(-1, c"nups");
    let n = l.tonumber(-1);
    l.settop(-4);
    n
}

/// The bytes of the value at `root` not yet counted (seen at `seen`),
/// marking what it counts. Work waits on a Lua table used as a stack.
unsafe fn walk(l: L, root: c_int, seen: c_int) -> f64 {
    l.createtable(0, 0);
    let stack = l.gettop();
    let mut depth: c_int = 1;
    l.pushvalue(root);
    l.rawseti(stack, 1);
    let mut bytes = 0.0;
    while depth > 0 {
        l.rawgeti(stack, depth);
        l.pushnil();
        l.rawseti(stack, depth);
        depth -= 1;
        let value = l.gettop();
        let kind = l.type_of(value);
        let counted = matches!(kind, TTABLE | TSTRING | TFUNCTION);
        if counted {
            l.pushvalue(value);
            l.rawget(seen);
            let already = l.type_of(-1) != TNIL;
            l.settop(value);
            if !already {
                l.pushvalue(value);
                l.pushboolean(1);
                l.rawset(seen);
                match kind {
                    TSTRING => bytes += STRING + l.objlen(value) as f64 + 1.0,
                    TFUNCTION => bytes += FUNCTION + UPVALUE * upvalues(l, value),
                    _ => {
                        let length = l.objlen(value) as f64;
                        let mut entries = 0.0;
                        l.pushnil();
                        while l.next(value) != 0 {
                            entries += 1.0;
                            depth += 1;
                            l.rawseti(stack, depth);
                            depth += 1;
                            l.pushvalue(-1);
                            l.rawseti(stack, depth);
                        }
                        bytes += TABLE + length * ARRAY_SLOT + hash_nodes(entries - length) * HASH_NODE;
                        if l.getmetatable(value) != 0 {
                            depth += 1;
                            l.rawseti(stack, depth);
                        }
                    }
                }
            }
        }
        l.settop(value - 1);
    }
    l.settop(stack - 1);
    bytes
}

/// analysis.memory.Measure(roots) -> { rows = { name, bytes }s, total }
unsafe extern "C-unwind" fn measure(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.settop(1);
    l.createtable(0, 0);
    let seen = l.gettop();
    l.createtable(0, 0);
    let rows = l.gettop();
    let mut total = 0.0;
    let mut i = 0;
    each_item(l, 1, |l, root| {
        l.rawgeti(root, 2);
        let value = l.gettop();
        let bytes = walk(l, value, seen);
        total += bytes;
        i += 1;
        l.createtable(0, 2);
        l.rawgeti(root, 1);
        l.setfield(-2, c"name");
        l.pushnumber(bytes);
        l.setfield(-2, c"bytes");
        l.rawseti(rows, i);
    });
    l.createtable(0, 2);
    l.pushvalue(rows);
    l.setfield(-2, c"rows");
    l.pushnumber(total);
    l.setfield(-2, c"total");
    1
}

unsafe fn push_lines(l: L, lines: &[String]) -> c_int {
    l.createtable(lines.len() as c_int, 0);
    for (i, line) in lines.iter().enumerate() {
        push_str(l, line);
        l.rawseti(-2, i as c_int + 1);
    }
    1
}

/// A number field of the table at `t`, or 0.
unsafe fn field(l: L, t: c_int, name: &CStr) -> f64 {
    crate::lua::field_number(l, t, name).unwrap_or(0.0)
}

/// A string (or number) field of the table at `t`, as text.
unsafe fn text_field(l: L, t: c_int, name: &CStr) -> String {
    l.getfield(t, name);
    let text = tostring(l, -1);
    l.settop(-2);
    text
}

/// analysis.memory.Format(report, rows) -> lines
unsafe extern "C-unwind" fn memory_format(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let limit = l.checknumber(2);
    l.getfield(1, c"rows");
    let rows_at = l.gettop();
    let mut rows = Vec::new();
    each_item(l, rows_at, |l, row| rows.push((text_field(l, row, c"name"), field(l, row, c"bytes"))));
    let total = field(l, 1, c"total");
    let mut lines = vec![format!("memory: {:.1} KB estimated over {} roots", total / 1024.0, rows.len())];
    rows.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.0.cmp(&b.0)));
    for (name, bytes) in rows.iter().take(limit.max(0.0) as usize) {
        lines.push(format!("{:10.1} KB  {name}", bytes / 1024.0));
    }
    drop(rows);
    let pushed = push_lines(l, &lines);
    drop(lines);
    pushed
}

// analysis.analytics --------------------------------------------------------

const WINDOW: usize = 128;
const PERCENTILE: f64 = 0.95;

#[derive(Default)]
struct Ring {
    values: Vec<f64>,
    next: usize,
}

impl Ring {
    fn push(&mut self, v: f64) {
        if self.values.len() < WINDOW {
            self.values.push(v);
        } else {
            self.values[self.next] = v;
        }
        self.next = (self.next + 1) % WINDOW;
    }

    fn ordered(&self) -> Vec<f64> {
        if self.values.len() < WINDOW {
            return self.values.clone();
        }
        let mut out = self.values[self.next..].to_vec();
        out.extend_from_slice(&self.values[..self.next]);
        out
    }
}

struct Timer {
    count: f64,
    total: f64,
    min: f64,
    max: f64,
    last: f64,
    samples: Ring,
}

#[derive(Default)]
pub struct Analytics {
    timers: HashMap<Vec<u8>, Timer>,
    counters: HashMap<Vec<u8>, f64>,
    depth: u32,
    frame_seconds: f64,
    frames: f64,
    over_budget: f64,
    pressure: Ring,
    pressure_peak: f64,
    memory_times: Ring,
    memory_kb: Ring,
    memory_min: f64,
    memory_peak: f64,
}

impl Analytics {
    fn fresh() -> Self {
        Analytics { memory_min: f64::INFINITY, ..Default::default() }
    }
}

impl Native for Analytics {
    const NAME: &'static CStr = c"foundation.analysis.analytics";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Reset", reset),
        (c"Start", start),
        (c"Stop", stop),
        (c"Time", time),
        (c"Count", count),
        (c"Frame", frame),
        (c"Report", report),
    ];
}

/// port:method() of the port kept in the analytics' environment.
unsafe fn ask(l: L, port: &CStr, method: &CStr) -> f64 {
    super::util::env_field(l, 1, port);
    l.getfield(-1, method);
    l.pushvalue(-2);
    l.call(1, 1);
    let n = l.tonumber(-1);
    l.settop(-3);
    n
}

unsafe extern "C-unwind" fn new(l: L) -> c_int {
    l.settop(2);
    userdata::push(l, Analytics::fresh());
    super::slots::fresh_environment(l, -1);
    l.getfenv(-1);
    l.pushvalue(1);
    l.setfield(-2, c"clock");
    l.pushvalue(2);
    l.setfield(-2, c"memory");
    l.settop(-2);
    1
}

unsafe extern "C-unwind" fn reset(l: L) -> c_int {
    *userdata::check::<Analytics>(l, 1) = Analytics::fresh();
    0
}

unsafe extern "C-unwind" fn start(l: L) -> c_int {
    userdata::check::<Analytics>(l, 1).depth += 1;
    number(l, ask(l, c"clock", c"Now"))
}

/// Records a span of the timer named at `name` started at `started`.
unsafe fn stop_span(l: L, name: c_int, started: f64) {
    let key = string_at(l, name).map(<[u8]>::to_vec).unwrap_or_else(|| tostring(l, name).into_bytes());
    if userdata::check::<Analytics>(l, 1).depth == 0 {
        let shown = String::from_utf8_lossy(&key).into_owned();
        drop(key);
        raise_where(l, format!("analytics: {shown} stopped with no span started"));
    }
    let seconds = ask(l, c"clock", c"Now") - started;
    let a = userdata::check::<Analytics>(l, 1);
    a.depth -= 1;
    if a.depth == 0 {
        a.frame_seconds += seconds;
    }
    let timer = a.timers.entry(key).or_insert_with(|| Timer {
        count: 0.0,
        total: 0.0,
        min: f64::INFINITY,
        max: 0.0,
        last: 0.0,
        samples: Ring::default(),
    });
    timer.count += 1.0;
    timer.total += seconds;
    timer.min = timer.min.min(seconds);
    timer.max = timer.max.max(seconds);
    timer.last = seconds;
    timer.samples.push(seconds);
}

unsafe extern "C-unwind" fn stop(l: L) -> c_int {
    let started = l.checknumber(3);
    stop_span(l, 2, started);
    0
}

/// a:Time(name, fn, ...) -> fn's results, the call timed under name
unsafe extern "C-unwind" fn time(l: L) -> c_int {
    let n = l.gettop();
    userdata::check::<Analytics>(l, 1).depth += 1;
    let started = ask(l, c"clock", c"Now");
    l.pushvalue(3);
    for i in 4..=n {
        l.pushvalue(i);
    }
    l.call((n - 3).max(0), -1);
    let results = l.gettop() - n;
    stop_span(l, 2, started);
    results
}

unsafe extern "C-unwind" fn count(l: L) -> c_int {
    let n = if l.type_of(3) == TNUMBER { l.tonumber(3) } else { 1.0 };
    let key = string_at(l, 2).map(<[u8]>::to_vec).unwrap_or_else(|| tostring(l, 2).into_bytes());
    *userdata::check::<Analytics>(l, 1).counters.entry(key).or_insert(0.0) += n;
    0
}

unsafe extern "C-unwind" fn frame(l: L) -> c_int {
    let budget = l.checknumber(2);
    let kb = ask(l, c"memory", c"Kilobytes");
    let now = ask(l, c"clock", c"Now");
    let a = userdata::check::<Analytics>(l, 1);
    let pressure = a.frame_seconds / budget;
    a.frame_seconds = 0.0;
    a.frames += 1.0;
    if pressure > 1.0 {
        a.over_budget += 1.0;
    }
    a.pressure_peak = a.pressure_peak.max(pressure);
    a.pressure.push(pressure);
    a.memory_times.push(now);
    a.memory_kb.push(kb);
    a.memory_min = a.memory_min.min(kb);
    a.memory_peak = a.memory_peak.max(kb);
    0
}

/// The nearest-rank percentile, as math.stats' Percentile.
fn percentile(mut values: Vec<f64>, p: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    values.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let rank = (p * values.len() as f64).ceil().max(1.0) as usize;
    values.get(rank - 1).copied().unwrap_or(0.0)
}

unsafe fn set(l: L, name: &CStr, value: f64) {
    l.pushnumber(value);
    l.setfield(-2, name);
}

unsafe extern "C-unwind" fn report(l: L) -> c_int {
    let a = userdata::check::<Analytics>(l, 1);
    l.createtable(0, 4);
    l.createtable(0, a.timers.len() as c_int);
    for (name, t) in &a.timers {
        l.pushlstring(name.as_ptr().cast(), name.len());
        l.createtable(0, 7);
        set(l, c"count", t.count);
        set(l, c"total", t.total);
        set(l, c"mean", t.total / t.count);
        set(l, c"min", t.min);
        set(l, c"max", t.max);
        set(l, c"last", t.last);
        set(l, c"p95", percentile(t.samples.ordered(), PERCENTILE));
        l.rawset(-3);
    }
    l.setfield(-2, c"timers");
    l.createtable(0, a.counters.len() as c_int);
    for (name, n) in &a.counters {
        l.pushlstring(name.as_ptr().cast(), name.len());
        l.pushnumber(*n);
        l.rawset(-3);
    }
    l.setfield(-2, c"counters");
    let pressures = a.pressure.ordered();
    l.createtable(0, 5);
    set(l, c"frames", a.frames);
    set(l, c"last", pressures.last().copied().unwrap_or(0.0));
    let mean = if pressures.is_empty() { 0.0 } else { pressures.iter().fold(0.0, |s, v| s + v) / pressures.len() as f64 };
    set(l, c"mean", mean);
    set(l, c"peak", a.pressure_peak);
    set(l, c"overBudget", a.over_budget);
    l.setfield(-2, c"pressure");
    let (times, kbs) = (a.memory_times.ordered(), a.memory_kb.ordered());
    l.createtable(0, 4);
    let mut growth = 0.0;
    if let (Some(&last), Some(&first)) = (kbs.last(), kbs.first()) {
        set(l, c"kb", last);
        set(l, c"min", a.memory_min);
        set(l, c"peak", a.memory_peak);
        let elapsed = times.last().copied().unwrap_or(0.0) - times.first().copied().unwrap_or(0.0);
        if elapsed > 0.0 {
            growth = (last - first) / elapsed;
        }
    }
    set(l, c"growthPerSecond", growth);
    l.setfield(-2, c"memory");
    1
}

/// The keys of the table at `t` with their table or number values, read
/// by `read` (pushed value at the top).
unsafe fn entries_of<T>(l: L, t: c_int, mut read: impl FnMut(L, c_int) -> T) -> Vec<(Vec<u8>, T)> {
    let mut out = Vec::new();
    if l.type_of(t) != TTABLE {
        return out;
    }
    l.pushnil();
    while l.next(t) != 0 {
        let key = string_at(l, -2).map(<[u8]>::to_vec).unwrap_or_else(|| tostring(l, -2).into_bytes());
        let value = l.gettop();
        out.push((key, read(l, value)));
        l.settop(-2);
    }
    out
}

/// Lua's %d: the number truncated toward zero, as string.format gives it.
fn whole(n: f64) -> i64 {
    n as i64
}

/// analytics.Format(report) -> console lines
unsafe extern "C-unwind" fn format_report(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.getfield(1, c"pressure");
    let p = l.gettop();
    l.getfield(1, c"memory");
    let m = l.gettop();
    let mut lines = vec![format!(
        "pressure: {} frames, last {:.1}%, mean {:.1}%, peak {:.1}%, {} over budget",
        whole(field(l, p, c"frames")),
        field(l, p, c"last") * 100.0,
        field(l, p, c"mean") * 100.0,
        field(l, p, c"peak") * 100.0,
        whole(field(l, p, c"overBudget"))
    )];
    if crate::lua::field_number(l, m, c"kb").is_some() {
        lines.push(format!(
            "memory: {:.0} kB (least {:.0}, most {:.0}), {:+.1} kB/s",
            field(l, m, c"kb"),
            field(l, m, c"min"),
            field(l, m, c"peak"),
            field(l, m, c"growthPerSecond")
        ));
    } else {
        lines.push("memory: no frame sampled yet".into());
    }
    l.getfield(1, c"timers");
    let timers_at = l.gettop();
    let mut timers = entries_of(l, timers_at, |l, t| {
        [field(l, t, c"count"), field(l, t, c"total"), field(l, t, c"mean"), field(l, t, c"p95"), field(l, t, c"max")]
    });
    timers.sort_by(|a, b| b.1[1].partial_cmp(&a.1[1]).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.0.cmp(&b.0)));
    for (name, t) in &timers {
        lines.push(format!(
            "  {}: {} calls, {:.3} ms total, mean {:.3}, p95 {:.3}, max {:.3} ms",
            String::from_utf8_lossy(name),
            whole(t[0]),
            t[1] * 1000.0,
            t[2] * 1000.0,
            t[3] * 1000.0,
            t[4] * 1000.0
        ));
    }
    drop(timers);
    l.getfield(1, c"counters");
    let counters_at = l.gettop();
    let mut counters = entries_of(l, counters_at, |l, v| l.tonumber(v));
    counters.sort_by(|a, b| a.0.cmp(&b.0));
    for (name, n) in &counters {
        lines.push(format!("  {}: {}", String::from_utf8_lossy(name), whole(*n)));
    }
    drop(counters);
    let pushed = push_lines(l, &lines);
    drop(lines);
    pushed
}

/// Pushes { name, count, share }s, largest first (ties by name), the top n.
unsafe fn push_rows(l: L, counts: &[(Vec<u8>, f64)], total: f64, n: usize) {
    let mut rows: Vec<&(Vec<u8>, f64)> = counts.iter().collect();
    rows.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.0.cmp(&b.0)));
    l.createtable(rows.len().min(n) as c_int, 0);
    for (i, (name, count)) in rows.iter().take(n).enumerate() {
        l.createtable(0, 3);
        l.pushlstring(name.as_ptr().cast(), name.len());
        l.setfield(-2, c"name");
        set(l, c"count", *count);
        set(l, c"share", if total > 0.0 { count / total } else { 0.0 });
        l.rawseti(-2, i as c_int + 1);
    }
}

/// analytics.SampleReport(sampled, n) -> the profiler's report, top n each
unsafe extern "C-unwind" fn sample_report(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let n = l.checknumber(2).max(0.0) as usize;
    let total = field(l, 1, c"samples");
    l.getfield(1, c"states");
    let states_at = l.gettop();
    let states = entries_of(l, states_at, |l, v| l.tonumber(v));
    l.getfield(1, c"stacks");
    let stacks_at = l.gettop();
    let stacks = entries_of(l, stacks_at, |l, v| l.tonumber(v));
    let mut leaves: HashMap<Vec<u8>, f64> = HashMap::new();
    let mut inclusive: HashMap<Vec<u8>, f64> = HashMap::new();
    for (stack, count) in &stacks {
        let mut seen = std::collections::HashSet::new();
        let mut leaf = None;
        for frame in stack.split(|&c| c == b';').filter(|f| !f.is_empty()) {
            if seen.insert(frame) {
                *inclusive.entry(frame.to_vec()).or_insert(0.0) += count;
            }
            leaf = Some(frame);
        }
        if let Some(leaf) = leaf {
            *leaves.entry(leaf.to_vec()).or_insert(0.0) += count;
        }
    }
    let leaves: Vec<_> = leaves.into_iter().collect();
    let inclusive: Vec<_> = inclusive.into_iter().collect();
    l.createtable(0, 5);
    set(l, c"samples", total);
    push_rows(l, &states, total, n);
    l.setfield(-2, c"states");
    push_rows(l, &leaves, total, n);
    l.setfield(-2, c"self");
    push_rows(l, &inclusive, total, n);
    l.setfield(-2, c"inclusive");
    push_rows(l, &stacks, total, n);
    l.setfield(-2, c"stacks");
    drop((states, stacks, leaves, inclusive));
    1
}

/// analytics.FormatSamples(report) -> console lines
unsafe extern "C-unwind" fn format_samples(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let mut lines = vec![format!("samples: {}", whole(field(l, 1, c"samples")))];
    for (title, key) in [
        ("-- VM state", c"states"),
        ("-- self (the function running)", c"self"),
        ("-- inclusive (on the stack)", c"inclusive"),
        ("-- stacks", c"stacks"),
    ] {
        lines.push(title.into());
        l.getfield(1, key);
        let rows = l.gettop();
        if l.type_of(rows) == TTABLE {
            each_item(l, rows, |l, row| {
                lines.push(format!(
                    "{:6.1}% {:7}  {}",
                    field(l, row, c"share") * 100.0,
                    whole(field(l, row, c"count")),
                    text_field(l, row, c"name")
                ));
            });
        }
        l.settop(rows - 1);
    }
    let pushed = push_lines(l, &lines);
    drop(lines);
    pushed
}

/// Pushes the memory module table.
unsafe fn push_memory_module(l: L) {
    module::push(l, &[(c"Measure", measure), (c"Format", memory_format)], None);
    for (name, value) in [
        (c"TABLE", TABLE),
        (c"ARRAY_SLOT", ARRAY_SLOT),
        (c"HASH_NODE", HASH_NODE),
        (c"STRING", STRING),
        (c"FUNCTION", FUNCTION),
        (c"UPVALUE", UPVALUE),
    ] {
        set(l, name, value);
    }
}

/// Pushes the analytics module table.
unsafe fn push_analytics_module(l: L) {
    module::push(
        l,
        &[
            (c"New", new),
            (c"Format", format_report),
            (c"SampleReport", sample_report),
            (c"FormatSamples", format_samples),
        ],
        None,
    );
    set(l, c"WINDOW", WINDOW as f64);
    set(l, c"PERCENTILE", PERCENTILE);
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[
    (c"memory", push_memory_module),
    (c"analytics", push_analytics_module),
];
