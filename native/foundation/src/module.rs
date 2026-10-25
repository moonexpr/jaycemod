//! Module tables as foundation's Lua twins publish them, and where a server
//! puts them: at their globals before the indexes run, each a whole module.

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

/// Puts the native module table at the top of the stack (popped) at its
/// global, `namespace.key` (the namespace made when absent) or `key` at the
/// root, before foundation's indexes run: each index line's Twin then keeps
/// it as the module, whole (core.namespace refuses one that lacks part of
/// the Lua twin's interface).
///
/// # Safety
/// `l` is a live state with a module table at the top, after `lua::open`.
pub unsafe fn provide(l: L, namespace: Option<&CStr>, key: &CStr) {
    let api = api();
    match namespace {
        None => (api.setfield)(l, GLOBALSINDEX, key.as_ptr()),
        Some(namespace) => {
            (api.getfield)(l, GLOBALSINDEX, namespace.as_ptr());
            if (api.type_of)(l, -1) != TTABLE {
                (api.settop)(l, -2);
                (api.createtable)(l, 0, 4);
                (api.pushvalue)(l, -1);
                (api.setfield)(l, GLOBALSINDEX, namespace.as_ptr());
            }
            (api.pushvalue)(l, -2);
            (api.setfield)(l, -2, key.as_ptr());
            (api.settop)(l, -3);
        }
    }
}
