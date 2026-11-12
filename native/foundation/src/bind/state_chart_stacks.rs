//! generator.state_chart's stacks, native: NextBot's Action/Behavior engine, the
//! Lua twin's contract (foundation/generator/state_chart.lua). Action and Behavior
//! are class tables of C functions extending the module's State and Root with
//! core.class, as the Lua twin's do, and every step is a method call looked up on
//! the action, so a subclass's override runs in its place. Actions are Lua tables
//! with the Lua twin's fields.

use super::core::extend;
use super::state_chart::{
    append, ask_here as state_ask_here, continue_result, field_is, field_string, field_truthy,
    invoke_on_start as state_invoke_on_start, is_nil, or_try, prep,
    process_pending_events as state_process_pending_events, push_range, push_result, set_getter,
    shared, state_fields, truthy, CHANGE_TO, CONTINUE, DONE,
};
use super::timer;
use super::util::boolean;
use crate::lua::{push_str, raise_owned, set_function, CFunction, L};
use std::ffi::{c_int, CStr};

// ActionResultType's stack entry, between state_chart's.
const SUSPEND_FOR: f64 = 2.0;

/// Pushes a C function, to call as a parent's method.
unsafe fn push_c(l: L, function: CFunction) {
    l.pushcclosure(function, 0);
}

unsafe fn set_nil(l: L, obj: c_int, name: &CStr) {
    l.pushnil();
    l.setfield(obj, name);
}

unsafe fn set_flag(l: L, obj: c_int, name: &CStr, value: bool) {
    l.pushboolean(value as c_int);
    l.setfield(obj, name);
}

/// Moves the action in `slot` on to the one buried under it.
unsafe fn to_buried(l: L, slot: c_int) {
    l.settop(slot);
    l.getfield(slot, c"_buried");
    l.replace(slot);
}

// Action ----------------------------------------------------------------------------

unsafe extern "C-unwind" fn action_fields(l: L) -> c_int {
    l.settop(1);
    push_c(l, state_fields);
    l.pushvalue(1);
    l.call(1, 1);
    set_flag(l, -2, c"_suspended", false);
    1
}

/// SuspendFor(action, reason): clears any pending event transition, or the new
/// action would at once be out of scope.
unsafe extern "C-unwind" fn suspend_for(l: L) -> c_int {
    l.settop(3);
    shared(l, c"no_event");
    l.setfield(1, c"_eventResult");
    push_result(l, SUSPEND_FOR, 2, 3, 0);
    1
}

/// TrySuspendFor(action, priority, reason).
unsafe extern "C-unwind" fn try_suspend_for(l: L) -> c_int {
    l.settop(4);
    push_result(l, SUSPEND_FOR, 2, 4, or_try(l, 3));
    1
}

unsafe extern "C-unwind" fn requests_change(l: L) -> c_int {
    l.settop(2);
    let change = field_is(l, 2, c"type", CHANGE_TO)
        || field_is(l, 2, c"type", SUSPEND_FOR)
        || field_is(l, 2, c"type", DONE);
    boolean(l, change)
}

/// Action::IsOutOfScope: a buried action leaving or changing makes me stale.
unsafe extern "C-unwind" fn is_out_of_scope(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"_buried");
    let under = 2;
    loop {
        if !truthy(l, under) {
            break;
        }
        l.getfield(under, c"_eventResult");
        if field_is(l, 3, c"type", CHANGE_TO) || field_is(l, 3, c"type", DONE) {
            return boolean(l, true);
        }
        to_buried(l, under);
    }
    boolean(l, false)
}

/// Action::ProcessPendingEvents: my own requested change first, then a
/// SUSPEND_FOR left on an action buried under me.
unsafe extern "C-unwind" fn process_pending_events(l: L) -> c_int {
    l.settop(1);
    push_c(l, state_process_pending_events);
    l.pushvalue(1);
    l.call(1, 1);
    shared(l, c"continue");
    if l.rawequal(2, 3) == 0 {
        l.settop(2);
        return 1;
    }
    l.settop(1);
    l.getfield(1, c"_buried");
    let under = 2;
    loop {
        if !truthy(l, under) {
            break;
        }
        l.getfield(under, c"_eventResult");
        if field_is(l, 3, c"type", SUSPEND_FOR) {
            shared(l, c"no_event");
            l.setfield(under, c"_eventResult");
            return 1;
        }
        to_buried(l, under);
    }
    shared(l, c"continue");
    1
}

