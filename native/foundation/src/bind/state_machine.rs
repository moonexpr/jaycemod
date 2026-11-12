//! generator.state_machine, native: a flat state machine, the Lua twin's
//! contract (foundation/generator/state_machine.lua). A definition and a
//! machine are tables, as the Lua twin's are (def: name, states (a named
//! set), edges, enter, leave, think, changing; machine: def, current), with
//! native metatables whose methods are C functions.

use super::util::boolean;
use crate::lua::{push_str, raise_where, set_function, string_at, tostring, L, TFUNCTION, TNIL, TTABLE};
use std::ffi::{c_int, CStr};

const DEFINITION: &CStr = c"foundation.generator.state_machine.definition";
const MACHINE: &CStr = c"foundation.generator.state_machine.machine";

unsafe fn metatable(l: L, name: &CStr, methods: &[(&CStr, crate::lua::CFunction)]) {
    if l.newmetatable(name) != 0 {
        l.pushvalue(-1);
        l.setfield(-2, c"__index");
        for (n, f) in methods {
            set_function(l, n, *f);
        }
    }
}

/// The definition's name, for refusals.
unsafe fn def_name(l: L, def: c_int) -> String {
    l.getfield(def, c"name");
    let name = tostring(l, -1);
    l.settop(-2);
    name
}

/// Whether the definition at `def` declares the state at `state`.
unsafe fn declares(l: L, def: c_int, state: c_int) -> bool {
    let top = l.gettop();
    let state = if state < 0 { top + state + 1 } else { state };
    l.getfield(def, c"states");
    let states = l.gettop();
    l.getfield(states, c"Has");
    l.pushvalue(states);
    l.pushvalue(state);
    l.call(2, 1);
    let has = l.toboolean(-1) != 0;
    l.settop(top);
    has
}

unsafe fn undeclared(l: L, def: c_int, state: c_int, where_: &str) -> ! {
    let name = def_name(l, def);
    let given = tostring(l, state);
    raise_where(l, format!("state machine {name}: {where_} names undeclared state {given}"))
}

/// Copies the handlers spec[kind] (state -> fn) into def[kind], checked.
unsafe fn handlers(l: L, def: c_int, spec: c_int, kind: &CStr) {
    l.createtable(0, 0);
    let out = l.gettop();
    l.getfield(spec, kind);
    let given = l.gettop();
    if l.type_of(given) == TTABLE {
        l.pushnil();
        while l.next(given) != 0 {
            let (state, f) = (l.gettop() - 1, l.gettop());
            let kind_name = kind.to_string_lossy();
            if !declares(l, def, state) {
                undeclared(l, def, state, &kind_name);
            }
            if l.type_of(f) != TFUNCTION {
                let (name, s) = (def_name(l, def), tostring(l, state));
                raise_where(l, format!("state machine {name}: {kind_name} for {s} is not a function"));
            }
            l.pushvalue(state);
            l.pushvalue(f);
            l.rawset(out);
            l.settop(-2);
        }
    }
    l.settop(out);
    l.setfield(def, kind);
}

/// generator.state_machine.Define(spec) -> a definition
unsafe extern "C-unwind" fn define(l: L) -> c_int {
    l.settop(1);
    l.checktype(1, TTABLE);
    l.getfield(1, c"name");
    let name_at = l.gettop();
    let Some(name) = string_at(l, name_at).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned()) else {
        let given = tostring(l, name_at);
        raise_where(l, format!("state machine {given}: needs a name"));
    };
    l.getfield(1, c"states");
    let states = l.gettop();
    if l.type_of(states) != TTABLE || l.objlen(states) == 0 {
        raise_where(l, format!("state machine {name}: declares no states"));
    }
    l.createtable(0, 8);
    let def = l.gettop();
    l.pushvalue(name_at);
    l.setfield(def, c"name");
    l.getfield(crate::lua::GLOBALSINDEX, c"world");
    l.getfield(-1, c"sets");
    l.getfield(-1, c"Named");
    push_str(l, &format!("state machine {name}"));
    l.pushvalue(states);
    l.call(2, 1);
    l.setfield(def, c"states");
    l.settop(def);
    l.getfield(1, c"transitions");
    let given = l.gettop();
    if l.type_of(given) == TTABLE {
        l.createtable(0, 0);
        let edges = l.gettop();
        l.pushnil();
        while l.next(given) != 0 {
            let (from, targets) = (l.gettop() - 1, l.gettop());
            if !declares(l, def, from) {
                undeclared(l, def, from, "transitions");
            }
            l.createtable(0, 0);
            let set = l.gettop();
            let mut i = 1;
            loop {
                l.rawgeti(targets, i);
                if l.type_of(-1) == TNIL {
                    l.settop(-2);
                    break;
                }
                if !declares(l, def, -1) {
                    let shown = tostring(l, from);
                    undeclared(l, def, l.gettop(), &format!("transitions from {shown}"));
                }
                l.pushboolean(1);
                l.rawset(set);
                i += 1;
            }
            l.pushvalue(from);
            l.insert(-2);
            l.rawset(edges);
            l.settop(targets - 1);
        }
        l.setfield(def, c"edges");
    }
    l.settop(def);
    for kind in [c"enter", c"leave", c"think"] {
        handlers(l, def, 1, kind);
    }
    l.getfield(1, c"changing");
    if l.type_of(-1) != TNIL && l.type_of(-1) != TFUNCTION {
        raise_where(l, format!("state machine {name}: changing is not a function"));
    }
    drop(name);
    l.setfield(def, c"changing");
    metatable(l, DEFINITION, &[(c"New", def_new)]);
    l.setmetatable(def);
    1
}

