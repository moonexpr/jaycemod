//! core.class, core.port, core.constants and core.enum, native: the Lua
//! twins' contracts (foundation/core/). These are mechanisms over Lua
//! tables, so the native ones make and work on tables too, their metamethods
//! and methods C functions: a constant set is still a plain table whose
//! constants are raw fields, read at plain-table speed. Each set's own state
//! (name, count, numbering) is kept in a weak-keyed table in the registry,
//! apart from its constants, as the Lua twins keep it apart.

use super::util::{boolean, each_item, nothing, number};
use crate::lua::{api, push_str, raise_at, raise_where, set_function, string_at, tostring, L, TFUNCTION, TNIL, TNUMBER, TSTRING, TTABLE};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;

fn upvalue(i: c_int) -> c_int {
    crate::lua::GLOBALSINDEX - i
}

/// Pushes the registry's weak-keyed table `name`, made the first time.
unsafe fn weak_table(l: L, name: &CStr) {
    let api = api();
    (api.getfield)(l, REGISTRY, name.as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.createtable)(l, 0, 0);
    (api.createtable)(l, 0, 1);
    push_str(l, "k");
    (api.setfield)(l, -2, c"__mode".as_ptr());
    (api.setmetatable)(l, -2);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, name.as_ptr());
}

/// Pushes registry table `name`[value at `key`].
unsafe fn state_of(l: L, name: &CStr, key: c_int) {
    let api = api();
    let key = if key < 0 { (api.gettop)(l) + key + 1 } else { key };
    weak_table(l, name);
    (api.pushvalue)(l, key);
    (api.rawget)(l, -2);
    (api.remove)(l, -2);
}

// core.class -----------------------------------------------------------------

/// The metamethods a subclass copies from its parent: Lua reads an
/// instance's metamethods from its class alone, never through __index.
const INHERITED: &[&CStr] = &[
    c"__newindex",
    c"__call",
    c"__tostring",
    c"__len",
    c"__eq",
    c"__lt",
    c"__le",
    c"__concat",
    c"__unm",
    c"__add",
    c"__sub",
    c"__mul",
    c"__div",
    c"__mod",
    c"__pow",
];

/// class.Extend(parent, fields) -> a class
pub(super) unsafe extern "C-unwind" fn extend(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let has_parent = (api.type_of)(l, 1) == TTABLE;
    (api.createtable)(l, 0, 4);
    let class = (api.gettop)(l);
    if has_parent {
        for name in INHERITED {
            push_str(l, &name.to_string_lossy());
            (api.rawget)(l, 1);
            if (api.type_of)(l, -1) != TNIL {
                push_str(l, &name.to_string_lossy());
                (api.insert)(l, -2);
                (api.rawset)(l, class);
            } else {
                (api.settop)(l, -2);
            }
        }
        push_str(l, "__index");
        (api.rawget)(l, 1);
        if (api.rawequal)(l, -1, 1) == 0 {
            push_str(l, "__index");
            (api.insert)(l, -2);
            (api.rawset)(l, class);
        } else {
            (api.settop)(l, -2);
        }
    }
    if (api.type_of)(l, 2) == TTABLE {
        (api.pushnil)(l);
        while (api.next)(l, 2) != 0 {
            (api.pushvalue)(l, -2);
            (api.insert)(l, -2);
            (api.rawset)(l, class);
        }
    }
    push_str(l, "__index");
    (api.rawget)(l, class);
    let own_index = (api.type_of)(l, -1) != TNIL;
    (api.settop)(l, -2);
    if !own_index {
        push_str(l, "__index");
        (api.pushvalue)(l, class);
        (api.rawset)(l, class);
    }
    if has_parent {
        (api.pushvalue)(l, 1);
        (api.setmetatable)(l, class);
    }
    1
}

/// class.New(class, fields) -> an instance
unsafe extern "C-unwind" fn new_instance(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.type_of)(l, 2) != TTABLE {
        (api.settop)(l, 1);
        (api.createtable)(l, 0, 0);
    }
    (api.pushvalue)(l, 1);
    (api.setmetatable)(l, 2);
    1
}

