//! generator.state_chart, native: the hierarchical statechart, the Lua
//! twin's contract (foundation/generator/state_chart.lua). State and Root
//! are class tables of C functions, extended with core.class as the Lua
//! twin's are (state_chart_stacks extends both), so every step the engine
//! takes on a state or a root is a method call looked up on it: a subclass's
//! override runs in its place. States, roots, results, charts and machines
//! are Lua tables with the Lua twin's fields.

use super::util::boolean;
use crate::lua::{
    push_str, raise_owned, raise_where, set_function, string_at, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL,
    TNUMBER, TSTRING, TTABLE,
};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;
const SHARED: &CStr = c"foundation.generator.state_chart";

// ActionResultType, in NextBot's numbers (2, SUSPEND_FOR, is the stacks').
pub(super) const CONTINUE: f64 = 0.0;
pub(super) const CHANGE_TO: f64 = 1.0;
pub(super) const DONE: f64 = 3.0;
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
pub(super) unsafe fn shared(l: L, name: &CStr) {
    l.getfield(REGISTRY, SHARED);
    l.getfield(-1, name);
    l.replace(-2);
}

/// Pushes core.<module>.<name>, read when called, as the Lua twin reads its
/// globals.
unsafe fn core_fn(l: L, module: &CStr, name: &CStr) {
    l.getfield(GLOBALSINDEX, c"core");
    l.getfield(-1, module);
    l.getfield(-1, name);
    l.replace(-3);
    l.settop(-2);
}

/// Pushes obj.name and obj: a method call's function and receiver, ready
/// for its arguments.
pub(super) unsafe fn prep(l: L, obj: c_int, name: &CStr) {
    l.getfield(obj, name);
    l.pushvalue(obj);
}

pub(super) unsafe fn push_range(l: L, from: c_int, to: c_int) {
    for i in from..=to {
        l.pushvalue(i);
    }
}

pub(super) unsafe fn truthy(l: L, index: c_int) -> bool {
    l.toboolean(index) != 0
}

pub(super) unsafe fn is_nil(l: L, index: c_int) -> bool {
    l.type_of(index) == TNIL
}

/// Whether the value at `index` is the number `n`.
unsafe fn is_number(l: L, index: c_int, n: f64) -> bool {
    l.type_of(index) == TNUMBER && l.tonumber(index) == n
}

/// Whether obj.name is the number `n`.
pub(super) unsafe fn field_is(l: L, obj: c_int, name: &CStr, n: f64) -> bool {
    l.getfield(obj, name);
    let is = is_number(l, -1, n);
    l.settop(-2);
    is
}

pub(super) unsafe fn field_truthy(l: L, obj: c_int, name: &CStr) -> bool {
    l.getfield(obj, name);
    let is = truthy(l, -1);
    l.settop(-2);
    is
}

pub(super) unsafe fn field_string(l: L, obj: c_int, name: &CStr) -> String {
    l.getfield(obj, name);
    let text = tostring(l, -1);
    l.settop(-2);
    text
}

/// Leaves the bottom-most of a chain of `_child` links from the value at
/// `slot` in `slot`.
unsafe fn innermost(l: L, slot: c_int) {
    loop {
        l.getfield(slot, c"_child");
        if !truthy(l, -1) {
            l.settop(-2);
            return;
        }
        l.replace(slot);
    }
}

/// Pushes { type, action, reason, priority }: `action` and `reason` stack
/// indices (0 for none), `priority` one too, 0 for RESULT_TRY.
pub(super) unsafe fn push_result(l: L, kind: f64, action: c_int, reason: c_int, priority: c_int) {
    l.createtable(0, 4);
    l.pushnumber(kind);
    l.setfield(-2, c"type");
    if action != 0 {
        l.pushvalue(action);
        l.setfield(-2, c"action");
    }
    if reason != 0 {
        l.pushvalue(reason);
        l.setfield(-2, c"reason");
    }
    if priority != 0 {
        l.pushvalue(priority);
    } else {
        l.pushnumber(RESULT_TRY);
    }
    l.setfield(-2, c"priority");
}

/// `priority or RESULT_TRY`, for push_result.
pub(super) unsafe fn or_try(l: L, index: c_int) -> c_int {
    if truthy(l, index) { index } else { 0 }
}

