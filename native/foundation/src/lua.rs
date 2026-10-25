//! Lua 5.1's C API as LuaJIT exports it, resolved by name when the module
//! opens: from GMod's `lua_shared.dll` on Windows, from the host process (the
//! `luajit` the tests run in) elsewhere.
//!
//! Every function is `C-unwind`: a Lua error unwinds through Rust frames, so
//! a function calling one that can raise keeps nothing alive that needs a
//! destructor.

use std::ffi::{c_char, c_int, c_void, CStr};
use std::sync::OnceLock;

#[repr(C)]
pub struct State {
    _private: [u8; 0],
}
pub type L = *mut State;
pub type CFunction = unsafe extern "C-unwind" fn(L) -> c_int;

pub const GLOBALSINDEX: c_int = -10002;
pub const TNIL: c_int = 0;
pub const TSTRING: c_int = 4;
pub const TNUMBER: c_int = 3;
pub const TTABLE: c_int = 5;
pub const TUSERDATA: c_int = 7;
pub const TFUNCTION: c_int = 6;

macro_rules! api {
    ($($field:ident: fn($($arg:ty),*) $(-> $ret:ty)? = $symbol:literal;)*) => {
        /// The C API functions this module calls.
        pub struct Api {
            $(pub $field: unsafe extern "C-unwind" fn($($arg),*) $(-> $ret)?,)*
        }

        impl Api {
            unsafe fn load(find: impl Fn(&CStr) -> *mut c_void) -> Result<Self, String> {
                Ok(Self {
                    $($field: {
                        let address = find($symbol);
                        if address.is_null() {
                            return Err(format!("the Lua runtime exports no {}", $symbol.to_string_lossy()));
                        }
                        // SAFETY: the export `$symbol` has this signature in Lua 5.1's API.
                        std::mem::transmute::<*mut c_void, unsafe extern "C-unwind" fn($($arg),*) $(-> $ret)?>(address)
                    },)*
                })
            }
        }
    };
}

api! {
    gettop: fn(L) -> c_int = c"lua_gettop";
    settop: fn(L, c_int) = c"lua_settop";
    remove: fn(L, c_int) = c"lua_remove";
    pushvalue: fn(L, c_int) = c"lua_pushvalue";
    type_of: fn(L, c_int) -> c_int = c"lua_type";
    tonumber: fn(L, c_int) -> f64 = c"lua_tonumber";
    objlen: fn(L, c_int) -> usize = c"lua_objlen";
    pushnil: fn(L) = c"lua_pushnil";
    pushnumber: fn(L, f64) = c"lua_pushnumber";
    pushboolean: fn(L, c_int) = c"lua_pushboolean";
    toboolean: fn(L, c_int) -> c_int = c"lua_toboolean";
    call: fn(L, c_int, c_int) = c"lua_call";
    pushcclosure: fn(L, CFunction, c_int) = c"lua_pushcclosure";
    createtable: fn(L, c_int, c_int) = c"lua_createtable";
    getfield: fn(L, c_int, *const c_char) = c"lua_getfield";
    setfield: fn(L, c_int, *const c_char) = c"lua_setfield";
    rawgeti: fn(L, c_int, c_int) = c"lua_rawgeti";
    rawget: fn(L, c_int) = c"lua_rawget";
    rawset: fn(L, c_int) = c"lua_rawset";
    concat: fn(L, c_int) = c"lua_concat";
    replace: fn(L, c_int) = c"lua_replace";
    insert: fn(L, c_int) = c"lua_insert";
    gettable: fn(L, c_int) = c"lua_gettable";
    equal: fn(L, c_int, c_int) -> c_int = c"lua_equal";
    rawequal: fn(L, c_int, c_int) -> c_int = c"lua_rawequal";
    lessthan: fn(L, c_int, c_int) -> c_int = c"lua_lessthan";
    where_: fn(L, c_int) = c"luaL_where";
    next: fn(L, c_int) -> c_int = c"lua_next";
    getmetatable: fn(L, c_int) -> c_int = c"lua_getmetatable";
    getfenv: fn(L, c_int) = c"lua_getfenv";
    setfenv: fn(L, c_int) -> c_int = c"lua_setfenv";
    tolstring: fn(L, c_int, *mut usize) -> *const c_char = c"lua_tolstring";
    rawseti: fn(L, c_int, c_int) = c"lua_rawseti";
    newuserdata: fn(L, usize) -> *mut c_void = c"lua_newuserdata";
    touserdata: fn(L, c_int) -> *mut c_void = c"lua_touserdata";
    setmetatable: fn(L, c_int) -> c_int = c"lua_setmetatable";
    newmetatable: fn(L, *const c_char) -> c_int = c"luaL_newmetatable";
    checkudata: fn(L, c_int, *const c_char) -> *mut c_void = c"luaL_checkudata";
    checknumber: fn(L, c_int) -> f64 = c"luaL_checknumber";
    checktype: fn(L, c_int, c_int) = c"luaL_checktype";
    pushlstring: fn(L, *const c_char, usize) = c"lua_pushlstring";
    error: fn(L) -> c_int = c"lua_error";
}

