//! CTFBotTacticalMonitor (tf_bot_tactical_monitor.cpp), what it decides. A native
//! action: its child is the scenario's, and what it suspends for a table of its
//! config makes. The rest of TF2's Update (the round's end, buff items, health and
//! ammo, sentries, teleporters) waits on what it needs from the game.

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