/// class.IsA(value, class) -> whether class is value's class or an ancestor
unsafe extern "C-unwind" fn is_a(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.type_of)(l, 1) != TTABLE {
        return boolean(l, false);
    }
    (api.pushvalue)(l, 1);
    while (api.getmetatable)(l, -1) != 0 {
        if (api.equal)(l, -1, 2) != 0 {
            return boolean(l, true);
        }
        (api.remove)(l, -2);
    }
    boolean(l, false)
}

/// A guard's __newindex: upvalue 1 the check; refusals blame the assignment.
unsafe extern "C-unwind" fn guarded_newindex(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    (api.pushvalue)(l, upvalue(1));
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 3);
    (api.call)(l, 2, 1);
    if (api.toboolean)(l, -1) != 0 {
        if (api.type_of)(l, -1) == TSTRING || (api.type_of)(l, -1) == TNUMBER {
            let why = tostring(l, -1);
            raise_where(l, why);
        }
        (api.error)(l);
    }
    (api.settop)(l, 3);
    (api.rawset)(l, 1);
    0
}

/// class.Guard(class, check) -> class
unsafe extern "C-unwind" fn guard(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    push_str(l, "__newindex");
    (api.pushvalue)(l, 2);
    (api.pushcclosure)(l, guarded_newindex, 1);
    (api.rawset)(l, 1);
    (api.pushvalue)(l, 1);
    1
}

/// Pushes the own methods called `name` along the line of classes from the
/// class at `class`, most derived first, as a list; its index.
unsafe fn line(l: L, class: c_int, name: &str) -> c_int {
    let api = api();
    (api.createtable)(l, 0, 0);
    let list = (api.gettop)(l);
    let mut n = 0;
    (api.pushvalue)(l, class);
    while (api.type_of)(l, -1) == TTABLE {
        push_str(l, name);
        (api.rawget)(l, -2);
        if (api.toboolean)(l, -1) != 0 {
            n += 1;
            (api.rawseti)(l, list, n);
        } else {
            (api.settop)(l, -2);
        }
        if (api.getmetatable)(l, -1) == 0 {
            (api.pushnil)(l);
        }
        (api.remove)(l, -2);
    }
    (api.settop)(l, list);
    list
}

/// class.Construct(class, ...) -> a new instance, each own Init run base first
unsafe extern "C-unwind" fn construct(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let instance = (api.gettop)(l);
    (api.pushvalue)(l, 1);
    (api.setmetatable)(l, instance);
    let inits = line(l, 1, "Init");
    let count = (api.objlen)(l, inits) as c_int;
    for i in (1..=count).rev() {
        (api.rawgeti)(l, inits, i);
        (api.pushvalue)(l, instance);
        for a in 2..=n {
            (api.pushvalue)(l, a);
        }
        (api.call)(l, n, 0);
    }
    (api.pushvalue)(l, instance);
    1
}

/// class.Destroy(instance, ...): each own Destroy, most derived first
pub(super) unsafe extern "C-unwind" fn destroy(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l);
    if (api.getmetatable)(l, 1) == 0 {
        (api.pushnil)(l);
    }
    let class = (api.gettop)(l);
    let destroys = line(l, class, "Destroy");
    let mut i = 1;
    loop {
        (api.rawgeti)(l, destroys, i);
        if (api.type_of)(l, -1) == TNIL {
            break;
        }
        for a in 1..=n {
            (api.pushvalue)(l, a);
        }
        (api.call)(l, n, 0);
        i += 1;
    }
    0
}

// core.port --------------------------------------------------------------------

const PORT_META: &CStr = c"foundation.core.port";

/// Pushes the port metatable (methods by name, __index itself).
unsafe fn port_meta(l: L) {
    let api = api();
    if (api.newmetatable)(l, PORT_META.as_ptr()) != 0 {
        (api.pushvalue)(l, -1);
        (api.setfield)(l, -2, c"__index".as_ptr());
        set_function(l, c"Check", port_check);
        set_function(l, c"Facade", port_facade);
        set_function(l, c"Methods", port_methods);
        set_function(l, c"Name", port_name);
    }
}