unsafe extern "C-unwind" fn result(l: L) -> c_int {
    l.settop(4);
    l.createtable(0, 4);
    for (i, name) in [c"type", c"action", c"reason", c"priority"].iter().enumerate() {
        l.pushvalue(i as c_int + 1);
        l.setfield(-2, name);
    }
    1
}

// State -----------------------------------------------------------------------------

unsafe extern "C-unwind" fn state_extend(l: L) -> c_int {
    l.settop(2);
    core_fn(l, c"class", c"Extend");
    l.pushvalue(1);
    l.createtable(0, 1);
    l.pushvalue(2);
    l.setfield(-2, c"name");
    l.call(2, 1);
    1
}

unsafe extern "C-unwind" fn state_new(l: L) -> c_int {
    let n = l.gettop().max(1);
    l.settop(n);
    core_fn(l, c"class", c"New");
    l.pushvalue(1);
    prep(l, 1, c"_Fields");
    l.call(1, 1);
    l.call(2, 1);
    let state = n + 1;
    prep(l, state, c"Init");
    push_range(l, 2, n);
    l.call(n, 0);
    l.pushvalue(state);
    1
}

pub(super) unsafe extern "C-unwind" fn state_fields(l: L) -> c_int {
    l.createtable(0, 2);
    l.pushboolean(0);
    l.setfield(-2, c"_started");
    shared(l, c"no_event");
    l.setfield(-2, c"_eventResult");
    1
}

unsafe extern "C-unwind" fn nothing(_l: L) -> c_int {
    0
}

unsafe extern "C-unwind" fn no_state(l: L) -> c_int {
    l.pushnil();
    1
}

pub(super) unsafe extern "C-unwind" fn continue_result(l: L) -> c_int {
    shared(l, c"continue");
    1
}

unsafe extern "C-unwind" fn change_to(l: L) -> c_int {
    l.settop(3);
    push_result(l, CHANGE_TO, 2, 3, 0);
    1
}

unsafe extern "C-unwind" fn done(l: L) -> c_int {
    l.settop(2);
    push_result(l, DONE, 0, 2, 0);
    1
}

unsafe extern "C-unwind" fn try_continue(l: L) -> c_int {
    l.settop(2);
    push_result(l, CONTINUE, 0, 0, or_try(l, 2));
    1
}

unsafe extern "C-unwind" fn try_change_to(l: L) -> c_int {
    l.settop(4);
    push_result(l, CHANGE_TO, 2, 4, or_try(l, 3));
    1
}

unsafe extern "C-unwind" fn try_done(l: L) -> c_int {
    l.settop(3);
    push_result(l, DONE, 0, 3, or_try(l, 2));
    1
}

unsafe extern "C-unwind" fn try_to_sustain(l: L) -> c_int {
    l.settop(3);
    push_result(l, SUSTAIN, 0, 3, or_try(l, 2));
    1
}

/// A getter of the field named by upvalue 1.
unsafe extern "C-unwind" fn getter(l: L) -> c_int {
    l.settop(1);
    l.pushvalue(upvalue(1));
    l.gettable(1);
    1
}

unsafe extern "C-unwind" fn full_name(l: L) -> c_int {
    l.settop(1);
    let mut names: Vec<Vec<u8>> = Vec::new();
    l.pushvalue(1);
    while truthy(l, 2) {
        l.getfield(2, c"name");
        let Some(name) = string_at(l, -1).map(<[u8]>::to_vec) else {
            drop(names);
            raise_where(l, "invalid value in table for 'concat'".into())
        };
        names.push(name);
        l.settop(2);
        l.getfield(2, c"_parent");
        l.replace(2);
    }
    names.reverse();
    let joined = names.join(&b'/');
    drop(names);
    l.pushlstring(joined.as_ptr().cast(), joined.len());
    1
}

unsafe extern "C-unwind" fn requests_change(l: L) -> c_int {
    l.settop(2);
    let change = field_is(l, 2, c"type", CHANGE_TO) || field_is(l, 2, c"type", DONE);
    boolean(l, change)
}

unsafe extern "C-unwind" fn never(l: L) -> c_int {
    boolean(l, false)
}

pub(super) unsafe extern "C-unwind" fn process_pending_events(l: L) -> c_int {
    l.settop(1);
    prep(l, 1, c"_RequestsChange");
    l.getfield(1, c"_eventResult");
    l.call(2, 1);
    if truthy(l, 2) {
        l.getfield(1, c"_eventResult");
        shared(l, c"no_event");
        l.setfield(1, c"_eventResult");
        return 1;
    }
    shared(l, c"continue");
    1
}

