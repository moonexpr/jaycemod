//! `gmsv_wsprofile_win64.dll`: LuaJIT's sampling profiler
//! (`luaJIT_profile_start`), which GMod's `lua_shared.dll` exports but no
//! Lua library reaches, counted natively and handed to Lua as one table.
//!
//! ```lua
//! require("wsprofile")
//! wsprofile.Start("fi1", "F;", -12)  -- mode, stack format, depth (see below)
//! -- ... play ...
//! local result = wsprofile.Stop()
//! -- { samples = n, states = { compiled = n, interpreted = n, c = n, gc = n,
//! --   compiler = n }, stacks = { ["outer;...;leaf"] = n } }
//! ```
//!
//! `mode` is LuaJIT's profiler mode ('f' function or 'l' line granularity,
//! 'i<ms>' the sampling interval); `format` and `depth` are
//! `luaJIT_profile_dumpstack`'s (a negative depth lists the outermost frame
//! first). Shaping the result into a report is foundation.core.analytics's.

pub mod tally;

#[cfg(windows)]
mod binding;
