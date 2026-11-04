//! wartactics.scenarios' model: what a registry holds and what compiling it makes, as
//! Rust values. What only Lua can hold (an entry's `active` and its `scenario`) stays
//! with the binding, in the order of `Compiled::entries`. The rules are the Lua twin's
//! (addons/wartactics/lua/wartactics/scenarios.lua).

use std::collections::{BTreeMap, HashMap};

pub const FREEFORM_PRIORITY: f64 = 0.0;
pub const MODE_PRIORITY: f64 = 10.0;

/// A scenario as it is registered, checked at the binding's seam. `V` is what the
/// binding keeps for it.
#[derive(Clone, Debug, PartialEq)]
pub struct Spec<V> {
    pub name: Vec<u8>,
    pub priority: f64,
    pub mode: Option<Vec<u8>>,
    pub monitor: Option<Vec<u8>>,
    pub behaviors: Vec<Vec<u8>>,
    pub value: V,
}

/// Why a registry did not compile: the scenario, and the behaviour nobody gave.
#[derive(Debug, PartialEq)]
pub enum Refused {
    Monitor {
        scenario: Vec<u8>,
        monitor: Vec<u8>,
    },
    Behavior {
        scenario: Vec<u8>,
        behavior: Vec<u8>,
    },
}

impl std::fmt::Display for Refused {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = String::from_utf8_lossy;
        match self {
            Refused::Monitor { scenario, monitor } => write!(
                f,
                "scenario {}'s monitor {} is no behaviour registered with NextSoldier",
                text(scenario),
                text(monitor)
            ),
            Refused::Behavior { scenario, behavior } => write!(
                f,
                "scenario {} relies on {}, no behaviour registered with NextSoldier",
                text(scenario),
                text(behavior)
            ),
        }
    }
}

/// Scenarios as registered, each name once: a name again replaces its entry and gives
/// back what it replaced.
#[derive(Debug)]
pub struct Registry<V> {
    specs: BTreeMap<Vec<u8>, Spec<V>>,
}

impl<V> Default for Registry<V> {
    fn default() -> Self {
        Self {
            specs: BTreeMap::new(),
        }
    }
}

impl<V: Clone> Registry<V> {
    pub fn register(&mut self, spec: Spec<V>) -> Option<Spec<V>> {
        self.specs.insert(spec.name.clone(), spec)
    }

    /// The immutable structure a decision reads; `has` answers for the behaviours
    /// soldiers were given. A later register reaches only the next compile.
    pub fn compile(&self, mut has: impl FnMut(&[u8]) -> bool) -> Result<Compiled<V>, Refused> {
        for spec in self.specs.values() {
            if let Some(monitor) = &spec.monitor {
                if !has(monitor) {
                    return Err(Refused::Monitor {
                        scenario: spec.name.clone(),
                        monitor: monitor.clone(),
                    });
                }
            }
            for behavior in &spec.behaviors {
                if !has(behavior) {
                    return Err(Refused::Behavior {
                        scenario: spec.name.clone(),
                        behavior: behavior.clone(),
                    });
                }
            }
        }
        let mut entries: Vec<Spec<V>> = self.specs.values().cloned().collect();
        // highest priority first, a tie to the name first (specs come in name order)
        entries.sort_by(|a, b| b.priority.total_cmp(&a.priority));
        let mut by_mode: HashMap<Vec<u8>, Vec<u32>> = HashMap::new();
        for entry in &entries {
            if let Some(mode) = &entry.mode {
                by_mode.entry(mode.clone()).or_default();
            }
        }
        let mut any_mode = Vec::new();
        for (i, entry) in entries.iter().enumerate() {
            let i = i as u32;
            match &entry.mode {
                Some(mode) => by_mode.get_mut(mode).expect("made above").push(i),
                None => {
                    any_mode.push(i);
                    by_mode.values_mut().for_each(|list| list.push(i));
                }
            }
        }
        Ok(Compiled {
            entries,
            any_mode,
            by_mode,
        })
    }
}

#[derive(Debug)]
pub struct Compiled<V> {
    pub entries: Vec<Spec<V>>,
    any_mode: Vec<u32>,
    by_mode: HashMap<Vec<u8>, Vec<u32>>,
}

impl<V> Compiled<V> {
    /// Whom a choice asks for `mode`: its own and those of any mode, in order.
    pub fn candidates(&self, mode: Option<&[u8]>) -> &[u32] {
        mode.and_then(|m| self.by_mode.get(m))
            .unwrap_or(&self.any_mode)
    }