unsafe extern "C-unwind" fn store_pending_event_result(l: L) -> c_int {
    l.settop(2);
    if field_is(l, 2, c"type", CONTINUE) {
        return 0;
    }
    l.getfield(2, c"priority");
    l.getfield(1, c"_eventResult");
    l.getfield(4, c"priority");
    // result.priority >= stored: the latest wins a tie
    if l.lessthan(5, 3) != 0 || l.equal(5, 3) != 0 {
        l.pushvalue(2);
        l.setfield(1, c"_eventResult");
    }
    0
}

/// _InvokeOnStart(me, root, priorState): the child starts before my own
/// OnStart.
pub(super) unsafe extern "C-unwind" fn invoke_on_start(l: L) -> c_int {
    l.settop(4);
    l.pushboolean(1);
    l.setfield(1, c"_started");
    l.pushvalue(2);
    l.setfield(1, c"_actor");
    if truthy(l, 4) {
        l.getfield(4, c"_parent");
        l.setfield(1, c"_parent");
    }
    l.getfield(1, c"_parent");
    if truthy(l, 5) {
        l.pushvalue(1);
        l.setfield(5, c"_child");
    }
    l.settop(4);
    prep(l, 1, c"InitialContainedAction");
    l.pushvalue(2);
    l.call(2, 1);
    let child = 5;
    l.pushvalue(child);
    l.setfield(1, c"_child");
    if truthy(l, child) {
        l.pushvalue(1);
        l.setfield(child, c"_parent");
        prep(l, child, c"_ApplyResult");
        l.pushvalue(2);
        l.pushvalue(3);
        prep(l, 1, c"ChangeTo");
        l.pushvalue(child);
        push_str(l, "Starting child Action");
        l.call(3, 1);
        l.call(4, 1);
        l.setfield(1, c"_child");
    }
    prep(l, 1, c"OnStart");
    l.pushvalue(2);
    l.pushvalue(4);
    l.call(3, 1);
    1
}

/// _InvokeUpdate(me, root, interval): scope, pending events, the child, then
/// myself.
unsafe extern "C-unwind" fn invoke_update(l: L) -> c_int {
    l.settop(4);
    prep(l, 1, c"_IsOutOfScope");
    l.call(1, 1);
    if truthy(l, 5) {
        prep(l, 1, c"Done");
        push_str(l, "Out of scope");
        l.call(2, 1);
        return 1;
    }
    l.settop(4);
    if !field_truthy(l, 1, c"_started") {
        prep(l, 1, c"ChangeTo");
        l.pushvalue(1);
        push_str(l, "Starting Action");
        l.call(3, 1);
        return 1;
    }
    prep(l, 1, c"_ProcessPendingEvents");
    l.call(1, 1);
    if !field_is(l, 5, c"type", CONTINUE) {
        return 1;
    }
    l.settop(4);
    l.getfield(1, c"_child");
    if truthy(l, 5) {
        prep(l, 5, c"_ApplyResult");
        l.pushvalue(2);
        l.pushvalue(3);
        prep(l, 5, c"_InvokeUpdate");
        push_range(l, 2, 4);
        l.call(4, 1);
        l.call(4, 1);
        l.setfield(1, c"_child");
    }
    l.settop(4);
    prep(l, 1, c"Update");
    l.pushvalue(2);
    l.pushvalue(4);
    l.call(3, 1);
    1
}

/// _InvokeOnEnd(me, root, nextState): my child, then me.
unsafe extern "C-unwind" fn invoke_on_end(l: L) -> c_int {
    l.settop(4);
    if !field_truthy(l, 1, c"_started") {
        return 0;
    }
    l.pushboolean(0);
    l.setfield(1, c"_started");
    l.getfield(1, c"_child");
    if truthy(l, 5) {
        prep(l, 5, c"_InvokeOnEnd");
        push_range(l, 2, 4);
        l.call(4, 0);
    }
    l.settop(4);
    prep(l, 1, c"OnEnd");
    l.pushvalue(2);
    l.pushvalue(4);
    l.call(3, 0);
    0
}