/// port.New(name, methods) -> a port
pub(super) unsafe extern "C-unwind" fn port_new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let name = string_at(l, 1).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned());
    let Some(name) = name else {
        let given = tostring(l, 1);
        raise_where(l, format!("a port needs a name, not {given}"));
    };
    if (api.type_of)(l, 2) != TTABLE {
        raise_where(l, format!("port {name} needs a list of methods"));
    }
    let mut problem = None;
    let mut seen = std::collections::HashSet::new();
    let mut count = 0;
    each_item(l, 2, |l, m| {
        if problem.is_some() {
            return;
        }
        count += 1;
        match string_at(l, m) {
            None => problem = Some(format!("port {name} has a non-name: {}", tostring(l, m))),
            Some(s) => {
                let s = s.to_vec();
                if !seen.insert(s.clone()) {
                    let shown = String::from_utf8_lossy(&s);
                    problem = Some(format!("named set port {name}: port {name}: lists {shown} twice"));
                }
            }
        }
    });
    drop(seen);
    if let Some(problem) = problem {
        drop(name);
        raise_where(l, problem);
    }
    if count == 0 {
        raise_where(l, format!("port {name} declares no methods"));
    }
    drop(name);
    (api.createtable)(l, 0, 2);
    let port = (api.gettop)(l);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, port, c"name".as_ptr());
    (api.createtable)(l, 0, 0);
    let list = (api.gettop)(l);
    let mut n = 0;
    each_item(l, 2, |l, m| {
        n += 1;
        (api.pushvalue)(l, m);
        (api.rawseti)(l, list, n);
    });
    (api.setfield)(l, port, c"methods".as_ptr());
    port_meta(l);
    (api.setmetatable)(l, port);
    1
}

/// port.Is(value) -> whether value is a port
unsafe extern "C-unwind" fn port_is(l: L) -> c_int {
    let api = api();
    if (api.getmetatable)(l, 1) == 0 {
        return boolean(l, false);
    }
    port_meta(l);
    let same = (api.rawequal)(l, -1, -2) != 0;
    boolean(l, same)
}

/// Pushes the port at 1's method list.
unsafe fn methods_of(l: L) -> c_int {
    let api = api();
    (api.getfield)(l, 1, c"methods".as_ptr());
    (api.gettop)(l)
}

pub(super) unsafe extern "C-unwind" fn port_check(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let list = methods_of(l);
    let mut missing = Vec::new();
    each_item(l, list, |l, m| {
        (api.pushvalue)(l, m);
        (api.gettable)(l, 2);
        if (api.type_of)(l, -1) != TFUNCTION {
            missing.push(tostring(l, m));
        }
    });
    if !missing.is_empty() {
        (api.getfield)(l, 1, c"name".as_ptr());
        let name = tostring(l, -1);
        let text = format!("value is not a {name}: no {}", missing.join(", "));
        drop(missing);
        drop(name);
        raise_at(l, 2, text);
    }
    (api.pushvalue)(l, 2);
    1
}

/// A facade's method: upvalue 1 the value, 2 the method's name.
unsafe extern "C-unwind" fn facade_call(l: L) -> c_int {
    let api = api();
    let n = (api.gettop)(l);
    (api.pushvalue)(l, upvalue(1));
    (api.pushvalue)(l, upvalue(2));
    (api.gettable)(l, -2);
    (api.insert)(l, 2);
    (api.insert)(l, 3);
    // stack: facade, fn, value, args...
    (api.call)(l, n, -1);
    (api.gettop)(l) - 1
}

unsafe extern "C-unwind" fn port_facade(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let list = methods_of(l);
    (api.createtable)(l, 0, 0);
    let facade = (api.gettop)(l);
    each_item(l, list, |l, m| {
        (api.pushvalue)(l, m);
        (api.pushvalue)(l, 2);
        (api.pushvalue)(l, m);
        (api.pushcclosure)(l, facade_call, 2);
        (api.rawset)(l, facade);
    });
    1
}

unsafe extern "C-unwind" fn port_methods(l: L) -> c_int {
    let api = api();
    let list = methods_of(l);
    (api.createtable)(l, 0, 0);
    let copy = (api.gettop)(l);
    let mut n = 0;
    each_item(l, list, |l, m| {
        n += 1;
        (api.pushvalue)(l, m);
        (api.rawseti)(l, copy, n);
    });
    1
}

unsafe extern "C-unwind" fn port_name(l: L) -> c_int {
    (api().getfield)(l, 1, c"name".as_ptr());
    1
}