    /// The first candidate `active` holds for.
    pub fn choose(&self, mode: Option<&[u8]>, mut active: impl FnMut(u32) -> bool) -> Option<u32> {
        self.candidates(mode).iter().copied().find(|&i| active(i))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(name: &str, priority: f64, mode: Option<&str>) -> Spec<()> {
        Spec {
            name: name.into(),
            priority,
            mode: mode.map(Into::into),
            monitor: None,
            behaviors: Vec::new(),
            value: (),
        }
    }

    fn registry(specs: Vec<Spec<()>>) -> Registry<()> {
        let mut registry = Registry::default();
        for s in specs {
            registry.register(s);
        }
        registry
    }

    fn name(compiled: &Compiled<()>, i: u32) -> String {
        String::from_utf8_lossy(&compiled.entries[i as usize].name).into_owned()
    }

    fn all() -> impl FnMut(&[u8]) -> bool {
        |_| true
    }

    #[test]
    fn the_highest_priority_active_is_chosen_and_a_tie_goes_to_the_name_first() {
        let compiled = registry(vec![
            spec("any", 0.0, None),
            spec("payload", 10.0, Some("payload")),
            spec("zebra", 20.0, Some("payload")),
            spec("aardvark", 20.0, Some("payload")),
        ])
        .compile(all())
        .unwrap();
        let first = compiled.choose(Some(b"payload"), |_| true).unwrap();
        assert_eq!(name(&compiled, first), "aardvark");
        let held = compiled
            .choose(Some(b"payload"), |i| name(&compiled, i) == "payload")
            .unwrap();
        assert_eq!(name(&compiled, held), "payload");
    }

    #[test]
    fn a_choice_asks_only_its_modes_and_those_of_any_mode() {
        let compiled = registry(vec![
            spec("any", 0.0, None),
            spec("koth_a", 5.0, Some("koth")),
            spec("payload_a", 5.0, Some("payload")),
            spec("anywhere", 5.0, None),
        ])
        .compile(all())
        .unwrap();
        let asked = |mode: Option<&[u8]>| -> Vec<String> {
            compiled
                .candidates(mode)
                .iter()
                .map(|&i| name(&compiled, i))
                .collect()
        };
        assert_eq!(asked(Some(b"payload")), ["anywhere", "payload_a", "any"]);
        assert_eq!(
            asked(Some(b"arena")),
            ["anywhere", "any"],
            "an unknown mode"
        );
        assert_eq!(asked(None), ["anywhere", "any"], "no mode");
    }

    #[test]
    fn nothing_active_chooses_nothing() {
        let compiled = registry(vec![spec("payload", 10.0, Some("payload"))])
            .compile(all())
            .unwrap();
        assert_eq!(compiled.choose(Some(b"koth"), |_| true), None);
    }

    #[test]
    fn a_name_again_replaces_its_entry_and_gives_back_the_old() {
        let mut registry = registry(vec![spec("a", 1.0, None)]);
        assert_eq!(
            registry.register(spec("a", 2.0, None)).unwrap().priority,
            1.0
        );
        let compiled = registry.compile(all()).unwrap();
        assert_eq!(compiled.entries.len(), 1);
        assert_eq!(compiled.entries[0].priority, 2.0);
    }

    #[test]
    fn what_compiled_keeps_what_it_was_made_from() {
        let mut registry = registry(vec![spec("a", 1.0, None)]);
        let compiled = registry.compile(all()).unwrap();
        registry.register(spec("a", 9.0, None));
        assert_eq!(compiled.entries[0].priority, 1.0);
        assert_eq!(registry.compile(all()).unwrap().entries[0].priority, 9.0);
    }

    #[test]
    fn a_behaviour_nobody_gave_is_refused_naming_both() {
        let mut lost = spec("lost", 1.0, None);
        lost.monitor = Some("Missing".into());
        let refused = registry(vec![lost]).compile(|_| false).unwrap_err();
        assert_eq!(
            refused.to_string(),
            "scenario lost's monitor Missing is no behaviour registered with NextSoldier"
        );
        let mut relies = spec("lost", 1.0, None);
        relies.behaviors = vec!["Travel".into(), "Missing".into()];
        let refused = registry(vec![relies])
            .compile(|b| b == b"Travel")
            .unwrap_err();
        assert_eq!(
            refused.to_string(),
            "scenario lost relies on Missing, no behaviour registered with NextSoldier"
        );
    }
}
