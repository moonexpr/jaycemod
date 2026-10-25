//! generator.state_machine, native: a flat state machine, the Lua twin's
//! contract (foundation/generator/state_machine.lua). A definition and a
//! machine are tables, as the Lua twin's are (def: name, states (a named
//! set), edges, enter, leave, think, changing; machine: def, current), with
//! native metatables whose methods are C functions.

use super::util::boolean;
use crate::lua::{api, push_str, raise_where, set_function, string_at, tostring, L, TFUNCTION, TNIL, TTABLE};
use std::ffi::{c_int, CStr};

const DEFINITION: &CStr = c"foundation.generator.state_machine.definition";
const MACHINE: &CStr = c"foundation.generator.state_machine.machine";

unsafe fn metatable(l: L, name: &CStr, methods: &[(&CStr, crate::lua::CFunction)]) {
    let api = api();
    if (api.newmetatable)(l, name.as_ptr()) != 0 {
        (api.pushvalue)(l, -1);
        (api.setfield)(l, -2, c"__index".as_ptr());
        for (n, f) in methods {
            set_function(l, n, *f);
        }
    }
}

/// The definition's name, for refusals.
unsafe fn def_name(l: L, def: c_int) -> String {
    let api = api();
    (api.getfield)(l, def, c"name".as_ptr());
    let name = tostring(l, -1);
    (api.settop)(l, -2);
    name
}

/// Whether the definition at `def` declares the state at `state`.
unsafe fn declares(l: L, def: c_int, state: c_int) -> bool {
    let api = api();
    let top = (api.gettop)(l);
    let state = if state < 0 { top + state + 1 } else { state };
    (api.getfield)(l, def, c"states".as_ptr());
    let states = (api.gettop)(l);
    (api.getfield)(l, states, c"Has".as_ptr());
    (api.pushvalue)(l, states);
    (api.pushvalue)(l, state);
    (api.call)(l, 2, 1);
    let has = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, top);
    has
}

unsafe fn undeclared(l: L, def: c_int, state: c_int, where_: &str) -> ! {
    let name = def_name(l, def);
    let given = tostring(l, state);
    raise_where(l, format!("state machine {name}: {where_} names undeclared state {given}"))
}

/// Copies the handlers spec[kind] (state -> fn) into def[kind], checked.
unsafe fn handlers(l: L, def: c_int, spec: c_int, kind: &CStr) {
    let api = api();
    (api.createtable)(l, 0, 0);
    let out = (api.gettop)(l);
    (api.getfield)(l, spec, kind.as_ptr());
    let given = (api.gettop)(l);
    if (api.type_of)(l, given) == TTABLE {
        (api.pushnil)(l);
        while (api.next)(l, given) != 0 {
            let (state, f) = ((api.gettop)(l) - 1, (api.gettop)(l));
            let kind_name = kind.to_string_lossy();
            if !declares(l, def, state) {
                undeclared(l, def, state, &kind_name);
            }
            if (api.type_of)(l, f) != TFUNCTION {
                let (name, s) = (def_name(l, def), tostring(l, state));
                raise_where(l, format!("state machine {name}: {kind_name} for {s} is not a function"));
            }
            (api.pushvalue)(l, state);
            (api.pushvalue)(l, f);
            (api.rawset)(l, out);
            (api.settop)(l, -2);
        }
    }
    (api.settop)(l, out);
    (api.setfield)(l, def, kind.as_ptr());
}