// core.constants ----------------------------------------------------------------

const SET_STATE: &CStr = c"foundation.core.constants.state";

/// The name of the set at `set`, or tostring of it.
unsafe fn set_name(l: L, set: c_int) -> String {
    let api = api();
    state_of(l, SET_STATE, set);
    if (api.type_of)(l, -1) == TTABLE {
        (api.getfield)(l, -1, c"name".as_ptr());
        let name = tostring(l, -1);
        (api.settop)(l, -3);
        return name;
    }
    (api.settop)(l, -2);
    tostring(l, set)
}

/// A set's __index: a method along its classes, or the reader's error.
unsafe extern "C-unwind" fn set_lookup(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.getmetatable)(l, 1) == 0 {
        (api.pushnil)(l);
    }
    while (api.type_of)(l, -1) == TTABLE {
        (api.pushvalue)(l, 2);
        (api.rawget)(l, -2);
        if (api.type_of)(l, -1) != TNIL {
            return 1;
        }
        (api.settop)(l, -2);
        if (api.getmetatable)(l, -1) == 0 {
            (api.pushnil)(l);
        }
        (api.remove)(l, -2);
    }
    let name = set_name(l, 1);
    let key = tostring(l, 2);
    raise_where(l, format!("{name}: no constant {key}"))
}

unsafe extern "C-unwind" fn set_fixed(l: L) -> c_int {
    let name = set_name(l, 1);
    let key = tostring(l, 2);
    raise_where(l, format!("{name}: constants are fixed, no new {key}"))
}

unsafe extern "C-unwind" fn set_parse(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.type_of)(l, 2) == TNIL {
        return nothing(l);
    }
    (api.rawget)(l, 1);
    1
}

unsafe extern "C-unwind" fn set_tostring(l: L) -> c_int {
    let api = api();
    state_of(l, SET_STATE, 1);
    if (api.type_of)(l, -1) != TTABLE {
        return nothing(l);
    }
    (api.getfield)(l, -1, c"name".as_ptr());
    1
}

unsafe extern "C-unwind" fn set_len(l: L) -> c_int {
    let api = api();
    state_of(l, SET_STATE, 1);
    (api.getfield)(l, -1, c"count".as_ptr());
    1
}

fn is_constant_name(s: &[u8]) -> bool {
    !s.is_empty() && s[0].is_ascii_uppercase() && s.iter().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || *c == b'_')
}

/// ConstantSet:Init(name, constants), blaming New's caller (three calls up:
/// Init, Construct, New).
unsafe extern "C-unwind" fn set_init(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    let name = string_at(l, 2).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned());
    let Some(name) = name else { raise_at(l, 3, "a constant set needs a name".into()) };
    let empty = (api.type_of)(l, 3) != TTABLE || {
        (api.pushnil)(l);
        let any = (api.next)(l, 3) != 0;
        if any {
            (api.settop)(l, -3);
        }
        !any
    };
    if empty {
        raise_at(l, 3, format!("{name}: a constant set needs constants"));
    }
    let mut count = 0.0;
    let mut bad = None;
    (api.pushnil)(l);
    while (api.next)(l, 3) != 0 {
        let ok = (api.type_of)(l, -2) == TSTRING && string_at(l, -2).is_some_and(is_constant_name);
        if !ok && bad.is_none() {
            bad = Some(tostring(l, -2));
        }
        if ok {
            (api.pushvalue)(l, -2);
            (api.insert)(l, -2);
            (api.rawset)(l, 1);
            count += 1.0;
        } else {
            (api.settop)(l, -2);
        }
    }
    if let Some(key) = bad {
        raise_at(l, 3, format!("{name}: a constant's name is upper case, not {key}"));
    }
    weak_table(l, SET_STATE);
    (api.pushvalue)(l, 1);
    (api.createtable)(l, 0, 2);
    push_str(l, &name);
    (api.setfield)(l, -2, c"name".as_ptr());
    (api.pushnumber)(l, count);
    (api.setfield)(l, -2, c"count".as_ptr());
    (api.rawset)(l, -3);
    0
}

