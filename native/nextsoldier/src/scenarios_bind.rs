//! wartactics.scenarios, native: the bridge between Lua and `scenarios.rs`, which holds
//! the state. What only Lua can hold is kept by number in a userdata's environment:
//! a registry's by its spec's id, a compiled structure's by its entry's place.

use crate::scenarios::{Compiled, Registry, Spec, FREEFORM_PRIORITY, MODE_PRIORITY};
use foundation::lua::{
    api, raise_where, string_at, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TNUMBER,
    TSTRING, TTABLE,
};
use foundation::module;
use foundation::userdata::{self, Native};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;
const SHARED: &CStr = c"nextsoldier.scenarios.shared";
const REQUIRE: &CStr = c"nextsoldier.scenarios.require";

pub struct RegistryData {
    model: Registry<u32>,
    next_id: u32,
}

impl Native for RegistryData {
    const NAME: &'static CStr = c"wartactics.scenarios.registry";
    const METHODS: &'static [(&'static CStr, CFunction)] =
        &[(c"Register", register), (c"Compile", compile)];
}

pub struct CompiledData {
    pub model: Compiled<u32>,
}

impl Native for CompiledData {
    const NAME: &'static CStr = c"wartactics.scenarios.compiled";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Choose", choose_method),
        (c"Class", class),
        (c"Behaviors", behaviors),
        (c"Entries", entries),
        (c"__newindex", compiled_refuses),
    ];
}

/// An entry, one a place in a compiled structure, which its environment keeps alive.
pub struct EntryData {
    compiled: *const CompiledData,
    place: u32,
}

impl EntryData {
    /// SAFETY of the read: its environment holds the compiled structure it points at.
    fn spec(&self) -> &Spec<u32> {
        unsafe { &(&*self.compiled).model.entries[self.place as usize] }
    }
}

impl Native for EntryData {
    const NAME: &'static CStr = c"wartactics.scenarios.entry";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[(c"__newindex", entry_refuses)];
    const INDEX: Option<CFunction> = Some(entry_index);
}

unsafe fn absolute(l: L, index: c_int) -> c_int {
    if index < 0 && index > REGISTRY {
        (api().gettop)(l) + index + 1
    } else {
        index
    }
}

unsafe fn check(l: L, ok: bool, why: &str) {
    if !ok {
        raise_where(l, format!("a scenario spec {why}"));
    }
}

/// A non-empty name in the field `name` of the table at 2 (left on the stack).
unsafe fn name_field(l: L, name: &CStr) -> Option<Vec<u8>> {
    (api().getfield)(l, 2, name.as_ptr());
    string_at(l, -1)
        .filter(|s| !s.is_empty())
        .map(<[u8]>::to_vec)
}