/// generator.state_machine.Define(spec) -> a definition
unsafe extern "C-unwind" fn define(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.checktype)(l, 1, TTABLE);
    (api.getfield)(l, 1, c"name".as_ptr());
    let name_at = (api.gettop)(l);
    let Some(name) = string_at(l, name_at).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned()) else {
        let given = tostring(l, name_at);
        raise_where(l, format!("state machine {given}: needs a name"));
    };
    (api.getfield)(l, 1, c"states".as_ptr());
    let states = (api.gettop)(l);
    if (api.type_of)(l, states) != TTABLE || (api.objlen)(l, states) == 0 {
        raise_where(l, format!("state machine {name}: declares no states"));
    }
    (api.createtable)(l, 0, 8);
    let def = (api.gettop)(l);
    (api.pushvalue)(l, name_at);
    (api.setfield)(l, def, c"name".as_ptr());
    (api.getfield)(l, crate::lua::GLOBALSINDEX, c"world".as_ptr());
    (api.getfield)(l, -1, c"sets".as_ptr());
    (api.getfield)(l, -1, c"Named".as_ptr());
    push_str(l, &format!("state machine {name}"));
    (api.pushvalue)(l, states);
    (api.call)(l, 2, 1);
    (api.setfield)(l, def, c"states".as_ptr());
    (api.settop)(l, def);
    (api.getfield)(l, 1, c"transitions".as_ptr());
    let given = (api.gettop)(l);
    if (api.type_of)(l, given) == TTABLE {
        (api.createtable)(l, 0, 0);
        let edges = (api.gettop)(l);
        (api.pushnil)(l);
        while (api.next)(l, given) != 0 {
            let (from, targets) = ((api.gettop)(l) - 1, (api.gettop)(l));
            if !declares(l, def, from) {
                undeclared(l, def, from, "transitions");
            }
            (api.createtable)(l, 0, 0);
            let set = (api.gettop)(l);
            let mut i = 1;
            loop {
                (api.rawgeti)(l, targets, i);
                if (api.type_of)(l, -1) == TNIL {
                    (api.settop)(l, -2);
                    break;
                }
                if !declares(l, def, -1) {
                    let shown = tostring(l, from);
                    undeclared(l, def, (api.gettop)(l), &format!("transitions from {shown}"));
                }
                (api.pushboolean)(l, 1);
                (api.rawset)(l, set);
                i += 1;
            }
            (api.pushvalue)(l, from);
            (api.insert)(l, -2);
            (api.rawset)(l, edges);
            (api.settop)(l, targets - 1);
        }
        (api.setfield)(l, def, c"edges".as_ptr());
    }
    (api.settop)(l, def);
    for kind in [c"enter", c"leave", c"think"] {
        handlers(l, def, 1, kind);
    }
    (api.getfield)(l, 1, c"changing".as_ptr());
    if (api.type_of)(l, -1) != TNIL && (api.type_of)(l, -1) != TFUNCTION {
        raise_where(l, format!("state machine {name}: changing is not a function"));
    }
    drop(name);
    (api.setfield)(l, def, c"changing".as_ptr());
    metatable(l, DEFINITION, &[(c"New", def_new)]);
    (api.setmetatable)(l, def);
    1
}

/// definition:New(initial) -> a machine
unsafe extern "C-unwind" fn def_new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if !declares(l, 1, 2) {
        undeclared(l, 1, 2, "the initial state");
    }
    (api.createtable)(l, 0, 2);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"def".as_ptr());
    (api.pushvalue)(l, 2);
    (api.setfield)(l, -2, c"current".as_ptr());
    metatable(
        l,
        MACHINE,
        &[
            (c"State", machine_state),
            (c"Is", machine_is),
            (c"Can", machine_can),
            (c"Enter", machine_enter),
            (c"Transition", machine_transition),
            (c"Restore", machine_restore),
            (c"Think", machine_think),
        ],
    );
    (api.setmetatable)(l, -2);
    1
}

/// Pushes the machine at 1's definition; its index.
unsafe fn def_of(l: L) -> c_int {
    (api().getfield)(l, 1, c"def".as_ptr());
    (api().gettop)(l)
}

unsafe extern "C-unwind" fn machine_state(l: L) -> c_int {
    (api().getfield)(l, 1, c"current".as_ptr());
    1
}

unsafe extern "C-unwind" fn machine_is(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.getfield)(l, 1, c"current".as_ptr());
    let same = (api.equal)(l, -1, 2) != 0;
    boolean(l, same)
}

/// Whether the machine at 1 may move to the state at `state`.
unsafe fn can(l: L, state: c_int) -> bool {
    let api = api();
    let top = (api.gettop)(l);
    let def = def_of(l);
    if !declares(l, def, state) {
        (api.settop)(l, top);
        return false;
    }
    (api.getfield)(l, def, c"edges".as_ptr());
    if (api.type_of)(l, -1) == TNIL {
        (api.settop)(l, top);
        return true;
    }
    (api.getfield)(l, 1, c"current".as_ptr());
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) != TTABLE {
        (api.settop)(l, top);
        return false;
    }
    (api.pushvalue)(l, state);
    (api.rawget)(l, -2);
    let ok = (api.type_of)(l, -1) == crate::lua::TBOOLEAN && (api.toboolean)(l, -1) != 0;
    (api.settop)(l, top);
    ok
}

