//! core.class, core.port, core.constants and core.enum, native: the Lua
//! twins' contracts (foundation/core/). These are mechanisms over Lua
//! tables, so the native ones make and work on tables too, their metamethods
//! and methods C functions: a constant set is still a plain table whose
//! constants are raw fields, read at plain-table speed. Each set's own state
//! (name, count, numbering) is kept in a weak-keyed table in the registry,
//! apart from its constants, as the Lua twins keep it apart.

use super::util::{boolean, each_item, nothing, number};
use crate::lua::{push_str, raise_at, raise_where, set_function, string_at, tostring, L, TFUNCTION, TNIL, TNUMBER, TSTRING, TTABLE};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;

fn upvalue(i: c_int) -> c_int {
    crate::lua::GLOBALSINDEX - i
}

/// Pushes the registry's weak-keyed table `name`, made the first time.
unsafe fn weak_table(l: L, name: &CStr) {
    l.getfield(REGISTRY, name);
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    l.createtable(0, 0);
    l.createtable(0, 1);
    push_str(l, "k");
    l.setfield(-2, c"__mode");
    l.setmetatable(-2);
    l.pushvalue(-1);
    l.setfield(REGISTRY, name);
}

/// Pushes registry table `name`[value at `key`].
unsafe fn state_of(l: L, name: &CStr, key: c_int) {
    let key = if key < 0 { l.gettop() + key + 1 } else { key };
    weak_table(l, name);
    l.pushvalue(key);
    l.rawget(-2);
    l.remove(-2);
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
    l.settop(2);
    let has_parent = l.type_of(1) == TTABLE;
    l.createtable(0, 4);
    let class = l.gettop();
    if has_parent {
        for name in INHERITED {
            push_str(l, &name.to_string_lossy());
            l.rawget(1);
            if l.type_of(-1) != TNIL {
                push_str(l, &name.to_string_lossy());
                l.insert(-2);
                l.rawset(class);
            } else {
                l.settop(-2);
            }
        }
        push_str(l, "__index");
        l.rawget(1);
        if l.rawequal(-1, 1) == 0 {
            push_str(l, "__index");
            l.insert(-2);
            l.rawset(class);
        } else {
            l.settop(-2);
        }
    }
    if l.type_of(2) == TTABLE {
        l.pushnil();
        while l.next(2) != 0 {
            l.pushvalue(-2);
            l.insert(-2);
            l.rawset(class);
        }
    }
    push_str(l, "__index");
    l.rawget(class);
    let own_index = l.type_of(-1) != TNIL;
    l.settop(-2);
    if !own_index {
        push_str(l, "__index");
        l.pushvalue(class);
        l.rawset(class);
    }
    if has_parent {
        l.pushvalue(1);
        l.setmetatable(class);
    }
    1
}

/// class.New(class, fields) -> an instance
unsafe extern "C-unwind" fn new_instance(l: L) -> c_int {
    l.settop(2);
    if l.type_of(2) != TTABLE {
        l.settop(1);
        l.createtable(0, 0);
    }
    l.pushvalue(1);
    l.setmetatable(2);
    1
}

/// class.IsA(value, class) -> whether class is value's class or an ancestor
unsafe extern "C-unwind" fn is_a(l: L) -> c_int {
    l.settop(2);
    if l.type_of(1) != TTABLE {
        return boolean(l, false);
    }
    l.pushvalue(1);
    while l.getmetatable(-1) != 0 {
        if l.equal(-1, 2) != 0 {
            return boolean(l, true);
        }
        l.remove(-2);
    }
    boolean(l, false)
}

/// A guard's __newindex: upvalue 1 the check; refusals blame the assignment.
unsafe extern "C-unwind" fn guarded_newindex(l: L) -> c_int {
    l.settop(3);
    l.pushvalue(upvalue(1));
    l.pushvalue(2);
    l.pushvalue(3);
    l.call(2, 1);
    if l.toboolean(-1) != 0 {
        if l.type_of(-1) == TSTRING || l.type_of(-1) == TNUMBER {
            let why = tostring(l, -1);
            raise_where(l, why);
        }
        l.error();
    }
    l.settop(3);
    l.rawset(1);
    0
}

