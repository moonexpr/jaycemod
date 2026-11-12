//! core.namespace, native: the global tables the gamemode's modules are
//! published in, the Lua twin's contract (foundation/core/namespace.lua).
//! The loader runs every index in this module's Environment, so on a server
//! with the binary the indexes themselves run on it. Which keys a namespace
//! owns, its name and its deferred loads are kept, as the Lua twin keeps
//! them, in weak-keyed tables on the module's table (`Names`, `Owned`,
//! `Deferred`), which every function holds as its upvalue 1.

use crate::lua::{push_str, raise_where, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TSTRING, TTABLE};
use std::ffi::{c_int, CStr};

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

/// The module table, every function's upvalue 1.
const MODULE: c_int = GLOBALSINDEX - 1;

/// Pushes the module's table `name` (Names, Owned, Deferred, Lazy).
unsafe fn book(l: L, name: &CStr) {
    l.getfield(MODULE, name);
}

fn type_name(kind: c_int) -> &'static str {
    match kind {
        0 => "nil",
        1 => "boolean",
        2 => "userdata",
        3 => "number",
        4 => "string",
        5 => "table",
        6 => "function",
        7 => "userdata",
        8 => "thread",
        _ => "no value",
    }
}

/// `ns.key`, by the name the namespace was made under, for refusals.
unsafe fn name_of(l: L, ns: c_int, key: c_int) -> String {
    format!("{}.{}", ns_name(l, ns), tostring(l, key))
}

/// Names[ns] or tostring(ns).
unsafe fn ns_name(l: L, ns: c_int) -> String {
    book(l, c"Names");
    l.pushvalue(ns);
    l.rawget(-2);
    let name = if l.toboolean(-1) != 0 { tostring(l, -1) } else { tostring(l, ns) };
    l.settop(-3);
    name
}

/// Whether Export, Replace, Twin or Defer set ns[key].
unsafe fn owns(l: L, ns: c_int, key: c_int) -> bool {
    let top = l.gettop();
    book(l, c"Owned");
    l.pushvalue(ns);
    l.rawget(-2);
    let owned = if l.type_of(-1) == TNIL {
        false
    } else {
        l.pushvalue(key);
        l.gettable(-2);
        l.type_of(-1) == 1 && l.toboolean(-1) != 0
    };
    l.settop(top);
    owned
}

/// ns[key] = the value at `value` (0: nil), the key the namespace's own.
unsafe fn set(l: L, ns: c_int, key: c_int, value: c_int) {
    let top = l.gettop();
    book(l, c"Owned");
    let owned = top + 1;
    l.pushvalue(ns);
    l.rawget(owned);
    if l.type_of(-1) == TNIL {
        l.settop(owned);
        l.createtable(0, 4);
        l.pushvalue(ns);
        l.pushvalue(-2);
        l.settable(owned);
    }
    l.pushvalue(key);
    l.pushboolean(1);
    l.settable(-3);
    l.pushvalue(key);
    if value == 0 {
        l.pushnil();
    } else {
        l.pushvalue(value);
    }
    l.settable(ns);
    l.settop(top);
}

/// Whether a key is a name: a letter or _, then letters, digits or _.
fn is_name(key: &[u8]) -> bool {
    match key.split_first() {
        Some((first, rest)) => {
            (first.is_ascii_alphabetic() || *first == b'_') && rest.iter().all(|b| b.is_ascii_alphanumeric() || *b == b'_')
        }
        None => false,
    }
}

/// Refuses, blamed on the index line, a namespace that is no table, a key
/// that is no name, or nothing set.
unsafe fn check_set(l: L, ns: c_int, key: c_int, value: c_int) {
    if l.type_of(ns) != TTABLE {
        let given = tostring(l, ns);
        raise_where(l, format!("a namespace is a table, not {given}"));
    }
    let named = l.type_of(key) == TSTRING && crate::lua::string_at(l, key).is_some_and(is_name);
    if !named {
        let name = name_of(l, ns, key);
        raise_where(l, format!("{name}: a key is a name"));
    }
    if l.type_of(value) == TNIL {
        let name = name_of(l, ns, key);
        raise_where(l, format!("{name} is set to nothing"));
    }
}

unsafe fn rawget_is_nil(l: L, ns: c_int, key: c_int) -> bool {
    l.pushvalue(key);
    l.rawget(ns);
    let none = l.type_of(-1) == TNIL;
    l.settop(-2);
    none
}