/// registry:Register(spec): parsed here, so the registry holds only what is valid.
unsafe extern "C-unwind" fn register(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    check(l, (api.type_of)(l, 2) == TTABLE, "is a table");
    let name = name_field(l, c"name");
    check(l, name.is_some(), "needs a name");
    (api.getfield)(l, 2, c"priority".as_ptr());
    check(
        l,
        (api.type_of)(l, -1) == TNUMBER,
        "needs a number priority",
    );
    let priority = (api.tonumber)(l, -1);
    (api.getfield)(l, 2, c"mode".as_ptr());
    let mode_kind = (api.type_of)(l, -1);
    check(
        l,
        mode_kind == TNIL || mode_kind == TSTRING,
        "names its mode by the rounds mode's NAME",
    );
    let mode = string_at(l, -1).map(<[u8]>::to_vec);
    (api.getfield)(l, 2, c"active".as_ptr());
    let active = (api.gettop)(l);
    let active_kind = (api.type_of)(l, active);
    check(
        l,
        active_kind == TNIL || active_kind == TFUNCTION,
        "gives its further criteria as active(context)",
    );
    (api.getfield)(l, 2, c"scenario".as_ptr());
    let scenario = (api.gettop)(l);
    let scenario_kind = (api.type_of)(l, scenario);
    check(
        l,
        scenario_kind == TTABLE || scenario_kind == TSTRING,
        "needs its Scenario class or module",
    );
    (api.getfield)(l, 2, c"monitor".as_ptr());
    let monitor_kind = (api.type_of)(l, -1);
    let monitor = string_at(l, -1)
        .filter(|s| !s.is_empty())
        .map(<[u8]>::to_vec);
    check(
        l,
        monitor_kind == TNIL || monitor.is_some(),
        "names its monitor as it is registered with NextSoldier",
    );
    (api.getfield)(l, 2, c"behaviors".as_ptr());
    let list = (api.gettop)(l);
    let list_kind = (api.type_of)(l, list);
    check(
        l,
        list_kind == TNIL || list_kind == TTABLE,
        "lists the behaviours it relies on",
    );
    let mut relies = Vec::new();
    if list_kind == TTABLE {
        let mut i = 1;
        loop {
            (api.rawgeti)(l, list, i);
            if (api.type_of)(l, -1) == TNIL {
                break;
            }
            let Some(behavior) = string_at(l, -1)
                .filter(|s| !s.is_empty())
                .map(<[u8]>::to_vec)
            else {
                drop(relies);
                raise_where(
                    l,
                    "a scenario spec names each behaviour it relies on".into(),
                );
            };
            relies.push(behavior);
            (api.settop)(l, -2);
            i += 1;
        }
    }
    let data = userdata::check::<RegistryData>(l, 1);
    data.next_id += 1;
    let id = data.next_id;
    (api.getfenv)(l, 1);
    let values = (api.gettop)(l);
    (api.pushvalue)(l, active);
    (api.rawseti)(l, values, id as c_int * 2);
    (api.pushvalue)(l, scenario);
    (api.rawseti)(l, values, id as c_int * 2 + 1);
    let replaced = data.model.register(Spec {
        name: name.unwrap_or_default(),
        priority,
        mode,
        monitor,
        behaviors: relies,
        value: id,
    });
    if let Some(old) = replaced {
        (api.pushnil)(l);
        (api.rawseti)(l, values, old.value as c_int * 2);
        (api.pushnil)(l);
        (api.rawseti)(l, values, old.value as c_int * 2 + 1);
    }
    0
}

/// Whether the behaviours at `behaviors` (what answers Has) have `name`.
unsafe fn has(l: L, behaviors: c_int, name: &[u8]) -> bool {
    let api = api();
    (api.getfield)(l, behaviors, c"Has".as_ptr());
    (api.pushvalue)(l, behaviors);
    (api.pushlstring)(l, name.as_ptr().cast(), name.len());
    (api.call)(l, 2, 1);
    let yes = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    yes
}

/// registry:Compile(behaviors) -> the structure a decision reads.
unsafe extern "C-unwind" fn compile(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let data = userdata::check::<RegistryData>(l, 1);
    let compiled = match data.model.compile(|name| has(l, 2, name)) {
        Ok(compiled) => compiled,
        Err(refused) => raise_where(l, refused.to_string()),
    };
    let count = compiled.entries.len();
    let ids: Vec<u32> = compiled.entries.iter().map(|e| e.value).collect();
    userdata::push(l, CompiledData { model: compiled });
    let made = (api.gettop)(l);
    let from = &*userdata::check::<CompiledData>(l, made) as *const CompiledData;
    (api.createtable)(l, count as c_int * 2, 2);
    let values = (api.gettop)(l);
    (api.getfenv)(l, 1);
    let source = (api.gettop)(l);
    (api.createtable)(l, count as c_int, 0);
    let list = (api.gettop)(l);
    for (place, id) in ids.iter().enumerate() {
        let place_key = place as c_int * 2 + 1;
        (api.rawgeti)(l, source, *id as c_int * 2);
        (api.rawseti)(l, values, place_key);
        (api.rawgeti)(l, source, *id as c_int * 2 + 1);
        (api.rawseti)(l, values, place_key + 1);
        userdata::push(
            l,
            EntryData {
                compiled: from,
                place: place as u32,
            },
        );
        (api.pushvalue)(l, values);
        (api.setfenv)(l, -2);
        (api.rawseti)(l, list, place as c_int + 1);
    }
    drop(ids);
    (api.pushvalue)(l, list);
    (api.setfield)(l, values, c"entries".as_ptr());
    (api.pushvalue)(l, made);
    (api.setfield)(l, values, c"compiled".as_ptr());
    (api.pushvalue)(l, values);
    (api.setfenv)(l, made);
    (api.pushvalue)(l, made);
    1
}

