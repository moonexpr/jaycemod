//! The module's Lua face: native twins of foundation's Lua modules, laid out
//! by namespace as the Lua ones are published, and installed over them when
//! GMod opens the module.

mod avl;
mod heap;
mod nodegraph;
mod slots;

use crate::lua::{api, set_function, CFunction, L};
use std::ffi::{c_int, CStr};

/// probe.Nothing(): the cost of a call across the boundary and nothing else.
unsafe extern "C-unwind" fn probe_nothing(_l: L) -> c_int {
    0
}

/// probe.Add(a, b) -> a + b: a call that reads two numbers and returns one.
unsafe extern "C-unwind" fn probe_add(l: L) -> c_int {
    let api = api();
    let sum = (api.checknumber)(l, 1) + (api.checknumber)(l, 2);
    (api.pushnumber)(l, sum);
    1
}

unsafe fn library(l: L, name: &CStr, functions: &[(&CStr, CFunction)]) {
    let api = api();
    (api.createtable)(l, 0, functions.len() as c_int);
    for (function_name, function) in functions {
        set_function(l, function_name, *function);
    }
    (api.setfield)(l, -2, name.as_ptr());
}

/// Pushes the module's table, laid out as foundation's globals are
/// (`.tree.heap`, `.nodegraph`), with the boundary probes, for the tests and the bench.
unsafe fn module(l: L) {
    let api = api();
    (api.createtable)(l, 0, 2);
    (api.createtable)(l, 0, 2);
    heap::push_module(l);
    (api.setfield)(l, -2, c"heap".as_ptr());
    avl::push_module(l);
    (api.setfield)(l, -2, c"avl".as_ptr());
    (api.setfield)(l, -2, c"tree".as_ptr());
    library(l, c"nodegraph", nodegraph::FUNCTIONS);
    library(l, c"probe", &[(c"Nothing", probe_nothing), (c"Add", probe_add)]);
}

/// Installs each native twin that measured faster over its Lua twin's
/// global (docs/native-foundation-plan.md has the measurements).
unsafe fn install(l: L) {
    heap::push_module(l);
    crate::module::install(l, c"tree", c"heap");
    avl::push_module(l);
    crate::module::install(l, c"tree", c"avl");
    crate::module::patch(l, None, c"nodegraph", nodegraph::FUNCTIONS);
}

/// GMod's entry point: the server requires the module right after
/// foundation's indexes have published the Lua twins.
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(l: L) -> c_int {
    if crate::lua::open().is_err() {
        return 0;
    }
    install(l);
    0
}

#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_close(_l: L) -> c_int {
    0
}

/// Stock Lua's entry point (`package.loadlib`), for the LuaJIT tests and the
/// bench: returns the module's table, installing nothing, so the Lua twins
/// stay beside it as the oracle.
#[no_mangle]
pub unsafe extern "C-unwind" fn luaopen_foundation(l: L) -> c_int {
    if crate::lua::open().is_err() {
        return 0;
    }
    module(l);
    1
}
