//! analysis.memory and analysis.analytics, native: the Lua twins'
//! contracts (foundation/analysis/). memory walks Lua's own objects through
//! the C API (with an explicit stack, so a long chain cannot overflow the C
//! stack); analytics keeps its timers, counters and rings in Rust, its clock
//! and memory the caller's ports.

use super::util::{each_item, number};
use crate::lua::{api, push_str, raise_where, string_at, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TNUMBER, TSTRING, TTABLE};
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
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"debug".as_ptr());
    (api.getfield)(l, -1, c"getinfo".as_ptr());
    (api.pushvalue)(l, f);
    push_str(l, "u");
    (api.call)(l, 2, 1);
    (api.getfield)(l, -1, c"nups".as_ptr());
    let n = (api.tonumber)(l, -1);
    (api.settop)(l, -4);
    n
}

/// The bytes of the value at `root` not yet counted (seen at `seen`),
/// marking what it counts. Work waits on a Lua table used as a stack.
unsafe fn walk(l: L, root: c_int, seen: c_int) -> f64 {
    let api = api();
    (api.createtable)(l, 0, 0);
    let stack = (api.gettop)(l);
    let mut depth: c_int = 1;
    (api.pushvalue)(l, root);
    (api.rawseti)(l, stack, 1);
    let mut bytes = 0.0;
    while depth > 0 {
        (api.rawgeti)(l, stack, depth);
        (api.pushnil)(l);
        (api.rawseti)(l, stack, depth);
        depth -= 1;
        let value = (api.gettop)(l);
        let kind = (api.type_of)(l, value);
        let counted = matches!(kind, TTABLE | TSTRING | TFUNCTION);
        if counted {
            (api.pushvalue)(l, value);
            (api.rawget)(l, seen);
            let already = (api.type_of)(l, -1) != TNIL;
            (api.settop)(l, value);
            if !already {
                (api.pushvalue)(l, value);
                (api.pushboolean)(l, 1);
                (api.rawset)(l, seen);
                match kind {
                    TSTRING => bytes += STRING + (api.objlen)(l, value) as f64 + 1.0,
                    TFUNCTION => bytes += FUNCTION + UPVALUE * upvalues(l, value),
                    _ => {
                        let length = (api.objlen)(l, value) as f64;
                        let mut entries = 0.0;
                        (api.pushnil)(l);
                        while (api.next)(l, value) != 0 {
                            entries += 1.0;
                            depth += 1;
                            (api.rawseti)(l, stack, depth);
                            depth += 1;
                            (api.pushvalue)(l, -1);
                            (api.rawseti)(l, stack, depth);
                        }
                        bytes += TABLE + length * ARRAY_SLOT + hash_nodes(entries - length) * HASH_NODE;
                        if (api.getmetatable)(l, value) != 0 {
                            depth += 1;
                            (api.rawseti)(l, stack, depth);
                        }
                    }
                }
            }
        }
        (api.settop)(l, value - 1);
    }
    (api.settop)(l, stack - 1);
    bytes
}

/// analysis.memory.Measure(roots) -> { rows = { name, bytes }s, total }
unsafe extern "C-unwind" fn measure(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.settop)(l, 1);
    (api.createtable)(l, 0, 0);
    let seen = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let rows = (api.gettop)(l);
    let mut total = 0.0;
    let mut i = 0;
    each_item(l, 1, |l, root| {
        (api.rawgeti)(l, root, 2);
        let value = (api.gettop)(l);
        let bytes = walk(l, value, seen);
        total += bytes;
        i += 1;
        (api.createtable)(l, 0, 2);
        (api.rawgeti)(l, root, 1);
        (api.setfield)(l, -2, c"name".as_ptr());
        (api.pushnumber)(l, bytes);
        (api.setfield)(l, -2, c"bytes".as_ptr());
        (api.rawseti)(l, rows, i);
    });
    (api.createtable)(l, 0, 2);
    (api.pushvalue)(l, rows);
    (api.setfield)(l, -2, c"rows".as_ptr());
    (api.pushnumber)(l, total);
    (api.setfield)(l, -2, c"total".as_ptr());
    1
}

unsafe fn push_lines(l: L, lines: &[String]) -> c_int {
    let api = api();
    (api.createtable)(l, lines.len() as c_int, 0);
    for (i, line) in lines.iter().enumerate() {
        push_str(l, line);
        (api.rawseti)(l, -2, i as c_int + 1);
    }
    1
}

/// A number field of the table at `t`, or 0.
unsafe fn field(l: L, t: c_int, name: &CStr) -> f64 {
    crate::lua::field_number(l, t, name).unwrap_or(0.0)
}

