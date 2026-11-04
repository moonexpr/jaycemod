//! `gmsv_nextsoldier_win64.dll`: NextSoldier on the engine's own NextBot system.
//! A CLuaNextBot already runs IIntention > Behavior > Action, with one Action on
//! it, CLuaBehaviour, which only calls Lua. This binary builds more Action objects,
//! whose hooks are Lua tables' methods, and links them under it: the engine then
//! starts, updates, suspends, ends and deletes them. A bot player has no statechart
//! of its own, so `player.CreateNextSoldier` gives it one.

pub mod image;
pub mod layout;
pub mod scenario_monitor;
pub mod scenarios;
pub mod scenarios_bind;
pub mod tactical;

#[cfg(all(windows, target_arch = "x86_64"))]
pub(crate) mod engine;

/// Stock Lua's entry point (`package.loadlib`), for the LuaJIT tests: the module's
/// table laid out as the globals, installing nothing.
///
/// # Safety
/// Called by Lua with a live state.
#[no_mangle]
pub unsafe extern "C-unwind" fn luaopen_nextsoldier(l: foundation::lua::L) -> std::ffi::c_int {
    if foundation::lua::open().is_err() {
        return 0;
    }
    let api = foundation::lua::api();
    (api.createtable)(l, 0, 1);
    (api.createtable)(l, 0, 1);
    scenarios_bind::push_module(l);
    (api.setfield)(l, -2, c"scenarios".as_ptr());
    (api.setfield)(l, -2, c"wartactics".as_ptr());
    1
}
