//! `gmsv_foundation_win64.dll`: Sandcastle's foundation structures and
//! algorithms, native. Opened, it sets `foundation.native`, which the Lua
//! modules read to back themselves; the Lua implementations stay as the
//! oracle the native ones are tested against, and as what the client runs.
//!
//! ```lua
//! require("foundation")            -- GMod: lua/bin/gmsv_foundation_win64.dll
//! local heap = foundation.native.heap.New()
//! heap:Push(2.5, 7)                -- key, value: both numbers
//! local value, key = heap:Pop()
//! ```
//!
//! Native structures hold numbers only: a slot, an id, a cost. Whatever a
//! number stands for stays in Lua, in arrays by slot.
//!
//! The crate is also a Rust library: `native/wetsands` builds on its
//! structures and its binding, with the `entry` feature off so only one set
//! of entry points is exported from each DLL.

pub mod astar;
pub mod graph;
pub mod heap;
pub mod lua;
pub mod userdata;

#[cfg(feature = "entry")]
mod bind;
