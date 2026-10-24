//! `gmsv_foundation_win64.dll`: Sandcastle's foundation structures and
//! algorithms, native: a drop-in replacement for foundation's Lua modules on
//! a server that loads it. Opened by GMod, it installs each native module
//! over the global its Lua twin publishes (`tree.heap`...), where the two
//! keep one contract, or patches single functions over a Lua module where
//! only they gain (`nodegraph`'s pair searches); the Lua stays the oracle
//! and what clients run. `luaopen_foundation` returns the module's table
//! (the twins, the probes) for the tests and the bench, installing nothing:
//!
//! ```lua
//! local native = package.loadlib(path, "luaopen_foundation")()
//! local heap = native.tree.heap()
//! heap:Push(2.5, entry)            -- a number key, any value
//! local value, key = heap:Pop()
//! ```
//!
//! Native structures hold numbers: a key, an id, a cost. Lua values they
//! are given are kept by slot in the userdata's environment table.
//!
//! The crate is also a Rust library: `native/wetsands` builds on its
//! structures and its binding, with the `entry` feature off so only one set
//! of entry points is exported from each DLL.

pub mod astar;
pub mod avl;
pub mod graph;
pub mod heap;
pub mod lua;
pub mod module;
pub mod nearest;
pub mod userdata;

#[cfg(feature = "entry")]
mod bind;
