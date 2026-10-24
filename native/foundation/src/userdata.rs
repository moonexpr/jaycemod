//! Rust values as Lua full userdata: one metatable a type, its methods read
//! through `__index`, dropped once by `__gc`. Each value is stored behind a
//! tag (a hash of its type's name), so a method checks its argument's type
//! with two API calls rather than luaL_checkudata's registry lookup by name.

use crate::lua::{api, raise_owned, set_function, CFunction, L, TUSERDATA};
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
    let api = api();
    let slot = (api.newuserdata)(l, std::mem::size_of::<Tagged<T>>()).cast::<Tagged<T>>();
    // SAFETY: newuserdata returned the size of a Tagged<T>, aligned to 8.
    slot.write(Tagged { tag: tag_of(T::NAME), value });
    if (api.newmetatable)(l, T::NAME.as_ptr()) != 0 {
        match T::INDEX {
            Some(index) => set_function(l, c"__index", index),
            None => {
                (api.pushvalue)(l, -1);
                (api.setfield)(l, -2, c"__index".as_ptr());
            }
        }
        set_function(l, c"__gc", collect::<T>);
        for (name, function) in T::METHODS {
            set_function(l, name, *function);
        }
    }
    (api.setmetatable)(l, -2);
}

/// The userdata of type T at `index`; anything else is a Lua error naming T.
///
/// # Safety
/// `l` is a live state, after `lua::open`; the reference is used only while
/// the userdata stays on the stack, and no other reference to it is live.
pub unsafe fn check<'a, T: Native>(l: L, index: c_int) -> &'a mut T {
    let api = api();
    if (api.type_of)(l, index) == TUSERDATA {
        let tagged = (api.touserdata)(l, index).cast::<Tagged<T>>();
        // SAFETY: every userdata at least 8 bytes long that this module
        // pushed starts with its tag; a userdata of another module is read
        // only if at least that long, checked first.
        if (api.objlen)(l, index) >= std::mem::size_of::<Tagged<T>>() && (*tagged).tag == tag_of(T::NAME) {
            return &mut (*tagged).value;
        }
    }
    raise_owned(l, format!("argument {index}: a {} is wanted", T::NAME.to_string_lossy()))
}
