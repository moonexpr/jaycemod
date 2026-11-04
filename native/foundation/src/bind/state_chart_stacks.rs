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
use crate::lua::{api, push_str, raise_owned, set_function, CFunction, L};
use std::ffi::{c_int, CStr};

// ActionResultType's stack entry, between state_chart's.
const SUSPEND_FOR: f64 = 2.0;

/// Pushes a C function, to call as a parent's method.
unsafe fn push_c(l: L, function: CFunction) {
    (api().pushcclosure)(l, function, 0);
}

unsafe fn set_nil(l: L, obj: c_int, name: &CStr) {
    let api = api();
    (api.pushnil)(l);
    (api.setfield)(l, obj, name.as_ptr());
}

unsafe fn set_flag(l: L, obj: c_int, name: &CStr, value: bool) {
    let api = api();
    (api.pushboolean)(l, value as c_int);
    (api.setfield)(l, obj, name.as_ptr());
}

/// Moves the action in `slot` on to the one buried under it.
unsafe fn to_buried(l: L, slot: c_int) {
    let api = api();
    (api.settop)(l, slot);
    (api.getfield)(l, slot, c"_buried".as_ptr());
    (api.replace)(l, slot);
}

// Action ----------------------------------------------------------------------------

unsafe extern "C-unwind" fn action_fields(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    push_c(l, state_fields);
    (api.pushvalue)(l, 1);
    (api.call)(l, 1, 1);
    set_flag(l, -2, c"_suspended", false);
    1
}

/// SuspendFor(action, reason): clears any pending event transition, or the new
/// action would at once be out of scope.
unsafe extern "C-unwind" fn suspend_for(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    shared(l, c"no_event");
    (api.setfield)(l, 1, c"_eventResult".as_ptr());
    push_result(l, SUSPEND_FOR, 2, 3, 0);
    1
}

/// TrySuspendFor(action, priority, reason).
unsafe extern "C-unwind" fn try_suspend_for(l: L) -> c_int {
    (api().settop)(l, 4);
    push_result(l, SUSPEND_FOR, 2, 4, or_try(l, 3));
    1
}

unsafe extern "C-unwind" fn requests_change(l: L) -> c_int {
    (api().settop)(l, 2);
    let change = field_is(l, 2, c"type", CHANGE_TO)
        || field_is(l, 2, c"type", SUSPEND_FOR)
        || field_is(l, 2, c"type", DONE);
    boolean(l, change)
}

/// Action::IsOutOfScope: a buried action leaving or changing makes me stale.
unsafe extern "C-unwind" fn is_out_of_scope(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"_buried".as_ptr());
    let under = 2;
    loop {
        if !truthy(l, under) {
            break;
        }
        (api.getfield)(l, under, c"_eventResult".as_ptr());
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
    let api = api();
    (api.settop)(l, 1);
    push_c(l, state_process_pending_events);
    (api.pushvalue)(l, 1);
    (api.call)(l, 1, 1);
    shared(l, c"continue");
    if (api.rawequal)(l, 2, 3) == 0 {
        (api.settop)(l, 2);
        return 1;
    }
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"_buried".as_ptr());
    let under = 2;
    loop {
        if !truthy(l, under) {
            break;
        }
        (api.getfield)(l, under, c"_eventResult".as_ptr());
        if field_is(l, 3, c"type", SUSPEND_FOR) {
            shared(l, c"no_event");
            (api.setfield)(l, under, c"_eventResult".as_ptr());
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
    let api = api();
    (api.settop)(l, 5);
    (api.pushvalue)(l, 5);
    (api.setfield)(l, 1, c"_buried".as_ptr());
    if truthy(l, 5) {
        (api.pushvalue)(l, 1);
        (api.setfield)(l, 5, c"_covering".as_ptr());
    }
    set_nil(l, 1, c"_covering");
    push_c(l, state_invoke_on_start);
    push_range(l, 1, 4);
    (api.call)(l, 4, 1);
    1
}

/// _InvokeOnEnd(me, behavior, nextAction): my children, top down, then me, then
/// whatever covers me.
unsafe extern "C-unwind" fn invoke_on_end(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    if !field_truthy(l, 1, c"_started") {
        return 0;
    }
    set_flag(l, 1, c"_started", false);
    (api.getfield)(l, 1, c"_child".as_ptr());
    let child = 5;
    loop {
        if !truthy(l, child) {
            break;
        }
        (api.getfield)(l, child, c"_buried".as_ptr());
        prep(l, child, c"_InvokeOnEnd");
        push_range(l, 2, 4);
        (api.call)(l, 4, 0);
        (api.replace)(l, child);
    }
    (api.settop)(l, 4);
    prep(l, 1, c"OnEnd");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 4);
    (api.call)(l, 3, 0);
    (api.getfield)(l, 1, c"_covering".as_ptr());
    if truthy(l, 5) {
        prep(l, 5, c"_InvokeOnEnd");
        push_range(l, 2, 4);
        (api.call)(l, 4, 0);
    }
    0
}

