//! CTFBotTacticalMonitor (tf_bot_tactical_monitor.cpp), native. It runs what the
//! scenario runs, and over all of that suspends for a retreat, or for what a command
//! names, each made by a function of its config. The rest of TF2's Update (the round's
//! end, buff items, health and ammo, sentries, teleporters) waits on what it needs from
//! the game.

use crate::layout::ANSWER_YES;

#[derive(Debug, PartialEq)]
pub enum Step {
    Continue,
    Retreat,
}

/// What it does with what the Behavior answered to ShouldRetreat, from the innermost
/// action out. `never_retreats`: a mode's rule, as MvM's robots.
pub fn step(should_retreat: i32, never_retreats: bool) -> Step {
    if should_retreat == ANSWER_YES && !never_retreats {
        Step::Retreat
    } else {
        Step::Continue
    }
}

#[cfg(all(windows, target_arch = "x86_64"))]
pub(crate) use hooks::KIND;

#[cfg(all(windows, target_arch = "x86_64"))]
mod hooks {
    use super::{step, Step};
    use crate::engine::{self, Kind};
    use crate::layout::*;
    use crate::outcome::{Made, Outcome, Reason};
    use foundation::lua::{api, raise_where, L, TTABLE};
    use std::ffi::{c_char, c_int, c_void, CStr};
    use std::ptr::null_mut;

    const NAME: &CStr = c"TacticalMonitor";

    pub(crate) const KIND: Kind = Kind {
        name: NAME,
        slots,
        init,
        constructor,
    };

    fn slots() -> Vec<(usize, usize)> {
        vec![
            (UPDATE, update as *const () as usize),
            (INITIAL_CONTAINED, initial_contained as *const () as usize),
            (ON_COMMAND_STRING, on_command_string as *const () as usize),
        ]
    }

    /// Its state: whether it never retreats, read once from its config.
    unsafe fn init(l: L, config: c_int) -> u64 {
        (api().getfield)(l, config, c"never_retreats".as_ptr());
        ((api().toboolean)(l, -1) != 0) as u64
    }

    /// engine.TacticalMonitor{ scenario, never_retreats, retreat, commands } -> the
    /// monitor, to Insert or return as an action: `scenario` the action it runs,
    /// `retreat` and each of `commands` a function of the soldier making what it
    /// suspends for.
    unsafe extern "C-unwind" fn constructor(l: L) -> c_int {
        let api = api();
        (api.settop)(l, 1);
        (api.checktype)(l, 1, TTABLE);
        (api.getfield)(l, 1, c"scenario".as_ptr());
        if (api.type_of)(l, -1) != TTABLE {
            raise_where(
                l,
                "TacticalMonitor needs the scenario action it runs".into(),
            );
        }
        (api.settop)(l, 1);
        engine::mark_config(l, NAME);
        1
    }

    /// As CTFBotTacticalMonitor's `new CTFBotScenarioMonitor`.
    unsafe extern "win64" fn initial_contained(
        this: *mut LuaAction,
        _me: *mut c_void,
    ) -> *mut Action {
        engine::with_config(this, |l| {
            (api().getfield)(l, -1, c"scenario".as_ptr());
            engine::action_from_top(l, this)
        })
    }

    /// Asks the actions it runs, through the engine's own query walk, whether to retreat.
    unsafe extern "win64" fn update(
        this: *mut LuaAction,
        ret: *mut ActionResult,
        me: *mut u8,
        _interval: f32,
    ) -> *mut ActionResult {
        let answer = engine::behavior_answer(this, me, SHOULD_RETREAT);
        let mut outcome = Outcome::Continue;
        if step(answer, (*this).state != 0) == Step::Retreat {
            let action = engine::with_config(this, |l| {
                (api().getfield)(l, -1, c"retreat".as_ptr());
                engine::made_by(l, this)
            });
            if let Some(made) = Made::new(action) {
                outcome = Outcome::SuspendFor(made, Reason::of(c"Backing off"));
            }
        }
        ret.write(outcome.action_result());
        ret
    }

    /// The command its config names, suspended for at the next update, over everything
    /// it runs.
    unsafe extern "win64" fn on_command_string(
        this: *mut LuaAction,
        ret: *mut EventResult,
        _me: *mut c_void,
        command: *const c_char,
    ) -> *mut EventResult {
        let action = engine::with_config(this, |l| {
            (api().getfield)(l, -1, c"commands".as_ptr());
            if (api().type_of)(l, -1) != TTABLE {
                return null_mut();
            }
            (api().getfield)(l, -1, command);
            engine::made_by(l, this)
        });
        let outcome = match Made::new(action) {
            Some(made) => {
                Outcome::SuspendFor(made, engine::interned(CStr::from_ptr(command).to_bytes()))
            }
            None => Outcome::Continue,
        };
        ret.write(outcome.event_result(RESULT_TRY));
        ret
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::layout::{ANSWER_NO, ANSWER_UNDEFINED};

    #[test]
    fn it_retreats_when_the_actions_it_runs_say_so() {
        assert_eq!(step(ANSWER_YES, false), Step::Retreat);
    }

    #[test]
    fn a_robot_never_retreats_whatever_they_say() {
        assert_eq!(step(ANSWER_YES, true), Step::Continue);
    }

    #[test]
    fn no_answer_and_no_are_the_same() {
        assert_eq!(step(ANSWER_NO, false), Step::Continue);
        assert_eq!(step(ANSWER_UNDEFINED, false), Step::Continue);
    }
}
