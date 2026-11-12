//! Lua values kept by slot in a userdata's environment table: a native
//! structure holds the slot, the table holds the value it stands for.
//!
//! The two halves of the exchange: `ValueSlots` is the model, slot numbers
//! handed out and taken back in Rust alone; `keep`, `Kept` and `Taken` are
//! the wire, the request's value written to its slot and a slot's value
//! written back as the response.

use crate::exchange::Reply;
use crate::lua::L;
use std::ffi::c_int;

/// The place of one Lua value in its userdata's environment table.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Slot(u32);

impl Slot {
    fn index(self) -> c_int {
        self.0 as c_int
    }
}

/// Which slots are in use: freed ones are handed out again first.
#[derive(Default)]
pub struct ValueSlots {
    free: Vec<u32>,
    next: u32,
}

impl ValueSlots {
    /// A slot no value holds.
    pub fn take(&mut self) -> Slot {
        Slot(self.free.pop().unwrap_or_else(|| {
            self.next += 1;
            self.next
        }))
    }

    /// Hands `slot` back, for its environment entry to be let go (`Taken`,
    /// `let_go`).
    pub fn give_back(&mut self, slot: Slot) {
        self.free.push(slot.0);
    }

    /// Every slot free, for an environment made new (`fresh_environment`).
    pub fn reset(&mut self) {
        *self = ValueSlots::default();
    }
}

/// Writes the value at `value` to `slot`, in the environment of the userdata
/// at index 1.
///
/// # Safety
/// `l` is the running call's state, its userdata at index 1 and a value at
/// `value`.
pub unsafe fn keep(l: L, slot: Slot, value: c_int) {
    l.getfenv(1);
    l.pushvalue(value);
    l.rawseti(-2, slot.index());
    l.settop(-2);
}

/// Clears `slot`'s entry, so the value it held may be collected.
///
/// # Safety
/// As `keep`.
pub unsafe fn let_go(l: L, slot: Slot) {
    l.getfenv(1);
    l.pushnil();
    l.rawseti(-2, slot.index());
    l.settop(-2);
}

/// The response of the value in a slot, left kept.
pub struct Kept(pub Slot);

impl Reply for Kept {
    unsafe fn reply(self, l: L) -> c_int {
        l.getfenv(1);
        l.rawgeti(-1, self.0.index());
        l.remove(-2);
        1
    }
}

/// The response of the value in a slot given back: written, then let go.
pub struct Taken(pub Slot);

impl Reply for Taken {
    unsafe fn reply(self, l: L) -> c_int {
        Kept(self.0).reply(l);
        let_go(l, self.0);
        1
    }
}

/// The response of the values in some slots, a fresh list in their order.
pub struct KeptList(pub Vec<Slot>);

impl Reply for KeptList {
    unsafe fn reply(self, l: L) -> c_int {
        l.createtable(self.0.len() as c_int, 0);
        for (i, slot) in self.0.into_iter().enumerate() {
            Kept(slot).reply(l);
            l.rawseti(-2, i as c_int + 1);
        }
        1
    }
}

/// Gives the userdata at `index` an empty environment table.
///
/// # Safety
/// `l` is a live state with a userdata at `index` (absolute or -1).
pub unsafe fn fresh_environment(l: L, index: c_int) {
    l.createtable(0, 0);
    l.setfenv(if index < 0 { index - 1 } else { index });
}