/// class.Guard(class, check) -> class
unsafe extern "C-unwind" fn guard(l: L) -> c_int {
    l.settop(2);
    push_str(l, "__newindex");
    l.pushvalue(2);
    l.pushcclosure(guarded_newindex, 1);
    l.rawset(1);
    l.pushvalue(1);
    1
}

/// Pushes the own methods called `name` along the line of classes from the
/// class at `class`, most derived first, as a list; its index.
unsafe fn line(l: L, class: c_int, name: &str) -> c_int {
    l.createtable(0, 0);
    let list = l.gettop();
    let mut n = 0;
    l.pushvalue(class);
    while l.type_of(-1) == TTABLE {
        push_str(l, name);
        l.rawget(-2);
        if l.toboolean(-1) != 0 {
            n += 1;
            l.rawseti(list, n);
        } else {
            l.settop(-2);
        }
        if l.getmetatable(-1) == 0 {
            l.pushnil();
        }
        l.remove(-2);
    }
    l.settop(list);
    list
}

/// class.Construct(class, ...) -> a new instance, each own Init run base first
unsafe extern "C-unwind" fn construct(l: L) -> c_int {
    let n = l.gettop();
    l.createtable(0, 0);
    let instance = l.gettop();
    l.pushvalue(1);
    l.setmetatable(instance);
    let inits = line(l, 1, "Init");
    let count = l.objlen(inits) as c_int;
    for i in (1..=count).rev() {
        l.rawgeti(inits, i);
        l.pushvalue(instance);
        for a in 2..=n {
            l.pushvalue(a);
        }
        l.call(n, 0);
    }
    l.pushvalue(instance);
    1
}

/// class.Destroy(instance, ...): each own Destroy, most derived first
pub(super) unsafe extern "C-unwind" fn destroy(l: L) -> c_int {
    let n = l.gettop();
    if l.getmetatable(1) == 0 {
        l.pushnil();
    }
    let class = l.gettop();
    let destroys = line(l, class, "Destroy");
    let mut i = 1;
    loop {
        l.rawgeti(destroys, i);
        if l.type_of(-1) == TNIL {
            break;
        }
        for a in 1..=n {
            l.pushvalue(a);
        }
        l.call(n, 0);
        i += 1;
    }
    0
}

// core.port --------------------------------------------------------------------

const PORT_META: &CStr = c"foundation.core.port";

/// Pushes the port metatable (methods by name, __index itself).
unsafe fn port_meta(l: L) {
    if l.newmetatable(PORT_META) != 0 {
        l.pushvalue(-1);
        l.setfield(-2, c"__index");
        set_function(l, c"Check", port_check);
        set_function(l, c"Facade", port_facade);
        set_function(l, c"Methods", port_methods);
        set_function(l, c"Name", port_name);
    }
}

/// port.New(name, methods) -> a port
pub(super) unsafe extern "C-unwind" fn port_new(l: L) -> c_int {
    l.settop(2);
    let name = string_at(l, 1).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned());
    let Some(name) = name else {
        let given = tostring(l, 1);
        raise_where(l, format!("a port needs a name, not {given}"));
    };
    if l.type_of(2) != TTABLE {
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
    l.createtable(0, 2);
    let port = l.gettop();
    l.pushvalue(1);
    l.setfield(port, c"name");
    l.createtable(0, 0);
    let list = l.gettop();
    let mut n = 0;
    each_item(l, 2, |l, m| {
        n += 1;
        l.pushvalue(m);
        l.rawseti(list, n);
    });
    l.setfield(port, c"methods");
    port_meta(l);
    l.setmetatable(port);
    1
}

