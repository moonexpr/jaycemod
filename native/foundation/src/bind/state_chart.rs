//! generator.state_chart, native: the hierarchical statechart, the Lua
//! twin's contract (foundation/generator/state_chart.lua). State and Root
//! are class tables of C functions, extended with core.class as the Lua
//! twin's are (games' generator.hfsm extends both), so every step the engine
//! takes on a state or a root is a method call looked up on it: a subclass's
//! override runs in its place. States, roots, results, charts and machines
//! are Lua tables with the Lua twin's fields.

use super::util::boolean;
use crate::lua::{
    api, push_str, raise_owned, raise_where, set_function, string_at, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL,
    TNUMBER, TSTRING, TTABLE,
};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;
const SHARED: &CStr = c"foundation.generator.state_chart";

// ActionResultType, in NextBot's numbers (2 is a stack's SUSPEND_FOR).
const CONTINUE: f64 = 0.0;
const CHANGE_TO: f64 = 1.0;
const DONE: f64 = 3.0;
const SUSTAIN: f64 = 4.0;

// EventResultPriorityType
const RESULT_NONE: f64 = 0.0;
const RESULT_TRY: f64 = 1.0;
const RESULT_IMPORTANT: f64 = 2.0;
const RESULT_CRITICAL: f64 = 3.0;

// QueryResultType
const ANSWER_NO: f64 = 0.0;
const ANSWER_YES: f64 = 1.0;
const ANSWER_UNDEFINED: f64 = 2.0;

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

/// Pushes one of the values the module shares by identity (`continue`,
/// `no_event`, `ChartClass`, `MachineClass`).
unsafe fn shared(l: L, name: &CStr) {
    let api = api();
    (api.getfield)(l, REGISTRY, SHARED.as_ptr());
    (api.getfield)(l, -1, name.as_ptr());
    (api.replace)(l, -2);
}

/// Pushes core.<module>.<name>, read when called, as the Lua twin reads its
/// globals.
unsafe fn core_fn(l: L, module: &CStr, name: &CStr) {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"core".as_ptr());
    (api.getfield)(l, -1, module.as_ptr());
    (api.getfield)(l, -1, name.as_ptr());
    (api.replace)(l, -3);
    (api.settop)(l, -2);
}

/// Pushes obj.name and obj: a method call's function and receiver, ready
/// for its arguments.
unsafe fn prep(l: L, obj: c_int, name: &CStr) {
    let api = api();
    (api.getfield)(l, obj, name.as_ptr());
    (api.pushvalue)(l, obj);
}

unsafe fn push_range(l: L, from: c_int, to: c_int) {
    for i in from..=to {
        (api().pushvalue)(l, i);
    }
}

unsafe fn truthy(l: L, index: c_int) -> bool {
    (api().toboolean)(l, index) != 0
}

unsafe fn is_nil(l: L, index: c_int) -> bool {
    (api().type_of)(l, index) == TNIL
}

/// Whether the value at `index` is the number `n`.
unsafe fn is_number(l: L, index: c_int, n: f64) -> bool {
    let api = api();
    (api.type_of)(l, index) == TNUMBER && (api.tonumber)(l, index) == n
}

/// Whether obj.name is the number `n`.
unsafe fn field_is(l: L, obj: c_int, name: &CStr, n: f64) -> bool {
    let api = api();
    (api.getfield)(l, obj, name.as_ptr());
    let is = is_number(l, -1, n);
    (api.settop)(l, -2);
    is
}

unsafe fn field_truthy(l: L, obj: c_int, name: &CStr) -> bool {
    let api = api();
    (api.getfield)(l, obj, name.as_ptr());
    let is = truthy(l, -1);
    (api.settop)(l, -2);
    is
}

unsafe fn field_string(l: L, obj: c_int, name: &CStr) -> String {
    let api = api();
    (api.getfield)(l, obj, name.as_ptr());
    let text = tostring(l, -1);
    (api.settop)(l, -2);
    text
}

/// Leaves the bottom-most of a chain of `_child` links from the value at
/// `slot` in `slot`.
unsafe fn innermost(l: L, slot: c_int) {
    let api = api();
    loop {
        (api.getfield)(l, slot, c"_child".as_ptr());
        if !truthy(l, -1) {
            (api.settop)(l, -2);
            return;
        }
        (api.replace)(l, slot);
    }
}

/// Pushes { type, action, reason, priority }: `action` and `reason` stack
/// indices (0 for none), `priority` one too, 0 for RESULT_TRY.
unsafe fn push_result(l: L, kind: f64, action: c_int, reason: c_int, priority: c_int) {
    let api = api();
    (api.createtable)(l, 0, 4);
    (api.pushnumber)(l, kind);
    (api.setfield)(l, -2, c"type".as_ptr());
    if action != 0 {
        (api.pushvalue)(l, action);
        (api.setfield)(l, -2, c"action".as_ptr());
    }
    if reason != 0 {
        (api.pushvalue)(l, reason);
        (api.setfield)(l, -2, c"reason".as_ptr());
    }
    if priority != 0 {
        (api.pushvalue)(l, priority);
    } else {
        (api.pushnumber)(l, RESULT_TRY);
    }
    (api.setfield)(l, -2, c"priority".as_ptr());
}

/// `priority or RESULT_TRY`, for push_result.
unsafe fn or_try(l: L, index: c_int) -> c_int {
    if truthy(l, index) { index } else { 0 }
}

