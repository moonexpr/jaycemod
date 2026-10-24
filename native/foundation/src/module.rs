//! Module tables as foundation's Lua twins publish them, and their install
//! over the globals: a whole module replaced (an object's constructor and
//! its type), or single functions patched over the Lua module where only
//! they gain.

use crate::lua::{api, set_function, CFunction, GLOBALSINDEX, L, TTABLE};
use std::ffi::{c_int, CStr};

/// A module whose table, called, constructs: `Heap()` as `Heap.New()`.
pub trait Constructor {
    const NEW: CFunction;
}

/// The module table's __call: drops the table, then constructs.
///
/// # Safety
/// Called by Lua as a metamethod, with the module table first.
pub unsafe extern "C-unwind" fn call<C: Constructor>(l: L) -> c_int {
    (api().remove)(l, 1);
    (C::NEW)(l)
}

/// Pushes a module table holding `functions`, callable when `call` is given.
///
/// # Safety
/// `l` is a live state, after `lua::open`.
pub unsafe fn push(l: L, functions: &[(&CStr, CFunction)], call: Option<CFunction>) {
    let api = api();
    (api.createtable)(l, 0, functions.len() as c_int);
    for (name, function) in functions {
        set_function(l, name, *function);
    }
    if let Some(call) = call {
        (api.createtable)(l, 0, 1);
        set_function(l, c"__call", call);
        (api.setmetatable)(l, -2);
    }
}

/// The table `namespace` names (a global), pushed; its index, or None
/// (nothing pushed) when the global is no table.
unsafe fn global_table(l: L, name: &CStr) -> Option<c_int> {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, name.as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return Some((api.gettop)(l));
    }
    (api.settop)(l, -2);
    None
}

/// Replaces `namespace.key` with the module table at the top of the stack
/// (popped), when the Lua twin's namespace is published.
///
/// # Safety
/// `l` is a live state with a module table at the top, after `lua::open`.
pub unsafe fn install(l: L, namespace: &CStr, key: &CStr) {
    let api = api();
    if let Some(ns) = global_table(l, namespace) {
        (api.pushvalue)(l, ns - 1);
        (api.setfield)(l, ns, key.as_ptr());
        (api.settop)(l, -2);
    }
    (api.settop)(l, -2);
}

/// Sets each of `functions` over the Lua module `path` names (a global
/// `name`, or `namespace.name`), when it is published.
///
/// # Safety
/// `l` is a live state, after `lua::open`.
pub unsafe fn patch(l: L, namespace: Option<&CStr>, name: &CStr, functions: &[(&CStr, CFunction)]) {
    let api = api();
    let module = match namespace {
        None => global_table(l, name),
        Some(namespace) => {
            let Some(ns) = global_table(l, namespace) else { return };
            (api.getfield)(l, ns, name.as_ptr());
            if (api.type_of)(l, -1) == TTABLE {
                Some((api.gettop)(l))
            } else {
                (api.settop)(l, -3);
                return;
            }
        }
    };
    let Some(module) = module else { return };
    for (function_name, function) in functions {
        (api.pushcclosure)(l, *function, 0);
        (api.setfield)(l, module, function_name.as_ptr());
    }
    (api.settop)(l, if namespace.is_some() { -3 } else { -2 });
}
