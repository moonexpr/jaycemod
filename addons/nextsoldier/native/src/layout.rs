//! The engine's NextBot objects as GMod's win64 server.dll lays them out: the
//! SDK's NextBotBehavior.h with Dota's #ifdef block out, read from the binary
//! (CLuaNextBotIntention::Reset constructs both, and its slots 1 and 43 read them).
//! A GMod update can move any of this: `engine::open` checks what it can against
//! the running binary and refuses to bind otherwise.

use std::ffi::{c_char, c_void};

pub const ACTION_CLASS: &str = ".?AV?$Action@VCLuaNextBot@@@@";
pub const ROOT_CLASS: &str = ".?AVCLuaBehaviour@@";
pub const BOT_CLASS: &str = ".?AVCLuaNextBot@@";
pub const INTENTION_CLASS: &str = ".?AVCLuaNextBotIntention@CLuaNextBot@@";
pub const ENTITY_LIST_CLASS: &str = ".?AVCGlobalEntityList@@";
pub const PLAYER_CLASS: &str = ".?AV?$NextBotPlayer@VCGMOD_Player@@@@";
pub const BASE_INTENTION_CLASS: &str = ".?AVIIntention@@";
pub const BEHAVIOR_CLASS: &str = ".?AV?$Behavior@VCLuaNextBot@@@@";

/// INextBotEventResponder's 42, then Action's own.
pub const ACTION_SLOTS: usize = 91;
pub const QUERY_SLOTS: usize = 9;

// Action's slots.
pub const DESTRUCTOR: usize = 0;
pub const GET_NAME: usize = 42;
pub const ON_START: usize = 45;
pub const UPDATE: usize = 46;
pub const ON_END: usize = 47;
pub const ON_SUSPEND: usize = 48;
pub const ON_RESUME: usize = 49;
pub const INITIAL_CONTAINED: usize = 50;
pub const ON_STUCK: usize = 56;
pub const ON_INJURED: usize = 63;
pub const ON_COMMAND_STRING: usize = 82;

// IContextualQuery's slots, in the vtable at +8.
pub const SHOULD_HURRY: usize = 2;
pub const SHOULD_RETREAT: usize = 3;

// INextBotEventResponder's OnCommandString, on an INextBot: the event's way in.
pub const RESPONDER_COMMAND_STRING: usize = 34;

// CBaseEntity's slots and field, checked by reach.rs against the Lua methods' calls.
pub const IS_ALIVE: usize = 66;
pub const IS_PLAYER: usize = 81;
pub const EYE_POSITION: usize = 132;
pub const EYE_ANGLES: usize = 133;
pub const ENTITY_TEAM: usize = 0x2A4;

// INextBot, at INEXTBOT_OFFSET in a CLuaNextBot.
pub const INEXTBOT_OFFSET: usize = 0x2240;
pub const GET_INTENTION: usize = 50;

// CLuaNextBotIntention: slot FIRST_CONTAINED is `mov rax, [rcx + 0x28]; ret`.
pub const FIRST_CONTAINED: usize = 1;
pub const NEXT_CONTAINED: usize = 2;
pub const INTENTION_BEHAVIOR: usize = 0x28;
pub const RETURNS_BEHAVIOR: [u8; 5] = [0x48, 0x8B, 0x41, 0x28, 0xC3];

// Behavior<CLuaNextBot>: the action at its root.
pub const BEHAVIOR_ACTION: usize = 0x10;
pub const BEHAVIOR_WORDS: usize = 14; // CLuaNextBotIntention::Reset allocates 0x70
                                      // The actor it last updated with; ~Behavior ends its actions only when one is set.
pub const BEHAVIOR_ME: usize = 0x48;