unsafe extern "C-unwind" fn result(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.createtable)(l, 0, 4);
    for (i, name) in [c"type", c"action", c"reason", c"priority"].iter().enumerate() {
        (api.pushvalue)(l, i as c_int + 1);
        (api.setfield)(l, -2, name.as_ptr());
    }
    1
}

// State -----------------------------------------------------------------------------

unsafe extern "C-unwind" fn state_extend(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    core_fn(l, c"class", c"Extend");
    (api.pushvalue)(l, 1);
    (api.createtable)(l, 0, 1);
    (api.pushvalue)(l, 2);
    (api.setfield)(l, -2, c"name".as_ptr());
    (api.call)(l, 2, 1);
    1
}

unsafe extern "C-unwind" fn state_new(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(1);
    (api.settop)(l, n);
    core_fn(l, c"class", c"New");
    (api.pushvalue)(l, 1);
    prep(l, 1, c"_Fields");
    (api.call)(l, 1, 1);
    (api.call)(l, 2, 1);
    let state = n + 1;
    prep(l, state, c"Init");
    push_range(l, 2, n);
    (api.call)(l, n, 0);
    (api.pushvalue)(l, state);
    1
}

unsafe extern "C-unwind" fn state_fields(l: L) -> c_int {
    let api = api();
    (api.createtable)(l, 0, 2);
    (api.pushboolean)(l, 0);
    (api.setfield)(l, -2, c"_started".as_ptr());
    shared(l, c"no_event");
    (api.setfield)(l, -2, c"_eventResult".as_ptr());
    1
}

unsafe extern "C-unwind" fn nothing(_l: L) -> c_int {
    0
}

unsafe extern "C-unwind" fn no_state(l: L) -> c_int {
    (api().pushnil)(l);
    1
}

unsafe extern "C-unwind" fn continue_result(l: L) -> c_int {
    shared(l, c"continue");
    1
}

unsafe extern "C-unwind" fn change_to(l: L) -> c_int {
    (api().settop)(l, 3);
    push_result(l, CHANGE_TO, 2, 3, 0);
    1
}

unsafe extern "C-unwind" fn done(l: L) -> c_int {
    (api().settop)(l, 2);
    push_result(l, DONE, 0, 2, 0);
    1
}

unsafe extern "C-unwind" fn try_continue(l: L) -> c_int {
    (api().settop)(l, 2);
    push_result(l, CONTINUE, 0, 0, or_try(l, 2));
    1
}

unsafe extern "C-unwind" fn try_change_to(l: L) -> c_int {
    (api().settop)(l, 4);
    push_result(l, CHANGE_TO, 2, 4, or_try(l, 3));
    1
}

unsafe extern "C-unwind" fn try_done(l: L) -> c_int {
    (api().settop)(l, 3);
    push_result(l, DONE, 0, 3, or_try(l, 2));
    1
}

unsafe extern "C-unwind" fn try_to_sustain(l: L) -> c_int {
    (api().settop)(l, 3);
    push_result(l, SUSTAIN, 0, 3, or_try(l, 2));
    1
}

/// A getter of the field named by upvalue 1.
unsafe extern "C-unwind" fn getter(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.pushvalue)(l, upvalue(1));
    (api.gettable)(l, 1);
    1
}

unsafe extern "C-unwind" fn full_name(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    let mut names: Vec<Vec<u8>> = Vec::new();
    (api.pushvalue)(l, 1);
    while truthy(l, 2) {
        (api.getfield)(l, 2, c"name".as_ptr());
        let Some(name) = string_at(l, -1).map(<[u8]>::to_vec) else {
            drop(names);
            raise_where(l, "invalid value in table for 'concat'".into())
        };
        names.push(name);
        (api.settop)(l, 2);
        (api.getfield)(l, 2, c"_parent".as_ptr());
        (api.replace)(l, 2);
    }
    names.reverse();
    let joined = names.join(&b'/');
    drop(names);
    (api.pushlstring)(l, joined.as_ptr().cast(), joined.len());
    1
}

unsafe extern "C-unwind" fn requests_change(l: L) -> c_int {
    (api().settop)(l, 2);
    let change = field_is(l, 2, c"type", CHANGE_TO) || field_is(l, 2, c"type", DONE);
    boolean(l, change)
}

unsafe extern "C-unwind" fn never(l: L) -> c_int {
    boolean(l, false)
}

unsafe extern "C-unwind" fn process_pending_events(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    prep(l, 1, c"_RequestsChange");
    (api.getfield)(l, 1, c"_eventResult".as_ptr());
    (api.call)(l, 2, 1);
    if truthy(l, 2) {
        (api.getfield)(l, 1, c"_eventResult".as_ptr());
        shared(l, c"no_event");
        (api.setfield)(l, 1, c"_eventResult".as_ptr());
        return 1;
    }
    shared(l, c"continue");
    1
}

unsafe extern "C-unwind" fn store_pending_event_result(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if field_is(l, 2, c"type", CONTINUE) {
        return 0;
    }
    (api.getfield)(l, 2, c"priority".as_ptr());
    (api.getfield)(l, 1, c"_eventResult".as_ptr());
    (api.getfield)(l, 4, c"priority".as_ptr());
    // result.priority >= stored: the latest wins a tie
    if (api.lessthan)(l, 5, 3) != 0 || (api.equal)(l, 5, 3) != 0 {
        (api.pushvalue)(l, 2);
        (api.setfield)(l, 1, c"_eventResult".as_ptr());
    }
    0
}

