//! `gmsv_wetsands_win64.dll`: foundation.wetsands, native, a drop-in
//! replacement on a server that loads it. Opened by GMod, it installs
//! itself over `wetsands.navsearch`, the global its Lua twin
//! (foundation/wetsands/navsearch.lua) was published to, keeping that
//! contract; the Lua stays the oracle and what clients run. Built on the
//! foundation crate as a Rust library (its structures, its binding), so the
//! two DLLs share code but not entry points.
//!
//! ```lua
//! require("wetsands")                -- GMod: lua/bin/gmsv_wetsands_win64.dll
//! local NavSearch = wetsands.navsearch
//! local mesh = NavSearch.Mesh()
//! mesh:Area(id, x, y, z, attributes) -- every area, then
//! mesh:Link(from, to, distance, rise) -- each area's links in order
//! mesh:Seal()
//! local search = NavSearch.New(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded, told, rules)
//! while search:Step(16) == "running" do end
//! local route = search:Route()
//! ```

pub mod navmesh;
pub mod search;
pub mod walker;
pub mod walks;

/// The values the Source SDK 2013's headers name (native/vendor), read at
/// build time under their Source names: `source::nav::NAV_MESH_CROUCH`.
pub mod source {
    include!(concat!(env!("OUT_DIR"), "/source.rs"));
}

#[cfg(test)]
#[path = "../build/headers.rs"]
mod headers;



mod bind;
