//! Lua values kept by slot in a userdata's environment table: a native
//! structure holds the slot (a number), the table holds what it stands for.

use crate::lua::{api, L};
use std::ffi::c_int;

#[derive(Default)]
pub struct ValueSlots {
    free: Vec<u32>,
    next: u32,
}

impl ValueSlots {
    /// A slot for the value at `value` (stored in the environment of the
    /// userdata at index 1).
    ///
    /// # Safety
    /// `l` is a live state with the userdata at index 1 and a value at `value`.
    pub unsafe fn store(&mut self, l: L, value: c_int) -> u32 {
        let slot = self.free.pop().unwrap_or_else(|| {
            self.next += 1;
            self.next
        });
        let api = api();
        (api.getfenv)(l, 1);
        (api.pushvalue)(l, value);
        (api.rawseti)(l, -2, slot as c_int);
        (api.settop)(l, -2);
        slot
    }

    /// Pushes the value in `slot`.
    ///
    /// # Safety
    /// As store.
    pub unsafe fn push(l: L, slot: u32) {
        let api = api();
        (api.getfenv)(l, 1);
        (api.rawgeti)(l, -1, slot as c_int);
        (api.remove)(l, -2);
    }

    /// Lets `slot` go, its value with it.
    ///
    /// # Safety
    /// As store.
    pub unsafe fn release(&mut self, l: L, slot: u32) {
        let api = api();
        (api.getfenv)(l, 1);
        (api.pushnil)(l);
        (api.rawseti)(l, -2, slot as c_int);
        (api.settop)(l, -2);
        self.free.push(slot);
    }

    /// Lets every slot go: a fresh environment for the userdata at index 1.
    ///
    /// # Safety
    /// As store.
    pub unsafe fn clear(&mut self, l: L) {
        *self = ValueSlots::default();
        fresh_environment(l, 1);
    }
}

/// Gives the userdata at `index` an empty environment table.
///
/// # Safety
/// `l` is a live state with a userdata at `index` (absolute or -1).
pub unsafe fn fresh_environment(l: L, index: c_int) {
    let api = api();
    (api.createtable)(l, 0, 0);
    (api.setfenv)(l, if index < 0 { index - 1 } else { index });
}