/// A string (or number) field of the table at `t`, as text.
unsafe fn text_field(l: L, t: c_int, name: &CStr) -> String {
    let api = api();
    (api.getfield)(l, t, name.as_ptr());
    let text = tostring(l, -1);
    (api.settop)(l, -2);
    text
}

/// analysis.memory.Format(report, rows) -> lines
unsafe extern "C-unwind" fn memory_format(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let limit = (api.checknumber)(l, 2);
    (api.getfield)(l, 1, c"rows".as_ptr());
    let rows_at = (api.gettop)(l);
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
    let api = api();
    super::util::env_field(l, 1, port);
    (api.getfield)(l, -1, method.as_ptr());
    (api.pushvalue)(l, -2);
    (api.call)(l, 1, 1);
    let n = (api.tonumber)(l, -1);
    (api.settop)(l, -3);
    n
}

unsafe extern "C-unwind" fn new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    userdata::push(l, Analytics::fresh());
    super::slots::fresh_environment(l, -1);
    (api.getfenv)(l, -1);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"clock".as_ptr());
    (api.pushvalue)(l, 2);
    (api.setfield)(l, -2, c"memory".as_ptr());
    (api.settop)(l, -2);
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
    let started = (api().checknumber)(l, 3);
    stop_span(l, 2, started);
    0
}

/// a:Time(name, fn, ...) -> fn's results, the call timed under name
unsafe extern "C-unwind" fn time(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l);
    userdata::check::<Analytics>(l, 1).depth += 1;
    let started = ask(l, c"clock", c"Now");
    (api.pushvalue)(l, 3);
    for i in 4..=n {
        (api.pushvalue)(l, i);
    }
    (api.call)(l, (n - 3).max(0), -1);
    let results = (api.gettop)(l) - n;
    stop_span(l, 2, started);
    results
}

unsafe extern "C-unwind" fn count(l: L) -> c_int {
    let api = api();
    let n = if (api.type_of)(l, 3) == TNUMBER { (api.tonumber)(l, 3) } else { 1.0 };
    let key = string_at(l, 2).map(<[u8]>::to_vec).unwrap_or_else(|| tostring(l, 2).into_bytes());
    *userdata::check::<Analytics>(l, 1).counters.entry(key).or_insert(0.0) += n;
    0
}

unsafe extern "C-unwind" fn frame(l: L) -> c_int {
    let budget = (api().checknumber)(l, 2);
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
    (api().pushnumber)(l, value);
    (api().setfield)(l, -2, name.as_ptr());
}

unsafe extern "C-unwind" fn report(l: L) -> c_int {
    let api = api();
    let a = userdata::check::<Analytics>(l, 1);
    (api.createtable)(l, 0, 4);
    (api.createtable)(l, 0, a.timers.len() as c_int);
    for (name, t) in &a.timers {
        (api.pushlstring)(l, name.as_ptr().cast(), name.len());
        (api.createtable)(l, 0, 7);
        set(l, c"count", t.count);
        set(l, c"total", t.total);
        set(l, c"mean", t.total / t.count);
        set(l, c"min", t.min);
        set(l, c"max", t.max);
        set(l, c"last", t.last);
        set(l, c"p95", percentile(t.samples.ordered(), PERCENTILE));
        (api.rawset)(l, -3);
    }
    (api.setfield)(l, -2, c"timers".as_ptr());
    (api.createtable)(l, 0, a.counters.len() as c_int);
    for (name, n) in &a.counters {
        (api.pushlstring)(l, name.as_ptr().cast(), name.len());
        (api.pushnumber)(l, *n);
        (api.rawset)(l, -3);
    }
    (api.setfield)(l, -2, c"counters".as_ptr());
    let pressures = a.pressure.ordered();
    (api.createtable)(l, 0, 5);
    set(l, c"frames", a.frames);
    set(l, c"last", pressures.last().copied().unwrap_or(0.0));
    let mean = if pressures.is_empty() { 0.0 } else { pressures.iter().fold(0.0, |s, v| s + v) / pressures.len() as f64 };
    set(l, c"mean", mean);
    set(l, c"peak", a.pressure_peak);
    set(l, c"overBudget", a.over_budget);
    (api.setfield)(l, -2, c"pressure".as_ptr());
    let (times, kbs) = (a.memory_times.ordered(), a.memory_kb.ordered());
    (api.createtable)(l, 0, 4);
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
    (api.setfield)(l, -2, c"memory".as_ptr());
    1
}