/// Pushes globals[name] (at `globals`, `name`), made when absent.
unsafe fn namespace_in(l: L, globals: c_int, name: c_int) {
    l.pushvalue(name);
    l.rawget(globals);
    let ns = l.gettop();
    match l.type_of(ns) {
        TNIL => {
            l.settop(ns - 1);
            l.createtable(0, 0);
            l.pushvalue(name);
            l.pushvalue(ns);
            l.settable(globals);
        }
        TTABLE => {}
        kind => {
            let global = tostring(l, name);
            raise_where(l, format!("global {global} is a {}, not a namespace", type_name(kind)));
        }
    }
    book(l, c"Names");
    l.pushvalue(ns);
    l.rawget(-2);
    if l.toboolean(-1) == 0 {
        l.pushvalue(ns);
        l.pushvalue(name);
        l.settable(-4);
    }
    l.settop(ns);
}

unsafe extern "C-unwind" fn namespace(l: L) -> c_int {
    l.settop(2);
    namespace_in(l, 1, 2);
    1
}

unsafe extern "C-unwind" fn export(l: L) -> c_int {
    l.settop(3);
    check_set(l, 1, 2, 3);
    if !rawget_is_nil(l, 1, 2) && !owns(l, 1, 2) {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} is taken; Replace it to take it over on purpose"));
    }
    set(l, 1, 2, 3);
    0
}

unsafe extern "C-unwind" fn replace(l: L) -> c_int {
    l.settop(3);
    check_set(l, 1, 2, 3);
    if rawget_is_nil(l, 1, 2) {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} holds nothing to replace; Export it"));
    }
    set(l, 1, 2, 3);
    0
}

/// Whether a binary module made the value at `index`: a table holding a C
/// function.
unsafe fn is_native(l: L, index: c_int) -> bool {
    if l.type_of(index) != TTABLE {
        return false;
    }
    l.pushnil();
    while l.next(index) != 0 {
        if l.type_of(-1) == TFUNCTION && l.iscfunction(-1) != 0 {
            l.settop(-3);
            return true;
        }
        l.settop(-2);
    }
    false
}

/// module(...)'s own keys, which a Lua twin's table holds and its native
/// twin does not take.
fn module_key(key: &[u8]) -> bool {
    matches!(key, b"_M" | b"_NAME" | b"_PACKAGE")
}

unsafe extern "C-unwind" fn twin(l: L) -> c_int {
    l.settop(3);
    check_set(l, 1, 2, 3);
    l.pushvalue(2);
    l.rawget(1);
    let native = 4;
    if !is_native(l, native) {
        if l.type_of(native) != TNIL && !owns(l, 1, 2) {
            let name = name_of(l, 1, 2);
            raise_where(l, format!("{name} is taken by something other than a native twin"));
        }
        set(l, 1, 2, 3);
        l.pushvalue(3);
        return 1;
    }
    let mut missing = Vec::new();
    l.pushnil();
    while l.next(3) != 0 {
        let key = l.gettop() - 1;
        let skip = l.type_of(key) == TSTRING && crate::lua::string_at(l, key).is_some_and(module_key);
        if !skip {
            l.pushvalue(key);
            l.rawget(native);
            if l.type_of(-1) == TNIL {
                missing.push(tostring(l, key));
            }
            l.settop(-2);
        }
        l.settop(-2);
    }
    if !missing.is_empty() {
        missing.sort();
        let name = name_of(l, 1, 2);
        let lacks = missing.join(", ");
        drop(missing);
        raise_where(l, format!("{name}: the native twin lacks {lacks}"));
    }
    set(l, 1, 2, native);
    l.pushvalue(native);
    1
}

/// Defer(ns, key, load) with the stack's 1, 2 and the loader at `load`.
unsafe fn defer_at(l: L, load: c_int) {
    check_set(l, 1, 2, load);
    let kind = l.type_of(load);
    if kind != TFUNCTION {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} is deferred to a {}, not a loader", type_name(kind)));
    }
    if !rawget_is_nil(l, 1, 2) && !owns(l, 1, 2) {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} is taken; a deferred key needs a free one"));
    }
    let top = l.gettop();
    if l.getmetatable(1) == 0 {
        book(l, c"Lazy");
        l.setmetatable(1);
    } else {
        book(l, c"Lazy");
        if l.rawequal(-1, -2) == 0 {
            let name = name_of(l, 1, 2);
            let ns = ns_name(l, 1);
            raise_where(l, format!("{name}: {ns} has a metatable of its own"));
        }
    }
    l.settop(top);
    book(l, c"Deferred");
    let deferred = top + 1;
    l.pushvalue(1);
    l.rawget(deferred);
    if l.type_of(-1) == TNIL {
        l.settop(deferred);
        l.createtable(0, 4);
        l.pushvalue(1);
        l.pushvalue(-2);
        l.settable(deferred);
    }
    l.pushvalue(2);
    l.pushvalue(load);
    l.settable(-3);
    l.settop(top);
    set(l, 1, 2, 0);
}

