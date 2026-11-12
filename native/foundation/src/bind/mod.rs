//! The module's Lua face: native twins of foundation's Lua modules, laid out
//! by namespace as the Lua ones are published, and installed over them when
//! GMod opens the module.

mod analysis;
mod avl;
mod cache;
mod calendar;
mod codec;
mod configstore;
mod core;
mod heap;
mod list;
mod math;
mod util;
mod world;
mod namespace;
mod nodegraph;
mod schedule;
mod state_chart;
mod state_chart_stacks;
mod state_machine;
mod timer;
mod pathfinder;
mod paths;
mod search;
mod select;
mod slots;
mod transaction;

use crate::lua::{set_function, CFunction, L};
use std::ffi::{c_int, CStr};

/// probe.Nothing(): the cost of a call across the boundary and nothing else.
unsafe extern "C-unwind" fn probe_nothing(_l: L) -> c_int {
    0
}

/// probe.Add(a, b) -> a + b: a call that reads two numbers and returns one.
unsafe extern "C-unwind" fn probe_add(l: L) -> c_int {
    let sum = l.checknumber(1) + l.checknumber(2);
    l.pushnumber(sum);
    1
}

unsafe fn library(l: L, name: &CStr, functions: &[(&CStr, CFunction)]) {
    l.createtable(0, functions.len() as c_int);
    for (function_name, function) in functions {
        set_function(l, function_name, *function);
    }
    l.setfield(-2, name);
}

/// A namespace's native modules, by name: what pushes each one's table.
pub type Modules = &'static [(&'static CStr, unsafe fn(L))];

/// One namespace: its name (None for the globals' root) and its modules.
type Namespace = (Option<&'static CStr>, Modules);

/// Every native module, each named once, where its Lua twin is published.
/// The tests' table and the server's install are both laid out from it.
const NAMESPACES: &[Namespace] = &[
    (Some(c"tree"), &[(c"heap", heap::push_module), (c"avl", avl::push_module)]),
    (
        Some(c"graph"),
        &[(c"pathfinder", pathfinder::push_module), (c"search", search::push_module), (c"paths", paths::push_module)],
    ),
    (
        None,
        &[
            (c"nodegraph", nodegraph::push_module),
            (c"configstore", configstore::push_module),
            (c"transaction", transaction::push_module),
        ],
    ),
    (Some(c"list"), list::MODULES),
    (Some(c"world"), world::MODULES),
    (Some(c"math"), math::MODULES),
    (Some(c"core"), core::MODULES),
    (Some(c"cache"), cache::MODULES),
    (Some(c"timer"), timer::MODULES),
    (Some(c"generator"), &[(c"state_machine", state_machine::push_module), (c"state_chart", state_chart::push_module)]),
    (Some(c"analysis"), analysis::MODULES),
    (Some(c"file"), codec::FILE_MODULES),
    (Some(c"encoding"), codec::ENCODING_MODULES),
];

/// Pushes the module's table, laid out as foundation's globals are
/// (`.tree.heap`, `.nodegraph`), with the boundary probes, for the tests and the bench.
unsafe fn module(l: L) {
    l.createtable(0, NAMESPACES.len() as c_int);
    for (namespace, modules) in NAMESPACES {
        if namespace.is_some() {
            l.createtable(0, modules.len() as c_int);
        }
        for (name, push) in *modules {
            push(l);
            l.setfield(-2, name);
        }
        if let Some(namespace) = namespace {
            l.setfield(-2, namespace);
        }
    }
    library(l, c"probe", &[(c"Nothing", probe_nothing), (c"Add", probe_add)]);
}

/// Provides each native twin, whole, at its Lua twin's global, before the
/// indexes run (docs/native-foundation-plan.md).
unsafe fn provide(l: L) {
    for (namespace, modules) in NAMESPACES {
        for (name, push) in *modules {
            push(l);
            crate::module::provide(l, *namespace, name);
        }
    }
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