static API: OnceLock<Api> = OnceLock::new();

#[cfg(windows)]
fn finder() -> Result<impl Fn(&CStr) -> *mut c_void, String> {
    extern "system" {
        fn GetModuleHandleA(name: *const c_char) -> *mut c_void;
        fn GetProcAddress(module: *mut c_void, name: *const c_char) -> *mut c_void;
    }
    // SAFETY: a module handle lookup by a NUL-terminated name.
    let module = unsafe { GetModuleHandleA(c"lua_shared.dll".as_ptr()) };
    if module.is_null() {
        return Err("lua_shared.dll is not loaded".into());
    }
    // SAFETY: the handle stays valid while GMod runs.
    Ok(move |name: &CStr| unsafe { GetProcAddress(module, name.as_ptr()) })
}

#[cfg(unix)]
fn finder() -> Result<impl Fn(&CStr) -> *mut c_void, String> {
    extern "C" {
        fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    }
    #[cfg(target_os = "macos")]
    const RTLD_DEFAULT: *mut c_void = -2isize as *mut c_void;
    #[cfg(not(target_os = "macos"))]
    const RTLD_DEFAULT: *mut c_void = std::ptr::null_mut();
    // SAFETY: a symbol lookup in the process's global scope.
    Ok(|name: &CStr| unsafe { dlsym(RTLD_DEFAULT, name.as_ptr()) })
}

/// Resolves the API once; every later call reuses it.
pub fn open() -> Result<&'static Api, String> {
    if let Some(api) = API.get() {
        return Ok(api);
    }
    let find = finder()?;
    // SAFETY: `find` returns the addresses of the named exports, or null.
    let api = unsafe { Api::load(find)? };
    Ok(API.get_or_init(|| api))
}

/// The API `open` resolved: every Lua-reachable function runs after it.
pub fn api() -> &'static Api {
    API.get().expect("the module resolved the API before any function was reachable")
}

/// Sets `table[name] = function` on the table at the top of the stack.
///
/// # Safety
/// `l` is a live state with a table at the top, after `open`.
pub unsafe fn set_function(l: L, name: &CStr, function: CFunction) {
    let api = api();
    (api.pushcclosure)(l, function, 0);
    (api.setfield)(l, -2, name.as_ptr());
}

/// Pushes `text` as a Lua string.
///
/// # Safety
/// `l` is a live state, after `open`.
pub unsafe fn push_str(l: L, text: &str) {
    (api().pushlstring)(l, text.as_ptr().cast(), text.len());
}

/// The number in `table[name]` (the table at `index`), or None when absent.
///
/// # Safety
/// `l` is a live state with a table at `index` (an absolute index), after `open`.
pub unsafe fn field_number(l: L, index: c_int, name: &CStr) -> Option<f64> {
    let api = api();
    (api.getfield)(l, index, name.as_ptr());
    let value = ((api.type_of)(l, -1) == TNUMBER).then(|| (api.tonumber)(l, -1));
    (api.settop)(l, -2);
    value
}

