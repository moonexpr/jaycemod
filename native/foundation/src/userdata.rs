//! Rust values as Lua full userdata: one metatable a type, its methods read
//! through `__index`, dropped once by `__gc`.

use crate::lua::{api, set_function, CFunction, L};
use std::ffi::{c_int, CStr};

/// A Rust type Lua holds as a userdata handle.
pub trait Native: Sized + 'static {
    /// The metatable's registry name, which also names the type in errors.
    const NAME: &'static CStr;
    /// Its methods and metamethods (`__len`, `__tostring`), by name.
    const METHODS: &'static [(&'static CStr, CFunction)];
}

unsafe extern "C-unwind" fn collect<T: Native>(l: L) -> c_int {
    let value = (api().checkudata)(l, 1, T::NAME.as_ptr()).cast::<T>();
    // SAFETY: __gc runs once, on a userdata `push` initialised with a T.
    std::ptr::drop_in_place(value);
    0
}

/// Pushes `value` as a new userdata of its type.
pub unsafe fn push<T: Native>(l: L, value: T) {
    const { assert!(std::mem::align_of::<T>() <= 8, "Lua aligns userdata to 8 bytes") };
    let api = api();
    let slot = (api.newuserdata)(l, std::mem::size_of::<T>()).cast::<T>();
    // SAFETY: newuserdata returned size_of::<T>() bytes, aligned to 8.
    slot.write(value);
    if (api.newmetatable)(l, T::NAME.as_ptr()) != 0 {
        (api.pushvalue)(l, -1);
        (api.setfield)(l, -2, c"__index".as_ptr());
        set_function(l, c"__gc", collect::<T>);
        for (name, function) in T::METHODS {
            set_function(l, name, *function);
        }
    }
    (api.setmetatable)(l, -2);
}

/// The userdata of type T at `index`; anything else is a Lua error naming T.
pub unsafe fn check<'a, T: Native>(l: L, index: c_int) -> &'a mut T {
    // SAFETY: checkudata returns only a userdata carrying T's metatable,
    // which `push` gave only to values it initialised as a T.
    &mut *(api().checkudata)(l, index, T::NAME.as_ptr()).cast::<T>()
}
