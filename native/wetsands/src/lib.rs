//! `gmsv_wetsands_win64.dll`: foundation.wetsands, native. Opened, it sets
//! `foundation.wetsands.native`, which `foundation.wetsands`' Lua modules
//! read to back themselves; the Lua implementations stay the oracle.
//! Built on the foundation crate as a Rust library (its structures, its
//! binding), so the two DLLs share code but not entry points.
//!
//! ```lua
//! require("wetsands")                -- GMod: lua/bin/gmsv_wetsands_win64.dll
//! local mesh = foundation.wetsands.native.mesh.New()
//! mesh:Area(id, x, y, z, attributes) -- every area, then
//! mesh:Link(from, to, distance, rise) -- each area's links in order
//! mesh:Seal()
//! local search = mesh:Search(model, start, goal, maxExpanded, gx, gy, gz)
//! while search:Step(16, traversable, crossable) == "running" do end
//! local route = search:Route()
//! ```

pub mod navmesh;
pub mod search;
pub mod walker;

/// The values the Source SDK 2013's headers name (native/vendor), read at
/// build time under their Source names: `source::nav::NAV_MESH_CROUCH`.
pub mod source {
    include!(concat!(env!("OUT_DIR"), "/source.rs"));
}

#[cfg(test)]
#[path = "../build/headers.rs"]
mod headers;



mod bind;