/// _InvokeOnStart(me, root, priorState): the child starts before my own
/// OnStart.
unsafe extern "C-unwind" fn invoke_on_start(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.pushboolean)(l, 1);
    (api.setfield)(l, 1, c"_started".as_ptr());
    (api.pushvalue)(l, 2);
    (api.setfield)(l, 1, c"_actor".as_ptr());
    if truthy(l, 4) {
        (api.getfield)(l, 4, c"_parent".as_ptr());
        (api.setfield)(l, 1, c"_parent".as_ptr());
    }
    (api.getfield)(l, 1, c"_parent".as_ptr());
    if truthy(l, 5) {
        (api.pushvalue)(l, 1);
        (api.setfield)(l, 5, c"_child".as_ptr());
    }
    (api.settop)(l, 4);
    prep(l, 1, c"InitialContainedAction");
    (api.pushvalue)(l, 2);
    (api.call)(l, 2, 1);
    let child = 5;
    (api.pushvalue)(l, child);
    (api.setfield)(l, 1, c"_child".as_ptr());
    if truthy(l, child) {
        (api.pushvalue)(l, 1);
        (api.setfield)(l, child, c"_parent".as_ptr());
        prep(l, child, c"_ApplyResult");
        (api.pushvalue)(l, 2);
        (api.pushvalue)(l, 3);
        prep(l, 1, c"ChangeTo");
        (api.pushvalue)(l, child);
        push_str(l, "Starting child Action");
        (api.call)(l, 3, 1);
        (api.call)(l, 4, 1);
        (api.setfield)(l, 1, c"_child".as_ptr());
    }
    prep(l, 1, c"OnStart");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 4);
    (api.call)(l, 3, 1);
    1
}

/// _InvokeUpdate(me, root, interval): scope, pending events, the child, then
/// myself.
unsafe extern "C-unwind" fn invoke_update(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    prep(l, 1, c"_IsOutOfScope");
    (api.call)(l, 1, 1);
    if truthy(l, 5) {
        prep(l, 1, c"Done");
        push_str(l, "Out of scope");
        (api.call)(l, 2, 1);
        return 1;
    }
    (api.settop)(l, 4);
    if !field_truthy(l, 1, c"_started") {
        prep(l, 1, c"ChangeTo");
        (api.pushvalue)(l, 1);
        push_str(l, "Starting Action");
        (api.call)(l, 3, 1);
        return 1;
    }
    prep(l, 1, c"_ProcessPendingEvents");
    (api.call)(l, 1, 1);
    if !field_is(l, 5, c"type", CONTINUE) {
        return 1;
    }
    (api.settop)(l, 4);
    (api.getfield)(l, 1, c"_child".as_ptr());
    if truthy(l, 5) {
        prep(l, 5, c"_ApplyResult");
        (api.pushvalue)(l, 2);
        (api.pushvalue)(l, 3);
        prep(l, 5, c"_InvokeUpdate");
        push_range(l, 2, 4);
        (api.call)(l, 4, 1);
        (api.call)(l, 4, 1);
        (api.setfield)(l, 1, c"_child".as_ptr());
    }
    (api.settop)(l, 4);
    prep(l, 1, c"Update");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 4);
    (api.call)(l, 3, 1);
    1
}

/// _InvokeOnEnd(me, root, nextState): my child, then me.
unsafe extern "C-unwind" fn invoke_on_end(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    if !field_truthy(l, 1, c"_started") {
        return 0;
    }
    (api.pushboolean)(l, 0);
    (api.setfield)(l, 1, c"_started".as_ptr());
    (api.getfield)(l, 1, c"_child".as_ptr());
    if truthy(l, 5) {
        prep(l, 5, c"_InvokeOnEnd");
        push_range(l, 2, 4);
        (api.call)(l, 4, 0);
    }
    (api.settop)(l, 4);
    prep(l, 1, c"OnEnd");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 4);
    (api.call)(l, 3, 0);
    0
}

/// transitions[CHANGE_TO](self, me, root, result): the new state takes my
/// parent.
unsafe extern "C-unwind" fn transition_change_to(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.getfield)(l, 4, c"action".as_ptr());
    let next = 5;
    if is_nil(l, next) {
        let name = field_string(l, 1, c"name");
        let reason = if field_truthy(l, 4, c"reason") { field_string(l, 4, c"reason") } else { "no reason".into() };
        raise_owned(l, format!("{name}: ChangeTo needs a state ({reason})"));
    }
    prep(l, 1, c"_InvokeOnEnd");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, next);
    (api.call)(l, 4, 0);
    prep(l, next, c"_InvokeOnStart");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, 1);
    (api.call)(l, 4, 1);
    let started = 6;
    if (api.equal)(l, 1, next) == 0 {
        prep(l, 3, c"_DestroyAction");
        (api.pushvalue)(l, 1);
        (api.call)(l, 2, 0);
    }
    prep(l, next, c"_ApplyResult");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, started);
    (api.call)(l, 4, 1);
    1
}

/// transitions[DONE]: nothing takes my place.
unsafe extern "C-unwind" fn transition_done(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    prep(l, 1, c"_InvokeOnEnd");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushnil)(l);
    (api.call)(l, 4, 0);
    prep(l, 3, c"_DestroyAction");
    (api.pushvalue)(l, 1);
    (api.call)(l, 2, 0);
    (api.pushnil)(l);
    1
}