/// _InvokeOnSuspend(me, behavior, interruptingAction): returns the action now on
/// top, which is my buried one when OnSuspend asks to be Done instead.
unsafe extern "C-unwind" fn invoke_on_suspend(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.getfield)(l, 1, c"_child".as_ptr());
    if truthy(l, 5) {
        prep(l, 5, c"_InvokeOnSuspend");
        push_range(l, 2, 4);
        (api.call)(l, 4, 1);
        (api.setfield)(l, 1, c"_child".as_ptr());
    }
    (api.settop)(l, 4);
    set_flag(l, 1, c"_suspended", true);
    prep(l, 1, c"OnSuspend");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 4);
    (api.call)(l, 3, 1);
    if field_is(l, 5, c"type", DONE) {
        prep(l, 1, c"_InvokeOnEnd");
        (api.pushvalue)(l, 2);
        (api.pushvalue)(l, 3);
        (api.pushnil)(l);
        (api.call)(l, 4, 0);
        (api.getfield)(l, 1, c"_buried".as_ptr());
        prep(l, 3, c"_DestroyAction");
        (api.pushvalue)(l, 1);
        (api.call)(l, 2, 0);
        return 1;
    }
    (api.pushvalue)(l, 1);
    1
}

/// _InvokeOnResume(me, behavior, interruptingAction): skipped while a change
/// from an event is pending.
unsafe extern "C-unwind" fn invoke_on_resume(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    if !field_truthy(l, 1, c"_suspended") {
        shared(l, c"continue");
        return 1;
    }
    prep(l, 1, c"_RequestsChange");
    (api.getfield)(l, 1, c"_eventResult".as_ptr());
    (api.call)(l, 2, 1);
    if truthy(l, 5) {
        shared(l, c"continue");
        return 1;
    }
    (api.settop)(l, 4);
    set_flag(l, 1, c"_suspended", false);
    set_nil(l, 1, c"_covering");
    (api.getfield)(l, 1, c"_parent".as_ptr());
    if truthy(l, 5) {
        (api.pushvalue)(l, 1);
        (api.setfield)(l, 5, c"_child".as_ptr());
    }
    (api.settop)(l, 4);
    (api.getfield)(l, 1, c"_child".as_ptr());
    if truthy(l, 5) {
        prep(l, 5, c"_ApplyResult");
        (api.pushvalue)(l, 2);
        (api.pushvalue)(l, 3);
        prep(l, 5, c"_InvokeOnResume");
        push_range(l, 2, 4);
        (api.call)(l, 4, 1);
        (api.call)(l, 4, 1);
        (api.setfield)(l, 1, c"_child".as_ptr());
    }
    (api.settop)(l, 4);
    prep(l, 1, c"OnResume");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 4);
    (api.call)(l, 3, 1);
    1
}

/// Calls the action at `action`'s _ApplyResult(me, behavior, result at `result`),
/// leaving what it returns.
unsafe fn apply(l: L, action: c_int, result: c_int) {
    let api = api();
    prep(l, action, c"_ApplyResult");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, result);
    (api.call)(l, 4, 1);
}

/// transitions[CHANGE_TO](self, me, behavior, result): the new action takes my
/// parent and my buried action.
unsafe extern "C-unwind" fn transition_change_to(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.getfield)(l, 4, c"action".as_ptr());
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
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, next);
    (api.call)(l, 4, 0);
    prep(l, next, c"_InvokeOnStart");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, 1);
    (api.getfield)(l, 1, c"_buried".as_ptr());
    (api.call)(l, 5, 1);
    let started = 6;
    if (api.equal)(l, 1, next) == 0 {
        prep(l, 3, c"_DestroyAction");
        (api.pushvalue)(l, 1);
        (api.call)(l, 2, 0);
    }
    apply(l, next, started);
    1
}

