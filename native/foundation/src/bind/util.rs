//! Small pieces every native module's binding uses.

use crate::lua::{L, TNIL, TNUMBER};
use std::ffi::{c_int, CStr};

/// Pushes `n`; one result.
pub unsafe fn number(l: L, n: f64) -> c_int {
    l.pushnumber(n);
    1
}

/// Pushes nil; one result.
pub unsafe fn nothing(l: L) -> c_int {
    l.pushnil();
    1
}

/// Pushes a boolean; one result.
pub unsafe fn boolean(l: L, b: bool) -> c_int {
    l.pushboolean(b as c_int);
    1
}

/// Whether the value at `index` can be read by field, as a point is: a
/// table, or a userdata answering through its metatable (GMod's Vector).
pub unsafe fn indexable(l: L, index: c_int) -> bool {
    matches!(l.type_of(index), crate::lua::TTABLE | crate::lua::TUSERDATA)
}

/// Whether argument `i` is nil or not given at all.
pub unsafe fn absent(l: L, i: c_int) -> bool {
    l.type_of(i) <= TNIL
}

/// The number at `index`, or None for any other value.
pub unsafe fn number_at(l: L, index: c_int) -> Option<f64> {
    (l.type_of(index) == TNUMBER).then(|| l.tonumber(index))
}

/// Pushes field `name` of the userdata at `ud`'s environment table.
pub unsafe fn env_field(l: L, ud: c_int, name: &CStr) {
    l.getfenv(ud);
    l.getfield(-1, name);
    l.remove(-2);
}

/// Sets field `name` of the userdata at `ud`'s environment to a new table.
pub unsafe fn env_table(l: L, ud: c_int, name: &CStr) {
    l.getfenv(ud);
    l.createtable(0, 0);
    l.setfield(-2, name);
    l.settop(-2);
}

/// Each value of the list at `list` (absolute), in order until the first
/// nil, pushed for `visit` (at the top) and popped after.
pub unsafe fn each_item(l: L, list: c_int, mut visit: impl FnMut(L, c_int)) {
    let mut i = 1;
    loop {
        l.rawgeti(list, i);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            return;
        }
        let top = l.gettop();
        visit(l, top);
        l.settop(top - 1);
        i += 1;
    }
}
