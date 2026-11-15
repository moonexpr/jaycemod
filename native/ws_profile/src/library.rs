//! `lua_shared`, the library GMod's Lua lives in, found in the running
//! process: `lua_shared.dll` on Windows; on Linux the process's global scope
//! (where `luajit` itself puts the C API), else the first of `LUA_SHARED`
//! already loaded, which `dlopen` with `RTLD_NOLOAD` hands back without loading
//! anything. The engine loads it without `RTLD_GLOBAL`, so a server needs the latter.

use std::ffi::{c_char, c_void, CStr};

/// Where GMod's builds keep `lua_shared`, relative to the server's root (its
/// working directory): the 64-bit build's, then the 32-bit server's and
/// client's, then any library by that name already loaded.
#[cfg(unix)]
pub const LUA_SHARED: [&CStr; 4] = [
    c"bin/linux64/lua_shared.so",
    c"garrysmod/bin/lua_shared_srv.so",
    c"garrysmod/bin/lua_shared.so",
    c"lua_shared.so",
];

/// A loaded library, by its handle.
pub struct Library(*mut c_void);

/// The first of `candidates` that `open` finds loaded, with its name.
pub fn first_loaded<'a>(
    candidates: &[&'a CStr],
    open: impl Fn(&CStr) -> *mut c_void,
) -> Option<(*mut c_void, &'a CStr)> {
    candidates.iter().find_map(|name| {
        let handle = open(name);
        (!handle.is_null()).then_some((handle, *name))
    })
}

#[cfg(windows)]
impl Library {
    /// `lua_shared.dll`, or why not.
    pub fn find() -> Result<Self, String> {
        extern "system" {
            fn GetModuleHandleA(name: *const c_char) -> *mut c_void;
        }
        // SAFETY: a module handle lookup by a NUL-terminated name.
        let module = unsafe { GetModuleHandleA(c"lua_shared.dll".as_ptr()) };
        if module.is_null() {
            return Err("lua_shared.dll is not loaded".into());
        }
        Ok(Self(module))
    }

    /// The address of the export `name`, or null.
    pub fn symbol(&self, name: &CStr) -> *mut c_void {
        extern "system" {
            fn GetProcAddress(module: *mut c_void, name: *const c_char) -> *mut c_void;
        }
        // SAFETY: the handle stays valid while GMod runs; `name` is NUL-terminated.
        unsafe { GetProcAddress(self.0, name.as_ptr()) }
    }
}

#[cfg(unix)]
#[cfg_attr(target_os = "linux", link(name = "dl"))]
extern "C" {
    fn dlopen(name: *const c_char, flags: i32) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
}

#[cfg(target_os = "macos")]
const RTLD_DEFAULT: *mut c_void = -2isize as *mut c_void;
#[cfg(all(unix, not(target_os = "macos")))]
const RTLD_DEFAULT: *mut c_void = std::ptr::null_mut();
#[cfg(unix)]
const RTLD_LAZY: i32 = 1;
#[cfg(target_os = "macos")]
const RTLD_NOLOAD: i32 = 0x10;
#[cfg(all(unix, not(target_os = "macos")))]
const RTLD_NOLOAD: i32 = 4;

#[cfg(unix)]
impl Library {
    /// The global scope when it holds Lua's C API, else the first of
    /// `LUA_SHARED` loaded, or why neither.
    pub fn find() -> Result<Self, String> {
        let global = Self(RTLD_DEFAULT);
        if !global.symbol(c"lua_pushnumber").is_null() {
            return Ok(global);
        }
        Self::loaded(&LUA_SHARED).ok_or_else(|| {
            let names: Vec<_> = LUA_SHARED.iter().map(|n| n.to_string_lossy()).collect();
            format!(
                "lua_shared is not loaded: not in the process's scope, nor at {}",
                names.join(", ")
            )
        })
    }

    /// The first of `candidates` already loaded; loads nothing.
    pub fn loaded(candidates: &[&CStr]) -> Option<Self> {
        // SAFETY: dlopen with RTLD_NOLOAD only returns a library already loaded.
        let open = |name: &CStr| unsafe { dlopen(name.as_ptr(), RTLD_LAZY | RTLD_NOLOAD) };
        first_loaded(candidates, open).map(|(handle, _)| Self(handle))
    }

    /// The address of the symbol `name`, or null.
    pub fn symbol(&self, name: &CStr) -> *mut c_void {
        // SAFETY: a symbol lookup by a NUL-terminated name in a loaded library or the global scope.
        unsafe { dlsym(self.0, name.as_ptr()) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    fn handle(n: usize) -> *mut c_void {
        n as *mut c_void
    }

    #[test]
    fn test_first_loaded_takes_the_first_candidate_open_finds_and_asks_no_further() {
        let asked = RefCell::new(Vec::new());
        let open = |name: &CStr| {
            asked.borrow_mut().push(name.to_owned());
            if name == c"b.so" || name == c"c.so" {
                handle(2)
            } else {
                std::ptr::null_mut()
            }
        };
        let found = first_loaded(&[c"a.so", c"b.so", c"c.so"], open);
        assert_eq!(found, Some((handle(2), c"b.so")));
        assert_eq!(
            *asked.borrow(),
            vec![c"a.so".to_owned(), c"b.so".to_owned()]
        );
    }

    #[test]
    fn test_first_loaded_is_none_when_nothing_is_loaded() {
        assert_eq!(
            first_loaded(&[c"a.so", c"b.so"], |_| std::ptr::null_mut()),
            None
        );
    }

    #[cfg(unix)]
    #[test]
    fn test_lua_shared_tries_the_64_bit_servers_library_first() {
        assert_eq!(LUA_SHARED[0], c"bin/linux64/lua_shared.so");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn test_loaded_finds_a_library_the_process_has_and_loads_none_it_lacks() {
        assert!(Library::loaded(&[c"libnot_a_library_here.so"]).is_none());
        let libc = Library::loaded(&[c"libnot_a_library_here.so", c"libc.so.6"]);
        assert!(libc.is_some_and(|libc| !libc.symbol(c"strlen").is_null()));
    }
}