/// transitions[CHANGE_TO](self, me, root, result): the new state takes my
/// parent.
unsafe extern "C-unwind" fn transition_change_to(l: L) -> c_int {
    l.settop(4);
    l.getfield(4, c"action");
    let next = 5;
    if is_nil(l, next) {
        let name = field_string(l, 1, c"name");
        let reason = if field_truthy(l, 4, c"reason") { field_string(l, 4, c"reason") } else { "no reason".into() };
        raise_owned(l, format!("{name}: ChangeTo needs a state ({reason})"));
    }
    prep(l, 1, c"_InvokeOnEnd");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(next);
    l.call(4, 0);
    prep(l, next, c"_InvokeOnStart");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(1);
    l.call(4, 1);
    let started = 6;
    if l.equal(1, next) == 0 {
        prep(l, 3, c"_DestroyAction");
        l.pushvalue(1);
        l.call(2, 0);
    }
    prep(l, next, c"_ApplyResult");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(started);
    l.call(4, 1);
    1
}

/// transitions[DONE]: nothing takes my place.
unsafe extern "C-unwind" fn transition_done(l: L) -> c_int {
    l.settop(4);
    prep(l, 1, c"_InvokeOnEnd");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushnil();
    l.call(4, 0);
    prep(l, 3, c"_DestroyAction");
    l.pushvalue(1);
    l.call(2, 0);
    l.pushnil();
    1
}

/// _ApplyResult(me, root, result): the state now active in my place; a
/// root's watcher hears of each change first.
unsafe extern "C-unwind" fn apply_result(l: L) -> c_int {
    l.settop(4);
    l.getfield(1, c"transitions");
    l.getfield(4, c"type");
    l.gettable(5);
    let apply = 6;
    if is_nil(l, apply) {
        l.pushvalue(1);
        return 1;
    }
    l.getfield(3, c"watcher");
    if truthy(l, 7) {
        l.getfield(4, c"action");
        let next = 8;
        prep(l, 7, c"Transition");
        l.getfield(4, c"type");
        l.getfield(1, c"name");
        if truthy(l, next) {
            l.getfield(next, c"name");
        } else {
            l.pushvalue(next);
        }
        l.getfield(4, c"reason");
        l.pushboolean(l.equal(next, 1));
        l.call(6, 0);
    }
    l.pushvalue(apply);
    push_range(l, 1, 4);
    l.call(4, 1);
    1
}

/// _HandleEvent(name, ...): an event's handler on me, its result stored as
/// my pending change.
unsafe extern "C-unwind" fn handle_event(l: L) -> c_int {
    let n = l.gettop().max(2);
    l.settop(n);
    l.pushvalue(2);
    l.gettable(1);
    let handler = n + 1;
    if truthy(l, handler) {
        prep(l, 1, c"_StorePendingEventResult");
        l.pushvalue(handler);
        l.pushvalue(1);
        l.getfield(1, c"_actor");
        push_range(l, 3, n);
        l.call(n, 1);
        l.call(2, 0);
    }
    0
}

/// _ProcessEvent(name, ...): an unstarted state ignores events; I handle
/// it, then my active child.
unsafe extern "C-unwind" fn process_event(l: L) -> c_int {
    let n = l.gettop().max(2);
    l.settop(n);
    if !field_truthy(l, 1, c"_started") {
        return 0;
    }
    prep(l, 1, c"_HandleEvent");
    push_range(l, 2, n);
    l.call(n, 0);
    l.getfield(1, c"_child");
    if truthy(l, n + 1) {
        prep(l, n + 1, c"_ProcessEvent");
        push_range(l, 2, n);
        l.call(n, 0);
    }
    0
}

/// _AskHere(me, name, ...): my answer to a query, or nil.
pub(super) unsafe extern "C-unwind" fn ask_here(l: L) -> c_int {
    let n = l.gettop().max(3);
    l.settop(n);
    l.pushvalue(3);
    l.gettable(1);
    if truthy(l, n + 1) {
        l.pushvalue(1);
        l.pushvalue(2);
        push_range(l, 4, n);
        l.call(n - 1, 1);
        if !is_nil(l, n + 1) && !is_number(l, n + 1, ANSWER_UNDEFINED) {
            return 1;
        }
    }
    l.pushnil();
    1
}

/// Pushes the first answer from the innermost state under the one at
/// `state` out to the one at `stop` (exclusive; 0: none), asking
/// _AskHere(me, name, args from..=to).
unsafe fn ask_outward(l: L, state: c_int, stop: c_int, me: c_int, name: c_int, from: c_int, to: c_int) {
    l.pushvalue(state);
    let at = l.gettop();
    innermost(l, at);
    while truthy(l, at) && (stop == 0 || l.equal(at, stop) == 0) {
        prep(l, at, c"_AskHere");
        l.pushvalue(me);
        l.pushvalue(name);
        push_range(l, from, to);
        l.call(3 + (to - from + 1).max(0), 1);
        if !is_nil(l, -1) {
            l.replace(at);
            return;
        }
        l.settop(at);
        l.getfield(at, c"_parent");
        l.replace(at);
    }
    l.settop(at - 1);
    l.pushnumber(ANSWER_UNDEFINED);
}