/// transitions[SUSPEND_FOR]: the new action always goes on top of the stack.
unsafe extern "C-unwind" fn transition_suspend_for(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.getfield)(l, 4, c"action".as_ptr());
    let next = 5;
    (api.pushvalue)(l, 1);
    let top = 6;
    loop {
        (api.getfield)(l, top, c"_covering".as_ptr());
        if !truthy(l, -1) {
            (api.settop)(l, top);
            break;
        }
        (api.replace)(l, top);
    }
    prep(l, top, c"_InvokeOnSuspend");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, next);
    (api.call)(l, 4, 1);
    (api.replace)(l, top);
    prep(l, next, c"_InvokeOnStart");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, top);
    (api.pushvalue)(l, top);
    (api.call)(l, 5, 1);
    let started = 7;
    apply(l, next, started);
    1
}

/// transitions[DONE]: resume the buried action, or leave the stack empty.
unsafe extern "C-unwind" fn transition_done(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    (api.getfield)(l, 1, c"_buried".as_ptr());
    let resumed = 5;
    prep(l, 1, c"_InvokeOnEnd");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, resumed);
    (api.call)(l, 4, 0);
    prep(l, 3, c"_DestroyAction");
    (api.pushvalue)(l, 1);
    (api.call)(l, 2, 0);
    if is_nil(l, resumed) {
        (api.pushnil)(l);
        return 1;
    }
    prep(l, resumed, c"_InvokeOnResume");
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, 1);
    (api.call)(l, 4, 1);
    let result = 6;
    apply(l, resumed, result);
    1
}

/// _HandleEvent(name, ...), PROCESS_EVENT: the event walks me and the actions
/// buried under me while each continues; the first other result is stored on the
/// action that gave it.
unsafe extern "C-unwind" fn handle_event(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(2);
    (api.settop)(l, n);
    (api.getfield)(l, 1, c"_actor".as_ptr());
    let actor = n + 1;
    (api.pushvalue)(l, 1);
    let action = n + 2;
    let result = n + 3;
    loop {
        if !truthy(l, action) {
            break;
        }
        (api.pushvalue)(l, 2);
        (api.gettable)(l, action);
        if truthy(l, result) {
            (api.pushvalue)(l, action);
            (api.pushvalue)(l, actor);
            push_range(l, 3, n);
            (api.call)(l, n, 1);
        } else {
            (api.settop)(l, action);
            shared(l, c"continue");
        }
        if !field_is(l, result, c"type", CONTINUE) {
            prep(l, action, c"_StorePendingEventResult");
            (api.pushvalue)(l, result);
            (api.call)(l, 2, 0);
            return 0;
        }
        to_buried(l, action);
    }
    0
}

/// _AskHere(me, name, ...): a query asks me, then the actions buried under me.
unsafe extern "C-unwind" fn ask_here(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l).max(3);
    (api.settop)(l, n);
    (api.pushvalue)(l, 1);
    let current = n + 1;
    loop {
        if !truthy(l, current) {
            break;
        }
        push_c(l, state_ask_here);
        (api.pushvalue)(l, current);
        push_range(l, 2, n);
        (api.call)(l, n, 1);
        if !is_nil(l, -1) {
            return 1;
        }
        to_buried(l, current);
    }
    (api.pushnil)(l);
    1
}

// Behavior --------------------------------------------------------------------------

/// Appends { name, short, depth, suspended, passthrough } for the action at
/// `start`, the actions it contains a level deeper, then those buried under it:
/// Action::DebugString's order.
unsafe fn stack_frames(l: L, start: c_int, depth: f64, frames: c_int) {
    let api = api();
    let base = (api.gettop)(l);
    (api.pushvalue)(l, start);
    let action = base + 1;
    loop {
        if !truthy(l, action) {
            break;
        }
        (api.createtable)(l, 0, 5);
        (api.getfield)(l, action, c"name".as_ptr());
        (api.setfield)(l, -2, c"name".as_ptr());
        (api.getfield)(l, action, c"shortName".as_ptr());
        if !truthy(l, -1) {
            (api.settop)(l, -2);
            (api.getfield)(l, action, c"name".as_ptr());
        }
        (api.setfield)(l, -2, c"short".as_ptr());
        (api.pushnumber)(l, depth);
        (api.setfield)(l, -2, c"depth".as_ptr());
        (api.getfield)(l, action, c"_suspended".as_ptr());
        (api.setfield)(l, -2, c"suspended".as_ptr());
        (api.getfield)(l, action, c"passthrough".as_ptr());
        (api.setfield)(l, -2, c"passthrough".as_ptr());
        append(l, frames);
        (api.getfield)(l, action, c"_child".as_ptr());
        if truthy(l, -1) {
            let child = (api.gettop)(l);
            stack_frames(l, child, depth + 1.0, frames);
        }
        to_buried(l, action);
    }
    (api.settop)(l, base);
}