unsafe extern "C-unwind" fn defer(l: L) -> c_int {
    l.settop(3);
    defer_at(l, 3);
    0
}

/// Lazy.__index(ns, key): a read of a deferred key loads it, once.
unsafe extern "C-unwind" fn lazy_index(l: L) -> c_int {
    l.settop(2);
    book(l, c"Deferred");
    l.pushvalue(1);
    l.rawget(3);
    let loads = 4;
    if l.toboolean(loads) == 0 {
        l.pushnil();
        return 1;
    }
    l.pushvalue(2);
    l.gettable(loads);
    if l.type_of(5) == TNIL {
        return 1;
    }
    l.call(0, 1);
    l.pushvalue(2);
    l.pushnil();
    l.settable(loads);
    l.pushvalue(2);
    l.pushvalue(5);
    l.rawset(1);
    1
}

/// The environment's Namespace(name): upvalue 2 the globals.
unsafe extern "C-unwind" fn env_namespace(l: L) -> c_int {
    l.settop(1);
    l.pushvalue(upvalue(2));
    namespace_in(l, 2, 1);
    1
}

/// A deferred module's loader: require(name), upvalues 1 and 2.
unsafe extern "C-unwind" fn loader(l: L) -> c_int {
    l.pushvalue(upvalue(1));
    l.pushvalue(upvalue(2));
    l.call(1, 1);
    1
}

/// The environment's Defer(ns, key, name): upvalue 2 the require.
unsafe extern "C-unwind" fn env_defer(l: L) -> c_int {
    l.settop(3);
    l.pushvalue(upvalue(2));
    l.pushvalue(3);
    l.pushcclosure(loader, 2);
    defer_at(l, 4);
    0
}

/// Pushes the C function `f` closed over the module (and `extra` values on
/// top, popped).
unsafe fn closure(l: L, f: CFunction, extra: c_int) {
    l.pushvalue(MODULE);
    l.insert(-1 - extra);
    l.pushcclosure(f, 1 + extra);
}

unsafe extern "C-unwind" fn environment(l: L) -> c_int {
    l.settop(2);
    book(l, c"Names");
    l.pushvalue(1);
    push_str(l, "_G");
    l.settable(-3);
    l.settop(2);
    l.createtable(0, 6);
    let env = 3;
    l.pushvalue(1);
    closure(l, env_namespace, 1);
    l.setfield(env, c"Namespace");
    for name in [c"Export", c"Replace", c"Twin"] {
        l.getfield(MODULE, name);
        l.setfield(env, name);
    }
    l.pushvalue(2);
    closure(l, env_defer, 1);
    l.setfield(env, c"Defer");
    l.pushvalue(2);
    l.setfield(env, c"require");
    l.createtable(0, 1);
    l.pushvalue(1);
    l.setfield(-2, c"__index");
    l.setmetatable(env);
    1
}

const REGISTRY: c_int = -10000;
const BOOKS: &CStr = c"foundation.core.namespace";

unsafe fn weak_keyed(l: L) {
    l.createtable(0, 0);
    l.createtable(0, 1);
    push_str(l, "k");
    l.setfield(-2, c"__mode");
    l.setmetatable(-2);
}

/// Pushes the books (Names, Owned, Deferred, Lazy): one set a Lua state,
/// kept in the registry, so a module opened again (a reload) goes on with
/// the namespaces the first one made, as the Lua twin's `Names = Names or`
/// does.
unsafe fn push_books(l: L) {
    l.getfield(REGISTRY, BOOKS);
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    l.createtable(0, 4);
    let books = l.gettop();
    for name in [c"Names", c"Owned", c"Deferred"] {
        weak_keyed(l);
        l.setfield(books, name);
    }
    l.createtable(0, 1);
    l.pushvalue(books);
    l.pushcclosure(lazy_index, 1);
    l.setfield(-2, c"__index");
    l.setfield(books, c"Lazy");
    l.pushvalue(books);
    l.setfield(REGISTRY, BOOKS);
}

/// Pushes the core.namespace module table.
pub unsafe fn push_module(l: L) {
    l.createtable(0, 10);
    let module = l.gettop();
    push_books(l);
    for name in [c"Names", c"Owned", c"Deferred", c"Lazy"] {
        l.getfield(-1, name);
        l.setfield(module, name);
    }
    l.settop(module);
    let functions: [(&CStr, CFunction); 6] = [
        (c"Namespace", namespace),
        (c"Export", export),
        (c"Replace", replace),
        (c"Twin", twin),
        (c"Defer", defer),
        (c"Environment", environment),
    ];
    for (name, f) in functions {
        l.pushvalue(module);
        l.pushcclosure(f, 1);
        l.setfield(module, name);
    }
}
