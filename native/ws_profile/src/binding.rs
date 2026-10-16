//! The GMod side: `lua_shared.dll`'s functions resolved at load, the module's
//! entry points, and the profiler callback feeding a `Tally`.

use crate::tally::{Tally, VmState};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::sync::{Mutex, OnceLock};

#[repr(C)]
pub struct LuaState {
    _private: [u8; 0],
}
type L = *mut LuaState;
type CFunction = unsafe extern "C" fn(L) -> c_int;
type ProfileCallback = unsafe extern "C" fn(*mut c_void, L, c_int, c_int);

const LUA_GLOBALSINDEX: c_int = -10002;
const LUA_TSTRING: c_int = 4;
const LUA_TNUMBER: c_int = 3;
const GLOBAL_NAME: &CStr = c"wsprofile";
const LUA_SHARED: &CStr = c"lua_shared.dll";
const DEFAULT_MODE: &CStr = c"fi1";
const DEFAULT_FORMAT: &CStr = c"F;";
const DEFAULT_DEPTH: c_int = -12;

extern "system" {
    fn GetModuleHandleA(name: *const c_char) -> *mut c_void;
    fn GetProcAddress(module: *mut c_void, name: *const c_char) -> *mut c_void;
}

/// The `lua_shared.dll` functions this module calls.
struct Api {
    createtable: unsafe extern "C" fn(L, c_int, c_int),
    pushlstring: unsafe extern "C" fn(L, *const c_char, usize),
    pushnumber: unsafe extern "C" fn(L, f64),
    pushboolean: unsafe extern "C" fn(L, c_int),
    pushcclosure: unsafe extern "C" fn(L, CFunction, c_int),
    setfield: unsafe extern "C" fn(L, c_int, *const c_char),
    rawset: unsafe extern "C" fn(L, c_int),
    type_of: unsafe extern "C" fn(L, c_int) -> c_int,
    tolstring: unsafe extern "C" fn(L, c_int, *mut usize) -> *const c_char,
    tonumber: unsafe extern "C" fn(L, c_int) -> f64,
    profile_start: unsafe extern "C" fn(L, *const c_char, ProfileCallback, *mut c_void),
    profile_stop: unsafe extern "C" fn(L),
    profile_dumpstack: unsafe extern "C" fn(L, *const c_char, c_int, *mut usize) -> *const c_char,
}

/// An exported function of `lua_shared.dll` as `T`, or which one is missing.
unsafe fn resolve<T: Copy>(module: *mut c_void, name: &CStr) -> Result<T, String> {
    let address = GetProcAddress(module, name.as_ptr());
    if address.is_null() {
        return Err(format!(
            "lua_shared.dll exports no {}",
            name.to_string_lossy()
        ));
    }
    // SAFETY: T is the function pointer type of the export `name`.
    Ok(std::mem::transmute_copy(&address))
}

impl Api {
    unsafe fn load() -> Result<Self, String> {
        let module = GetModuleHandleA(LUA_SHARED.as_ptr());
        if module.is_null() {
            return Err("lua_shared.dll is not loaded".into());
        }
        Ok(Self {
            createtable: resolve(module, c"lua_createtable")?,
            pushlstring: resolve(module, c"lua_pushlstring")?,
            pushnumber: resolve(module, c"lua_pushnumber")?,
            pushboolean: resolve(module, c"lua_pushboolean")?,
            pushcclosure: resolve(module, c"lua_pushcclosure")?,
            setfield: resolve(module, c"lua_setfield")?,
            rawset: resolve(module, c"lua_rawset")?,
            type_of: resolve(module, c"lua_type")?,
            tolstring: resolve(module, c"lua_tolstring")?,
            tonumber: resolve(module, c"lua_tonumber")?,
            profile_start: resolve(module, c"luaJIT_profile_start")?,
            profile_stop: resolve(module, c"luaJIT_profile_stop")?,
            profile_dumpstack: resolve(module, c"luaJIT_profile_dumpstack")?,
        })
    }

    unsafe fn push_str(&self, l: L, s: &str) {
        (self.pushlstring)(l, s.as_ptr().cast(), s.len());
    }
}

static API: OnceLock<Api> = OnceLock::new();

/// The open window: its tally and how it reads stacks.
struct Window {
    tally: Tally,
    format: CString,
    depth: c_int,
}

static WINDOW: Mutex<Option<Window>> = Mutex::new(None);

fn api() -> &'static Api {
    API.get()
        .expect("gmod13_open resolved the API before any function was reachable")
}

