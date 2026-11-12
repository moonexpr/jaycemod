//! tree.heap, native: number keys in foundation's Heap (ties by push
//! order), each value kept by slot in the heap userdata's environment table.

use super::slots::{fresh_environment, keep, Kept, Slot, Taken, ValueSlots};
use crate::exchange::{pure, respond};
use crate::heap::Heap;
use crate::lua::{CFunction, L};
use crate::module::{self, Constructor};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

/// Number keys over Lua values: the heap orders slots, the userdata's
/// environment holds what each stands for.
#[derive(Default)]
pub struct KeyedHeap {
    heap: Heap<Slot>,
    slots: ValueSlots,
}

impl KeyedHeap {
    /// A slot for a value pushed under `key`, for the request to fill.
    fn push(&mut self, key: f64) -> Slot {
        let slot = self.slots.take();
        self.heap.push(key, slot);
        slot
    }

    /// The first value's slot and key, taken out.
    fn pop(&mut self) -> Option<(Slot, f64)> {
        let (slot, key) = self.heap.pop()?;
        self.slots.give_back(slot);
        Some((slot, key))
    }

    fn clear(&mut self) {
        self.heap.clear();
        self.slots.reset();
    }
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
    let key = l.checknumber(2);
    let mut heap = userdata::check::<KeyedHeap>(l, 1);
    let heap = &mut *heap;
    let slot = pure(l, || heap.push(key));
    keep(l, slot, 3);
    0
}

/// heap:Pop() -> value, key of the first, taken out; nil when empty
unsafe extern "C-unwind" fn pop(l: L) -> c_int {
    let mut heap = userdata::check::<KeyedHeap>(l, 1);
    let heap = &mut *heap;
    respond(l, || Ok(heap.pop().map(|(slot, key)| (Taken(slot), key))))
}

/// heap:Peek() -> value, key of the first, left in; nil when empty
unsafe extern "C-unwind" fn peek(l: L) -> c_int {
    let heap = userdata::get::<KeyedHeap>(l, 1);
    let heap = &*heap;
    respond(l, || Ok(heap.heap.peek().map(|(slot, key)| (Kept(slot), key))))
}

/// heap:Size(), #heap
unsafe extern "C-unwind" fn size(l: L) -> c_int {
    let heap = userdata::get::<KeyedHeap>(l, 1);
    let heap = &*heap;
    respond(l, || Ok(heap.heap.len()))
}

/// heap:Clear(): empty, the push order starting again
unsafe extern "C-unwind" fn clear(l: L) -> c_int {
    let mut heap = userdata::check::<KeyedHeap>(l, 1);
    let heap = &mut *heap;
    pure(l, || heap.clear());
    fresh_environment(l, 1);
    0
}

/// Pushes the tree.heap module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], Some(module::call::<New>));
}
