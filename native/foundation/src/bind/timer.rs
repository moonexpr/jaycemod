//! timer.countdown and timer.interval, native: NextBot's CountdownTimer and
//! IntervalTimer, the Lua twins' contract (foundation/timer/). A timer is a Lua
//! table with the Lua twin's fields, so what reads a model's state as data reads
//! it the same; its methods are C functions asking its clock port for the time.

use super::state_chart::class;
use super::util::{boolean, number};
use crate::lua::{api, CFunction, GLOBALSINDEX, L, TTABLE};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;
const SHARED: &CStr = c"foundation.timer";

/// IntervalTimer::GetElapsedTime when unstarted.
const INTERVAL_UNSTARTED: f64 = 99999.9;
/// The timestamp an unstarted timer holds.
const UNSTARTED: f64 = -1.0;

/// clock:Now(), of the timer at index 1.
unsafe fn now(l: L) -> f64 {
    let api = api();
    (api.getfield)(l, 1, c"clock".as_ptr());
    (api.getfield)(l, -1, c"Now".as_ptr());
    (api.pushvalue)(l, -2);
    (api.call)(l, 1, 1);
    let time = (api.tonumber)(l, -1);
    (api.settop)(l, -3);
    time
}

unsafe fn field(l: L, name: &CStr) -> f64 {
    let api = api();
    (api.getfield)(l, 1, name.as_ptr());
    let value = (api.tonumber)(l, -1);
    (api.settop)(l, -2);
    value
}

unsafe fn set_field(l: L, name: &CStr, value: f64) {
    let api = api();
    (api.pushnumber)(l, value);
    (api.setfield)(l, 1, name.as_ptr());
}

fn class_upvalue() -> c_int {
    GLOBALSINDEX - 1
}

/// A new timer on the clock at index 1, of the class in upvalue 1.
unsafe fn new_timer(l: L, duration: bool) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.createtable)(l, 0, 3);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"clock".as_ptr());
    (api.pushnumber)(l, UNSTARTED);
    (api.setfield)(l, -2, c"timestamp".as_ptr());
    if duration {
        (api.pushnumber)(l, 0.0);
        (api.setfield)(l, -2, c"duration".as_ptr());
    }
    (api.pushvalue)(l, class_upvalue());
    (api.setmetatable)(l, -2);
    1
}

unsafe extern "C-unwind" fn invalidate(l: L) -> c_int {
    set_field(l, c"timestamp", UNSTARTED);
    0
}

unsafe extern "C-unwind" fn has_started(l: L) -> c_int {
    boolean(l, field(l, c"timestamp") > 0.0)
}

// Countdown -------------------------------------------------------------------------

unsafe extern "C-unwind" fn countdown_new(l: L) -> c_int {
    new_timer(l, true)
}

unsafe extern "C-unwind" fn countdown_reset(l: L) -> c_int {
    let time = now(l) + field(l, c"duration");
    set_field(l, c"timestamp", time);
    0
}

unsafe extern "C-unwind" fn countdown_start(l: L) -> c_int {
    let duration = (api().checknumber)(l, 2);
    let time = now(l) + duration;
    set_field(l, c"timestamp", time);
    set_field(l, c"duration", duration);
    0
}

unsafe extern "C-unwind" fn countdown_is_elapsed(l: L) -> c_int {
    boolean(l, now(l) > field(l, c"timestamp"))
}

unsafe extern "C-unwind" fn countdown_elapsed_time(l: L) -> c_int {
    number(l, now(l) - field(l, c"timestamp") + field(l, c"duration"))
}

unsafe extern "C-unwind" fn countdown_remaining_time(l: L) -> c_int {
    number(l, field(l, c"timestamp") - now(l))
}

unsafe extern "C-unwind" fn countdown_duration(l: L) -> c_int {
    if field(l, c"timestamp") > 0.0 {
        return number(l, field(l, c"duration"));
    }
    number(l, 0.0)
}

// Interval --------------------------------------------------------------------------