/// QueryBelow(me, name, ...): the query asked only of the states I contain.
unsafe extern "C-unwind" fn query_below(l: L) -> c_int {
    let n = l.gettop().max(3);
    l.settop(n);
    l.getfield(1, c"_child");
    if is_nil(l, n + 1) {
        l.pushnumber(ANSWER_UNDEFINED);
        return 1;
    }
    ask_outward(l, n + 1, 1, 2, 3, 4, n);
    1
}

// Root ------------------------------------------------------------------------------

unsafe extern "C-unwind" fn root_new(l: L) -> c_int {
    l.settop(3);
    core_fn(l, c"class", c"New");
    l.pushvalue(1);
    l.createtable(0, 5);
    l.pushvalue(2);
    l.setfield(-2, c"action");
    l.pushvalue(3);
    l.setfield(-2, c"name");
    l.createtable(0, 0);
    l.setfield(-2, c"dead");
    l.call(2, 1);
    1
}

unsafe extern "C-unwind" fn root_watch(l: L) -> c_int {
    l.settop(2);
    l.setfield(1, c"watcher");
    0
}

pub(super) unsafe fn append(l: L, list: c_int) {
    let n = l.objlen(list);
    l.rawseti(list, n as c_int + 1);
}

/// Appends { name, depth } for the state at `state` and its active children
/// to the list at `frames`.
unsafe fn stack_frames(l: L, state: c_int, depth: f64, frames: c_int) {
    l.createtable(0, 2);
    l.getfield(state, c"name");
    l.setfield(-2, c"name");
    l.pushnumber(depth);
    l.setfield(-2, c"depth");
    append(l, frames);
    l.getfield(state, c"_child");
    let child = l.gettop();
    if truthy(l, child) {
        stack_frames(l, child, depth + 1.0, frames);
    }
    l.settop(child - 1);
}

unsafe extern "C-unwind" fn root_stack(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"action");
    l.createtable(0, 0);
    if !is_nil(l, 2) {
        stack_frames(l, 2, 1.0, 3);
    }
    1
}

unsafe extern "C-unwind" fn root_is_empty(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"action");
    boolean(l, is_nil(l, 2))
}

unsafe extern "C-unwind" fn root_update(l: L) -> c_int {
    l.settop(3);
    l.getfield(1, c"action");
    if is_nil(l, 4) {
        return 0;
    }
    l.pushvalue(2);
    l.setfield(1, c"me");
    prep(l, 4, c"_ApplyResult");
    l.pushvalue(2);
    l.pushvalue(1);
    prep(l, 4, c"_InvokeUpdate");
    l.pushvalue(2);
    l.pushvalue(1);
    l.pushvalue(3);
    l.call(4, 1);
    l.call(4, 1);
    l.setfield(1, c"action");
    prep(l, 1, c"_PurgeDeadActions");
    l.call(1, 0);
    0
}

unsafe extern "C-unwind" fn root_event(l: L) -> c_int {
    let n = l.gettop().max(3);
    l.settop(n);
    l.getfield(1, c"action");
    if is_nil(l, n + 1) {
        return 0;
    }
    l.getfield(1, c"watcher");
    if truthy(l, n + 2) {
        prep(l, n + 2, c"Event");
        l.pushvalue(3);
        l.call(2, 0);
    }
    l.getfield(1, c"action");
    let action = l.gettop();
    prep(l, action, c"_ProcessEvent");
    push_range(l, 3, n);
    l.call(n - 1, 0);
    0
}

unsafe extern "C-unwind" fn root_query(l: L) -> c_int {
    let n = l.gettop().max(3);
    l.settop(n);
    l.getfield(1, c"action");
    if is_nil(l, n + 1) {
        l.pushnumber(ANSWER_UNDEFINED);
        return 1;
    }
    ask_outward(l, n + 1, 0, 2, 3, 4, n);
    1
}

