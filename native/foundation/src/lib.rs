//! `gmsv_foundation_win64.dll`: Sandcastle's foundation structures and
//! algorithms, native: a drop-in replacement for foundation's Lua modules on
//! a server that loads it. Opened by GMod, it installs each native module
//! over the global its Lua twin publishes (`tree.heap`...), where the two
//! keep one contract; the Lua stays the oracle and what clients run. None
//! has its twin yet, so nothing is installed; `luaopen_foundation` returns
//! the module's table (structures, probes) for the tests and the bench:
//!
//! ```lua
//! local native = package.loadlib(path, "luaopen_foundation")()
//! local heap = native.heap.New()
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