/// definition:New(initial) -> a machine
unsafe extern "C-unwind" fn def_new(l: L) -> c_int {
    l.settop(2);
    if !declares(l, 1, 2) {
        undeclared(l, 1, 2, "the initial state");
    }
    l.createtable(0, 2);
    l.pushvalue(1);
    l.setfield(-2, c"def");
    l.pushvalue(2);
    l.setfield(-2, c"current");
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
    l.setmetatable(-2);
    1
}

/// Pushes the machine at 1's definition; its index.
unsafe fn def_of(l: L) -> c_int {
    l.getfield(1, c"def");
    l.gettop()
}

unsafe extern "C-unwind" fn machine_state(l: L) -> c_int {
    l.getfield(1, c"current");
    1
}

unsafe extern "C-unwind" fn machine_is(l: L) -> c_int {
    l.settop(2);
    l.getfield(1, c"current");
    let same = l.equal(-1, 2) != 0;
    boolean(l, same)
}

/// Whether the machine at 1 may move to the state at `state`.
unsafe fn can(l: L, state: c_int) -> bool {
    let top = l.gettop();
    let def = def_of(l);
    if !declares(l, def, state) {
        l.settop(top);
        return false;
    }
    l.getfield(def, c"edges");
    if l.type_of(-1) == TNIL {
        l.settop(top);
        return true;
    }
    l.getfield(1, c"current");
    l.rawget(-2);
    if l.type_of(-1) != TTABLE {
        l.settop(top);
        return false;
    }
    l.pushvalue(state);
    l.rawget(-2);
    let ok = l.type_of(-1) == crate::lua::TBOOLEAN && l.toboolean(-1) != 0;
    l.settop(top);
    ok
}

unsafe extern "C-unwind" fn machine_can(l: L) -> c_int {
    l.settop(2);
    boolean(l, can(l, 2))
}

unsafe fn no_transition(l: L, state: c_int) -> ! {
    let def = def_of(l);
    let name = def_name(l, def);
    l.getfield(1, c"current");
    let from = tostring(l, -1);
    let to = tostring(l, state);
    raise_where(l, format!("state machine {name}: no transition from {from} to {to}"))
}

/// Calls def[kind][state at `state`](args from 3), when there is one.
unsafe fn handler(l: L, kind: &CStr, state: c_int, nargs: c_int) {
    let def = def_of(l);
    l.getfield(def, kind);
    l.pushvalue(state);
    l.rawget(-2);
    if l.type_of(-1) == TFUNCTION {
        for i in 0..nargs {
            l.pushvalue(3 + i);
        }
        l.call(nargs, 0);
    }
    l.settop(def - 1);
}

/// Into the state at 2: set, changing(from, to, ...), then its enter(...).
unsafe fn enter(l: L, nargs: c_int) {
    l.getfield(1, c"current");
    let from = l.gettop();
    l.pushvalue(2);
    l.setfield(1, c"current");
    let def = def_of(l);
    l.getfield(def, c"changing");
    if l.type_of(-1) == TFUNCTION {
        l.pushvalue(from);
        l.pushvalue(2);
        for i in 0..nargs {
            l.pushvalue(3 + i);
        }
        l.call(nargs + 2, 0);
    }
    l.settop(from - 1);
    handler(l, c"enter", 2, nargs);
}

unsafe extern "C-unwind" fn machine_enter(l: L) -> c_int {
    let nargs = (l.gettop() - 2).max(0);
    if l.gettop() < 2 {
        l.settop(2);
    }
    if !can(l, 2) {
        no_transition(l, 2);
    }
    enter(l, nargs);
    0
}

unsafe extern "C-unwind" fn machine_transition(l: L) -> c_int {
    let nargs = (l.gettop() - 2).max(0);
    if l.gettop() < 2 {
        l.settop(2);
    }
    if !can(l, 2) {
        no_transition(l, 2);
    }
    l.getfield(1, c"current");
    let current = l.gettop();
    let top = nargs + 2;
    // handler reads args from 3; the current state sits above them
    handler(l, c"leave", current, nargs);
    l.settop(top);
    enter(l, nargs);
    0
}

unsafe extern "C-unwind" fn machine_restore(l: L) -> c_int {
    l.settop(2);
    let def = def_of(l);
    if !declares(l, def, 2) {
        undeclared(l, def, 2, "a restored state");
    }
    l.pushvalue(2);
    l.setfield(1, c"current");
    0
}

unsafe extern "C-unwind" fn machine_think(l: L) -> c_int {
    let nargs = (l.gettop() - 1).max(0);
    l.getfield(1, c"current");
    let current = l.gettop();
    let def = def_of(l);
    l.getfield(def, c"think");
    l.pushvalue(current);
    l.rawget(-2);
    if l.type_of(-1) == TFUNCTION {
        for i in 0..nargs {
            l.pushvalue(2 + i);
        }
        l.call(nargs, 0);
    }
    0
}

/// Pushes the generator.state_machine module table.
pub unsafe fn push_module(l: L) {
    crate::module::push(l, &[(c"Define", define)], None);
}