unsafe extern "C-unwind" fn root_destroy(l: L) -> c_int {
    l.settop(1);
    if field_truthy(l, 1, c"me") && field_truthy(l, 1, c"action") {
        l.getfield(1, c"action");
        prep(l, 2, c"_InvokeOnEnd");
        l.getfield(1, c"me");
        l.pushvalue(1);
        l.pushnil();
        l.call(4, 0);
        l.settop(1);
    }
    l.pushnil();
    l.setfield(1, c"action");
    0
}

unsafe extern "C-unwind" fn root_describe(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"action");
    if is_nil(l, 2) {
        push_str(l, "");
        return 1;
    }
    innermost(l, 2);
    prep(l, 2, c"GetFullName");
    l.call(1, 1);
    1
}

unsafe extern "C-unwind" fn root_destroy_action(l: L) -> c_int {
    l.settop(2);
    l.getfield(1, c"dead");
    l.pushvalue(2);
    append(l, 3);
    0
}

unsafe extern "C-unwind" fn root_purge_dead_actions(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"dead");
    let mut i = 1;
    loop {
        l.rawgeti(2, i);
        if is_nil(l, 3) {
            break;
        }
        l.getfield(3, c"_parent");
        if truthy(l, 4) {
            l.getfield(4, c"_child");
            if l.equal(5, 3) != 0 {
                l.pushnil();
                l.setfield(4, c"_child");
            }
        }
        l.settop(2);
        i += 1;
    }
    l.createtable(0, 0);
    l.setfield(1, c"dead");
    0
}

// Names a chart declares ------------------------------------------------------------

/// The string at `index`, or a refusal blamed on the caller: `what` needs a
/// name.
unsafe fn name_at(l: L, index: c_int, what: &str) -> String {
    let name = if l.type_of(index) == TSTRING { tostring(l, index) } else { String::new() };
    if name.is_empty() {
        raise_where(l, format!("{what} needs a name"));
    }
    name
}

/// Checks that the value at `index` is a list of names.
unsafe fn name_list(l: L, index: c_int, what: &str) {
    if l.type_of(index) != TTABLE {
        raise_where(l, format!("{what} must be a list of names"));
    }
    let mut i = 1;
    loop {
        l.rawgeti(index, i);
        let kind = l.type_of(-1);
        if kind == TNIL {
            l.settop(-2);
            return;
        }
        if kind != TSTRING {
            let given = tostring(l, -1);
            raise_where(l, format!("{what} has a non-name: {given}"));
        }
        l.settop(-2);
        i += 1;
    }
}

/// Pushes { name = true } for the list at `index`.
unsafe fn name_set(l: L, index: c_int) {
    if l.type_of(index) != TTABLE {
        let got = tostring(l, index);
        raise_where(l, format!("bad argument #1 to 'ipairs' (table expected, got {got})"));
    }
    l.createtable(0, 4);
    let set = l.gettop();
    let mut i = 1;
    loop {
        l.rawgeti(index, i);
        if is_nil(l, -1) {
            l.settop(set);
            return;
        }
        l.pushboolean(1);
        l.rawset(set);
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
    l.settop(1);
    if l.type_of(1) != TSTRING || !string_at(l, 1).is_some_and(event_name) {
        return 0;
    }
    for set in [c"lifecycle", c"events"] {
        l.getfield(upvalue(1), set);
        l.pushvalue(1);
        l.gettable(-2);
        let declared = truthy(l, -1);
        l.settop(1);
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
    l.getfield(1, key);
    if !truthy(l, -1) {
        l.settop(-2);
        l.createtable(0, 0);
    }
    let list = l.gettop();
    name_list(l, list, what);
    list
}

/// The Chart function of an engine (upvalue 1 the engine, 2 its lifecycle
/// set): Chart{ name, port, events?, queries?, initial }.
unsafe extern "C-unwind" fn make_chart(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"name");
    let name = name_at(l, 2, "a chart");
    l.settop(1);
    core_fn(l, c"port", c"Is");
    l.getfield(1, c"port");
    l.call(1, 1);
    if !truthy(l, 2) {
        raise_where(l, format!("chart {name} needs a Port"));
    }
    l.settop(1);
    l.getfield(1, c"initial");
    if l.type_of(2) != TFUNCTION {
        raise_where(l, format!("chart {name} needs initial(states)"));
    }
    l.settop(1);
    let events = spec_names(l, c"events", &format!("chart {name}'s events"));
    let mut i = 1;
    loop {
        l.rawgeti(events, i);
        if is_nil(l, -1) {
            l.settop(-2);
            break;
        }
        if !string_at(l, -1).is_some_and(event_name) {
            let event = tostring(l, -1);
            raise_where(l, format!("chart {name}: event {event} must start On"));
        }
        l.settop(-2);
        i += 1;
    }
    let queries = spec_names(l, c"queries", &format!("chart {name}'s queries"));
    l.createtable(0, 8);
    let chart = l.gettop();
    l.getfield(1, c"name");
    l.setfield(chart, c"name");
    l.getfield(1, c"port");
    l.setfield(chart, c"port");
    name_set(l, events);
    l.setfield(chart, c"events");
    name_set(l, queries);
    l.setfield(chart, c"queries");
    l.getfield(1, c"initial");
    l.setfield(chart, c"initial");
    l.pushvalue(upvalue(2));
    l.setfield(chart, c"lifecycle");
    l.getfield(upvalue(1), c"root");
    l.setfield(chart, c"root");
    shared(l, c"ChartClass");
    l.setmetatable(chart);
    core_fn(l, c"class", c"Guard");
    l.getfield(upvalue(1), c"state");
    let state = l.gettop();
    prep(l, state, c"Extend");
    l.getfield(1, c"name");
    l.call(2, 1);
    l.replace(state);
    l.pushvalue(chart);
    l.pushcclosure(state_guard, 1);
    l.call(2, 1);
    l.setfield(chart, c"base");
    l.pushvalue(chart);
    1
}

/// ChartsOf{ state, root, lifecycle } -> the Chart function of an engine.
unsafe extern "C-unwind" fn charts_of(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"lifecycle");
    name_set(l, 2);
    l.pushvalue(1);
    l.pushvalue(3);
    l.pushcclosure(make_chart, 2);
    1
}