/// The place of the first active entry, asked with the context at `context`; None
/// when none is. Exposed for the native ScenarioMonitor.
pub unsafe fn choose(l: L, compiled: c_int, context: c_int) -> Option<u32> {
    let api = api();
    let (compiled, context) = (absolute(l, compiled), absolute(l, context));
    let data = userdata::check::<CompiledData>(l, compiled);
    (api.getfenv)(l, compiled);
    let values = (api.gettop)(l);
    (api.getfield)(l, context, c"mode".as_ptr());
    let mode = string_at(l, -1);
    data.model.choose(mode, |place| {
        (api.rawgeti)(l, values, place as c_int * 2 + 1);
        if (api.type_of)(l, -1) != TFUNCTION {
            (api.settop)(l, -2);
            return true;
        }
        (api.pushvalue)(l, context);
        (api.call)(l, 1, 1);
        let active = (api.toboolean)(l, -1) != 0;
        (api.settop)(l, -2);
        active
    })
}

/// compiled:Choose(context) -> the active entry of highest priority.
unsafe extern "C-unwind" fn choose_method(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let Some(place) = choose(l, 1, 2) else {
        (api.getfield)(l, 2, c"mode".as_ptr());
        let mode = tostring(l, -1);
        raise_where(l, format!("no scenario is active for mode {mode}"));
    };
    push_entry(l, 1, place);
    1
}

/// Pushes the entry at `place` of the compiled structure at `compiled`.
pub unsafe fn push_entry(l: L, compiled: c_int, place: u32) {
    let api = api();
    (api.getfenv)(l, compiled);
    (api.getfield)(l, -1, c"entries".as_ptr());
    (api.rawgeti)(l, -1, place as c_int + 1);
    (api.replace)(l, -3);
    (api.settop)(l, -2);
}

/// The name of the monitor the entry at `place` runs, on the stack, or nil.
pub unsafe fn push_monitor(l: L, compiled: c_int, place: u32) {
    let data = userdata::check::<CompiledData>(l, compiled);
    match &data.model.entries[place as usize].monitor {
        Some(monitor) => (api().pushlstring)(l, monitor.as_ptr().cast(), monitor.len()),
        None => (api().pushnil)(l),
    }
}

/// UseRequire(require): what a scenario's module is required by, which the index hands
/// over: a module named may be its host's. The Lua twin's chunk has it as its own.
unsafe extern "C-unwind" fn use_require(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.checktype)(l, 1, TFUNCTION);
    (api.setfield)(l, REGISTRY, REQUIRE.as_ptr());
    0
}

/// compiled:Class(entry) -> its Scenario class; a module named is required each time,
/// so one loaded again, or put in place, is the one given.
unsafe extern "C-unwind" fn class(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let entry = userdata::check::<EntryData>(l, 2);
    (api.getfenv)(l, 2);
    (api.rawgeti)(l, -1, entry.place as c_int * 2 + 2);
    let scenario = (api.gettop)(l);
    if (api.type_of)(l, scenario) != TSTRING {
        return 1;
    }
    (api.getfield)(l, REGISTRY, REQUIRE.as_ptr());
    if (api.type_of)(l, -1) != TFUNCTION {
        (api.getfield)(l, GLOBALSINDEX, c"require".as_ptr());
    }
    (api.pushvalue)(l, scenario);
    (api.call)(l, 1, 1);
    (api.getfield)(l, -1, c"Scenario".as_ptr());
    1
}