unsafe extern "C-unwind" fn behavior_stack(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, 1, c"action".as_ptr());
    (api.createtable)(l, 0, 0);
    stack_frames(l, 2, 1.0, 3);
    1
}

/// _PurgeDeadActions, as ~Action: a dead action's parent's active child falls
/// back to its buried action, and its buried action is no longer covered.
unsafe extern "C-unwind" fn behavior_purge_dead_actions(l: L) -> c_int {
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
                (api.getfield)(l, 3, c"_buried".as_ptr());
                (api.setfield)(l, 4, c"_child".as_ptr());
            }
        }
        (api.settop)(l, 3);
        (api.getfield)(l, 3, c"_buried".as_ptr());
        if truthy(l, 4) {
            set_nil(l, 4, c"_covering");
        }
        (api.settop)(l, 2);
        i += 1;
    }
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, 1, c"dead".as_ptr());
    0
}

// The module ------------------------------------------------------------------------

/// Pushes Action: core.class's Extend of the State at `state`.
unsafe fn push_action(l: L, state: c_int) {
    let api = api();
    push_c(l, extend);
    (api.pushvalue)(l, state);
    (api.createtable)(l, 0, 2);
    push_str(l, "Action");
    (api.setfield)(l, -2, c"name".as_ptr());
    (api.pushboolean)(l, 0);
    (api.setfield)(l, -2, c"passthrough".as_ptr());
    (api.call)(l, 2, 1);
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
    (api.createtable)(l, 4, 0);
    (api.pushcclosure)(l, transition_change_to, 0);
    (api.rawseti)(l, -2, CHANGE_TO as c_int);
    (api.pushcclosure)(l, transition_suspend_for, 0);
    (api.rawseti)(l, -2, SUSPEND_FOR as c_int);
    (api.pushcclosure)(l, transition_done, 0);
    (api.rawseti)(l, -2, DONE as c_int);
    (api.setfield)(l, -2, c"transitions".as_ptr());
}

/// Adds the stacks to the module table at `module`: Action, Behavior, the timers
/// by the names actions use, and Chart, whose states are Actions.
pub(super) unsafe fn add_to(l: L, module: c_int) {
    let api = api();
    (api.pushnumber)(l, SUSPEND_FOR);
    (api.setfield)(l, module, c"SUSPEND_FOR".as_ptr());
    timer::push_interval_unstarted(l);
    (api.setfield)(l, module, c"INTERVAL_UNSTARTED".as_ptr());
    timer::push_new(l, c"countdown");
    (api.setfield)(l, module, c"CountdownTimer".as_ptr());
    timer::push_new(l, c"interval");
    (api.setfield)(l, module, c"IntervalTimer".as_ptr());

    (api.getfield)(l, module, c"State".as_ptr());
    let state = (api.gettop)(l);
    push_action(l, state);
    (api.setfield)(l, module, c"Action".as_ptr());
    (api.settop)(l, state - 1);

    push_c(l, extend);
    (api.getfield)(l, module, c"Root".as_ptr());
    (api.pushnil)(l);
    (api.call)(l, 2, 1);
    set_function(l, c"Stack", behavior_stack);
    set_function(l, c"_PurgeDeadActions", behavior_purge_dead_actions);
    (api.setfield)(l, module, c"Behavior".as_ptr());

    (api.getfield)(l, module, c"ChartsOf".as_ptr());
    (api.createtable)(l, 0, 3);
    (api.getfield)(l, module, c"Action".as_ptr());
    (api.setfield)(l, -2, c"state".as_ptr());
    (api.getfield)(l, module, c"Behavior".as_ptr());
    (api.setfield)(l, -2, c"root".as_ptr());
    (api.createtable)(l, 4, 0);
    for (i, name) in ["OnStart", "OnEnd", "OnSuspend", "OnResume"]
        .iter()
        .enumerate()
    {
        push_str(l, name);
        (api.rawseti)(l, -2, i as c_int + 1);
    }
    (api.setfield)(l, -2, c"lifecycle".as_ptr());
    (api.call)(l, 1, 1);
    (api.setfield)(l, module, c"Chart".as_ptr());
}