/// port.Is(value) -> whether value is a port
unsafe extern "C-unwind" fn port_is(l: L) -> c_int {
    if l.getmetatable(1) == 0 {
        return boolean(l, false);
    }
    port_meta(l);
    let same = l.rawequal(-1, -2) != 0;
    boolean(l, same)
}

/// Pushes the port at 1's method list.
unsafe fn methods_of(l: L) -> c_int {
    l.getfield(1, c"methods");
    l.gettop()
}

pub(super) unsafe extern "C-unwind" fn port_check(l: L) -> c_int {
    l.settop(2);
    let list = methods_of(l);
    let mut missing = Vec::new();
    each_item(l, list, |l, m| {
        l.pushvalue(m);
        l.gettable(2);
        if l.type_of(-1) != TFUNCTION {
            missing.push(tostring(l, m));
        }
    });
    if !missing.is_empty() {
        l.getfield(1, c"name");
        let name = tostring(l, -1);
        let text = format!("value is not a {name}: no {}", missing.join(", "));
        drop(missing);
        drop(name);
        raise_at(l, 2, text);
    }
    l.pushvalue(2);
    1
}

/// A facade's method: upvalue 1 the value, 2 the method's name.
unsafe extern "C-unwind" fn facade_call(l: L) -> c_int {
    let n = l.gettop();
    l.pushvalue(upvalue(1));
    l.pushvalue(upvalue(2));
    l.gettable(-2);
    l.insert(2);
    l.insert(3);
    // stack: facade, fn, value, args...
    l.call(n, -1);
    l.gettop() - 1
}

unsafe extern "C-unwind" fn port_facade(l: L) -> c_int {
    l.settop(2);
    let list = methods_of(l);
    l.createtable(0, 0);
    let facade = l.gettop();
    each_item(l, list, |l, m| {
        l.pushvalue(m);
        l.pushvalue(2);
        l.pushvalue(m);
        l.pushcclosure(facade_call, 2);
        l.rawset(facade);
    });
    1
}

unsafe extern "C-unwind" fn port_methods(l: L) -> c_int {
    let list = methods_of(l);
    l.createtable(0, 0);
    let copy = l.gettop();
    let mut n = 0;
    each_item(l, list, |l, m| {
        n += 1;
        l.pushvalue(m);
        l.rawseti(copy, n);
    });
    1
}

unsafe extern "C-unwind" fn port_name(l: L) -> c_int {
    l.getfield(1, c"name");
    1
}

// core.constants ----------------------------------------------------------------

const SET_STATE: &CStr = c"foundation.core.constants.state";

/// The name of the set at `set`, or tostring of it.
unsafe fn set_name(l: L, set: c_int) -> String {
    state_of(l, SET_STATE, set);
    if l.type_of(-1) == TTABLE {
        l.getfield(-1, c"name");
        let name = tostring(l, -1);
        l.settop(-3);
        return name;
    }
    l.settop(-2);
    tostring(l, set)
}

/// A set's __index: a method along its classes, or the reader's error.
unsafe extern "C-unwind" fn set_lookup(l: L) -> c_int {
    l.settop(2);
    if l.getmetatable(1) == 0 {
        l.pushnil();
    }
    while l.type_of(-1) == TTABLE {
        l.pushvalue(2);
        l.rawget(-2);
        if l.type_of(-1) != TNIL {
            return 1;
        }
        l.settop(-2);
        if l.getmetatable(-1) == 0 {
            l.pushnil();
        }
        l.remove(-2);
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
    l.settop(2);
    if l.type_of(2) == TNIL {
        return nothing(l);
    }
    l.rawget(1);
    1
}

unsafe extern "C-unwind" fn set_tostring(l: L) -> c_int {
    state_of(l, SET_STATE, 1);
    if l.type_of(-1) != TTABLE {
        return nothing(l);
    }
    l.getfield(-1, c"name");
    1
}

unsafe extern "C-unwind" fn set_len(l: L) -> c_int {
    state_of(l, SET_STATE, 1);
    l.getfield(-1, c"count");
    1
}

fn is_constant_name(s: &[u8]) -> bool {
    !s.is_empty() && s[0].is_ascii_uppercase() && s.iter().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || *c == b'_')
}