/// _ApplyResult(me, root, result): the state now active in my place; a
/// root's watcher hears of each change first.
unsafe extern "C-unwind" fn apply_result(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.getfield)(l, 1, c"transitions".as_ptr());
    (api.getfield)(l, 4, c"type".as_ptr());
    (api.gettable)(l, 5);
    let apply = 6;
    if is_nil(l, apply) {
        (api.pushvalue)(l, 1);
        return 1;
    }
    (api.getfield)(l, 3, c"watcher".as_ptr());
    if truthy(l, 7) {
        (api.getfield)(l, 4, c"action".as_ptr());
        let next = 8;
        prep(l, 7, c"Transition");
        (api.getfield)(l, 4, c"type".as_ptr());
        (api.getfield)(l, 1, c"name".as_ptr());
        if truthy(l, next) {
            (api.getfield)(l, next, c"name".as_ptr());
        } else {
            (api.pushvalue)(l, next);
        }
        (api.getfield)(l, 4, c"reason".as_ptr());
        (api.pushboolean)(l, (api.equal)(l, next, 1));
        (api.call)(l, 6, 0);
    }
    (api.pushvalue)(l, apply);
    push_range(l, 1, 4);
    (api.call)(l, 4, 1);
    1
}

/// _HandleEvent(name, ...): an event's handler on me, its result stored as
/// my pending change.
unsafe extern "C-unwind" fn handle_event(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(2);
    (api.settop)(l, n);
    (api.pushvalue)(l, 2);
    (api.gettable)(l, 1);
    let handler = n + 1;
    if truthy(l, handler) {
        prep(l, 1, c"_StorePendingEventResult");
        (api.pushvalue)(l, handler);
        (api.pushvalue)(l, 1);
        (api.getfield)(l, 1, c"_actor".as_ptr());
        push_range(l, 3, n);
        (api.call)(l, n, 1);
        (api.call)(l, 2, 0);
    }
    0
}

/// _ProcessEvent(name, ...): an unstarted state ignores events; I handle
/// it, then my active child.
unsafe extern "C-unwind" fn process_event(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(2);
    (api.settop)(l, n);
    if !field_truthy(l, 1, c"_started") {
        return 0;
    }
    prep(l, 1, c"_HandleEvent");
    push_range(l, 2, n);
    (api.call)(l, n, 0);
    (api.getfield)(l, 1, c"_child".as_ptr());
    if truthy(l, n + 1) {
        prep(l, n + 1, c"_ProcessEvent");
        push_range(l, 2, n);
        (api.call)(l, n, 0);
    }
    0
}

/// _AskHere(me, name, ...): my answer to a query, or nil.
unsafe extern "C-unwind" fn ask_here(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(3);
    (api.settop)(l, n);
    (api.pushvalue)(l, 3);
    (api.gettable)(l, 1);
    if truthy(l, n + 1) {
        (api.pushvalue)(l, 1);
        (api.pushvalue)(l, 2);
        push_range(l, 4, n);
        (api.call)(l, n - 1, 1);
        if !is_nil(l, n + 1) && !is_number(l, n + 1, ANSWER_UNDEFINED) {
            return 1;
        }
    }
    (api.pushnil)(l);
    1
}

/// Pushes the first answer from the innermost state under the one at
/// `state` out to the one at `stop` (exclusive; 0: none), asking
/// _AskHere(me, name, args from..=to).
unsafe fn ask_outward(l: L, state: c_int, stop: c_int, me: c_int, name: c_int, from: c_int, to: c_int) {
    let api = api();
    (api.pushvalue)(l, state);
    let at = (api.gettop)(l);
    innermost(l, at);
    while truthy(l, at) && (stop == 0 || (api.equal)(l, at, stop) == 0) {
        prep(l, at, c"_AskHere");
        (api.pushvalue)(l, me);
        (api.pushvalue)(l, name);
        push_range(l, from, to);
        (api.call)(l, 3 + (to - from + 1).max(0), 1);
        if !is_nil(l, -1) {
            (api.replace)(l, at);
            return;
        }
        (api.settop)(l, at);
        (api.getfield)(l, at, c"_parent".as_ptr());
        (api.replace)(l, at);
    }
    (api.settop)(l, at - 1);
    (api.pushnumber)(l, ANSWER_UNDEFINED);
}

/// QueryBelow(me, name, ...): the query asked only of the states I contain.
unsafe extern "C-unwind" fn query_below(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(3);
    (api.settop)(l, n);
    (api.getfield)(l, 1, c"_child".as_ptr());
    if is_nil(l, n + 1) {
        (api.pushnumber)(l, ANSWER_UNDEFINED);
        return 1;
    }
    ask_outward(l, n + 1, 1, 2, 3, 4, n);
    1
}

// Root ------------------------------------------------------------------------------

unsafe extern "C-unwind" fn root_new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    core_fn(l, c"class", c"New");
    (api.pushvalue)(l, 1);
    (api.createtable)(l, 0, 5);
    (api.pushvalue)(l, 2);
    (api.setfield)(l, -2, c"action".as_ptr());
    (api.pushvalue)(l, 3);
    (api.setfield)(l, -2, c"name".as_ptr());
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, c"dead".as_ptr());
    (api.call)(l, 2, 1);
    1
}

unsafe extern "C-unwind" fn root_watch(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.setfield)(l, 1, c"watcher".as_ptr());
    0
}

unsafe fn append(l: L, list: c_int) {
    let api = api();
    let n = (api.objlen)(l, list);
    (api.rawseti)(l, list, n as c_int + 1);
}