/// _InvokeOnStart(me, behavior, priorAction, buriedUnderMe): I cover the action
/// buried under me.
unsafe extern "C-unwind" fn invoke_on_start(l: L) -> c_int {
    l.settop(5);
    l.pushvalue(5);
    l.setfield(1, c"_buried");
    if truthy(l, 5) {
        l.pushvalue(1);
        l.setfield(5, c"_covering");
    }
    set_nil(l, 1, c"_covering");
    push_c(l, state_invoke_on_start);
    push_range(l, 1, 4);
    l.call(4, 1);
    1
}

/// _InvokeOnEnd(me, behavior, nextAction): my children, top down, then me, then
/// whatever covers me.
unsafe extern "C-unwind" fn invoke_on_end(l: L) -> c_int {
    l.settop(4);
    if !field_truthy(l, 1, c"_started") {
        return 0;
    }
    set_flag(l, 1, c"_started", false);
    l.getfield(1, c"_child");
    let child = 5;
    loop {
        if !truthy(l, child) {
            break;
        }
        l.getfield(child, c"_buried");
        prep(l, child, c"_InvokeOnEnd");
        push_range(l, 2, 4);
        l.call(4, 0);
        l.replace(child);
    }
    l.settop(4);
    prep(l, 1, c"OnEnd");
    l.pushvalue(2);
    l.pushvalue(4);
    l.call(3, 0);
    l.getfield(1, c"_covering");
    if truthy(l, 5) {
        prep(l, 5, c"_InvokeOnEnd");
        push_range(l, 2, 4);
        l.call(4, 0);
    }
    0
}

/// _InvokeOnSuspend(me, behavior, interruptingAction): returns the action now on
/// top, which is my buried one when OnSuspend asks to be Done instead.
unsafe extern "C-unwind" fn invoke_on_suspend(l: L) -> c_int {
    l.settop(4);
    l.getfield(1, c"_child");
    if truthy(l, 5) {
        prep(l, 5, c"_InvokeOnSuspend");
        push_range(l, 2, 4);
        l.call(4, 1);
        l.setfield(1, c"_child");
    }
    l.settop(4);
    set_flag(l, 1, c"_suspended", true);
    prep(l, 1, c"OnSuspend");
    l.pushvalue(2);
    l.pushvalue(4);
    l.call(3, 1);
    if field_is(l, 5, c"type", DONE) {
        prep(l, 1, c"_InvokeOnEnd");
        l.pushvalue(2);
        l.pushvalue(3);
        l.pushnil();
        l.call(4, 0);
        l.getfield(1, c"_buried");
        prep(l, 3, c"_DestroyAction");
        l.pushvalue(1);
        l.call(2, 0);
        return 1;
    }
    l.pushvalue(1);
    1
}

/// _InvokeOnResume(me, behavior, interruptingAction): skipped while a change
/// from an event is pending.
unsafe extern "C-unwind" fn invoke_on_resume(l: L) -> c_int {
    l.settop(4);
    if !field_truthy(l, 1, c"_suspended") {
        shared(l, c"continue");
        return 1;
    }
    prep(l, 1, c"_RequestsChange");
    l.getfield(1, c"_eventResult");
    l.call(2, 1);
    if truthy(l, 5) {
        shared(l, c"continue");
        return 1;
    }
    l.settop(4);
    set_flag(l, 1, c"_suspended", false);
    set_nil(l, 1, c"_covering");
    l.getfield(1, c"_parent");
    if truthy(l, 5) {
        l.pushvalue(1);
        l.setfield(5, c"_child");
    }
    l.settop(4);
    l.getfield(1, c"_child");
    if truthy(l, 5) {
        prep(l, 5, c"_ApplyResult");
        l.pushvalue(2);
        l.pushvalue(3);
        prep(l, 5, c"_InvokeOnResume");
        push_range(l, 2, 4);
        l.call(4, 1);
        l.call(4, 1);
        l.setfield(1, c"_child");
    }
    l.settop(4);
    prep(l, 1, c"OnResume");
    l.pushvalue(2);
    l.pushvalue(4);
    l.call(3, 1);
    1
}

/// Calls the action at `action`'s _ApplyResult(me, behavior, result at `result`),
/// leaving what it returns.
unsafe fn apply(l: L, action: c_int, result: c_int) {
    prep(l, action, c"_ApplyResult");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(result);
    l.call(4, 1);
}

