//! Rust values as Lua full userdata: one metatable a type, its methods read
//! through `__index`, dropped once by `__gc`. Each value is stored behind a
//! tag (a hash of its type's name), so a method checks its argument's type
//! with two API calls rather than luaL_checkudata's registry lookup by name.

use crate::lua::{raise_owned, set_function, CFunction, L, TUSERDATA};
use std::ffi::{c_int, CStr};

/// A Rust type Lua holds as a userdata handle.
pub trait Native: Sized + 'static {
    /// The metatable's registry name, which also names the type in errors.
    const NAME: &'static CStr;
    /// Its methods and metamethods (`__len`, `__tostring`), by name.
    const METHODS: &'static [(&'static CStr, CFunction)];
    /// Its `__index`, when it answers more than its methods (fields read
    /// from the value); None reads the methods alone.
    const INDEX: Option<CFunction> = None;
}

/// FNV-1a of a type's name: the tag its values carry.
const fn tag_of(name: &CStr) -> u64 {
    let bytes = name.to_bytes();
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    let mut i = 0;
    while i < bytes.len() {
        hash ^= bytes[i] as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        i += 1;
    }
    hash
}

#[repr(C)]
struct Tagged<T> {
    tag: u64,
    value: T,
}

unsafe extern "C-unwind" fn collect<T: Native>(l: L) -> c_int {
    let value: *mut T = check::<T>(l, 1);
    // SAFETY: __gc runs once, on a userdata `push` initialised with a T.
    std::ptr::drop_in_place(value);
    0
}

/// Pushes `value` as a new userdata of its type.
///
/// # Safety
/// `l` is a live state, after `lua::open`.
pub unsafe fn push<T: Native>(l: L, value: T) {
    const { assert!(std::mem::align_of::<Tagged<T>>() <= 8, "Lua aligns userdata to 8 bytes") };
    let slot = l.newuserdata(std::mem::size_of::<Tagged<T>>()).cast::<Tagged<T>>();
    // SAFETY: newuserdata returned the size of a Tagged<T>, aligned to 8.
    slot.write(Tagged { tag: tag_of(T::NAME), value });
    if l.newmetatable(T::NAME) != 0 {
        match T::INDEX {
            Some(index) => set_function(l, c"__index", index),
            None => {
                l.pushvalue(-1);
                l.setfield(-2, c"__index");
            }
        }
        set_function(l, c"__gc", collect::<T>);
        for (name, function) in T::METHODS {
            set_function(l, name, *function);
        }
    }
    l.setmetatable(-2);
}

/// The userdata of type T at `index`, to change; anything else is a Lua
/// error naming T.
///
/// # Safety
/// `l` is a live state, after `lua::open`; the reference is used only while
/// the userdata stays on the stack, and no other reference to it is live:
/// not one from another argument (Lua may pass one userdata as two, as
/// `m:Multiply(m)` does), nor one held across a call back into Lua. A
/// binding that only reads takes `get`.
pub unsafe fn check<'a, T: Native>(l: L, index: c_int) -> &'a mut T {
    &mut *value_at::<T>(l, index)
}

/// The userdata of type T at `index`, to read; anything else is a Lua error
/// naming T. Any number of these may be live over one value at once.
///
/// # Safety
/// As `check`, except that other shared references may be live; no `&mut`
/// to the value is.
pub unsafe fn get<'a, T: Native>(l: L, index: c_int) -> &'a T {
    &*value_at::<T>(l, index)
}

unsafe fn value_at<T: Native>(l: L, index: c_int) -> *mut T {
    if l.type_of(index) == TUSERDATA {
        let tagged = l.touserdata(index).cast::<Tagged<T>>();
        // SAFETY: every userdata at least 8 bytes long that this module
        // pushed starts with its tag; a userdata of another module is read
        // only if at least that long, checked first.
        if l.objlen(index) >= std::mem::size_of::<Tagged<T>>() && (*tagged).tag == tag_of(T::NAME) {
            return std::ptr::addr_of_mut!((*tagged).value);
        }
    }
    raise_owned(l, format!("argument {index}: a {} is wanted", T::NAME.to_string_lossy()))
}