/// Appends { name, depth } for the state at `state` and its active children
/// to the list at `frames`.
unsafe fn stack_frames(l: L, state: c_int, depth: f64, frames: c_int) {
    let api = api();
    (api.createtable)(l, 0, 2);
    (api.getfield)(l, state, c"name".as_ptr());
    (api.setfield)(l, -2, c"name".as_ptr());
    (api.pushnumber)(l, depth);
    (api.setfield)(l, -2, c"depth".as_ptr());
    append(l, frames);
    (api.getfield)(l, state, c"_child".as_ptr());
    let child = (api.gettop)(l);
    if truthy(l, child) {
        stack_frames(l, child, depth + 1.0, frames);
    }
    (api.settop)(l, child - 1);
}

unsafe extern "C-unwind" fn root_stack(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"action".as_ptr());
    (api.createtable)(l, 0, 0);
    if !is_nil(l, 2) {
        stack_frames(l, 2, 1.0, 3);
    }
    1
}

unsafe extern "C-unwind" fn root_is_empty(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"action".as_ptr());
    boolean(l, is_nil(l, 2))
}

unsafe extern "C-unwind" fn root_update(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    (api.getfield)(l, 1, c"action".as_ptr());
    if is_nil(l, 4) {
        return 0;
    }
    (api.pushvalue)(l, 2);
    (api.setfield)(l, 1, c"me".as_ptr());
    prep(l, 4, c"_ApplyResult");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 1);
    prep(l, 4, c"_InvokeUpdate");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 1);
    (api.pushvalue)(l, 3);
    (api.call)(l, 4, 1);
    (api.call)(l, 4, 1);
    (api.setfield)(l, 1, c"action".as_ptr());
    prep(l, 1, c"_PurgeDeadActions");
    (api.call)(l, 1, 0);
    0
}

unsafe extern "C-unwind" fn root_event(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(3);
    (api.settop)(l, n);
    (api.getfield)(l, 1, c"action".as_ptr());
    if is_nil(l, n + 1) {
        return 0;
    }
    (api.getfield)(l, 1, c"watcher".as_ptr());
    if truthy(l, n + 2) {
        prep(l, n + 2, c"Event");
        (api.pushvalue)(l, 3);
        (api.call)(l, 2, 0);
    }
    (api.getfield)(l, 1, c"action".as_ptr());
    let action = (api.gettop)(l);
    prep(l, action, c"_ProcessEvent");
    push_range(l, 3, n);
    (api.call)(l, n - 1, 0);
    0
}

unsafe extern "C-unwind" fn root_query(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(3);
    (api.settop)(l, n);
    (api.getfield)(l, 1, c"action".as_ptr());
    if is_nil(l, n + 1) {
        (api.pushnumber)(l, ANSWER_UNDEFINED);
        return 1;
    }
    ask_outward(l, n + 1, 0, 2, 3, 4, n);
    1
}

unsafe extern "C-unwind" fn root_destroy(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    if field_truthy(l, 1, c"me") && field_truthy(l, 1, c"action") {
        (api.getfield)(l, 1, c"action".as_ptr());
        prep(l, 2, c"_InvokeOnEnd");
        (api.getfield)(l, 1, c"me".as_ptr());
        (api.pushvalue)(l, 1);
        (api.pushnil)(l);
        (api.call)(l, 4, 0);
        (api.settop)(l, 1);
    }
    (api.pushnil)(l);
    (api.setfield)(l, 1, c"action".as_ptr());
    0
}

unsafe extern "C-unwind" fn root_describe(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"action".as_ptr());
    if is_nil(l, 2) {
        push_str(l, "");
        return 1;
    }
    innermost(l, 2);
    prep(l, 2, c"GetFullName");
    (api.call)(l, 1, 1);
    1
}

unsafe extern "C-unwind" fn root_destroy_action(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.getfield)(l, 1, c"dead".as_ptr());
    (api.pushvalue)(l, 2);
    append(l, 3);
    0
}

unsafe extern "C-unwind" fn root_purge_dead_actions(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"dead".as_ptr());
    let mut i = 1;
    loop {
        (api.rawgeti)(l, 2, i);
        if is_nil(l, 3) {
            break;
        }
        (api.getfield)(l, 3, c"_parent".as_ptr());
        if truthy(l, 4) {
            (api.getfield)(l, 4, c"_child".as_ptr());
            if (api.equal)(l, 5, 3) != 0 {
                (api.pushnil)(l);
                (api.setfield)(l, 4, c"_child".as_ptr());
            }
        }
        (api.settop)(l, 2);
        i += 1;
    }
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, 1, c"dead".as_ptr());
    0
}

// Names a chart declares ------------------------------------------------------------

/// The string at `index`, or a refusal blamed on the caller: `what` needs a
/// name.
unsafe fn name_at(l: L, index: c_int, what: &str) -> String {
    let api = api();
    let name = if (api.type_of)(l, index) == TSTRING { tostring(l, index) } else { String::new() };
    if name.is_empty() {
        raise_where(l, format!("{what} needs a name"));
    }
    name
}

/// Checks that the value at `index` is a list of names.
unsafe fn name_list(l: L, index: c_int, what: &str) {
    let api = api();
    if (api.type_of)(l, index) != TTABLE {
        raise_where(l, format!("{what} must be a list of names"));
    }
    let mut i = 1;
    loop {
        (api.rawgeti)(l, index, i);
        let kind = (api.type_of)(l, -1);
        if kind == TNIL {
            (api.settop)(l, -2);
            return;
        }
        if kind != TSTRING {
            let given = tostring(l, -1);
            raise_where(l, format!("{what} has a non-name: {given}"));
        }
        (api.settop)(l, -2);
        i += 1;
    }
}

