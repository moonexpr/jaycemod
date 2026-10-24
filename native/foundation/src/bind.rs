//! The module's Lua face: `foundation.native`, its structures and probes.

use crate::heap::Heap;
use crate::lua::{api, set_function, CFunction, GLOBALSINDEX, L, TTABLE};
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

/// Builds `foundation.native` and leaves it on the stack. The global
/// `foundation` is the Lua modules' (module() makes it), so it is extended,
/// or made when the binary opens first.
pub unsafe fn open(l: L) {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"foundation".as_ptr());
    if (api.type_of)(l, -1) != TTABLE {
        (api.settop)(l, -2);
        (api.createtable)(l, 0, 1);
        (api.pushvalue)(l, -1);
        (api.setfield)(l, GLOBALSINDEX, c"foundation".as_ptr());
    }
    (api.createtable)(l, 0, 2);
    library(l, c"heap", &[(c"New", heap_new)]);
    library(l, c"probe", &[(c"Nothing", probe_nothing), (c"Add", probe_add)]);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, -3, c"native".as_ptr());
}

/// GMod's entry point.
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(l: L) -> c_int {
    if crate::lua::open().is_err() {
        return 0;
    }
    open(l);
    (api().settop)(l, -3);
    0
}

#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_close(_l: L) -> c_int {
    0
}

/// Stock Lua's entry point (`package.loadlib`), for the LuaJIT tests:
/// returns `foundation.native`.
#[no_mangle]
pub unsafe extern "C-unwind" fn luaopen_foundation(l: L) -> c_int {
    if crate::lua::open().is_err() {
        return 0;
    }
    open(l);
    1
}