// NextBotPlayer<CGMOD_Player>'s INextBot, and the plain IIntention it holds: 46
// slots, its fields those of INextBotComponent (0x28 bytes). A player has no
// statechart of its own, so CreateNextSoldier gives it one: the engine's Behavior,
// run by CLuaNextBotIntention::Update on a shadow of the intention. That code takes
// its actor from GetBot() - INEXTBOT_OFFSET and reaches it only at + INEXTBOT_OFFSET,
// so it never sees that the actor is no CLuaNextBot.
pub const PLAYER_INEXTBOT_OFFSET: usize = 0x32C0;
pub const INTENTION_SLOTS: usize = 46;
pub const INTENTION_UPDATE: usize = 43;
pub const INTENTION_UPKEEP: usize = 44;
pub const COMPONENT_GET_BOT: usize = 45;
pub const COMPONENT_INTERVAL: usize = 0x0C;
pub const COMPONENT_BOT: usize = 0x10;
pub const INTENTION_QUERY: usize = 0x20;
pub const SHADOW_WORDS: usize = 6;
pub const RETURNS_BOT: [u8; 5] = [0x48, 0x8B, 0x41, 0x10, 0xC3];

// CBaseEntityList: its vtable, then CEntInfo { entity, serial, prev, next } by entindex.
pub const ENTITY_LIST_ENTRIES: usize = 8;
pub const ENTITY_INFO_SIZE: usize = 0x20;
/// A player's entity index is at most this: Source's MAX_PLAYERS, as GMod has it.
pub const MAX_PLAYERS: usize = 128;

// ActionResultType, EventResultPriorityType, QueryResultType
pub const CONTINUE: i32 = 0;
pub const CHANGE_TO: i32 = 1;
pub const SUSPEND_FOR: i32 = 2;
pub const RESULT_TRY: i32 = 1;
pub const ANSWER_NO: i32 = 0;
pub const ANSWER_YES: i32 = 1;
pub const ANSWER_UNDEFINED: i32 = 2;

/// ActionResult<Actor>, returned through a hidden pointer.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionResult {
    pub kind: i32,
    pub action: *mut Action,
    pub reason: *const c_char,
}

/// EventDesiredResult<Actor>, returned through a hidden pointer.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct EventResult {
    pub kind: i32,
    pub action: *mut Action,
    pub reason: *const c_char,
    pub priority: i32,
}

/// Action<CLuaNextBot>'s fields: the engine owns what they mean.
#[repr(C)]
pub struct Action {
    pub vtable: *const usize,
    pub query_vtable: *const usize,
    pub behavior: *mut c_void,
    pub parent: *mut Action,
    pub child: *mut Action,
    pub buried: *mut Action,
    pub covering: *mut Action,
    pub actor: *mut c_void,
    pub event: EventResult,
    pub started: bool,
    pub suspended: bool,
}

/// An Action of ours: the engine's, and the slot of its Lua table.
#[repr(C)]
pub struct LuaAction {
    pub base: Action,
    pub id: u32,
    /// A native action's own (its `Kind` says what it means); nothing for a Lua one.
    pub state: u64,
    /// engine.End has run its OnEnd: the destructor's own, later, is not to.
    pub ended: bool,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem::{offset_of, size_of};

    #[test]
    fn an_action_is_laid_out_as_the_binary_constructs_it() {
        assert_eq!(offset_of!(Action, query_vtable), 0x08);
        assert_eq!(offset_of!(Action, behavior), 0x10);
        assert_eq!(offset_of!(Action, parent), 0x18);
        assert_eq!(offset_of!(Action, child), 0x20);
        assert_eq!(offset_of!(Action, buried), 0x28);
        assert_eq!(offset_of!(Action, covering), 0x30);
        assert_eq!(offset_of!(Action, actor), 0x38);
        assert_eq!(offset_of!(Action, event), 0x40);
        assert_eq!(offset_of!(Action, started), 0x60);
        assert_eq!(offset_of!(Action, suspended), 0x61);
        assert_eq!(
            size_of::<Action>(),
            0x68,
            "CLuaNextBotIntention::Reset allocates 0x68"
        );
    }

    #[test]
    fn a_result_is_laid_out_as_the_hooks_fill_it() {
        assert_eq!(size_of::<ActionResult>(), 0x18);
        assert_eq!(offset_of!(EventResult, action), 0x08);
        assert_eq!(offset_of!(EventResult, reason), 0x10);
        assert_eq!(offset_of!(EventResult, priority), 0x18);
    }

    #[test]
    fn our_fields_come_after_the_engines() {
        assert_eq!(offset_of!(LuaAction, id), 0x68);
    }
}
