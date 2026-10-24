//! The module's Lua face: `foundation.native`, its structures and probes.

use crate::heap::Heap;
use crate::lua::{api, set_function, CFunction, L};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

impl Native for Heap {
    const NAME: &'static CStr = c"foundation.native.heap";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Push", heap_push),
        (c"Pop", heap_pop),
        (c"Peek", heap_peek),
        (c"Size", heap_size),
        (c"Clear", heap_clear),
        (c"__len", heap_size),
    ];
}

/// heap.New() -> an empty heap.
unsafe extern "C-unwind" fn heap_new(l: L) -> c_int {
    userdata::push(l, Heap::default());
    1
}

/// heap:Push(key, value)
unsafe extern "C-unwind" fn heap_push(l: L) -> c_int {
    let api = api();
    let key = (api.checknumber)(l, 2);
    let value = (api.checknumber)(l, 3);
    userdata::check::<Heap>(l, 1).push(key, value);
    0
}

unsafe fn push_entry(l: L, entry: Option<(f64, f64)>) -> c_int {
    let api = api();
    match entry {
        Some((value, key)) => {
            (api.pushnumber)(l, value);
            (api.pushnumber)(l, key);
            2
        }
        None => {
            (api.pushnil)(l);
            1
        }
    }
}

/// heap:Pop() -> the first value and its key, or nil.
unsafe extern "C-unwind" fn heap_pop(l: L) -> c_int {
    let entry = userdata::check::<Heap>(l, 1).pop();
    push_entry(l, entry)
}

/// heap:Peek() -> the first value and its key, left in, or nil.
unsafe extern "C-unwind" fn heap_peek(l: L) -> c_int {
    let entry = userdata::check::<Heap>(l, 1).peek();
    push_entry(l, entry)
}

/// heap:Size(), #heap
unsafe extern "C-unwind" fn heap_size(l: L) -> c_int {
    let size = userdata::check::<Heap>(l, 1).len();
    (api().pushnumber)(l, size as f64);
    1
}

/// heap:Clear()
unsafe extern "C-unwind" fn heap_clear(l: L) -> c_int {
    userdata::check::<Heap>(l, 1).clear();
    0
}

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

/// Pushes the module's table: its structures and probes, for the tests and
/// the boundary bench. No foundation module has a native twin of the same
/// contract yet, so the game's entry point installs nothing over a global.
unsafe fn module(l: L) {
    (api().createtable)(l, 0, 2);
    library(l, c"heap", &[(c"New", heap_new)]);
    library(l, c"probe", &[(c"Nothing", probe_nothing), (c"Add", probe_add)]);
}

/// GMod's entry point: the API resolved; nothing installed yet (see module).
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(_l: L) -> c_int {
    let _ = crate::lua::open();
    0
}

#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_close(_l: L) -> c_int {
    0
}

/// Stock Lua's entry point (`package.loadlib`), for the LuaJIT tests and the
/// bench: returns the module's table, installing nothing.
#[no_mangle]
pub unsafe extern "C-unwind" fn luaopen_foundation(l: L) -> c_int {
    if crate::lua::open().is_err() {
        return 0;
    }
    module(l);
    1
}
