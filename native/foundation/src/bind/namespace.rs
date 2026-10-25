//! core.namespace, native: the global tables the gamemode's modules are
//! published in, the Lua twin's contract (foundation/core/namespace.lua).
//! The loader runs every index in this module's Environment, so on a server
//! with the binary the indexes themselves run on it. Which keys a namespace
//! owns, its name and its deferred loads are kept, as the Lua twin keeps
//! them, in weak-keyed tables on the module's table (`Names`, `Owned`,
//! `Deferred`), which every function holds as its upvalue 1.

use crate::lua::{api, push_str, raise_where, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TSTRING, TTABLE};
use std::ffi::{c_int, CStr};

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

/// The module table, every function's upvalue 1.
const MODULE: c_int = GLOBALSINDEX - 1;

/// Pushes the module's table `name` (Names, Owned, Deferred, Lazy).
unsafe fn book(l: L, name: &CStr) {
    (api().getfield)(l, MODULE, name.as_ptr());
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
    let api = api();
    book(l, c"Names");
    (api.pushvalue)(l, ns);
    (api.rawget)(l, -2);
    let name = if (api.toboolean)(l, -1) != 0 { tostring(l, -1) } else { tostring(l, ns) };
    (api.settop)(l, -3);
    name
}

/// Whether Export, Replace, Twin or Defer set ns[key].
unsafe fn owns(l: L, ns: c_int, key: c_int) -> bool {
    let api = api();
    let top = (api.gettop)(l);
    book(l, c"Owned");
    (api.pushvalue)(l, ns);
    (api.rawget)(l, -2);
    let owned = if (api.type_of)(l, -1) == TNIL {
        false
    } else {
        (api.pushvalue)(l, key);
        (api.gettable)(l, -2);
        (api.type_of)(l, -1) == 1 && (api.toboolean)(l, -1) != 0
    };
    (api.settop)(l, top);
    owned
}

/// ns[key] = the value at `value` (0: nil), the key the namespace's own.
unsafe fn set(l: L, ns: c_int, key: c_int, value: c_int) {
    let api = api();
    let top = (api.gettop)(l);
    book(l, c"Owned");
    let owned = top + 1;
    (api.pushvalue)(l, ns);
    (api.rawget)(l, owned);
    if (api.type_of)(l, -1) == TNIL {
        (api.settop)(l, owned);
        (api.createtable)(l, 0, 4);
        (api.pushvalue)(l, ns);
        (api.pushvalue)(l, -2);
        (api.settable)(l, owned);
    }
    (api.pushvalue)(l, key);
    (api.pushboolean)(l, 1);
    (api.settable)(l, -3);
    (api.pushvalue)(l, key);
    if value == 0 {
        (api.pushnil)(l);
    } else {
        (api.pushvalue)(l, value);
    }
    (api.settable)(l, ns);
    (api.settop)(l, top);
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
    let api = api();
    if (api.type_of)(l, ns) != TTABLE {
        let given = tostring(l, ns);
        raise_where(l, format!("a namespace is a table, not {given}"));
    }
    let named = (api.type_of)(l, key) == TSTRING && crate::lua::string_at(l, key).is_some_and(is_name);
    if !named {
        let name = name_of(l, ns, key);
        raise_where(l, format!("{name}: a key is a name"));
    }
    if (api.type_of)(l, value) == TNIL {
        let name = name_of(l, ns, key);
        raise_where(l, format!("{name} is set to nothing"));
    }
}

unsafe fn rawget_is_nil(l: L, ns: c_int, key: c_int) -> bool {
    let api = api();
    (api.pushvalue)(l, key);
    (api.rawget)(l, ns);
    let none = (api.type_of)(l, -1) == TNIL;
    (api.settop)(l, -2);
    none
}

/// Pushes globals[name] (at `globals`, `name`), made when absent.
unsafe fn namespace_in(l: L, globals: c_int, name: c_int) {
    let api = api();
    (api.pushvalue)(l, name);
    (api.rawget)(l, globals);
    let ns = (api.gettop)(l);
    match (api.type_of)(l, ns) {
        TNIL => {
            (api.settop)(l, ns - 1);
            (api.createtable)(l, 0, 0);
            (api.pushvalue)(l, name);
            (api.pushvalue)(l, ns);
            (api.settable)(l, globals);
        }
        TTABLE => {}
        kind => {
            let global = tostring(l, name);
            raise_where(l, format!("global {global} is a {}, not a namespace", type_name(kind)));
        }
    }
    book(l, c"Names");
    (api.pushvalue)(l, ns);
    (api.rawget)(l, -2);
    if (api.toboolean)(l, -1) == 0 {
        (api.pushvalue)(l, ns);
        (api.pushvalue)(l, name);
        (api.settable)(l, -4);
    }
    (api.settop)(l, ns);
}

