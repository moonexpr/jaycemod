//! `probe`: seams of the boundary itself, in the tests' and the bench's table
//! only (`luaopen_foundation`); a server never installs them.

use crate::lua::{raise, CFunction, L};
use std::ffi::{c_int, CStr};
use std::sync::atomic::{AtomicU32, Ordering};

/// probe.Nothing(): the cost of a call across the boundary and nothing else.
unsafe extern "C-unwind" fn nothing(_l: L) -> c_int {
    0
}

/// probe.Add(a, b) -> a + b: a call that reads two numbers and returns one.
unsafe extern "C-unwind" fn add(l: L) -> c_int {
    let sum = l.checknumber(1) + l.checknumber(2);
    l.pushnumber(sum);
    1
}

static DROPPED: AtomicU32 = AtomicU32::new(0);

/// A value whose drop is counted.
struct Witness;

impl Drop for Witness {
    fn drop(&mut self) {
        DROPPED.fetch_add(1, Ordering::Relaxed);
    }
}

/// probe.RaiseDropping(): raises a Lua error while a Rust value is alive in
/// its frame, which `Dropped` counts once the error has unwound past it.
unsafe extern "C-unwind" fn raise_dropping(l: L) -> c_int {
    let _witness = Witness;
    raise(l, c"raised with a value alive")
}

/// probe.Dropped() -> how many values RaiseDropping's errors have dropped.
unsafe extern "C-unwind" fn dropped(l: L) -> c_int {
    l.pushnumber(DROPPED.load(Ordering::Relaxed) as f64);
    1
}

pub const FUNCTIONS: &[(&CStr, CFunction)] =
    &[(c"Nothing", nothing), (c"Add", add), (c"RaiseDropping", raise_dropping), (c"Dropped", dropped)];