/// Pushes { name = true } for the list at `index`.
unsafe fn name_set(l: L, index: c_int) {
    let api = api();
    if (api.type_of)(l, index) != TTABLE {
        let got = tostring(l, index);
        raise_where(l, format!("bad argument #1 to 'ipairs' (table expected, got {got})"));
    }
    (api.createtable)(l, 0, 4);
    let set = (api.gettop)(l);
    let mut i = 1;
    loop {
        (api.rawgeti)(l, index, i);
        if is_nil(l, -1) {
            (api.settop)(l, set);
            return;
        }
        (api.pushboolean)(l, 1);
        (api.rawset)(l, set);
        i += 1;
    }
}

/// Whether a name is an event's: On and a capital.
fn event_name(name: &[u8]) -> bool {
    name.len() >= 3 && name.starts_with(b"On") && name[2].is_ascii_uppercase()
}

/// A chart's guard on its state classes (upvalue 1 the chart): an On* name
/// must be a lifecycle hook or one of the chart's events.
unsafe extern "C-unwind" fn state_guard(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    if (api.type_of)(l, 1) != TSTRING || !string_at(l, 1).is_some_and(event_name) {
        return 0;
    }
    for set in [c"lifecycle", c"events"] {
        (api.getfield)(l, upvalue(1), set.as_ptr());
        (api.pushvalue)(l, 1);
        (api.gettable)(l, -2);
        let declared = truthy(l, -1);
        (api.settop)(l, 1);
        if declared {
            return 0;
        }
    }
    let chart = field_string(l, upvalue(1), c"name");
    let key = tostring(l, 1);
    push_str(l, &format!("{chart}: {key} is not a lifecycle hook or an event of the chart"));
    1
}

/// A list field of the spec at 1 (`spec[key] or {}`), pushed and checked.
unsafe fn spec_names(l: L, key: &CStr, what: &str) -> c_int {
    let api = api();
    (api.getfield)(l, 1, key.as_ptr());
    if !truthy(l, -1) {
        (api.settop)(l, -2);
        (api.createtable)(l, 0, 0);
    }
    let list = (api.gettop)(l);
    name_list(l, list, what);
    list
}

/// The Chart function of an engine (upvalue 1 the engine, 2 its lifecycle
/// set): Chart{ name, port, events?, queries?, initial }.
unsafe extern "C-unwind" fn make_chart(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"name".as_ptr());
    let name = name_at(l, 2, "a chart");
    (api.settop)(l, 1);
    core_fn(l, c"port", c"Is");
    (api.getfield)(l, 1, c"port".as_ptr());
    (api.call)(l, 1, 1);
    if !truthy(l, 2) {
        raise_where(l, format!("chart {name} needs a Port"));
    }
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"initial".as_ptr());
    if (api.type_of)(l, 2) != TFUNCTION {
        raise_where(l, format!("chart {name} needs initial(states)"));
    }
    (api.settop)(l, 1);
    let events = spec_names(l, c"events", &format!("chart {name}'s events"));
    let mut i = 1;
    loop {
        (api.rawgeti)(l, events, i);
        if is_nil(l, -1) {
            (api.settop)(l, -2);
            break;
        }
        if !string_at(l, -1).is_some_and(event_name) {
            let event = tostring(l, -1);
            raise_where(l, format!("chart {name}: event {event} must start On"));
        }
        (api.settop)(l, -2);
        i += 1;
    }
    let queries = spec_names(l, c"queries", &format!("chart {name}'s queries"));
    (api.createtable)(l, 0, 8);
    let chart = (api.gettop)(l);
    (api.getfield)(l, 1, c"name".as_ptr());
    (api.setfield)(l, chart, c"name".as_ptr());
    (api.getfield)(l, 1, c"port".as_ptr());
    (api.setfield)(l, chart, c"port".as_ptr());
    name_set(l, events);
    (api.setfield)(l, chart, c"events".as_ptr());
    name_set(l, queries);
    (api.setfield)(l, chart, c"queries".as_ptr());
    (api.getfield)(l, 1, c"initial".as_ptr());
    (api.setfield)(l, chart, c"initial".as_ptr());
    (api.pushvalue)(l, upvalue(2));
    (api.setfield)(l, chart, c"lifecycle".as_ptr());
    (api.getfield)(l, upvalue(1), c"root".as_ptr());
    (api.setfield)(l, chart, c"root".as_ptr());
    shared(l, c"ChartClass");
    (api.setmetatable)(l, chart);
    core_fn(l, c"class", c"Guard");
    (api.getfield)(l, upvalue(1), c"state".as_ptr());
    let state = (api.gettop)(l);
    prep(l, state, c"Extend");
    (api.getfield)(l, 1, c"name".as_ptr());
    (api.call)(l, 2, 1);
    (api.replace)(l, state);
    (api.pushvalue)(l, chart);
    (api.pushcclosure)(l, state_guard, 1);
    (api.call)(l, 2, 1);
    (api.setfield)(l, chart, c"base".as_ptr());
    (api.pushvalue)(l, chart);
    1
}

/// ChartsOf{ state, root, lifecycle } -> the Chart function of an engine.
unsafe extern "C-unwind" fn charts_of(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"lifecycle".as_ptr());
    name_set(l, 2);
    (api.pushvalue)(l, 1);
    (api.pushvalue)(l, 3);
    (api.pushcclosure)(l, make_chart, 2);
    1
}

// Chart and Machine -----------------------------------------------------------------

