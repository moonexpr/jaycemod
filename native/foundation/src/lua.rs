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
pub const TNUMBER: c_int = 3;
pub const TTABLE: c_int = 5;

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
    pushvalue: fn(L, c_int) = c"lua_pushvalue";
    type_of: fn(L, c_int) -> c_int = c"lua_type";
    tonumber: fn(L, c_int) -> f64 = c"lua_tonumber";
    objlen: fn(L, c_int) -> usize = c"lua_objlen";
    pushnil: fn(L) = c"lua_pushnil";
    pushnumber: fn(L, f64) = c"lua_pushnumber";
    pushcclosure: fn(L, CFunction, c_int) = c"lua_pushcclosure";
    createtable: fn(L, c_int, c_int) = c"lua_createtable";
    getfield: fn(L, c_int, *const c_char) = c"lua_getfield";
    setfield: fn(L, c_int, *const c_char) = c"lua_setfield";
    rawgeti: fn(L, c_int, c_int) = c"lua_rawgeti";
    rawseti: fn(L, c_int, c_int) = c"lua_rawseti";
    newuserdata: fn(L, usize) -> *mut c_void = c"lua_newuserdata";
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
pub unsafe fn set_function(l: L, name: &CStr, function: CFunction) {
    let api = api();
    (api.pushcclosure)(l, function, 0);
    (api.setfield)(l, -2, name.as_ptr());
}

/// A Lua error with `message`; it never returns.
pub unsafe fn raise(l: L, message: &CStr) -> ! {
    let api = api();
    let bytes = message.to_bytes();
    (api.pushlstring)(l, bytes.as_ptr().cast(), bytes.len());
    (api.error)(l);
    unreachable!("lua_error does not return")
}
