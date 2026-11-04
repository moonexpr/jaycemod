//! `gmsv_nextsoldier_win64.dll`: NextSoldier on the engine's own NextBot system.
//! A CLuaNextBot already runs IIntention > Behavior > Action, with one Action on
//! it, CLuaBehaviour, which only calls Lua. This binary builds more Action objects,
//! whose hooks are Lua tables' methods, and links them under it: the engine then
//! starts, updates, suspends, ends and deletes them.

pub mod image;
pub mod layout;

#[cfg(all(windows, target_arch = "x86_64"))]
mod engine;