/// transitions[CHANGE_TO](self, me, behavior, result): the new action takes my
/// parent and my buried action.
unsafe extern "C-unwind" fn transition_change_to(l: L) -> c_int {
    l.settop(4);
    l.getfield(4, c"action");
    let next = 5;
    if is_nil(l, next) {
        let name = field_string(l, 1, c"name");
        let reason = if field_truthy(l, 4, c"reason") {
            field_string(l, 4, c"reason")
        } else {
            "no reason".to_string()
        };
        raise_owned(l, format!("{name}: ChangeTo needs an action ({reason})"));
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
    l.getfield(1, c"_buried");
    l.call(5, 1);
    let started = 6;
    if l.equal(1, next) == 0 {
        prep(l, 3, c"_DestroyAction");
        l.pushvalue(1);
        l.call(2, 0);
    }
    apply(l, next, started);
    1
}

/// transitions[SUSPEND_FOR]: the new action always goes on top of the stack.
unsafe extern "C-unwind" fn transition_suspend_for(l: L) -> c_int {
    l.settop(4);
    l.getfield(4, c"action");
    let next = 5;
    l.pushvalue(1);
    let top = 6;
    loop {
        l.getfield(top, c"_covering");
        if !truthy(l, -1) {
            l.settop(top);
            break;
        }
        l.replace(top);
    }
    prep(l, top, c"_InvokeOnSuspend");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(next);
    l.call(4, 1);
    l.replace(top);
    prep(l, next, c"_InvokeOnStart");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(top);
    l.pushvalue(top);
    l.call(5, 1);
    let started = 7;
    apply(l, next, started);
    1
}

/// transitions[DONE]: resume the buried action, or leave the stack empty.
unsafe extern "C-unwind" fn transition_done(l: L) -> c_int {
    l.settop(4);
    l.getfield(1, c"_buried");
    let resumed = 5;
    prep(l, 1, c"_InvokeOnEnd");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(resumed);
    l.call(4, 0);
    prep(l, 3, c"_DestroyAction");
    l.pushvalue(1);
    l.call(2, 0);
    if is_nil(l, resumed) {
        l.pushnil();
        return 1;
    }
    prep(l, resumed, c"_InvokeOnResume");
    l.pushvalue(2);
    l.pushvalue(3);
    l.pushvalue(1);
    l.call(4, 1);
    let result = 6;
    apply(l, resumed, result);
    1
}

/// _HandleEvent(name, ...), PROCESS_EVENT: the event walks me and the actions
/// buried under me while each continues; the first other result is stored on the
/// action that gave it.
unsafe extern "C-unwind" fn handle_event(l: L) -> c_int {
    let n = l.gettop().max(2);
    l.settop(n);
    l.getfield(1, c"_actor");
    let actor = n + 1;
    l.pushvalue(1);
    let action = n + 2;
    let result = n + 3;
    loop {
        if !truthy(l, action) {
            break;
        }
        l.pushvalue(2);
        l.gettable(action);
        if truthy(l, result) {
            l.pushvalue(action);
            l.pushvalue(actor);
            push_range(l, 3, n);
            l.call(n, 1);
        } else {
            l.settop(action);
            shared(l, c"continue");
        }
        if !field_is(l, result, c"type", CONTINUE) {
            prep(l, action, c"_StorePendingEventResult");
            l.pushvalue(result);
            l.call(2, 0);
            return 0;
        }
        to_buried(l, action);
    }
    0
}

/// _AskHere(me, name, ...): a query asks me, then the actions buried under me.
unsafe extern "C-unwind" fn ask_here(l: L) -> c_int {
    let n = l.gettop().max(3);
    l.settop(n);
    l.pushvalue(1);
    let current = n + 1;
    loop {
        if !truthy(l, current) {
            break;
        }
        push_c(l, state_ask_here);
        l.pushvalue(current);
        push_range(l, 2, n);
        l.call(n, 1);
        if !is_nil(l, -1) {
            return 1;
        }
        to_buried(l, current);
    }
    l.pushnil();
    1
}

// Behavior --------------------------------------------------------------------------

/// Appends { name, short, depth, suspended, passthrough } for the action at
/// `start`, the actions it contains a level deeper, then those buried under it:
/// Action::DebugString's order.
unsafe fn stack_frames(l: L, start: c_int, depth: f64, frames: c_int) {
    let base = l.gettop();
    l.pushvalue(start);
    let action = base + 1;
    loop {
        if !truthy(l, action) {
            break;
        }
        l.createtable(0, 5);
        l.getfield(action, c"name");
        l.setfield(-2, c"name");
        l.getfield(action, c"shortName");
        if !truthy(l, -1) {
            l.settop(-2);
            l.getfield(action, c"name");
        }
        l.setfield(-2, c"short");
        l.pushnumber(depth);
        l.setfield(-2, c"depth");
        l.getfield(action, c"_suspended");
        l.setfield(-2, c"suspended");
        l.getfield(action, c"passthrough");
        l.setfield(-2, c"passthrough");
        append(l, frames);
        l.getfield(action, c"_child");
        if truthy(l, -1) {
            let child = l.gettop();
            stack_frames(l, child, depth + 1.0, frames);
        }
        to_buried(l, action);
    }
    l.settop(base);
}

unsafe extern "C-unwind" fn behavior_stack(l: L) -> c_int {
    l.settop(1);
    l.getfield(1, c"action");
    l.createtable(0, 0);
    stack_frames(l, 2, 1.0, 3);
    1
}

/// _PurgeDeadActions, as ~Action: a dead action's parent's active child falls
/// back to its buried action, and its buried action is no longer covered.
unsafe extern "C-unwind" fn behavior_purge_dead_actions(l: L) -> c_int {
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
                l.getfield(3, c"_buried");
                l.setfield(4, c"_child");
            }
        }
        l.settop(3);
        l.getfield(3, c"_buried");
        if truthy(l, 4) {
            set_nil(l, 4, c"_covering");
        }
        l.settop(2);
        i += 1;
    }
    l.createtable(0, 0);
    l.setfield(1, c"dead");
    0
}