unsafe extern "C-unwind" fn namespace(l: L) -> c_int {
    (api().settop)(l, 2);
    namespace_in(l, 1, 2);
    1
}

unsafe extern "C-unwind" fn export(l: L) -> c_int {
    (api().settop)(l, 3);
    check_set(l, 1, 2, 3);
    if !rawget_is_nil(l, 1, 2) && !owns(l, 1, 2) {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} is taken; Replace it to take it over on purpose"));
    }
    set(l, 1, 2, 3);
    0
}

unsafe extern "C-unwind" fn replace(l: L) -> c_int {
    (api().settop)(l, 3);
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
    let api = api();
    if (api.type_of)(l, index) != TTABLE {
        return false;
    }
    (api.pushnil)(l);
    while (api.next)(l, index) != 0 {
        if (api.type_of)(l, -1) == TFUNCTION && (api.iscfunction)(l, -1) != 0 {
            (api.settop)(l, -3);
            return true;
        }
        (api.settop)(l, -2);
    }
    false
}

/// module(...)'s own keys, which a Lua twin's table holds and its native
/// twin does not take.
fn module_key(key: &[u8]) -> bool {
    matches!(key, b"_M" | b"_NAME" | b"_PACKAGE")
}

unsafe extern "C-unwind" fn twin(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    check_set(l, 1, 2, 3);
    (api.pushvalue)(l, 2);
    (api.rawget)(l, 1);
    let native = 4;
    if !is_native(l, native) {
        if (api.type_of)(l, native) != TNIL && !owns(l, 1, 2) {
            let name = name_of(l, 1, 2);
            raise_where(l, format!("{name} is taken by something other than a native twin"));
        }
        set(l, 1, 2, 3);
        (api.pushvalue)(l, 3);
        return 1;
    }
    let mut missing = Vec::new();
    (api.pushnil)(l);
    while (api.next)(l, 3) != 0 {
        let key = (api.gettop)(l) - 1;
        let skip = (api.type_of)(l, key) == TSTRING && crate::lua::string_at(l, key).is_some_and(module_key);
        if !skip {
            (api.pushvalue)(l, key);
            (api.rawget)(l, native);
            if (api.type_of)(l, -1) == TNIL {
                missing.push(tostring(l, key));
            }
            (api.settop)(l, -2);
        }
        (api.settop)(l, -2);
    }
    if !missing.is_empty() {
        missing.sort();
        let name = name_of(l, 1, 2);
        let lacks = missing.join(", ");
        drop(missing);
        raise_where(l, format!("{name}: the native twin lacks {lacks}"));
    }
    set(l, 1, 2, native);
    (api.pushvalue)(l, native);
    1
}

/// Defer(ns, key, load) with the stack's 1, 2 and the loader at `load`.
unsafe fn defer_at(l: L, load: c_int) {
    let api = api();
    check_set(l, 1, 2, load);
    let kind = (api.type_of)(l, load);
    if kind != TFUNCTION {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} is deferred to a {}, not a loader", type_name(kind)));
    }
    if !rawget_is_nil(l, 1, 2) && !owns(l, 1, 2) {
        let name = name_of(l, 1, 2);
        raise_where(l, format!("{name} is taken; a deferred key needs a free one"));
    }
    let top = (api.gettop)(l);
    if (api.getmetatable)(l, 1) == 0 {
        book(l, c"Lazy");
        (api.setmetatable)(l, 1);
    } else {
        book(l, c"Lazy");
        if (api.rawequal)(l, -1, -2) == 0 {
            let name = name_of(l, 1, 2);
            let ns = ns_name(l, 1);
            raise_where(l, format!("{name}: {ns} has a metatable of its own"));
        }
    }
    (api.settop)(l, top);
    book(l, c"Deferred");
    let deferred = top + 1;
    (api.pushvalue)(l, 1);
    (api.rawget)(l, deferred);
    if (api.type_of)(l, -1) == TNIL {
        (api.settop)(l, deferred);
        (api.createtable)(l, 0, 4);
        (api.pushvalue)(l, 1);
        (api.pushvalue)(l, -2);
        (api.settable)(l, deferred);
    }
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, load);
    (api.settable)(l, -3);
    (api.settop)(l, top);
    set(l, 1, 2, 0);
}

unsafe extern "C-unwind" fn defer(l: L) -> c_int {
    (api().settop)(l, 3);
    defer_at(l, 3);
    0
}