/// compiled:Behaviors(entry) -> the names of those it relies on, a fresh list.
unsafe extern "C-unwind" fn behaviors(l: L) -> c_int {
    (api().settop)(l, 2);
    let entry = userdata::check::<EntryData>(l, 2);
    push_behaviors(l, entry);
    1
}

unsafe fn push_behaviors(l: L, entry: &EntryData) {
    let api = api();
    let list = &entry.spec().behaviors;
    (api.createtable)(l, list.len() as c_int, 0);
    for (i, name) in list.iter().enumerate() {
        (api.pushlstring)(l, name.as_ptr().cast(), name.len());
        (api.rawseti)(l, -2, i as c_int + 1);
    }
}

/// compiled:Entries() -> the entries, highest priority first, a fresh list.
unsafe extern "C-unwind" fn entries(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    let count = userdata::check::<CompiledData>(l, 1).model.entries.len();
    (api.createtable)(l, count as c_int, 0);
    for place in 0..count {
        push_entry(l, 1, place as u32);
        (api.rawseti)(l, 2, place as c_int + 1);
    }
    1
}

unsafe extern "C-unwind" fn compiled_refuses(l: L) -> c_int {
    let key = tostring(l, 2);
    raise_where(
        l,
        format!("the compiled scenarios is compiled: {key} cannot be set"),
    )
}

unsafe extern "C-unwind" fn entry_refuses(l: L) -> c_int {
    let entry = userdata::check::<EntryData>(l, 1);
    let name = String::from_utf8_lossy(&entry.spec().name).into_owned();
    let key = tostring(l, 2);
    raise_where(
        l,
        format!("scenario {name} is compiled: {key} cannot be set"),
    )
}

/// What an entry reads as: the spec it was made from.
unsafe extern "C-unwind" fn entry_index(l: L) -> c_int {
    let api = api();
    let entry = userdata::check::<EntryData>(l, 1);
    let spec = entry.spec();
    let bytes = |text: &[u8]| (api.pushlstring)(l, text.as_ptr().cast(), text.len());
    match string_at(l, 2).unwrap_or_default() {
        b"name" => bytes(&spec.name),
        b"priority" => (api.pushnumber)(l, spec.priority),
        b"mode" => match &spec.mode {
            Some(mode) => bytes(mode),
            None => (api.pushnil)(l),
        },
        b"monitor" => match &spec.monitor {
            Some(monitor) => bytes(monitor),
            None => (api.pushnil)(l),
        },
        b"behaviors" => push_behaviors(l, entry),
        b"active" => {
            (api.getfenv)(l, 1);
            (api.rawgeti)(l, -1, entry.place as c_int * 2 + 1);
        }
        b"scenario" => {
            (api.getfenv)(l, 1);
            (api.rawgeti)(l, -1, entry.place as c_int * 2 + 2);
        }
        _ => (api.pushnil)(l),
    }
    1
}

/// New() -> a registry.
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    userdata::push(
        l,
        RegistryData {
            model: Registry::default(),
            next_id: 0,
        },
    );
    (api().createtable)(l, 0, 0);
    (api().setfenv)(l, -2);
    1
}

/// Pushes the wartactics.scenarios module. Its Shared is one a Lua state, so a module
/// opened again goes on with what was registered.
pub unsafe fn push_module(l: L) {
    let api = api();
    module::push(l, &[(c"New", new), (c"UseRequire", use_require)], None);
    (api.pushnumber)(l, FREEFORM_PRIORITY);
    (api.setfield)(l, -2, c"FREEFORM_PRIORITY".as_ptr());
    (api.pushnumber)(l, MODE_PRIORITY);
    (api.setfield)(l, -2, c"MODE_PRIORITY".as_ptr());
    (api.getfield)(l, REGISTRY, SHARED.as_ptr());
    if (api.type_of)(l, -1) == TNIL {
        (api.settop)(l, -2);
        new(l);
        (api.pushvalue)(l, -1);
        (api.setfield)(l, REGISTRY, SHARED.as_ptr());
    }
    (api.setfield)(l, -2, c"Shared".as_ptr());
}