/// Whether `table[name]` (the table at `index`) is truthy.
///
/// # Safety
/// `l` is a live state with a table at `index` (an absolute index), after `open`.
pub unsafe fn field_truthy(l: L, index: c_int, name: &CStr) -> bool {
    let api = api();
    (api.getfield)(l, index, name.as_ptr());
    let value = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    value
}

/// The string at `index`, or None for any other value.
///
/// # Safety
/// `l` is a live state, after `open`; the bytes live while the value stays
/// on the stack.
pub unsafe fn string_at<'a>(l: L, index: c_int) -> Option<&'a [u8]> {
    let api = api();
    if (api.type_of)(l, index) != TSTRING {
        return None;
    }
    let mut len = 0usize;
    let text = (api.tolstring)(l, index, &mut len);
    Some(std::slice::from_raw_parts(text.cast::<u8>(), len))
}

/// Calls `visit(l)` with each key at -2 and its value at -1 of the table at
/// `index` (absolute), in `next`'s order.
///
/// # Safety
/// `l` is a live state with a table at `index`, after `open`; `visit` leaves
/// the stack as it found it.
pub unsafe fn each(l: L, index: c_int, mut visit: impl FnMut(L)) {
    let api = api();
    (api.pushnil)(l);
    while (api.next)(l, index) != 0 {
        visit(l);
        (api.settop)(l, -2);
    }
}

/// A Lua error with an owned `message`, pushed and dropped before raising.
///
/// # Safety
/// As `raise`.
pub unsafe fn raise_owned(l: L, message: String) -> ! {
    push_str(l, &message);
    drop(message);
    (api().error)(l);
    unreachable!("lua_error does not return")
}

/// A Lua error with `message`; it never returns.
///
/// # Safety
/// `l` is a live state, after `open`; the caller holds nothing that needs a
/// destructor, since the error unwinds past it.
pub unsafe fn raise(l: L, message: &CStr) -> ! {
    let api = api();
    let bytes = message.to_bytes();
    (api.pushlstring)(l, bytes.as_ptr().cast(), bytes.len());
    (api.error)(l);
    unreachable!("lua_error does not return")
}

/// A Lua error with `message` after the position of the Lua code that
/// called the running C function ("file:line: "), as Lua's error(message,
/// 2) gives from inside a Lua function; it never returns.
///
/// # Safety
/// As `raise`.
pub unsafe fn raise_where(l: L, message: String) -> ! {
    raise_at(l, 1, message)
}

/// A Lua error with `message` after the position of the Lua code `level`
/// calls up from the running C function (1: its caller), as Lua's
/// error(message, level + 1) gives from inside a Lua function.
///
/// # Safety
/// As `raise`.
pub unsafe fn raise_at(l: L, level: c_int, message: String) -> ! {
    let api = api();
    (api.where_)(l, level);
    push_str(l, &message);
    drop(message);
    (api.concat)(l, 2);
    (api.error)(l);
    unreachable!("lua_error does not return")
}

/// Pushes tostring(value at `index`), as Lua's tostring gives it.
///
/// # Safety
/// `l` is a live state, after `open`.
pub unsafe fn push_tostring(l: L, index: c_int) {
    let api = api();
    let index = if index < 0 && index > GLOBALSINDEX { (api.gettop)(l) + index + 1 } else { index };
    (api.getfield)(l, GLOBALSINDEX, c"tostring".as_ptr());
    (api.pushvalue)(l, index);
    (api.call)(l, 1, 1);
}

/// tostring(value at `index`), as an owned string.
///
/// # Safety
/// As `push_tostring`.
pub unsafe fn tostring(l: L, index: c_int) -> String {
    push_tostring(l, index);
    let text = string_at(l, -1).map(|b| String::from_utf8_lossy(b).into_owned()).unwrap_or_default();
    (api().settop)(l, -2);
    text
}