unsafe extern "C-unwind" fn set_has(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.type_of)(l, 2) == TNIL {
        return boolean(l, false);
    }
    (api.rawget)(l, 1);
    let has = (api.type_of)(l, -1) != TNIL;
    boolean(l, has)
}

unsafe extern "C-unwind" fn set_names(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.createtable)(l, 0, 0);
    let names = (api.gettop)(l);
    let mut n = 0;
    (api.pushnil)(l);
    while (api.next)(l, 1) != 0 {
        (api.settop)(l, -2);
        n += 1;
        (api.pushvalue)(l, -1);
        (api.rawseti)(l, names, n);
    }
    (api.getfield)(l, crate::lua::GLOBALSINDEX, c"table".as_ptr());
    (api.getfield)(l, -1, c"sort".as_ptr());
    (api.pushvalue)(l, names);
    (api.call)(l, 1, 0);
    (api.settop)(l, names);
    1
}

/// Calls core.class.Construct on the class at `class` with the arguments at
/// `first`..top, as the Lua twin's New does through Class.Construct.
pub(super) unsafe fn construct_through(l: L, class: c_int, first: c_int) -> c_int {
    let api = api();
    let top = (api.gettop)(l);
    (api.pushcclosure)(l, construct, 0);
    (api.pushvalue)(l, class);
    for i in first..=top {
        (api.pushvalue)(l, i);
    }
    (api.call)(l, top - first + 2, 1);
    1
}

/// Pushes the ConstantSet class.
unsafe fn constant_set_class(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.core.constants.ConstantSet".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.createtable)(l, 0, 10);
    set_function(l, c"__index", set_lookup);
    set_function(l, c"__newindex", set_fixed);
    set_function(l, c"__call", set_parse);
    set_function(l, c"__tostring", set_tostring);
    set_function(l, c"__len", set_len);
    set_function(l, c"Name", set_tostring);
    set_function(l, c"Init", set_init);
    set_function(l, c"Has", set_has);
    set_function(l, c"Names", set_names);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.core.constants.ConstantSet".as_ptr());
}

/// constants.New(name, constants) -> a constant set
unsafe extern "C-unwind" fn constants_new(l: L) -> c_int {
    (api().settop)(l, 2);
    constant_set_class(l);
    (api().insert)(l, 1);
    construct_through(l, 1, 2)
}

// core.enum ----------------------------------------------------------------------

const ENUM_STATE: &CStr = c"foundation.core.enum.state";

/// Pushes the enumeration at 1's state { first, names, byValue }; its index.
unsafe fn enum_state(l: L) -> c_int {
    state_of(l, ENUM_STATE, 1);
    (api().gettop)(l)
}

unsafe extern "C-unwind" fn enum_index(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.type_of)(l, 2) == TNUMBER {
        let state = enum_state(l);
        (api.getfield)(l, state, c"byValue".as_ptr());
        (api.pushvalue)(l, 2);
        (api.rawget)(l, -2);
        return 1;
    }
    set_lookup(l)
}

/// The value the token at 2 stands for, pushed (or nil).
unsafe fn enum_parse_value(l: L) {
    let api = api();
    if (api.type_of)(l, 2) == TNUMBER {
        let state = enum_state(l);
        (api.getfield)(l, state, c"byValue".as_ptr());
        (api.pushvalue)(l, 2);
        (api.rawget)(l, -2);
        let known = (api.type_of)(l, -1) != TNIL;
        (api.settop)(l, state - 1);
        if known {
            (api.pushvalue)(l, 2);
        } else {
            (api.pushnil)(l);
        }
        return;
    }
    if (api.type_of)(l, 2) == TNIL {
        (api.pushnil)(l);
        return;
    }
    (api.pushvalue)(l, 2);
    (api.rawget)(l, 1);
}

unsafe extern "C-unwind" fn enum_call(l: L) -> c_int {
    (api().settop)(l, 2);
    enum_parse_value(l);
    1
}

unsafe fn enum_count(l: L) -> usize {
    let api = api();
    let state = enum_state(l);
    (api.getfield)(l, state, c"names".as_ptr());
    let n = (api.objlen)(l, -1);
    (api.settop)(l, state - 1);
    n
}

unsafe extern "C-unwind" fn enum_len(l: L) -> c_int {
    number(l, enum_count(l) as f64)
}

