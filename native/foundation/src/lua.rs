//! Lua 5.1's C API as LuaJIT exports it, resolved by name when the module
//! opens: from GMod's `lua_shared.dll` on Windows, from the host process (the
//! `luajit` the tests run in) elsewhere.
//!
//! Every function is `C-unwind`: a Lua error unwinds through the Rust frames
//! between it and the `pcall` catching it, and their destructors run
//! (`tests/native_boundary_test.lua`). A Rust panic must never reach Lua:
//! the runtime aborts the process when foreign code catches one. Bindings
//! keep panics inside `exchange::respond`.

use std::ffi::{c_char, c_int, c_void, CStr};
use std::sync::OnceLock;

#[repr(C)]
pub struct State {
    _private: [u8; 0],
}

/// A Lua state, as the running C function was handed it: the transport a
/// binding reads its request from and writes its response to. Lua's C API
/// is its methods, named as the manual names them without `lua_`.
///
/// Every method is unsafe under one contract: the state is the one Lua is
/// running this call in, and every stack index names a live slot (or, for
/// those that take one, an absolute index or pseudo-index). LuaJIT grows the
/// stack on a push, so pushes need no `checkstack`.
///
/// Not `Send`: a handler that must not touch Lua (`exchange::respond`) is
/// held to it by that bound.
#[repr(transparent)]
#[derive(Clone, Copy)]
pub struct L(*mut State);

pub type CFunction = unsafe extern "C-unwind" fn(L) -> c_int;

pub const GLOBALSINDEX: c_int = -10002;
pub const TNIL: c_int = 0;
pub const TBOOLEAN: c_int = 1;
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
    pcall: fn(L, c_int, c_int, c_int) -> c_int = c"lua_pcall";
    pushcclosure: fn(L, CFunction, c_int) = c"lua_pushcclosure";
    createtable: fn(L, c_int, c_int) = c"lua_createtable";
    getfield: fn(L, c_int, *const c_char) = c"lua_getfield";
    setfield: fn(L, c_int, *const c_char) = c"lua_setfield";
    settable: fn(L, c_int) = c"lua_settable";
    iscfunction: fn(L, c_int) -> c_int = c"lua_iscfunction";
    rawgeti: fn(L, c_int, c_int) = c"lua_rawgeti";
    rawget: fn(L, c_int) = c"lua_rawget";
    rawset: fn(L, c_int) = c"lua_rawset";
    concat: fn(L, c_int) = c"lua_concat";
    replace: fn(L, c_int) = c"lua_replace";
    insert: fn(L, c_int) = c"lua_insert";
    gettable: fn(L, c_int) = c"lua_gettable";
    yield_: fn(L, c_int) -> c_int = c"lua_yield";
    pushthread: fn(L) -> c_int = c"lua_pushthread";
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