/// ConstantSet:Init(name, constants), blaming New's caller (three calls up:
/// Init, Construct, New).
unsafe extern "C-unwind" fn set_init(l: L) -> c_int {
    l.settop(3);
    let name = string_at(l, 2).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned());
    let Some(name) = name else { raise_at(l, 3, "a constant set needs a name".into()) };
    let empty = l.type_of(3) != TTABLE || {
        l.pushnil();
        let any = l.next(3) != 0;
        if any {
            l.settop(-3);
        }
        !any
    };
    if empty {
        raise_at(l, 3, format!("{name}: a constant set needs constants"));
    }
    let mut count = 0.0;
    let mut bad = None;
    l.pushnil();
    while l.next(3) != 0 {
        let ok = l.type_of(-2) == TSTRING && string_at(l, -2).is_some_and(is_constant_name);
        if !ok && bad.is_none() {
            bad = Some(tostring(l, -2));
        }
        if ok {
            l.pushvalue(-2);
            l.insert(-2);
            l.rawset(1);
            count += 1.0;
        } else {
            l.settop(-2);
        }
    }
    if let Some(key) = bad {
        raise_at(l, 3, format!("{name}: a constant's name is upper case, not {key}"));
    }
    weak_table(l, SET_STATE);
    l.pushvalue(1);
    l.createtable(0, 2);
    push_str(l, &name);
    l.setfield(-2, c"name");
    l.pushnumber(count);
    l.setfield(-2, c"count");
    l.rawset(-3);
    0
}

unsafe extern "C-unwind" fn set_has(l: L) -> c_int {
    l.settop(2);
    if l.type_of(2) == TNIL {
        return boolean(l, false);
    }
    l.rawget(1);
    let has = l.type_of(-1) != TNIL;
    boolean(l, has)
}

unsafe extern "C-unwind" fn set_names(l: L) -> c_int {
    l.settop(1);
    l.createtable(0, 0);
    let names = l.gettop();
    let mut n = 0;
    l.pushnil();
    while l.next(1) != 0 {
        l.settop(-2);
        n += 1;
        l.pushvalue(-1);
        l.rawseti(names, n);
    }
    l.getfield(crate::lua::GLOBALSINDEX, c"table");
    l.getfield(-1, c"sort");
    l.pushvalue(names);
    l.call(1, 0);
    l.settop(names);
    1
}

/// Calls core.class.Construct on the class at `class` with the arguments at
/// `first`..top, as the Lua twin's New does through Class.Construct.
pub(super) unsafe fn construct_through(l: L, class: c_int, first: c_int) -> c_int {
    let top = l.gettop();
    l.pushcclosure(construct, 0);
    l.pushvalue(class);
    for i in first..=top {
        l.pushvalue(i);
    }
    l.call(top - first + 2, 1);
    1
}

/// Pushes the ConstantSet class.
unsafe fn constant_set_class(l: L) {
    l.getfield(REGISTRY, c"foundation.core.constants.ConstantSet");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    l.createtable(0, 10);
    set_function(l, c"__index", set_lookup);
    set_function(l, c"__newindex", set_fixed);
    set_function(l, c"__call", set_parse);
    set_function(l, c"__tostring", set_tostring);
    set_function(l, c"__len", set_len);
    set_function(l, c"Name", set_tostring);
    set_function(l, c"Init", set_init);
    set_function(l, c"Has", set_has);
    set_function(l, c"Names", set_names);
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.core.constants.ConstantSet");
}

/// constants.New(name, constants) -> a constant set
unsafe extern "C-unwind" fn constants_new(l: L) -> c_int {
    l.settop(2);
    constant_set_class(l);
    l.insert(1);
    construct_through(l, 1, 2)
}

// core.enum ----------------------------------------------------------------------

const ENUM_STATE: &CStr = c"foundation.core.enum.state";