// Chart and Machine -----------------------------------------------------------------

unsafe extern "C-unwind" fn chart_state(l: L) -> c_int {
    l.settop(2);
    name_at(l, 2, "a state");
    l.getfield(1, c"base");
    prep(l, 3, c"Extend");
    l.pushvalue(2);
    l.call(2, 1);
    1
}

unsafe extern "C-unwind" fn chart_owns(l: L) -> c_int {
    l.settop(2);
    core_fn(l, c"class", c"IsA");
    l.pushvalue(2);
    l.getfield(1, c"base");
    l.call(2, 1);
    1
}

unsafe extern "C-unwind" fn chart_new(l: L) -> c_int {
    l.settop(3);
    l.getfield(1, c"port");
    prep(l, 4, c"Facade");
    prep(l, 4, c"Check");
    l.pushvalue(2);
    l.call(2, 1);
    l.call(2, 1);
    let me = 5;
    l.getfield(1, c"initial");
    l.pushvalue(3);
    l.call(1, 1);
    let first = 6;
    prep(l, 1, c"Owns");
    l.pushvalue(first);
    l.call(2, 1);
    if !truthy(l, 7) {
        let name = field_string(l, 1, c"name");
        raise_where(l, format!("chart {name}: initial gave a state of another chart"));
    }
    l.settop(first);
    l.createtable(0, 3);
    let machine = 7;
    l.pushvalue(1);
    l.setfield(machine, c"chart");
    l.pushvalue(me);
    l.setfield(machine, c"me");
    l.getfield(1, c"root");
    prep(l, 8, c"New");
    l.pushvalue(first);
    l.getfield(1, c"name");
    l.call(3, 1);
    l.setfield(machine, c"root");
    l.settop(machine);
    shared(l, c"MachineClass");
    l.setmetatable(machine);
    1
}

/// Calls self.root:<method>(self.me?, args 2..=n), pushing `results`.
unsafe fn on_root(l: L, method: &CStr, with_me: bool, n: c_int, results: c_int) -> c_int {
    l.getfield(1, c"root");
    let root = l.gettop();
    prep(l, root, method);
    if with_me {
        l.getfield(1, c"me");
    }
    push_range(l, 2, n);
    l.call(1 + with_me as c_int + (n - 1).max(0), results);
    results
}

/// Refuses a name the machine's chart does not declare in `set`.
unsafe fn declared(l: L, set: &CStr, what: &str) {
    let top = l.gettop();
    l.getfield(1, c"chart");
    l.getfield(-1, set);
    l.pushvalue(2);
    l.gettable(-2);
    if !truthy(l, -1) {
        let chart = field_string(l, top + 1, c"name");
        let name = tostring(l, 2);
        raise_where(l, format!("chart {chart} has no {what} {name}"));
    }
    l.settop(top);
}