unsafe extern "C-unwind" fn interval_new(l: L) -> c_int {
    new_timer(l, false)
}

unsafe extern "C-unwind" fn interval_start(l: L) -> c_int {
    let time = now(l);
    set_field(l, c"timestamp", time);
    0
}

unsafe extern "C-unwind" fn interval_elapsed_time(l: L) -> c_int {
    let timestamp = field(l, c"timestamp");
    if timestamp > 0.0 {
        return number(l, now(l) - timestamp);
    }
    number(l, INTERVAL_UNSTARTED)
}

// The names keep util_shared.h's "Then".
unsafe extern "C-unwind" fn interval_is_less_then(l: L) -> c_int {
    let duration = (api().checknumber)(l, 2);
    boolean(l, now(l) - field(l, c"timestamp") < duration)
}

unsafe extern "C-unwind" fn interval_is_greater_then(l: L) -> c_int {
    let duration = (api().checknumber)(l, 2);
    boolean(l, now(l) - field(l, c"timestamp") > duration)
}

// The modules -----------------------------------------------------------------------

/// Pushes a module whose New is `new`, closed over a class of `methods`.
unsafe fn timer_module(l: L, new: CFunction, methods: &[(&CStr, CFunction)]) {
    let api = api();
    crate::module::push(l, &[], None);
    class(l, methods);
    (api.pushcclosure)(l, new, 1);
    (api.setfield)(l, -2, c"New".as_ptr());
}

/// Pushes the table of both modules, one set a Lua state, kept in the registry:
/// generator.state_chart hands on these very constructors.
unsafe fn push_shared(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, SHARED.as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.createtable)(l, 0, 2);
    timer_module(
        l,
        countdown_new,
        &[
            (c"Reset", countdown_reset),
            (c"Start", countdown_start),
            (c"Invalidate", invalidate),
            (c"HasStarted", has_started),
            (c"IsElapsed", countdown_is_elapsed),
            (c"GetElapsedTime", countdown_elapsed_time),
            (c"GetRemainingTime", countdown_remaining_time),
            (c"GetCountdownDuration", countdown_duration),
        ],
    );
    (api.setfield)(l, -2, c"countdown".as_ptr());
    timer_module(
        l,
        interval_new,
        &[
            (c"Reset", interval_start),
            (c"Start", interval_start),
            (c"Invalidate", invalidate),
            (c"HasStarted", has_started),
            (c"GetElapsedTime", interval_elapsed_time),
            (c"IsLessThen", interval_is_less_then),
            (c"IsGreaterThen", interval_is_greater_then),
        ],
    );
    (api.pushnumber)(l, INTERVAL_UNSTARTED);
    (api.setfield)(l, -2, c"INTERVAL_UNSTARTED".as_ptr());
    (api.setfield)(l, -2, c"interval".as_ptr());
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, SHARED.as_ptr());
}

/// Pushes the constructor of a timer module: `countdown` or `interval`.
pub(super) unsafe fn push_new(l: L, module: &CStr) {
    let api = api();
    push_shared(l);
    (api.getfield)(l, -1, module.as_ptr());
    (api.getfield)(l, -1, c"New".as_ptr());
    (api.replace)(l, -3);
    (api.settop)(l, -2);
}

/// Pushes interval's INTERVAL_UNSTARTED.
pub(super) unsafe fn push_interval_unstarted(l: L) {
    (api().pushnumber)(l, INTERVAL_UNSTARTED);
}

/// Pushes timer module `name` from the shared table, so both are made once
/// and state_chart's CountdownTimer and IntervalTimer are these.
unsafe fn push_shared_module(l: L, name: &CStr) {
    let api = api();
    push_shared(l);
    (api.getfield)(l, -1, name.as_ptr());
    (api.remove)(l, -2);
}

unsafe fn push_countdown_module(l: L) {
    push_shared_module(l, c"countdown");
}

unsafe fn push_interval_module(l: L) {
    push_shared_module(l, c"interval");
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[(c"countdown", push_countdown_module), (c"interval", push_interval_module)];