/// Pushes the enumeration at 1's state { first, names, byValue }; its index.
unsafe fn enum_state(l: L) -> c_int {
    state_of(l, ENUM_STATE, 1);
    l.gettop()
}

unsafe extern "C-unwind" fn enum_index(l: L) -> c_int {
    l.settop(2);
    if l.type_of(2) == TNUMBER {
        let state = enum_state(l);
        l.getfield(state, c"byValue");
        l.pushvalue(2);
        l.rawget(-2);
        return 1;
    }
    set_lookup(l)
}

/// The value the token at 2 stands for, pushed (or nil).
unsafe fn enum_parse_value(l: L) {
    if l.type_of(2) == TNUMBER {
        let state = enum_state(l);
        l.getfield(state, c"byValue");
        l.pushvalue(2);
        l.rawget(-2);
        let known = l.type_of(-1) != TNIL;
        l.settop(state - 1);
        if known {
            l.pushvalue(2);
        } else {
            l.pushnil();
        }
        return;
    }
    if l.type_of(2) == TNIL {
        l.pushnil();
        return;
    }
    l.pushvalue(2);
    l.rawget(1);
}

unsafe extern "C-unwind" fn enum_call(l: L) -> c_int {
    l.settop(2);
    enum_parse_value(l);
    1
}

unsafe fn enum_count(l: L) -> usize {
    let state = enum_state(l);
    l.getfield(state, c"names");
    let n = l.objlen(-1);
    l.settop(state - 1);
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
    let state = enum_state(l);
    l.getfield(state, c"first");
    let first = l.tonumber(-1);
    l.getfield(state, c"names");
    let names = l.gettop();
    let mut parts: Vec<Vec<u8>> = Vec::new();
    let mut i = 0.0;
    each_item(l, names, |l, n| {
        let mut part = tostring(l, {
            l.pushnumber(first + i);
            -1
        })
        .into_bytes();
        l.settop(-2);
        part.push(b' ');
        part.extend(words(string_at(l, n).unwrap_or_default()));
        parts.push(part);
        i += 1.0;
    });
    let text = parts.join(&b", "[..]);
    drop(parts);
    l.pushlstring(text.as_ptr().cast(), text.len());
    drop(text);
    1
}

/// Enum's Init(self, name, constants, names, first): its numbering.
unsafe extern "C-unwind" fn enum_init(l: L) -> c_int {
    l.settop(5);
    let first = l.tonumber(5);
    l.createtable(0, 3);
    let state = l.gettop();
    l.pushvalue(5);
    l.setfield(state, c"first");
    l.pushvalue(4);
    l.setfield(state, c"names");
    l.createtable(0, 0);
    let by_value = l.gettop();
    let mut i = 0.0;
    each_item(l, 4, |l, name| {
        l.pushnumber(first + i);
        l.pushvalue(name);
        l.rawset(by_value);
        i += 1.0;
    });
    l.setfield(state, c"byValue");
    weak_table(l, ENUM_STATE);
    l.pushvalue(1);
    l.pushvalue(state);
    l.rawset(-3);
    0
}

unsafe extern "C-unwind" fn enum_name_of(l: L) -> c_int {
    l.settop(2);
    let state = enum_state(l);
    l.getfield(state, c"byValue");
    l.pushvalue(2);
    l.rawget(-2);
    1
}

unsafe extern "C-unwind" fn enum_valid(l: L) -> c_int {
    l.settop(2);
    enum_parse_value(l);
    let valid = l.type_of(-1) != TNIL;
    boolean(l, valid)
}

unsafe extern "C-unwind" fn enum_check(l: L) -> c_int {
    l.settop(2);
    let ok = l.type_of(2) == TNUMBER && {
        enum_parse_value(l);
        let v = l.type_of(-1) != TNIL;
        l.settop(2);
        v
    };
    if !ok {
        let name = set_name(l, 1);
        let value = tostring(l, 2);
        raise_where(l, format!("{name}: no value {value}"));
    }
    l.pushvalue(2);
    1
}