/// A name in words: TEAM_RED -> "Team red".
fn words(name: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(name.len());
    if let Some((&first, rest)) = name.split_first() {
        out.push(first);
        out.extend(rest.iter().map(|&c| if c == b'_' { b' ' } else { c.to_ascii_lowercase() }));
    }
    out
}

unsafe extern "C-unwind" fn enum_describe(l: L) -> c_int {
    let api = api();
    let state = enum_state(l);
    (api.getfield)(l, state, c"first".as_ptr());
    let first = (api.tonumber)(l, -1);
    (api.getfield)(l, state, c"names".as_ptr());
    let names = (api.gettop)(l);
    let mut parts: Vec<Vec<u8>> = Vec::new();
    let mut i = 0.0;
    each_item(l, names, |l, n| {
        let mut part = tostring(l, {
            (api.pushnumber)(l, first + i);
            -1
        })
        .into_bytes();
        (api.settop)(l, -2);
        part.push(b' ');
        part.extend(words(string_at(l, n).unwrap_or_default()));
        parts.push(part);
        i += 1.0;
    });
    let text = parts.join(&b", "[..]);
    drop(parts);
    (api.pushlstring)(l, text.as_ptr().cast(), text.len());
    drop(text);
    1
}

/// Enum's Init(self, name, constants, names, first): its numbering.
unsafe extern "C-unwind" fn enum_init(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 5);
    let first = (api.tonumber)(l, 5);
    (api.createtable)(l, 0, 3);
    let state = (api.gettop)(l);
    (api.pushvalue)(l, 5);
    (api.setfield)(l, state, c"first".as_ptr());
    (api.pushvalue)(l, 4);
    (api.setfield)(l, state, c"names".as_ptr());
    (api.createtable)(l, 0, 0);
    let by_value = (api.gettop)(l);
    let mut i = 0.0;
    each_item(l, 4, |l, name| {
        (api.pushnumber)(l, first + i);
        (api.pushvalue)(l, name);
        (api.rawset)(l, by_value);
        i += 1.0;
    });
    (api.setfield)(l, state, c"byValue".as_ptr());
    weak_table(l, ENUM_STATE);
    (api.pushvalue)(l, 1);
    (api.pushvalue)(l, state);
    (api.rawset)(l, -3);
    0
}

unsafe extern "C-unwind" fn enum_name_of(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let state = enum_state(l);
    (api.getfield)(l, state, c"byValue".as_ptr());
    (api.pushvalue)(l, 2);
    (api.rawget)(l, -2);
    1
}

unsafe extern "C-unwind" fn enum_valid(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    enum_parse_value(l);
    let valid = (api.type_of)(l, -1) != TNIL;
    boolean(l, valid)
}

unsafe extern "C-unwind" fn enum_check(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let ok = (api.type_of)(l, 2) == TNUMBER && {
        enum_parse_value(l);
        let v = (api.type_of)(l, -1) != TNIL;
        (api.settop)(l, 2);
        v
    };
    if !ok {
        let name = set_name(l, 1);
        let value = tostring(l, 2);
        raise_where(l, format!("{name}: no value {value}"));
    }
    (api.pushvalue)(l, 2);
    1
}

unsafe extern "C-unwind" fn enum_first(l: L) -> c_int {
    let state = enum_state(l);
    (api().getfield)(l, state, c"first".as_ptr());
    1
}

unsafe extern "C-unwind" fn enum_last(l: L) -> c_int {
    let count = enum_count(l) as f64;
    let api = api();
    let state = enum_state(l);
    (api.getfield)(l, state, c"first".as_ptr());
    let first = (api.tonumber)(l, -1);
    number(l, first + count - 1.0)
}

unsafe extern "C-unwind" fn enum_names(l: L) -> c_int {
    let api = api();
    let state = enum_state(l);
    (api.getfield)(l, state, c"names".as_ptr());
    let names = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let copy = (api.gettop)(l);
    let mut n = 0;
    each_item(l, names, |l, name| {
        n += 1;
        (api.pushvalue)(l, name);
        (api.rawseti)(l, copy, n);
    });
    1
}

