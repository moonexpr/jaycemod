//! tree.avl, native: foundation's Avl (number keys), each value kept by slot.

use super::slots::{fresh_environment, ValueSlots};
use crate::avl::Avl;
use crate::lua::{api, CFunction, L, TNUMBER};
use crate::module::{self, Constructor};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

#[derive(Default)]
pub struct Tree {
    avl: Avl,
    slots: ValueSlots,
}

impl Native for Tree {
    const NAME: &'static CStr = c"foundation.tree.avl";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Insert", insert),
        (c"Get", get),
        (c"Remove", remove),
        (c"Size", size),
        (c"Height", height),
        (c"Min", min),
        (c"Max", max),
        (c"Floor", floor),
        (c"Ceiling", ceiling),
        (c"Pairs", pairs),
        (c"__len", size),
    ];
}

struct New;
impl Constructor for New {
    const NEW: CFunction = new;
}

/// Avl() / Avl.New() -> an empty tree
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    userdata::push(l, Tree::default());
    fresh_environment(l, -1);
    1
}

/// tree:Insert(key, value): a key inserted again takes the new value
unsafe extern "C-unwind" fn insert(l: L) -> c_int {
    let key = (api().checknumber)(l, 2);
    let tree = userdata::check::<Tree>(l, 1);
    let slot = tree.slots.store(l, 3);
    if let Some(old) = tree.avl.insert(key, slot) {
        tree.slots.release(l, old);
    }
    0
}

/// tree:Get(key) -> its value, or nil
unsafe extern "C-unwind" fn get(l: L) -> c_int {
    let key = (api().checknumber)(l, 2);
    match userdata::check::<Tree>(l, 1).avl.get(key) {
        Some(slot) => ValueSlots::push(l, slot),
        None => (api().pushnil)(l),
    }
    1
}

/// tree:Remove(key) -> whether it was there
unsafe extern "C-unwind" fn remove(l: L) -> c_int {
    let key = (api().checknumber)(l, 2);
    let tree = userdata::check::<Tree>(l, 1);
    let removed = tree.avl.remove(key);
    if let Some(slot) = removed {
        tree.slots.release(l, slot);
    }
    (api().pushboolean)(l, removed.is_some() as c_int);
    1
}

unsafe extern "C-unwind" fn size(l: L) -> c_int {
    let size = userdata::check::<Tree>(l, 1).avl.len();
    (api().pushnumber)(l, size as f64);
    1
}

unsafe extern "C-unwind" fn height(l: L) -> c_int {
    let height = userdata::check::<Tree>(l, 1).avl.height();
    (api().pushnumber)(l, height as f64);
    1
}

/// Pushes key, value, or nil.
unsafe fn entry(l: L, found: Option<(f64, u32)>) -> c_int {
    match found {
        Some((key, slot)) => {
            (api().pushnumber)(l, key);
            ValueSlots::push(l, slot);
            2
        }
        None => {
            (api().pushnil)(l);
            1
        }
    }
}

unsafe extern "C-unwind" fn min(l: L) -> c_int {
    let found = userdata::check::<Tree>(l, 1).avl.min();
    entry(l, found)
}

unsafe extern "C-unwind" fn max(l: L) -> c_int {
    let found = userdata::check::<Tree>(l, 1).avl.max();
    entry(l, found)
}

unsafe extern "C-unwind" fn floor(l: L) -> c_int {
    let key = (api().checknumber)(l, 2);
    let found = userdata::check::<Tree>(l, 1).avl.floor(key);
    entry(l, found)
}

unsafe extern "C-unwind" fn ceiling(l: L) -> c_int {
    let key = (api().checknumber)(l, 2);
    let found = userdata::check::<Tree>(l, 1).avl.ceiling(key);
    entry(l, found)
}

/// The generic for's step: the entry after `key` (the least, for nil).
unsafe extern "C-unwind" fn step(l: L) -> c_int {
    let api = api();
    let after = ((api.type_of)(l, 2) == TNUMBER).then(|| (api.tonumber)(l, 2));
    let tree = userdata::check::<Tree>(l, 1);
    let found = match after {
        Some(key) => tree.avl.higher(key),
        None => tree.avl.min(),
    };
    entry(l, found)
}

/// tree:Pairs() -> step, tree, nil: the entries in order
unsafe extern "C-unwind" fn pairs(l: L) -> c_int {
    let api = api();
    userdata::check::<Tree>(l, 1);
    (api.pushcclosure)(l, step, 0);
    (api.pushvalue)(l, 1);
    (api.pushnil)(l);
    3
}

/// Pushes the tree.avl module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], Some(module::call::<New>));
}