// The module ------------------------------------------------------------------------

/// Pushes Action: core.class's Extend of the State at `state`.
unsafe fn push_action(l: L, state: c_int) {
    push_c(l, extend);
    l.pushvalue(state);
    l.createtable(0, 2);
    push_str(l, "Action");
    l.setfield(-2, c"name");
    l.pushboolean(0);
    l.setfield(-2, c"passthrough");
    l.call(2, 1);
    let methods: &[(&CStr, CFunction)] = &[
        (c"_Fields", action_fields),
        (c"OnSuspend", continue_result),
        (c"OnResume", continue_result),
        (c"SuspendFor", suspend_for),
        (c"TrySuspendFor", try_suspend_for),
        (c"_RequestsChange", requests_change),
        (c"_IsOutOfScope", is_out_of_scope),
        (c"_ProcessPendingEvents", process_pending_events),
        (c"_InvokeOnStart", invoke_on_start),
        (c"_InvokeOnEnd", invoke_on_end),
        (c"_InvokeOnSuspend", invoke_on_suspend),
        (c"_InvokeOnResume", invoke_on_resume),
        (c"_HandleEvent", handle_event),
        (c"_AskHere", ask_here),
    ];
    for (name, function) in methods {
        set_function(l, name, *function);
    }
    set_getter(l, c"GetActionBuriedUnderMe", "_buried");
    set_getter(l, c"IsSuspended", "_suspended");
    l.createtable(4, 0);
    l.pushcclosure(transition_change_to, 0);
    l.rawseti(-2, CHANGE_TO as c_int);
    l.pushcclosure(transition_suspend_for, 0);
    l.rawseti(-2, SUSPEND_FOR as c_int);
    l.pushcclosure(transition_done, 0);
    l.rawseti(-2, DONE as c_int);
    l.setfield(-2, c"transitions");
}

/// Adds the stacks to the module table at `module`: Action, Behavior, the timers
/// by the names actions use, and Chart, whose states are Actions.
pub(super) unsafe fn add_to(l: L, module: c_int) {
    l.pushnumber(SUSPEND_FOR);
    l.setfield(module, c"SUSPEND_FOR");
    timer::push_interval_unstarted(l);
    l.setfield(module, c"INTERVAL_UNSTARTED");
    timer::push_new(l, c"countdown");
    l.setfield(module, c"CountdownTimer");
    timer::push_new(l, c"interval");
    l.setfield(module, c"IntervalTimer");

    l.getfield(module, c"State");
    let state = l.gettop();
    push_action(l, state);
    l.setfield(module, c"Action");
    l.settop(state - 1);

    push_c(l, extend);
    l.getfield(module, c"Root");
    l.pushnil();
    l.call(2, 1);
    set_function(l, c"Stack", behavior_stack);
    set_function(l, c"_PurgeDeadActions", behavior_purge_dead_actions);
    l.setfield(module, c"Behavior");

    l.getfield(module, c"ChartsOf");
    l.createtable(0, 3);
    l.getfield(module, c"Action");
    l.setfield(-2, c"state");
    l.getfield(module, c"Behavior");
    l.setfield(-2, c"root");
    l.createtable(4, 0);
    for (i, name) in ["OnStart", "OnEnd", "OnSuspend", "OnResume"]
        .iter()
        .enumerate()
    {
        push_str(l, name);
        l.rawseti(-2, i as c_int + 1);
    }
    l.setfield(-2, c"lifecycle");
    l.call(1, 1);
    l.setfield(module, c"Chart");
}