/// Pushes the Enum class (extending ConstantSet).
unsafe fn enum_class(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.core.enum.Enum".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    constant_set_class(l);
    let parent = (api.gettop)(l);
    (api.createtable)(l, 0, 16);
    for name in INHERITED {
        (api.getfield)(l, parent, name.as_ptr());
        if (api.type_of)(l, -1) != TNIL {
            (api.setfield)(l, -2, name.as_ptr());
        } else {
            (api.settop)(l, -2);
        }
    }
    set_function(l, c"__index", enum_index);
    set_function(l, c"__call", enum_call);
    set_function(l, c"__len", enum_len);
    set_function(l, c"__tostring", enum_describe);
    set_function(l, c"Init", enum_init);
    set_function(l, c"NameOf", enum_name_of);
    set_function(l, c"Valid", enum_valid);
    set_function(l, c"Check", enum_check);
    set_function(l, c"First", enum_first);
    set_function(l, c"Last", enum_last);
    set_function(l, c"Count", enum_len);
    set_function(l, c"Names", enum_names);
    set_function(l, c"Describe", enum_describe);
    (api.pushvalue)(l, parent);
    (api.setmetatable)(l, -2);
    (api.remove)(l, parent);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.core.enum.Enum".as_ptr());
}

/// enum.New(name, first, names) -> an enumeration
unsafe extern "C-unwind" fn enum_new(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    let first = (api.type_of)(l, 2) == TNUMBER && {
        let f = (api.tonumber)(l, 2);
        f.floor() == f
    };
    if !first {
        let (name, given) = (tostring(l, 1), tostring(l, 2));
        raise_where(l, format!("{name}: an enumeration's first value is a whole number, not {given}"));
    }
    if (api.type_of)(l, 3) != TTABLE || (api.objlen)(l, 3) == 0 {
        let name = tostring(l, 1);
        raise_where(l, format!("{name}: an enumeration needs names"));
    }
    let start = (api.tonumber)(l, 2);
    (api.createtable)(l, 0, 0);
    let constants = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let copy = (api.gettop)(l);
    let mut twice = None;
    let mut i = 0;
    each_item(l, 3, |l, n| {
        if twice.is_some() {
            return;
        }
        (api.pushvalue)(l, n);
        (api.rawget)(l, constants);
        let seen = (api.type_of)(l, -1) != TNIL;
        (api.settop)(l, -2);
        if seen {
            twice = Some(tostring(l, n));
            return;
        }
        (api.pushvalue)(l, n);
        (api.pushnumber)(l, start + i as f64);
        (api.rawset)(l, constants);
        i += 1;
        (api.pushvalue)(l, n);
        (api.rawseti)(l, copy, i);
    });
    if let Some(n) = twice {
        let name = tostring(l, 1);
        raise_where(l, format!("{name}: {n} is named twice"));
    }
    enum_class(l);
    let class = (api.gettop)(l);
    (api.pushvalue)(l, 1);
    (api.pushvalue)(l, constants);
    (api.pushvalue)(l, copy);
    (api.pushvalue)(l, 2);
    construct_through(l, class, class + 1)
}

/// Pushes the core namespace's native modules into the table at the top.
pub unsafe fn push_modules(l: L) {
    let api = api();
    crate::module::push(
        l,
        &[
            (c"Extend", extend),
            (c"New", new_instance),
            (c"IsA", is_a),
            (c"Guard", guard),
            (c"Construct", construct),
            (c"Destroy", destroy),
        ],
        None,
    );
    (api.setfield)(l, -2, c"class".as_ptr());
    crate::module::push(l, &[(c"New", port_new), (c"Is", port_is)], None);
    (api.setfield)(l, -2, c"port".as_ptr());
    crate::module::push(l, &[(c"New", constants_new)], None);
    constant_set_class(l);
    (api.setfield)(l, -2, c"ConstantSet".as_ptr());
    (api.setfield)(l, -2, c"constants".as_ptr());
    crate::module::push(l, &[(c"New", enum_new)], None);
    enum_class(l);
    (api.setfield)(l, -2, c"Enum".as_ptr());
    (api.setfield)(l, -2, c"enum".as_ptr());
    super::namespace::push_module(l);
    (api.setfield)(l, -2, c"namespace".as_ptr());
}

pub const NAMES: &[&CStr] = &[c"class", c"port", c"constants", c"enum", c"namespace"];
