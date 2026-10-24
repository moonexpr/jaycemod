//! tree.heap, native: number keys in foundation's Heap (ties by push
//! order), each value kept by slot in the heap userdata's environment table.

use super::slots::{fresh_environment, ValueSlots};
use crate::heap::Heap;
use crate::lua::{api, CFunction, L};
use crate::module::{self, Constructor};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

#[derive(Default)]
pub struct KeyedHeap {
    heap: Heap,
    slots: ValueSlots,
}

impl Native for KeyedHeap {
    const NAME: &'static CStr = c"foundation.tree.heap";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Push", push),
        (c"Pop", pop),
        (c"Peek", peek),
        (c"Size", size),
        (c"Clear", clear),
        (c"__len", size),
    ];
}

struct New;
impl Constructor for New {
    const NEW: CFunction = new;
}

/// Heap() / Heap.New() -> an empty heap
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    userdata::push(l, KeyedHeap::default());
    fresh_environment(l, -1);
    1
}

/// heap:Push(key, value)
unsafe extern "C-unwind" fn push(l: L) -> c_int {
    let key = (api().checknumber)(l, 2);
    let heap = userdata::check::<KeyedHeap>(l, 1);
    let slot = heap.slots.store(l, 3);
    heap.heap.push(key, slot as f64);
    0
}

/// heap:Pop() -> value, key of the first, taken out; nil when empty
unsafe extern "C-unwind" fn pop(l: L) -> c_int {
    let api = api();
    let heap = userdata::check::<KeyedHeap>(l, 1);
    let Some((slot, key)) = heap.heap.pop() else {
        (api.pushnil)(l);
        return 1;
    };
    let slot = slot as u32;
    ValueSlots::push(l, slot);
    heap.slots.release(l, slot);
    (api.pushnumber)(l, key);
    2
}

/// heap:Peek() -> value, key of the first, left in; nil when empty
unsafe extern "C-unwind" fn peek(l: L) -> c_int {
    let api = api();
    let Some((slot, key)) = userdata::check::<KeyedHeap>(l, 1).heap.peek() else {
        (api.pushnil)(l);
        return 1;
    };
    ValueSlots::push(l, slot as u32);
    (api.pushnumber)(l, key);
    2
}

/// heap:Size(), #heap
unsafe extern "C-unwind" fn size(l: L) -> c_int {
    let size = userdata::check::<KeyedHeap>(l, 1).heap.len();
    (api().pushnumber)(l, size as f64);
    1
}

/// heap:Clear(): empty, the push order starting again
unsafe extern "C-unwind" fn clear(l: L) -> c_int {
    let heap = userdata::check::<KeyedHeap>(l, 1);
    heap.heap.clear();
    heap.slots.clear(l);
    0
}

/// Pushes the tree.heap module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], Some(module::call::<New>));
}