unsafe extern "C" fn on_sample(_data: *mut c_void, l: L, samples: c_int, vmstate: c_int) {
    let api = api();
    let mut window = WINDOW.lock().unwrap_or_else(|e| e.into_inner());
    let Some(window) = window.as_mut() else {
        return;
    };
    let mut len = 0usize;
    let text = (api.profile_dumpstack)(l, window.format.as_ptr(), window.depth, &mut len);
    let bytes = if text.is_null() {
        &[][..]
    } else {
        std::slice::from_raw_parts(text.cast::<u8>(), len)
    };
    let stack = String::from_utf8_lossy(bytes);
    window.tally.add(
        VmState::from_code(vmstate as u8),
        &stack,
        samples.max(0) as u64,
    );
}

/// The string argument at `index`, or `default` when it is absent.
unsafe fn opt_cstring(api: &Api, l: L, index: c_int, default: &CStr) -> CString {
    if (api.type_of)(l, index) != LUA_TSTRING {
        return default.to_owned();
    }
    let mut len = 0usize;
    let text = (api.tolstring)(l, index, &mut len);
    let bytes = std::slice::from_raw_parts(text.cast::<u8>(), len);
    CString::new(bytes).unwrap_or_else(|_| default.to_owned())
}

/// wsprofile.Start([mode], [format], [depth]) -> true, or false and why.
unsafe extern "C" fn start(l: L) -> c_int {
    let api = api();
    let mut window = WINDOW.lock().unwrap_or_else(|e| e.into_inner());
    if window.is_some() {
        (api.pushboolean)(l, 0);
        api.push_str(l, "a window is already open");
        return 2;
    }
    let mode = opt_cstring(api, l, 1, DEFAULT_MODE);
    let format = opt_cstring(api, l, 2, DEFAULT_FORMAT);
    let depth = if (api.type_of)(l, 3) == LUA_TNUMBER {
        (api.tonumber)(l, 3) as c_int
    } else {
        DEFAULT_DEPTH
    };
    *window = Some(Window {
        tally: Tally::default(),
        format,
        depth,
    });
    drop(window);
    (api.profile_start)(l, mode.as_ptr(), on_sample, std::ptr::null_mut());
    (api.pushboolean)(l, 1);
    1
}

/// wsprofile.Running() -> whether a window is open.
unsafe extern "C" fn running(l: L) -> c_int {
    let open = WINDOW.lock().unwrap_or_else(|e| e.into_inner()).is_some();
    (api().pushboolean)(l, open as c_int);
    1
}

/// wsprofile.Stop() -> { samples, states, stacks }, or nil when none was open.
unsafe extern "C" fn stop(l: L) -> c_int {
    let api = api();
    (api.profile_stop)(l);
    let Some(window) = WINDOW.lock().unwrap_or_else(|e| e.into_inner()).take() else {
        return 0;
    };
    let tally = window.tally;
    (api.createtable)(l, 0, 3);
    (api.pushnumber)(l, tally.samples() as f64);
    (api.setfield)(l, -2, c"samples".as_ptr());
    (api.createtable)(l, 0, tally.states().len() as c_int);
    for (state, count) in tally.states() {
        api.push_str(l, &state.name());
        (api.pushnumber)(l, *count as f64);
        (api.rawset)(l, -3);
    }
    (api.setfield)(l, -2, c"states".as_ptr());
    (api.createtable)(l, 0, tally.stacks().len() as c_int);
    for (stack, count) in tally.stacks() {
        api.push_str(l, stack);
        (api.pushnumber)(l, *count as f64);
        (api.rawset)(l, -3);
    }
    (api.setfield)(l, -2, c"stacks".as_ptr());
    1
}

/// GMod's entry point: resolve the API and set the global `wsprofile`.
#[no_mangle]
pub unsafe extern "C" fn gmod13_open(l: L) -> c_int {
    let api = match Api::load() {
        Ok(api) => API.get_or_init(|| api),
        Err(_) => return 0,
    };
    (api.createtable)(l, 0, 3);
    let functions: [(&CStr, CFunction); 3] =
        [(c"Start", start), (c"Stop", stop), (c"Running", running)];
    for (name, function) in functions {
        (api.pushcclosure)(l, function, 0);
        (api.setfield)(l, -2, name.as_ptr());
    }
    (api.setfield)(l, LUA_GLOBALSINDEX, GLOBAL_NAME.as_ptr());
    0
}

/// GMod's exit point: a window left open is closed with the state.
#[no_mangle]
pub unsafe extern "C" fn gmod13_close(l: L) -> c_int {
    if let Some(api) = API.get() {
        if WINDOW
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
            .is_some()
        {
            (api.profile_stop)(l);
        }
    }
    0
}
