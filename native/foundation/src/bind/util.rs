//! Small pieces every native module's binding uses.

use crate::lua::{api, L, TNIL, TNUMBER};
use std::ffi::{c_int, CStr};

/// Pushes `n`; one result.
pub unsafe fn number(l: L, n: f64) -> c_int {
    (api().pushnumber)(l, n);
    1
}

/// Pushes nil; one result.
pub unsafe fn nothing(l: L) -> c_int {
    (api().pushnil)(l);
    1
}

/// Pushes a boolean; one result.
pub unsafe fn boolean(l: L, b: bool) -> c_int {
    (api().pushboolean)(l, b as c_int);
    1
}

/// Whether argument `i` is nil or not given at all.
pub unsafe fn absent(l: L, i: c_int) -> bool {
    (api().type_of)(l, i) <= TNIL
}

/// The number at `index`, or None for any other value.
pub unsafe fn number_at(l: L, index: c_int) -> Option<f64> {
    let api = api();
    ((api.type_of)(l, index) == TNUMBER).then(|| (api.tonumber)(l, index))
}

/// Pushes field `name` of the userdata at `ud`'s environment table.
pub unsafe fn env_field(l: L, ud: c_int, name: &CStr) {
    let api = api();
    (api.getfenv)(l, ud);
    (api.getfield)(l, -1, name.as_ptr());
    (api.remove)(l, -2);
}

/// Sets field `name` of the userdata at `ud`'s environment to a new table.
pub unsafe fn env_table(l: L, ud: c_int, name: &CStr) {
    let api = api();
    (api.getfenv)(l, ud);
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, name.as_ptr());
    (api.settop)(l, -2);
}

/// Each value of the list at `list` (absolute), in order until the first
/// nil, pushed for `visit` (at the top) and popped after.
pub unsafe fn each_item(l: L, list: c_int, mut visit: impl FnMut(L, c_int)) {
    let api = api();
    let mut i = 1;
    loop {
        (api.rawgeti)(l, list, i);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            return;
        }
        let top = (api.gettop)(l);
        visit(l, top);
        (api.settop)(l, top - 1);
        i += 1;
    }
}