unsafe extern "C-unwind" fn chart_state(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    name_at(l, 2, "a state");
    (api.getfield)(l, 1, c"base".as_ptr());
    prep(l, 3, c"Extend");
    (api.pushvalue)(l, 2);
    (api.call)(l, 2, 1);
    1
}

unsafe extern "C-unwind" fn chart_owns(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    core_fn(l, c"class", c"IsA");
    (api.pushvalue)(l, 2);
    (api.getfield)(l, 1, c"base".as_ptr());
    (api.call)(l, 2, 1);
    1
}

unsafe extern "C-unwind" fn chart_new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    (api.getfield)(l, 1, c"port".as_ptr());
    prep(l, 4, c"Facade");
    prep(l, 4, c"Check");
    (api.pushvalue)(l, 2);
    (api.call)(l, 2, 1);
    (api.call)(l, 2, 1);
    let me = 5;
    (api.getfield)(l, 1, c"initial".as_ptr());
    (api.pushvalue)(l, 3);
    (api.call)(l, 1, 1);
    let first = 6;
    prep(l, 1, c"Owns");
    (api.pushvalue)(l, first);
    (api.call)(l, 2, 1);
    if !truthy(l, 7) {
        let name = field_string(l, 1, c"name");
        raise_where(l, format!("chart {name}: initial gave a state of another chart"));
    }
    (api.settop)(l, first);
    (api.createtable)(l, 0, 3);
    let machine = 7;
    (api.pushvalue)(l, 1);
    (api.setfield)(l, machine, c"chart".as_ptr());
    (api.pushvalue)(l, me);
    (api.setfield)(l, machine, c"me".as_ptr());
    (api.getfield)(l, 1, c"root".as_ptr());
    prep(l, 8, c"New");
    (api.pushvalue)(l, first);
    (api.getfield)(l, 1, c"name".as_ptr());
    (api.call)(l, 3, 1);
    (api.setfield)(l, machine, c"root".as_ptr());
    (api.settop)(l, machine);
    shared(l, c"MachineClass");
    (api.setmetatable)(l, machine);
    1
}

/// Calls self.root:<method>(self.me?, args 2..=n), pushing `results`.
unsafe fn on_root(l: L, method: &CStr, with_me: bool, n: c_int, results: c_int) -> c_int {
    let api = api();
    (api.getfield)(l, 1, c"root".as_ptr());
    let root = (api.gettop)(l);
    prep(l, root, method);
    if with_me {
        (api.getfield)(l, 1, c"me".as_ptr());
    }
    push_range(l, 2, n);
    (api.call)(l, 1 + with_me as c_int + (n - 1).max(0), results);
    results
}

/// Refuses a name the machine's chart does not declare in `set`.
unsafe fn declared(l: L, set: &CStr, what: &str) {
    let api = api();
    let top = (api.gettop)(l);
    (api.getfield)(l, 1, c"chart".as_ptr());
    (api.getfield)(l, -1, set.as_ptr());
    (api.pushvalue)(l, 2);
    (api.gettable)(l, -2);
    if !truthy(l, -1) {
        let chart = field_string(l, top + 1, c"name");
        let name = tostring(l, 2);
        raise_where(l, format!("chart {chart} has no {what} {name}"));
    }
    (api.settop)(l, top);
}

unsafe extern "C-unwind" fn machine_update(l: L) -> c_int {
    (api().settop)(l, 2);
    on_root(l, c"Update", true, 2, 0)
}

unsafe extern "C-unwind" fn machine_event(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(2);
    (api.settop)(l, n);
    declared(l, c"events", "event");
    on_root(l, c"Event", true, n, 0)
}

unsafe extern "C-unwind" fn machine_query(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(2);
    (api.settop)(l, n);
    declared(l, c"queries", "query");
    on_root(l, c"Query", true, n, 1)
}

unsafe extern "C-unwind" fn machine_describe(l: L) -> c_int {
    (api().settop)(l, 1);
    on_root(l, c"Describe", false, 1, 1)
}

unsafe extern "C-unwind" fn machine_is_empty(l: L) -> c_int {
    (api().settop)(l, 1);
    on_root(l, c"IsEmpty", false, 1, 1)
}

unsafe extern "C-unwind" fn machine_stack(l: L) -> c_int {
    (api().settop)(l, 1);
    on_root(l, c"Stack", false, 1, 1)
}

unsafe extern "C-unwind" fn machine_watch(l: L) -> c_int {
    (api().settop)(l, 2);
    on_root(l, c"Watch", false, 2, 0)
}

unsafe extern "C-unwind" fn machine_destroy(l: L) -> c_int {
    (api().settop)(l, 1);
    on_root(l, c"Destroy", false, 1, 0)
}

// The module ------------------------------------------------------------------------

/// Pushes a class table, its own __index, holding `methods`.
unsafe fn class(l: L, methods: &[(&CStr, CFunction)]) {
    let api = api();
    (api.createtable)(l, 0, methods.len() as c_int + 2);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, -2, c"__index".as_ptr());
    for (name, f) in methods {
        set_function(l, name, *f);
    }
}

unsafe fn set_getter(l: L, method: &CStr, field: &str) {
    let api = api();
    push_str(l, field);
    (api.pushcclosure)(l, getter, 1);
    (api.setfield)(l, -2, method.as_ptr());
}