unsafe extern "C-unwind" fn machine_update(l: L) -> c_int {
    l.settop(2);
    on_root(l, c"Update", true, 2, 0)
}

unsafe extern "C-unwind" fn machine_event(l: L) -> c_int {
    let n = l.gettop().max(2);
    l.settop(n);
    declared(l, c"events", "event");
    on_root(l, c"Event", true, n, 0)
}

unsafe extern "C-unwind" fn machine_query(l: L) -> c_int {
    let n = l.gettop().max(2);
    l.settop(n);
    declared(l, c"queries", "query");
    on_root(l, c"Query", true, n, 1)
}

unsafe extern "C-unwind" fn machine_describe(l: L) -> c_int {
    l.settop(1);
    on_root(l, c"Describe", false, 1, 1)
}

unsafe extern "C-unwind" fn machine_is_empty(l: L) -> c_int {
    l.settop(1);
    on_root(l, c"IsEmpty", false, 1, 1)
}

unsafe extern "C-unwind" fn machine_stack(l: L) -> c_int {
    l.settop(1);
    on_root(l, c"Stack", false, 1, 1)
}

unsafe extern "C-unwind" fn machine_watch(l: L) -> c_int {
    l.settop(2);
    on_root(l, c"Watch", false, 2, 0)
}

unsafe extern "C-unwind" fn machine_destroy(l: L) -> c_int {
    l.settop(1);
    on_root(l, c"Destroy", false, 1, 0)
}

// The module ------------------------------------------------------------------------

/// Pushes a class table, its own __index, holding `methods`.
pub(super) unsafe fn class(l: L, methods: &[(&CStr, CFunction)]) {
    l.createtable(0, methods.len() as c_int + 2);
    l.pushvalue(-1);
    l.setfield(-2, c"__index");
    for (name, f) in methods {
        set_function(l, name, *f);
    }
}

pub(super) unsafe fn set_getter(l: L, method: &CStr, field: &str) {
    push_str(l, field);
    l.pushcclosure(getter, 1);
    l.setfield(-2, method);
}

unsafe fn push_state(l: L) {
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
    l.setfield(-2, c"name");
    set_getter(l, c"GetName", "name");
    set_getter(l, c"GetActor", "_actor");
    set_getter(l, c"GetActiveChildAction", "_child");
    set_getter(l, c"GetParentAction", "_parent");
    l.createtable(4, 0);
    l.pushcclosure(transition_change_to, 0);
    l.rawseti(-2, CHANGE_TO as c_int);
    l.pushcclosure(transition_done, 0);
    l.rawseti(-2, DONE as c_int);
    l.setfield(-2, c"transitions");
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
    l.getfield(REGISTRY, SHARED);
    if l.type_of(-1) == TTABLE {
        l.settop(-2);
    } else {
        l.settop(-2);
        push_shared(l);
    }
    push_api(l);
}

/// The values the module shares by identity, one set a Lua state, kept in
/// the registry: a module opened again (a reload) hands out the same
/// CONTINUE_RESULT, which the stacks compare results to.
unsafe fn push_shared(l: L) {
    l.createtable(0, 4);
    let reg = l.gettop();
    push_result(l, CONTINUE, 0, 0, 0);
    l.setfield(reg, c"continue");
    push_result(l, CONTINUE, 0, 0, 0);
    l.pushnumber(RESULT_NONE);
    l.setfield(-2, c"priority");
    l.setfield(reg, c"no_event");
    class(l, &[(c"State", chart_state), (c"Owns", chart_owns), (c"New", chart_new)]);
    l.setfield(reg, c"ChartClass");
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
    l.setfield(reg, c"MachineClass");
    l.setfield(REGISTRY, SHARED);
}

unsafe fn push_api(l: L) {
    crate::module::push(l, &[(c"Result", result), (c"ChartsOf", charts_of)], None);
    let module = l.gettop();
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
        l.pushnumber(value);
        l.setfield(module, name);
    }
    shared(l, c"continue");
    l.setfield(module, c"CONTINUE_RESULT");
    shared(l, c"no_event");
    l.setfield(module, c"NO_EVENT_RESULT");
    push_state(l);
    l.setfield(module, c"State");
    push_root(l);
    l.setfield(module, c"Root");

    super::state_chart_stacks::add_to(l, module);
}