/// The C API as methods: each forwards to the function `open` resolved.
/// Those taking a field or type name take it as a `&CStr`.
#[allow(clippy::missing_safety_doc, reason = "one contract for all, on `L`")]
impl L {
    #[inline(always)]
    pub unsafe fn gettop(self) -> c_int {
        (api().gettop)(self)
    }
    #[inline(always)]
    pub unsafe fn settop(self, index: c_int) {
        (api().settop)(self, index)
    }
    #[inline(always)]
    pub unsafe fn remove(self, index: c_int) {
        (api().remove)(self, index)
    }
    #[inline(always)]
    pub unsafe fn pushvalue(self, index: c_int) {
        (api().pushvalue)(self, index)
    }
    #[inline(always)]
    pub unsafe fn type_of(self, index: c_int) -> c_int {
        (api().type_of)(self, index)
    }
    #[inline(always)]
    pub unsafe fn tonumber(self, index: c_int) -> f64 {
        (api().tonumber)(self, index)
    }
    #[inline(always)]
    pub unsafe fn objlen(self, index: c_int) -> usize {
        (api().objlen)(self, index)
    }
    #[inline(always)]
    pub unsafe fn pushnil(self) {
        (api().pushnil)(self)
    }
    #[inline(always)]
    pub unsafe fn pushnumber(self, n: f64) {
        (api().pushnumber)(self, n)
    }
    #[inline(always)]
    pub unsafe fn pushboolean(self, b: c_int) {
        (api().pushboolean)(self, b)
    }
    #[inline(always)]
    pub unsafe fn toboolean(self, index: c_int) -> c_int {
        (api().toboolean)(self, index)
    }
    #[inline(always)]
    pub unsafe fn call(self, args: c_int, results: c_int) {
        (api().call)(self, args, results)
    }
    #[inline(always)]
    pub unsafe fn pcall(self, args: c_int, results: c_int, handler: c_int) -> c_int {
        (api().pcall)(self, args, results, handler)
    }
    #[inline(always)]
    pub unsafe fn pushcclosure(self, function: CFunction, upvalues: c_int) {
        (api().pushcclosure)(self, function, upvalues)
    }
    #[inline(always)]
    pub unsafe fn createtable(self, array: c_int, hash: c_int) {
        (api().createtable)(self, array, hash)
    }
    #[inline(always)]
    pub unsafe fn getfield(self, index: c_int, name: &CStr) {
        (api().getfield)(self, index, name.as_ptr())
    }
    #[inline(always)]
    pub unsafe fn setfield(self, index: c_int, name: &CStr) {
        (api().setfield)(self, index, name.as_ptr())
    }
    #[inline(always)]
    pub unsafe fn settable(self, index: c_int) {
        (api().settable)(self, index)
    }
    #[inline(always)]
    pub unsafe fn iscfunction(self, index: c_int) -> c_int {
        (api().iscfunction)(self, index)
    }
    #[inline(always)]
    pub unsafe fn rawgeti(self, index: c_int, n: c_int) {
        (api().rawgeti)(self, index, n)
    }
    #[inline(always)]
    pub unsafe fn rawget(self, index: c_int) {
        (api().rawget)(self, index)
    }
    #[inline(always)]
    pub unsafe fn rawset(self, index: c_int) {
        (api().rawset)(self, index)
    }
    #[inline(always)]
    pub unsafe fn concat(self, n: c_int) {
        (api().concat)(self, n)
    }
    #[inline(always)]
    pub unsafe fn replace(self, index: c_int) {
        (api().replace)(self, index)
    }
    #[inline(always)]
    pub unsafe fn insert(self, index: c_int) {
        (api().insert)(self, index)
    }
    #[inline(always)]
    pub unsafe fn gettable(self, index: c_int) {
        (api().gettable)(self, index)
    }
    #[inline(always)]
    pub unsafe fn yield_(self, results: c_int) -> c_int {
        (api().yield_)(self, results)
    }
    #[inline(always)]
    pub unsafe fn pushthread(self) -> c_int {
        (api().pushthread)(self)
    }
    #[inline(always)]
    pub unsafe fn equal(self, a: c_int, b: c_int) -> c_int {
        (api().equal)(self, a, b)
    }
    #[inline(always)]
    pub unsafe fn rawequal(self, a: c_int, b: c_int) -> c_int {
        (api().rawequal)(self, a, b)
    }
    #[inline(always)]
    pub unsafe fn lessthan(self, a: c_int, b: c_int) -> c_int {
        (api().lessthan)(self, a, b)
    }
    #[inline(always)]
    pub unsafe fn where_(self, level: c_int) {
        (api().where_)(self, level)
    }
    #[inline(always)]
    pub unsafe fn next(self, index: c_int) -> c_int {
        (api().next)(self, index)
    }
    #[inline(always)]
    pub unsafe fn getmetatable(self, index: c_int) -> c_int {
        (api().getmetatable)(self, index)
    }
    #[inline(always)]
    pub unsafe fn getfenv(self, index: c_int) {
        (api().getfenv)(self, index)
    }
    #[inline(always)]
    pub unsafe fn setfenv(self, index: c_int) -> c_int {
        (api().setfenv)(self, index)
    }
    #[inline(always)]
    pub unsafe fn tolstring(self, index: c_int, len: *mut usize) -> *const c_char {
        (api().tolstring)(self, index, len)
    }
    #[inline(always)]
    pub unsafe fn rawseti(self, index: c_int, n: c_int) {
        (api().rawseti)(self, index, n)
    }
    #[inline(always)]
    pub unsafe fn newuserdata(self, size: usize) -> *mut c_void {
        (api().newuserdata)(self, size)
    }
    #[inline(always)]
    pub unsafe fn touserdata(self, index: c_int) -> *mut c_void {
        (api().touserdata)(self, index)
    }
    #[inline(always)]
    pub unsafe fn setmetatable(self, index: c_int) -> c_int {
        (api().setmetatable)(self, index)
    }
    #[inline(always)]
    pub unsafe fn newmetatable(self, name: &CStr) -> c_int {
        (api().newmetatable)(self, name.as_ptr())
    }
    #[inline(always)]
    pub unsafe fn checkudata(self, index: c_int, name: &CStr) -> *mut c_void {
        (api().checkudata)(self, index, name.as_ptr())
    }
    #[inline(always)]
    pub unsafe fn checknumber(self, index: c_int) -> f64 {
        (api().checknumber)(self, index)
    }
    #[inline(always)]
    pub unsafe fn checktype(self, index: c_int, kind: c_int) {
        (api().checktype)(self, index, kind)
    }
    #[inline(always)]
    pub unsafe fn pushlstring(self, text: *const c_char, len: usize) {
        (api().pushlstring)(self, text, len)
    }
    #[inline(always)]
    pub unsafe fn error(self) -> c_int {
        (api().error)(self)
    }
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

/// `open`, from a module's entry point: when the API cannot be resolved,
/// the reason is raised as a Lua error, so the `require` loading the module
/// stops the load with it rather than leaving the server on the Lua twins
/// unsaid. None only when not even `lua_pushlstring` and `lua_error` resolve
/// (no Lua at all), after writing the reason to stderr.
///
/// # Safety
/// `l` is the state calling the entry point.
pub unsafe fn open_or_raise(l: L) -> Option<&'static Api> {
    let reason = match open() {
        Ok(api) => return Some(api),
        Err(reason) => format!("foundation's native modules cannot load: {reason}"),
    };
    type PushString = unsafe extern "C-unwind" fn(L, *const c_char, usize);
    type Error = unsafe extern "C-unwind" fn(L) -> c_int;
    if let Ok(find) = finder() {
        let (push, error) = (find(c"lua_pushlstring"), find(c"lua_error"));
        if !push.is_null() && !error.is_null() {
            // SAFETY: Lua 5.1's exports of these names have these signatures.
            let (push, error) = (std::mem::transmute::<*mut c_void, PushString>(push), std::mem::transmute::<*mut c_void, Error>(error));
            push(l, reason.as_ptr().cast(), reason.len());
            drop(reason);
            error(l);
            unreachable!("lua_error does not return");
        }
    }
    eprintln!("{reason}");
    None
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
    l.pushcclosure(function, 0);
    l.setfield(-2, name);
}