unsafe extern "C-unwind" fn enum_first(l: L) -> c_int {
    let state = enum_state(l);
    l.getfield(state, c"first");
    1
}

unsafe extern "C-unwind" fn enum_last(l: L) -> c_int {
    let count = enum_count(l) as f64;
    let state = enum_state(l);
    l.getfield(state, c"first");
    let first = l.tonumber(-1);
    number(l, first + count - 1.0)
}

unsafe extern "C-unwind" fn enum_names(l: L) -> c_int {
    let state = enum_state(l);
    l.getfield(state, c"names");
    let names = l.gettop();
    l.createtable(0, 0);
    let copy = l.gettop();
    let mut n = 0;
    each_item(l, names, |l, name| {
        n += 1;
        l.pushvalue(name);
        l.rawseti(copy, n);
    });
    1
}

/// Pushes the Enum class (extending ConstantSet).
unsafe fn enum_class(l: L) {
    l.getfield(REGISTRY, c"foundation.core.enum.Enum");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    constant_set_class(l);
    let parent = l.gettop();
    l.createtable(0, 16);
    for name in INHERITED {
        l.getfield(parent, name);
        if l.type_of(-1) != TNIL {
            l.setfield(-2, name);
        } else {
            l.settop(-2);
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
    l.pushvalue(parent);
    l.setmetatable(-2);
    l.remove(parent);
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.core.enum.Enum");
}

/// enum.New(name, first, names) -> an enumeration
unsafe extern "C-unwind" fn enum_new(l: L) -> c_int {
    l.settop(3);
    let first = l.type_of(2) == TNUMBER && {
        let f = l.tonumber(2);
        f.floor() == f
    };
    if !first {
        let (name, given) = (tostring(l, 1), tostring(l, 2));
        raise_where(l, format!("{name}: an enumeration's first value is a whole number, not {given}"));
    }
    if l.type_of(3) != TTABLE || l.objlen(3) == 0 {
        let name = tostring(l, 1);
        raise_where(l, format!("{name}: an enumeration needs names"));
    }
    let start = l.tonumber(2);
    l.createtable(0, 0);
    let constants = l.gettop();
    l.createtable(0, 0);
    let copy = l.gettop();
    let mut twice = None;
    let mut i = 0;
    each_item(l, 3, |l, n| {
        if twice.is_some() {
            return;
        }
        l.pushvalue(n);
        l.rawget(constants);
        let seen = l.type_of(-1) != TNIL;
        l.settop(-2);
        if seen {
            twice = Some(tostring(l, n));
            return;
        }
        l.pushvalue(n);
        l.pushnumber(start + i as f64);
        l.rawset(constants);
        i += 1;
        l.pushvalue(n);
        l.rawseti(copy, i);
    });
    if let Some(n) = twice {
        let name = tostring(l, 1);
        raise_where(l, format!("{name}: {n} is named twice"));
    }
    enum_class(l);
    let class = l.gettop();
    l.pushvalue(1);
    l.pushvalue(constants);
    l.pushvalue(copy);
    l.pushvalue(2);
    construct_through(l, class, class + 1)
}

/// Pushes the class module table.
unsafe fn push_class_module(l: L) {
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
}

/// Pushes the port module table.
unsafe fn push_port_module(l: L) {
    crate::module::push(l, &[(c"New", port_new), (c"Is", port_is)], None);
}

/// Pushes the constants module table.
unsafe fn push_constants_module(l: L) {
    crate::module::push(l, &[(c"New", constants_new)], None);
    constant_set_class(l);
    l.setfield(-2, c"ConstantSet");
}

/// Pushes the enum module table.
unsafe fn push_enum_module(l: L) {
    crate::module::push(l, &[(c"New", enum_new)], None);
    enum_class(l);
    l.setfield(-2, c"Enum");
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[
    (c"class", push_class_module),
    (c"port", push_port_module),
    (c"constants", push_constants_module),
    (c"enum", push_enum_module),
    (c"namespace", super::namespace::push_module),
];
