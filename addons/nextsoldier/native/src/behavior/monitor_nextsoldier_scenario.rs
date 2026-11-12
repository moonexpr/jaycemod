//! CTFBotScenarioMonitor (tf_bot_scenario_monitor.cpp), native, on the scenario registry
//! it reads directly (`scenarios.rs`). It runs what the chosen scenario names, starting
//! over when the choice changes, and suspends all of that for its interrupts: TF2's
//! "I've picked up the flag". What it runs and what its interrupts ask stay Lua.

/// What its Update does, in TF2's order.
#[derive(Debug, PartialEq)]
pub enum Step {
    /// The scenario chosen is no longer the one it started with.
    StartOver,
    /// Go on to its interrupts.
    Interrupts,
}

/// `was` and `now`: places in the compiled structure. No choice now (nothing active)
/// keeps what it runs.
pub fn step(was: Option<u32>, now: Option<u32>) -> Step {
    if now.is_some() && now != was {
        Step::StartOver
    } else {
        Step::Interrupts
    }
}

/// The action state's encoding of a place: 0 is none.
pub fn encode(place: Option<u32>) -> u64 {
    place.map_or(0, |p| p as u64 + 1)
}

pub fn decode(state: u64) -> Option<u32> {
    state.checked_sub(1).map(|p| p as u32)
}

#[cfg(all(windows, target_arch = "x86_64"))]
pub(crate) use hooks::KIND;

#[cfg(all(windows, target_arch = "x86_64"))]
mod hooks {
    use super::{decode, encode, step, Step};
    use crate::engine::{self, Kind};
    use crate::layout::*;
    use crate::outcome::{Made, Outcome, Reason};
    use crate::scenarios_bind::{self, CompiledData};
    use foundation::lua::{api, raise_where, string_at, L, TFUNCTION, TNUMBER, TTABLE};
    use foundation::userdata;
    use std::ffi::{c_int, c_void, CStr};
    use std::ptr::null_mut;

