//! What an action tells the engine, as a value: a result can only hand the engine an
//! action that exists and a reason that lives as long as the engine holds it. The
//! engine's own ActionResult and EventResult are made from it, in one place.

use crate::layout::{Action, ActionResult, EventResult, CHANGE_TO, CONTINUE, SUSPEND_FOR};
use std::ffi::{c_char, CStr};
use std::ptr::{null_mut, NonNull};

/// ActionResultType's DONE, which no native kind answers yet.
const DONE: i32 = 3;

/// Why an action answered as it did: text the engine keeps by pointer, for good.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Reason(*const c_char);

impl Reason {
    pub const NONE: Reason = Reason(std::ptr::null());

    pub const fn of(text: &'static CStr) -> Self {
        Reason(text.as_ptr())
    }
}

/// An action made for the engine to run: never null.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Made(NonNull<Action>);

impl Made {
    /// None for a null action: nothing was made.
    pub fn new(action: *mut Action) -> Option<Self> {
        NonNull::new(action).map(Made)
    }
}

/// NextBotBehavior.h's ActionResultType, each with what it needs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    Continue,
    ChangeTo(Made, Reason),
    SuspendFor(Made, Reason),
    Done(Reason),
}

impl Outcome {
    /// A result as Lua or a hook spells it: a kind needing an action it lacks, or a
    /// kind the engine has no meaning for, continues.
    pub fn decode(kind: i32, action: Option<Made>, reason: Reason) -> Self {
        match (kind, action) {
            (CHANGE_TO, Some(made)) => Outcome::ChangeTo(made, reason),
            (SUSPEND_FOR, Some(made)) => Outcome::SuspendFor(made, reason),
            (DONE, _) => Outcome::Done(reason),
            _ => Outcome::Continue,
        }
    }

    /// Whether a result of `kind` hands the engine an action: only then is one made.
    pub fn needs_action(kind: i32) -> bool {
        kind == CHANGE_TO || kind == SUSPEND_FOR
    }

    fn parts(self) -> (i32, *mut Action, *const c_char) {
        match self {
            Outcome::Continue => (CONTINUE, null_mut(), Reason::NONE.0),
            Outcome::ChangeTo(made, reason) => (CHANGE_TO, made.0.as_ptr(), reason.0),
            Outcome::SuspendFor(made, reason) => (SUSPEND_FOR, made.0.as_ptr(), reason.0),
            Outcome::Done(reason) => (DONE, null_mut(), reason.0),
        }
    }

    pub fn action_result(self) -> ActionResult {
        let (kind, action, reason) = self.parts();
        ActionResult {
            kind,
            action,
            reason,
        }
    }

    /// As an event's answer, at `priority` (RESULT_TRY and up).
    pub fn event_result(self, priority: i32) -> EventResult {
        let (kind, action, reason) = self.parts();
        EventResult {
            kind,
            action,
            reason,
            priority,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::RESULT_TRY;

    fn made() -> Made {
        Made::new(NonNull::<Action>::dangling().as_ptr()).expect("not null")
    }

    #[test]
    fn test_made_new_refuses_null() {
        assert_eq!(Made::new(null_mut()), None);
    }

    #[test]
    fn test_decode_suspend_without_an_action_continues() {
        let reason = Reason::of(c"cover");
        assert_eq!(
            Outcome::decode(SUSPEND_FOR, None, reason),
            Outcome::Continue
        );
        assert_eq!(Outcome::decode(CHANGE_TO, None, reason), Outcome::Continue);
    }

    #[test]
    fn test_decode_keeps_each_kind_with_what_it_needs() {
        let (m, r) = (made(), Reason::of(c"next"));
        assert_eq!(Outcome::decode(CONTINUE, Some(m), r), Outcome::Continue);
        assert_eq!(
            Outcome::decode(CHANGE_TO, Some(m), r),
            Outcome::ChangeTo(m, r)
        );
        assert_eq!(
            Outcome::decode(SUSPEND_FOR, Some(m), r),
            Outcome::SuspendFor(m, r)
        );
        assert_eq!(Outcome::decode(DONE, None, r), Outcome::Done(r));
    }

    #[test]
    fn test_decode_done_drops_an_action_it_was_given() {
        let r = Reason::of(c"uncovered");
        assert_eq!(Outcome::decode(DONE, Some(made()), r), Outcome::Done(r));
    }

    #[test]
    fn test_decode_an_unknown_kind_continues() {
        assert_eq!(
            Outcome::decode(7, Some(made()), Reason::NONE),
            Outcome::Continue
        );
        assert_eq!(Outcome::decode(-1, None, Reason::NONE), Outcome::Continue);
    }

    #[test]
    fn test_needs_action_only_for_change_and_suspend() {
        assert!(Outcome::needs_action(crate::layout::CHANGE_TO));
        assert!(Outcome::needs_action(crate::layout::SUSPEND_FOR));
        assert!(!Outcome::needs_action(crate::layout::CONTINUE));
        assert!(!Outcome::needs_action(3));
        assert!(!Outcome::needs_action(7));
    }

    #[test]
    fn test_action_result_spells_each_kind() {
        let (m, r) = (made(), Reason::of(c"cover"));
        let suspend = Outcome::SuspendFor(m, r).action_result();
        assert_eq!(suspend.kind, SUSPEND_FOR);
        assert_eq!(suspend.action, m.0.as_ptr());
        assert_eq!(suspend.reason, c"cover".as_ptr());
        let done = Outcome::Done(r).action_result();
        assert_eq!((done.kind, done.action), (DONE, null_mut()));
        let continuing = Outcome::Continue.action_result();
        assert_eq!((continuing.kind, continuing.action), (CONTINUE, null_mut()));
        assert!(continuing.reason.is_null());
    }

    #[test]
    fn test_event_result_carries_its_priority() {
        let (m, r) = (made(), Reason::of(c"ow"));
        let hurt = Outcome::ChangeTo(m, r).event_result(2);
        assert_eq!(
            (hurt.kind, hurt.action, hurt.priority),
            (CHANGE_TO, m.0.as_ptr(), 2)
        );
        assert_eq!(
            Outcome::Continue.event_result(RESULT_TRY).priority,
            RESULT_TRY
        );
    }
}
