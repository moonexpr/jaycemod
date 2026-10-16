//! The counts a profiling window keeps: samples by LuaJIT VM state, and by
//! stack. Pure, so it is tested on any host; the binding feeds it.

use std::collections::{BTreeMap, HashMap};

/// What the VM was doing when sampled (`luaJIT_profile_callback`'s vmstate).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum VmState {
    /// Running compiled code (a trace): 'N'.
    Compiled,
    /// Running the interpreter: 'I'.
    Interpreted,
    /// Inside a C function: 'C'.
    C,
    /// Collecting garbage: 'G'.
    Gc,
    /// Inside the JIT compiler (recording, optimising, assembling): 'J'.
    Compiler,
    /// A state LuaJIT added after this binding was written.
    Other(u8),
}

impl VmState {
    pub fn from_code(code: u8) -> Self {
        match code {
            b'N' => Self::Compiled,
            b'I' => Self::Interpreted,
            b'C' => Self::C,
            b'G' => Self::Gc,
            b'J' => Self::Compiler,
            other => Self::Other(other),
        }
    }

    /// The name Lua reads it by.
    pub fn name(self) -> String {
        match self {
            Self::Compiled => "compiled".into(),
            Self::Interpreted => "interpreted".into(),
            Self::C => "c".into(),
            Self::Gc => "gc".into(),
            Self::Compiler => "compiler".into(),
            Self::Other(code) => format!("other_{}", code as char),
        }
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Tally {
    samples: u64,
    states: BTreeMap<VmState, u64>,
    stacks: HashMap<String, u64>,
}

impl Tally {
    /// `samples` samples (the profiler may coalesce several) taken in
    /// `state` with the stack `stack`.
    pub fn add(&mut self, state: VmState, stack: &str, samples: u64) {
        self.samples += samples;
        *self.states.entry(state).or_default() += samples;
        match self.stacks.get_mut(stack) {
            Some(count) => *count += samples,
            None => {
                self.stacks.insert(stack.to_owned(), samples);
            }
        }
    }

    pub fn samples(&self) -> u64 {
        self.samples
    }

    pub fn states(&self) -> &BTreeMap<VmState, u64> {
        &self.states
    }

    pub fn stacks(&self) -> &HashMap<String, u64> {
        &self.stacks
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vm_state_codes_map_to_their_states() {
        assert_eq!(VmState::from_code(b'N'), VmState::Compiled);
        assert_eq!(VmState::from_code(b'I'), VmState::Interpreted);
        assert_eq!(VmState::from_code(b'C'), VmState::C);
        assert_eq!(VmState::from_code(b'G'), VmState::Gc);
        assert_eq!(VmState::from_code(b'J'), VmState::Compiler);
    }

    #[test]
    fn an_unknown_code_is_kept_by_its_letter() {
        assert_eq!(VmState::from_code(b'X'), VmState::Other(b'X'));
        assert_eq!(VmState::from_code(b'X').name(), "other_X");
    }

    #[test]
    fn samples_add_up_by_state_and_by_stack() {
        let mut tally = Tally::default();
        tally.add(VmState::Interpreted, "Think;Update", 1);
        tally.add(VmState::Compiled, "Think;Update", 2);
        tally.add(VmState::Gc, "Think;Alloc", 1);
        assert_eq!(tally.samples(), 4);
        assert_eq!(tally.states()[&VmState::Interpreted], 1);
        assert_eq!(tally.states()[&VmState::Compiled], 2);
        assert_eq!(tally.states()[&VmState::Gc], 1);
        assert_eq!(tally.stacks()["Think;Update"], 3);
        assert_eq!(tally.stacks()["Think;Alloc"], 1);
    }

    #[test]
    fn an_empty_tally_has_no_samples() {
        let tally = Tally::default();
        assert_eq!(tally.samples(), 0);
        assert!(tally.states().is_empty());
        assert!(tally.stacks().is_empty());
    }
}