/// Lazy.__index(ns, key): a read of a deferred key loads it, once.
unsafe extern "C-unwind" fn lazy_index(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    book(l, c"Deferred");
    (api.pushvalue)(l, 1);
    (api.rawget)(l, 3);
    let loads = 4;
    if (api.toboolean)(l, loads) == 0 {
        (api.pushnil)(l);
        return 1;
    }
    (api.pushvalue)(l, 2);
    (api.gettable)(l, loads);
    if (api.type_of)(l, 5) == TNIL {
        return 1;
    }
    (api.call)(l, 0, 1);
    (api.pushvalue)(l, 2);
    (api.pushnil)(l);
    (api.settable)(l, loads);
    (api.pushvalue)(l, 2);
    (api.pushvalue)(l, 5);
    (api.rawset)(l, 1);
    1
}

/// The environment's Namespace(name): upvalue 2 the globals.
unsafe extern "C-unwind" fn env_namespace(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.pushvalue)(l, upvalue(2));
    namespace_in(l, 2, 1);
    1
}

/// A deferred module's loader: require(name), upvalues 1 and 2.
unsafe extern "C-unwind" fn loader(l: L) -> c_int {
    let api = api();
    (api.pushvalue)(l, upvalue(1));
    (api.pushvalue)(l, upvalue(2));
    (api.call)(l, 1, 1);
    1
}

/// The environment's Defer(ns, key, name): upvalue 2 the require.
unsafe extern "C-unwind" fn env_defer(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    (api.pushvalue)(l, upvalue(2));
    (api.pushvalue)(l, 3);
    (api.pushcclosure)(l, loader, 2);
    defer_at(l, 4);
    0
}

/// Pushes the C function `f` closed over the module (and `extra` values on
/// top, popped).
unsafe fn closure(l: L, f: CFunction, extra: c_int) {
    let api = api();
    (api.pushvalue)(l, MODULE);
    (api.insert)(l, -1 - extra);
    (api.pushcclosure)(l, f, 1 + extra);
}

unsafe extern "C-unwind" fn environment(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    book(l, c"Names");
    (api.pushvalue)(l, 1);
    push_str(l, "_G");
    (api.settable)(l, -3);
    (api.settop)(l, 2);
    (api.createtable)(l, 0, 6);
    let env = 3;
    (api.pushvalue)(l, 1);
    closure(l, env_namespace, 1);
    (api.setfield)(l, env, c"Namespace".as_ptr());
    for name in [c"Export", c"Replace", c"Twin"] {
        (api.getfield)(l, MODULE, name.as_ptr());
        (api.setfield)(l, env, name.as_ptr());
    }
    (api.pushvalue)(l, 2);
    closure(l, env_defer, 1);
    (api.setfield)(l, env, c"Defer".as_ptr());
    (api.pushvalue)(l, 2);
    (api.setfield)(l, env, c"require".as_ptr());
    (api.createtable)(l, 0, 1);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, -2, c"__index".as_ptr());
    (api.setmetatable)(l, env);
    1
}

const REGISTRY: c_int = -10000;
const BOOKS: &CStr = c"foundation.core.namespace";

unsafe fn weak_keyed(l: L) {
    let api = api();
    (api.createtable)(l, 0, 0);
    (api.createtable)(l, 0, 1);
    push_str(l, "k");
    (api.setfield)(l, -2, c"__mode".as_ptr());
    (api.setmetatable)(l, -2);
}

/// Pushes the books (Names, Owned, Deferred, Lazy): one set a Lua state,
/// kept in the registry, so a module opened again (a reload) goes on with
/// the namespaces the first one made, as the Lua twin's `Names = Names or`
/// does.
unsafe fn push_books(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, BOOKS.as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.createtable)(l, 0, 4);
    let books = (api.gettop)(l);
    for name in [c"Names", c"Owned", c"Deferred"] {
        weak_keyed(l);
        (api.setfield)(l, books, name.as_ptr());
    }
    (api.createtable)(l, 0, 1);
    (api.pushvalue)(l, books);
    (api.pushcclosure)(l, lazy_index, 1);
    (api.setfield)(l, -2, c"__index".as_ptr());
    (api.setfield)(l, books, c"Lazy".as_ptr());
    (api.pushvalue)(l, books);
    (api.setfield)(l, REGISTRY, BOOKS.as_ptr());
}

/// Pushes the core.namespace module table.
pub unsafe fn push_module(l: L) {
    let api = api();
    (api.createtable)(l, 0, 10);
    let module = (api.gettop)(l);
    push_books(l);
    for name in [c"Names", c"Owned", c"Deferred", c"Lazy"] {
        (api.getfield)(l, -1, name.as_ptr());
        (api.setfield)(l, module, name.as_ptr());
    }
    (api.settop)(l, module);
    let functions: [(&CStr, CFunction); 6] = [
        (c"Namespace", namespace),
        (c"Export", export),
        (c"Replace", replace),
        (c"Twin", twin),
        (c"Defer", defer),
        (c"Environment", environment),
    ];
    for (name, f) in functions {
        (api.pushvalue)(l, module);
        (api.pushcclosure)(l, f, 1);
        (api.setfield)(l, module, name.as_ptr());
    }
}
