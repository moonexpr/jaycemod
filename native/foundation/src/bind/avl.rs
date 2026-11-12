//! tree.avl, native: foundation's Avl (number keys), each value kept by slot.

use super::slots::{fresh_environment, keep, let_go, Kept, Slot, ValueSlots};
use super::util::number_at;
use crate::exchange::{pure, respond};
use crate::avl::Avl;
use crate::lua::{CFunction, L};
use crate::module::{self, Constructor};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

/// Number keys over Lua values, in order: the tree orders slots, the
/// userdata's environment holds what each stands for.
#[derive(Default)]
pub struct Tree {
    avl: Avl<Slot>,
    slots: ValueSlots,
}

impl Tree {
    /// A slot for the value set under `key`, and the slot of the value it
    /// replaced, given back.
    fn insert(&mut self, key: f64) -> (Slot, Option<Slot>) {
        let slot = self.slots.take();
        let replaced = self.avl.insert(key, slot);
        if let Some(old) = replaced {
            self.slots.give_back(old);
        }
        (slot, replaced)
    }

    /// The slot of the value under `key`, given back, if it was there.
    fn remove(&mut self, key: f64) -> Option<Slot> {
        let removed = self.avl.remove(key)?;
        self.slots.give_back(removed);
        Some(removed)
    }
}

/// An entry as the response: key, value; or nil.
fn entry(found: Option<(f64, Slot)>) -> Option<(f64, Kept)> {
    found.map(|(key, slot)| (key, Kept(slot)))
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
    let key = l.checknumber(2);
    let mut tree = userdata::check::<Tree>(l, 1);
    let tree = &mut *tree;
    let (slot, replaced) = pure(l, || tree.insert(key));
    if let Some(old) = replaced {
        let_go(l, old);
    }
    keep(l, slot, 3);
    0
}

/// tree:Get(key) -> its value, or nil
unsafe extern "C-unwind" fn get(l: L) -> c_int {
    let key = l.checknumber(2);
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(tree.avl.get(key).map(Kept)))
}

/// tree:Remove(key) -> whether it was there
unsafe extern "C-unwind" fn remove(l: L) -> c_int {
    let key = l.checknumber(2);
    let mut tree = userdata::check::<Tree>(l, 1);
    let tree = &mut *tree;
    let removed = pure(l, || tree.remove(key));
    if let Some(slot) = removed {
        let_go(l, slot);
    }
    respond(l, || Ok(removed.is_some()))
}

unsafe extern "C-unwind" fn size(l: L) -> c_int {
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(tree.avl.len()))
}

unsafe extern "C-unwind" fn height(l: L) -> c_int {
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(f64::from(tree.avl.height())))
}

unsafe extern "C-unwind" fn min(l: L) -> c_int {
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(entry(tree.avl.min())))
}

unsafe extern "C-unwind" fn max(l: L) -> c_int {
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(entry(tree.avl.max())))
}

unsafe extern "C-unwind" fn floor(l: L) -> c_int {
    let key = l.checknumber(2);
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(entry(tree.avl.floor(key))))
}

unsafe extern "C-unwind" fn ceiling(l: L) -> c_int {
    let key = l.checknumber(2);
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(entry(tree.avl.ceiling(key))))
}

/// The generic for's step: the entry after `key` (the least, for nil).
unsafe extern "C-unwind" fn step(l: L) -> c_int {
    let after = number_at(l, 2);
    let tree = userdata::get::<Tree>(l, 1);
    let tree = &*tree;
    respond(l, || Ok(entry(after.map_or_else(|| tree.avl.min(), |key| tree.avl.higher(key)))))
}

/// tree:Pairs() -> step, tree, nil: the entries in order
unsafe extern "C-unwind" fn pairs(l: L) -> c_int {
    userdata::check::<Tree>(l, 1);
    l.pushcclosure(step, 0);
    l.pushvalue(1);
    l.pushnil();
    3
}

/// Pushes the tree.avl module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], Some(module::call::<New>));
}