    const NAME: &CStr = c"ScenarioMonitor";

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
        ]
    }

    /// Chosen when it starts (InitialContainedAction).
    unsafe fn init(_l: L, _config: c_int) -> u64 {
        0
    }

    /// engine.ScenarioMonitor{ scenarios, context, behaviors, sides, interrupts } -> the
    /// monitor, as a TacticalMonitor's `scenario`: `scenarios` a compiled
    /// wartactics.scenarios, `context(me)` what it chooses by, `behaviors` name -> a
    /// function of the soldier making what a scenario's monitor names, `sides(me)` what
    /// it runs for a scenario naming none, and `interrupts` a list, in order, of
    /// { when(me), action(me), reason }.
    unsafe extern "C-unwind" fn constructor(l: L) -> c_int {
        let api = api();
        (api.settop)(l, 1);
        (api.checktype)(l, 1, TTABLE);
        (api.getfield)(l, 1, c"scenarios".as_ptr());
        userdata::check::<CompiledData>(l, -1);
        (api.getfield)(l, 1, c"context".as_ptr());
        if (api.type_of)(l, -1) != TFUNCTION {
            raise_where(
                l,
                "ScenarioMonitor needs context(me), what it chooses by".into(),
            );
        }
        (api.settop)(l, 1);
        engine::mark_config(l, NAME);
        1
    }

    /// choose(config, me) -> the place of the entry active for context(me), or nil: a C
    /// function, so that what it calls of Lua runs protected.
    unsafe extern "C-unwind" fn choose(l: L) -> c_int {
        let api = api();
        (api.settop)(l, 2);
        (api.getfield)(l, 1, c"scenarios".as_ptr());
        let compiled = (api.gettop)(l);
        (api.getfield)(l, 1, c"context".as_ptr());
        (api.pushvalue)(l, 2);
        (api.call)(l, 1, 1);
        match scenarios_bind::choose(l, compiled, -1) {
            Some(place) => (api.pushnumber)(l, place as f64),
            None => (api.pushnil)(l),
        }
        1
    }

    /// The place chosen now; nil and a failure alike are none.
    unsafe fn chosen(this: *mut LuaAction) -> Option<u32> {
        engine::with_config(this, |l| {
            let api = api();
            let config = (api.gettop)(l);
            (api.pushcclosure)(l, choose, 0);
            let called = engine::call_with_config(l, this, config);
            (called && (api.type_of)(l, -1) == TNUMBER).then(|| (api.tonumber)(l, -1) as u32)
        })
    }

    /// What the entry at `place` runs: the behaviour its monitor names, else the sides.
    unsafe extern "win64" fn initial_contained(
        this: *mut LuaAction,
        _me: *mut c_void,
    ) -> *mut Action {
        let place = chosen(this);
        (*this).state = encode(place);
        engine::with_config(this, |l| {
            let api = api();
            let config = (api.gettop)(l);
            if let Some(place) = place {
                (api.getfield)(l, config, c"scenarios".as_ptr());
                let compiled = (api.gettop)(l);
                scenarios_bind::push_monitor(l, compiled, place);
                if string_at(l, -1).is_some() {
                    let monitor = (api.gettop)(l);
                    (api.getfield)(l, config, c"behaviors".as_ptr());
                    if (api.type_of)(l, -1) == TTABLE {
                        (api.pushvalue)(l, monitor);
                        (api.rawget)(l, -2);
                        return engine::made_by(l, this);
                    }
                    return null_mut();
                }
            }
            (api.getfield)(l, config, c"sides".as_ptr());
            engine::made_by(l, this)
        })
    }

    /// The first interrupt whose `when` holds: its action, and its reason.
    unsafe fn interrupted(this: *mut LuaAction) -> Option<(Made, Reason)> {
        engine::with_config(this, |l| {
            let api = api();
            (api.getfield)(l, -1, c"interrupts".as_ptr());
            let list = (api.gettop)(l);
            if (api.type_of)(l, list) != TTABLE {
                return None;
            }
            let mut i = 1;
            loop {
                (api.settop)(l, list);
                (api.rawgeti)(l, list, i);
                let interrupt = (api.gettop)(l);
                if (api.type_of)(l, interrupt) != TTABLE {
                    return None;
                }
                (api.getfield)(l, interrupt, c"when".as_ptr());
                if engine::call_with_me(l, this, |_| 0) && (api.toboolean)(l, -1) != 0 {
                    (api.getfield)(l, interrupt, c"action".as_ptr());
                    let made = Made::new(engine::made_by(l, this))?;
                    (api.getfield)(l, interrupt, c"reason".as_ptr());
                    let reason = string_at(l, -1).map_or(Reason::NONE, engine::interned);
                    return Some((made, reason));
                }
                i += 1;
            }
        })
    }

    unsafe extern "win64" fn update(
        this: *mut LuaAction,
        ret: *mut ActionResult,
        _me: *mut u8,
        _interval: f32,
    ) -> *mut ActionResult {
        let outcome = match step(decode((*this).state), chosen(this)) {
            Step::StartOver => Made::new(engine::same_again(this))
                .map_or(Outcome::Continue, |made| {
                    Outcome::ChangeTo(made, Reason::of(c"scenario changed"))
                }),
            Step::Interrupts => interrupted(this).map_or(Outcome::Continue, |(made, reason)| {
                Outcome::SuspendFor(made, reason)
            }),
        };
        ret.write(outcome.action_result());
        ret
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_choice_changing_starts_it_over() {
        assert_eq!(step(Some(1), Some(2)), Step::StartOver);
        assert_eq!(
            step(None, Some(0)),
            Step::StartOver,
            "nothing chosen before"
        );
    }

    #[test]
    fn the_same_choice_goes_on_to_its_interrupts() {
        assert_eq!(step(Some(2), Some(2)), Step::Interrupts);
    }

    #[test]
    fn nothing_chosen_now_keeps_what_it_runs() {
        assert_eq!(step(Some(2), None), Step::Interrupts);
        assert_eq!(step(None, None), Step::Interrupts);
    }

    #[test]
    fn a_place_survives_the_state_it_is_kept_in() {
        assert_eq!(decode(encode(Some(0))), Some(0));
        assert_eq!(decode(encode(Some(7))), Some(7));
        assert_eq!(decode(encode(None)), None);
    }
}