/// The keys of the table at `t` with their table or number values, read
/// by `read` (pushed value at the top).
unsafe fn entries_of<T>(l: L, t: c_int, mut read: impl FnMut(L, c_int) -> T) -> Vec<(Vec<u8>, T)> {
    let api = api();
    let mut out = Vec::new();
    if (api.type_of)(l, t) != TTABLE {
        return out;
    }
    (api.pushnil)(l);
    while (api.next)(l, t) != 0 {
        let key = string_at(l, -2).map(<[u8]>::to_vec).unwrap_or_else(|| tostring(l, -2).into_bytes());
        let value = (api.gettop)(l);
        out.push((key, read(l, value)));
        (api.settop)(l, -2);
    }
    out
}

/// Lua's %d: the number truncated toward zero, as string.format gives it.
fn whole(n: f64) -> i64 {
    n as i64
}

/// analytics.Format(report) -> console lines
unsafe extern "C-unwind" fn format_report(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.getfield)(l, 1, c"pressure".as_ptr());
    let p = (api.gettop)(l);
    (api.getfield)(l, 1, c"memory".as_ptr());
    let m = (api.gettop)(l);
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
    (api.getfield)(l, 1, c"timers".as_ptr());
    let timers_at = (api.gettop)(l);
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
    (api.getfield)(l, 1, c"counters".as_ptr());
    let counters_at = (api.gettop)(l);
    let mut counters = entries_of(l, counters_at, |l, v| (api.tonumber)(l, v));
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
    let api = api();
    let mut rows: Vec<&(Vec<u8>, f64)> = counts.iter().collect();
    rows.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal).then_with(|| a.0.cmp(&b.0)));
    (api.createtable)(l, rows.len().min(n) as c_int, 0);
    for (i, (name, count)) in rows.iter().take(n).enumerate() {
        (api.createtable)(l, 0, 3);
        (api.pushlstring)(l, name.as_ptr().cast(), name.len());
        (api.setfield)(l, -2, c"name".as_ptr());
        set(l, c"count", *count);
        set(l, c"share", if total > 0.0 { count / total } else { 0.0 });
        (api.rawseti)(l, -2, i as c_int + 1);
    }
}

/// analytics.SampleReport(sampled, n) -> the profiler's report, top n each
unsafe extern "C-unwind" fn sample_report(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let n = (api.checknumber)(l, 2).max(0.0) as usize;
    let total = field(l, 1, c"samples");
    (api.getfield)(l, 1, c"states".as_ptr());
    let states_at = (api.gettop)(l);
    let states = entries_of(l, states_at, |l, v| (api.tonumber)(l, v));
    (api.getfield)(l, 1, c"stacks".as_ptr());
    let stacks_at = (api.gettop)(l);
    let stacks = entries_of(l, stacks_at, |l, v| (api.tonumber)(l, v));
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
    (api.createtable)(l, 0, 5);
    set(l, c"samples", total);
    push_rows(l, &states, total, n);
    (api.setfield)(l, -2, c"states".as_ptr());
    push_rows(l, &leaves, total, n);
    (api.setfield)(l, -2, c"self".as_ptr());
    push_rows(l, &inclusive, total, n);
    (api.setfield)(l, -2, c"inclusive".as_ptr());
    push_rows(l, &stacks, total, n);
    (api.setfield)(l, -2, c"stacks".as_ptr());
    drop((states, stacks, leaves, inclusive));
    1
}

/// analytics.FormatSamples(report) -> console lines
unsafe extern "C-unwind" fn format_samples(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let mut lines = vec![format!("samples: {}", whole(field(l, 1, c"samples")))];
    for (title, key) in [
        ("-- VM state", c"states"),
        ("-- self (the function running)", c"self"),
        ("-- inclusive (on the stack)", c"inclusive"),
        ("-- stacks", c"stacks"),
    ] {
        lines.push(title.into());
        (api.getfield)(l, 1, key.as_ptr());
        let rows = (api.gettop)(l);
        if (api.type_of)(l, rows) == TTABLE {
            each_item(l, rows, |l, row| {
                lines.push(format!(
                    "{:6.1}% {:7}  {}",
                    field(l, row, c"share") * 100.0,
                    whole(field(l, row, c"count")),
                    text_field(l, row, c"name")
                ));
            });
        }
        (api.settop)(l, rows - 1);
    }
    let pushed = push_lines(l, &lines);
    drop(lines);
    pushed
}

/// Pushes the analysis namespace's native modules into the table at the top.
pub unsafe fn push_modules(l: L) {
    let api = api();
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
    (api.setfield)(l, -2, c"memory".as_ptr());
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
    (api.setfield)(l, -2, c"analytics".as_ptr());
}

pub const NAMES: &[&CStr] = &[c"memory", c"analytics"];