unsafe fn push_state(l: L) {
    let api = api();
    class(
        l,
        &[
            (c"Extend", state_extend),
            (c"New", state_new),
            (c"_Fields", state_fields),
            (c"Init", nothing),
            (c"InitialContainedAction", no_state),
            (c"OnStart", continue_result),
            (c"Update", continue_result),
            (c"OnEnd", nothing),
            (c"Continue", continue_result),
            (c"ChangeTo", change_to),
            (c"Done", done),
            (c"TryContinue", try_continue),
            (c"TryChangeTo", try_change_to),
            (c"TryDone", try_done),
            (c"TryToSustain", try_to_sustain),
            (c"GetFullName", full_name),
            (c"_RequestsChange", requests_change),
            (c"_IsOutOfScope", never),
            (c"_ProcessPendingEvents", process_pending_events),
            (c"_StorePendingEventResult", store_pending_event_result),
            (c"_InvokeOnStart", invoke_on_start),
            (c"_InvokeUpdate", invoke_update),
            (c"_InvokeOnEnd", invoke_on_end),
            (c"_ApplyResult", apply_result),
            (c"_HandleEvent", handle_event),
            (c"_ProcessEvent", process_event),
            (c"_AskHere", ask_here),
            (c"QueryBelow", query_below),
        ],
    );
    push_str(l, "State");
    (api.setfield)(l, -2, c"name".as_ptr());
    set_getter(l, c"GetName", "name");
    set_getter(l, c"GetActor", "_actor");
    set_getter(l, c"GetActiveChildAction", "_child");
    set_getter(l, c"GetParentAction", "_parent");
    (api.createtable)(l, 4, 0);
    (api.pushcclosure)(l, transition_change_to, 0);
    (api.rawseti)(l, -2, CHANGE_TO as c_int);
    (api.pushcclosure)(l, transition_done, 0);
    (api.rawseti)(l, -2, DONE as c_int);
    (api.setfield)(l, -2, c"transitions".as_ptr());
}

unsafe fn push_root(l: L) {
    class(
        l,
        &[
            (c"New", root_new),
            (c"Watch", root_watch),
            (c"Stack", root_stack),
            (c"IsEmpty", root_is_empty),
            (c"Update", root_update),
            (c"Event", root_event),
            (c"Query", root_query),
            (c"Destroy", root_destroy),
            (c"Describe", root_describe),
            (c"_DestroyAction", root_destroy_action),
            (c"_PurgeDeadActions", root_purge_dead_actions),
        ],
    );
}

/// Pushes the generator.state_chart module table.
pub unsafe fn push_module(l: L) {
    let api = api();
    (api.createtable)(l, 0, 4);
    let reg = (api.gettop)(l);
    push_result(l, CONTINUE, 0, 0, 0);
    (api.setfield)(l, reg, c"continue".as_ptr());
    push_result(l, CONTINUE, 0, 0, 0);
    (api.pushnumber)(l, RESULT_NONE);
    (api.setfield)(l, -2, c"priority".as_ptr());
    (api.setfield)(l, reg, c"no_event".as_ptr());
    class(l, &[(c"State", chart_state), (c"Owns", chart_owns), (c"New", chart_new)]);
    (api.setfield)(l, reg, c"ChartClass".as_ptr());
    class(
        l,
        &[
            (c"Update", machine_update),
            (c"Event", machine_event),
            (c"Query", machine_query),
            (c"Describe", machine_describe),
            (c"IsEmpty", machine_is_empty),
            (c"Stack", machine_stack),
            (c"Watch", machine_watch),
            (c"Destroy", machine_destroy),
        ],
    );
    (api.setfield)(l, reg, c"MachineClass".as_ptr());
    (api.setfield)(l, REGISTRY, SHARED.as_ptr());

    crate::module::push(l, &[(c"Result", result), (c"ChartsOf", charts_of)], None);
    let module = (api.gettop)(l);
    for (name, value) in [
        (c"CONTINUE", CONTINUE),
        (c"CHANGE_TO", CHANGE_TO),
        (c"DONE", DONE),
        (c"SUSTAIN", SUSTAIN),
        (c"RESULT_NONE", RESULT_NONE),
        (c"RESULT_TRY", RESULT_TRY),
        (c"RESULT_IMPORTANT", RESULT_IMPORTANT),
        (c"RESULT_CRITICAL", RESULT_CRITICAL),
        (c"ANSWER_NO", ANSWER_NO),
        (c"ANSWER_YES", ANSWER_YES),
        (c"ANSWER_UNDEFINED", ANSWER_UNDEFINED),
    ] {
        (api.pushnumber)(l, value);
        (api.setfield)(l, module, name.as_ptr());
    }
    shared(l, c"continue");
    (api.setfield)(l, module, c"CONTINUE_RESULT".as_ptr());
    shared(l, c"no_event");
    (api.setfield)(l, module, c"NO_EVENT_RESULT".as_ptr());
    push_state(l);
    (api.setfield)(l, module, c"State".as_ptr());
    push_root(l);
    (api.setfield)(l, module, c"Root".as_ptr());

    (api.pushcclosure)(l, charts_of, 0);
    (api.createtable)(l, 0, 3);
    (api.getfield)(l, module, c"State".as_ptr());
    (api.setfield)(l, -2, c"state".as_ptr());
    (api.getfield)(l, module, c"Root".as_ptr());
    (api.setfield)(l, -2, c"root".as_ptr());
    (api.createtable)(l, 2, 0);
    push_str(l, "OnStart");
    (api.rawseti)(l, -2, 1);
    push_str(l, "OnEnd");
    (api.rawseti)(l, -2, 2);
    (api.setfield)(l, -2, c"lifecycle".as_ptr());
    (api.call)(l, 1, 1);
    (api.setfield)(l, module, c"Chart".as_ptr());
}