/// Pushes `text` as a Lua string.
///
/// # Safety
/// `l` is a live state, after `open`.
pub unsafe fn push_str(l: L, text: &str) {
    l.pushlstring(text.as_ptr().cast(), text.len());
}

/// The number in `table[name]` (the table at `index`), or None when absent.
///
/// # Safety
/// `l` is a live state with a table at `index` (an absolute index), after `open`.
pub unsafe fn field_number(l: L, index: c_int, name: &CStr) -> Option<f64> {
    l.getfield(index, name);
    let value = (l.type_of(-1) == TNUMBER).then(|| l.tonumber(-1));
    l.settop(-2);
    value
}

/// Whether `table[name]` (the table at `index`) is truthy.
///
/// # Safety
/// `l` is a live state with a table at `index` (an absolute index), after `open`.
pub unsafe fn field_truthy(l: L, index: c_int, name: &CStr) -> bool {
    l.getfield(index, name);
    let value = l.toboolean(-1) != 0;
    l.settop(-2);
    value
}

/// The string at `index`, or None for any other value.
///
/// # Safety
/// `l` is a live state, after `open`; the bytes live while the value stays
/// on the stack.
pub unsafe fn string_at<'a>(l: L, index: c_int) -> Option<&'a [u8]> {
    if l.type_of(index) != TSTRING {
        return None;
    }
    let mut len = 0usize;
    let text = l.tolstring(index, &mut len);
    Some(std::slice::from_raw_parts(text.cast::<u8>(), len))
}

/// Calls `visit(l)` with each key at -2 and its value at -1 of the table at
/// `index` (absolute), in `next`'s order.
///
/// # Safety
/// `l` is a live state with a table at `index`, after `open`; `visit` leaves
/// the stack as it found it.
pub unsafe fn each(l: L, index: c_int, mut visit: impl FnMut(L)) {
    l.pushnil();
    while l.next(index) != 0 {
        visit(l);
        l.settop(-2);
    }
}

/// A Lua error with an owned `message`, pushed and dropped before raising.
///
/// # Safety
/// As `raise`.
pub unsafe fn raise_owned(l: L, message: String) -> ! {
    push_str(l, &message);
    drop(message);
    l.error();
    unreachable!("lua_error does not return")
}

/// A Lua error with `message`; it never returns.
///
/// # Safety
/// `l` is a live state, after `open`; the caller holds nothing that needs a
/// destructor, since the error unwinds past it.
pub unsafe fn raise(l: L, message: &CStr) -> ! {
    let bytes = message.to_bytes();
    l.pushlstring(bytes.as_ptr().cast(), bytes.len());
    l.error();
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
    l.where_(level);
    push_str(l, &message);
    drop(message);
    l.concat(2);
    l.error();
    unreachable!("lua_error does not return")
}

/// Pushes tostring(value at `index`), as Lua's tostring gives it.
///
/// # Safety
/// `l` is a live state, after `open`.
pub unsafe fn push_tostring(l: L, index: c_int) {
    let index = if index < 0 && index > GLOBALSINDEX { l.gettop() + index + 1 } else { index };
    l.getfield(GLOBALSINDEX, c"tostring");
    l.pushvalue(index);
    l.call(1, 1);
}

/// tostring(value at `index`), as an owned string.
///
/// # Safety
/// As `push_tostring`.
pub unsafe fn tostring(l: L, index: c_int) -> String {
    push_tostring(l, index);
    let text = string_at(l, -1).map(|b| String::from_utf8_lossy(b).into_owned()).unwrap_or_default();
    l.settop(-2);
    text
}