unsafe extern "C-unwind" fn machine_can(l: L) -> c_int {
    (api().settop)(l, 2);
    boolean(l, can(l, 2))
}

unsafe fn no_transition(l: L, state: c_int) -> ! {
    let api = api();
    let def = def_of(l);
    let name = def_name(l, def);
    (api.getfield)(l, 1, c"current".as_ptr());
    let from = tostring(l, -1);
    let to = tostring(l, state);
    raise_where(l, format!("state machine {name}: no transition from {from} to {to}"))
}

/// Calls def[kind][state at `state`](args from 3), when there is one.
unsafe fn handler(l: L, kind: &CStr, state: c_int, nargs: c_int) {
    let api = api();
    let def = def_of(l);
    (api.getfield)(l, def, kind.as_ptr());
    (api.pushvalue)(l, state);
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) == TFUNCTION {
        for i in 0..nargs {
            (api.pushvalue)(l, 3 + i);
        }
        (api.call)(l, nargs, 0);
    }
    (api.settop)(l, def - 1);
}

/// Into the state at 2: set, changing(from, to, ...), then its enter(...).
unsafe fn enter(l: L, nargs: c_int) {
    let api = api();
    (api.getfield)(l, 1, c"current".as_ptr());
    let from = (api.gettop)(l);
    (api.pushvalue)(l, 2);
    (api.setfield)(l, 1, c"current".as_ptr());
    let def = def_of(l);
    (api.getfield)(l, def, c"changing".as_ptr());
    if (api.type_of)(l, -1) == TFUNCTION {
        (api.pushvalue)(l, from);
        (api.pushvalue)(l, 2);
        for i in 0..nargs {
            (api.pushvalue)(l, 3 + i);
        }
        (api.call)(l, nargs + 2, 0);
    }
    (api.settop)(l, from - 1);
    handler(l, c"enter", 2, nargs);
}

unsafe extern "C-unwind" fn machine_enter(l: L) -> c_int {
    let api = api();
    let nargs = ((api.gettop)(l) - 2).max(0);
    if (api.gettop)(l) < 2 {
        (api.settop)(l, 2);
    }
    if !can(l, 2) {
        no_transition(l, 2);
    }
    enter(l, nargs);
    0
}

unsafe extern "C-unwind" fn machine_transition(l: L) -> c_int {
    let api = api();
    let nargs = ((api.gettop)(l) - 2).max(0);
    if (api.gettop)(l) < 2 {
        (api.settop)(l, 2);
    }
    if !can(l, 2) {
        no_transition(l, 2);
    }
    (api.getfield)(l, 1, c"current".as_ptr());
    let current = (api.gettop)(l);
    let top = nargs + 2;
    // handler reads args from 3; the current state sits above them
    handler(l, c"leave", current, nargs);
    (api.settop)(l, top);
    enter(l, nargs);
    0
}

unsafe extern "C-unwind" fn machine_restore(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let def = def_of(l);
    if !declares(l, def, 2) {
        undeclared(l, def, 2, "a restored state");
    }
    (api.pushvalue)(l, 2);
    (api.setfield)(l, 1, c"current".as_ptr());
    0
}

unsafe extern "C-unwind" fn machine_think(l: L) -> c_int {
    let api = api();
    let nargs = ((api.gettop)(l) - 1).max(0);
    (api.getfield)(l, 1, c"current".as_ptr());
    let current = (api.gettop)(l);
    let def = def_of(l);
    (api.getfield)(l, def, c"think".as_ptr());
    (api.pushvalue)(l, current);
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) == TFUNCTION {
        for i in 0..nargs {
            (api.pushvalue)(l, 2 + i);
        }
        (api.call)(l, nargs, 0);
    }
    0
}

/// Pushes the generator.state_machine module table.
pub unsafe fn push_module(l: L) {
    crate::module::push(l, &[(c"Define", define)], None);
}
