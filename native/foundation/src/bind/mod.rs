//! The module's Lua face: native twins of foundation's Lua modules, laid out
//! by namespace as the Lua ones are published, and installed over them when
//! GMod opens the module.

mod analysis;
mod avl;
mod cache;
mod codec;
mod configstore;
mod core;
mod heap;
mod list;
mod math;
mod util;
mod world;
mod nodegraph;
mod schedule;
mod state_chart;
mod state_machine;
mod pathfinder;
mod search;
mod slots;
mod transaction;

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
    (api.createtable)(l, 0, 1);
    pathfinder::push_module(l);
    (api.setfield)(l, -2, c"pathfinder".as_ptr());
    search::push_module(l);
    (api.setfield)(l, -2, c"search".as_ptr());
    (api.setfield)(l, -2, c"graph".as_ptr());
    nodegraph::push_module(l);
    (api.setfield)(l, -2, c"nodegraph".as_ptr());
    configstore::push_module(l);
    (api.setfield)(l, -2, c"configstore".as_ptr());
    transaction::push_module(l);
    (api.setfield)(l, -2, c"transaction".as_ptr());
    namespace(l, c"list", list::push_modules);
    namespace(l, c"world", world::push_modules);
    namespace(l, c"math", math::push_modules);
    namespace(l, c"core", core::push_modules);
    namespace(l, c"cache", cache::push_modules);
    namespace(l, c"generator", generator_modules);
    namespace(l, c"analysis", analysis::push_modules);
    namespace(l, c"file", codec::push_file);
    namespace(l, c"encoding", codec::push_encoding);
    library(l, c"probe", &[(c"Nothing", probe_nothing), (c"Add", probe_add)]);
}

/// Pushes the generator namespace's native modules into the table at the top.
unsafe fn generator_modules(l: L) {
    state_machine::push_module(l);
    (api().setfield)(l, -2, c"state_machine".as_ptr());
    state_chart::push_module(l);
    (api().setfield)(l, -2, c"state_chart".as_ptr());
}

const GENERATOR_NAMES: &[&CStr] = &[c"state_machine", c"state_chart"];

/// Pushes a table of a namespace's native modules (filled by `push`) into the
/// table at the top of the stack, as `name`.
unsafe fn namespace(l: L, name: &CStr, push: unsafe fn(L)) {
    let api = api();
    (api.createtable)(l, 0, 8);
    push(l);
    (api.setfield)(l, -2, name.as_ptr());
}

/// Provides each of a namespace's native modules (filled by `push`, keyed by
/// `names`) at `namespace.<name>`.
unsafe fn provide_all(l: L, namespace: &CStr, push: unsafe fn(L), names: &[&CStr]) {
    let api = api();
    (api.createtable)(l, 0, names.len() as c_int);
    push(l);
    for name in names {
        (api.getfield)(l, -1, name.as_ptr());
        crate::module::provide(l, Some(namespace), name);
    }
    (api.settop)(l, -2);
}

/// Provides each native twin that is whole at its Lua twin's global, before
/// the indexes run (docs/native-foundation-plan.md).
unsafe fn provide(l: L) {
    heap::push_module(l);
    crate::module::provide(l, Some(c"tree"), c"heap");
    avl::push_module(l);
    crate::module::provide(l, Some(c"tree"), c"avl");
    pathfinder::push_module(l);
    crate::module::provide(l, Some(c"graph"), c"pathfinder");
    search::push_module(l);
    crate::module::provide(l, Some(c"graph"), c"search");
    provide_all(l, c"list", list::push_modules, list::NAMES);
    nodegraph::push_module(l);
    crate::module::provide(l, None, c"nodegraph");
    configstore::push_module(l);
    crate::module::provide(l, None, c"configstore");
    transaction::push_module(l);
    crate::module::provide(l, None, c"transaction");
    provide_all(l, c"world", world::push_modules, world::NAMES);
    provide_all(l, c"math", math::push_modules, math::NAMES);
    provide_all(l, c"core", core::push_modules, core::NAMES);
    provide_all(l, c"cache", cache::push_modules, cache::NAMES);
    provide_all(l, c"generator", generator_modules, GENERATOR_NAMES);
    provide_all(l, c"analysis", analysis::push_modules, analysis::NAMES);
    provide_all(l, c"file", codec::push_file, codec::FILE_NAMES);
    provide_all(l, c"encoding", codec::push_encoding, codec::ENCODING_NAMES);
}

/// GMod's entry point: the server requires the module before foundation's
/// indexes run.
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(l: L) -> c_int {
    if crate::lua::open().is_err() {
        return 0;
    }
    provide(l);
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
