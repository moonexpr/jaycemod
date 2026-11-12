//! Rust values as Lua full userdata: one metatable a type, its methods read
//! through `__index`, dropped once by `__gc`. Each value is stored behind a
//! tag (a hash of its type's name), so a method checks its argument's type
//! with two API calls rather than luaL_checkudata's registry lookup by name.

use crate::lua::{raise_owned, raise_where, set_function, CFunction, L, TUSERDATA};
use std::cell::{Ref, RefCell, RefMut};
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
    // A RefCell, as Lua may hand one value to a method twice (`m:Multiply(m)`)
    // or call its methods from a callback it is running: the second borrow
    // is refused, never aliased.
    value: RefCell<T>,
}

unsafe extern "C-unwind" fn collect<T: Native>(l: L) -> c_int {
    let value = cell_at::<T>(l, 1);
    // SAFETY: __gc runs once, on a userdata `push` initialised with a T; no
    // borrow is live, as the value is unreachable.
    std::ptr::drop_in_place(value.cast_mut());
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
    slot.write(Tagged { tag: tag_of(T::NAME), value: RefCell::new(value) });
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

/// The userdata of type T at `index`, to change, held until the guard
/// drops (a Lua error unwinding past it drops it too); anything else is a
/// Lua error naming T, and so is a value already borrowed: by another
/// argument, or by a method of it running a callback that called back in.
///
/// # Safety
/// `l` is a live state, after `lua::open`; the guard is dropped while the
/// userdata stays on the stack.
pub unsafe fn check<'a, T: Native>(l: L, index: c_int) -> RefMut<'a, T> {
    match (*cell_at::<T>(l, index)).try_borrow_mut() {
        Ok(value) => value,
        Err(_) => in_use::<T>(l, index),
    }
}

/// The userdata of type T at `index`, to read: any number of these may be
/// held over one value, but not beside a `check`. Refused as `check` is.
///
/// # Safety
/// As `check`.
pub unsafe fn get<'a, T: Native>(l: L, index: c_int) -> Ref<'a, T> {
    match (*cell_at::<T>(l, index)).try_borrow() {
        Ok(value) => value,
        Err(_) => in_use::<T>(l, index),
    }
}

unsafe fn in_use<T: Native>(l: L, index: c_int) -> ! {
    raise_where(l, format!("argument {index}: this {} is in use by a call still running", T::NAME.to_string_lossy()))
}

unsafe fn cell_at<T: Native>(l: L, index: c_int) -> *const RefCell<T> {
    if l.type_of(index) == TUSERDATA {
        let tagged = l.touserdata(index).cast::<Tagged<T>>();
        // SAFETY: every userdata at least 8 bytes long that this module
        // pushed starts with its tag; a userdata of another module is read
        // only if at least that long, checked first.
        if l.objlen(index) >= std::mem::size_of::<Tagged<T>>() && (*tagged).tag == tag_of(T::NAME) {
            return std::ptr::addr_of!((*tagged).value);
        }
    }
    raise_owned(l, format!("argument {index}: a {} is wanted", T::NAME.to_string_lossy()))
}
