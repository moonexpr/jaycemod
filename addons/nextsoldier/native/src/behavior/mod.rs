//! The behaviours implemented in Rust: TF2's NextBot Actions, each a kind the engine
//! runs under a Behavior as it runs a Lua one. A kind's decisions are plain functions
//! here, tested apart from the engine; its hooks are the engine's (`crate::engine`).
//!
//! A file's name says where it stands: `main_X` is a behaviour stack of its own, and
//! `monitor_X_Y` the high-level controller Y within stack X. A soldier runs two stacks,
//! as L4D2's survivors run their behaviour and their legs:
//!
//! ```text
//! main_nextsoldier   NextSoldier's intention, in place of a bot player's default one
//!   TacticalMonitor (monitor_nextsoldier_tactical)
//!     ScenarioMonitor (monitor_nextsoldier_scenario) > ...   what it is doing
//! main_nextlegs      NextLegs, the stack beside it   who it is with, where it stands
//! ```

pub mod main_nextlegs;
#[cfg(all(windows, target_arch = "x86_64"))]
pub(crate) mod main_nextsoldier;
pub mod monitor_nextsoldier_scenario;
pub mod monitor_nextsoldier_tactical;
