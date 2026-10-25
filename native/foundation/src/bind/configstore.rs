//! configstore, native: named whole-number values held to ranges and
//! guarded, the Lua twin's contract (foundation/configstore.lua). The keys
//! and ranges are Rust's; each entry is a read-only proxy table kept in the
//! store's environment (env.entries), so store[key] gives the same entry
//! each time. Parse reads numbers with Lua's own tonumber and quotes with
//! its %q, so refusals read as the Lua twin's.

use super::slots::fresh_environment;
use super::util::{boolean, env_field, nothing, number, number_at};
use crate::lua::{api, push_str, raise_where, set_function, string_at, tostring, CFunction, GLOBALSINDEX, L, TNIL};
use crate::module;
use crate::userdata::{self, Native};
use std::collections::BTreeMap;
use std::ffi::{c_int, CStr};

struct Entry {
    min: f64,
    max: f64,
}

pub struct Store {
    name: String,
    entries: BTreeMap<Vec<u8>, Entry>,
}

impl Native for Store {
    const NAME: &'static CStr = c"foundation.configstore";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Range", range),
        (c"Switch", switch),
        (c"Get", get),
        (c"Has", has),
        (c"Size", size),
        (c"Keys", keys),
        (c"Allowed", allowed),
        (c"Parse", parse),
        (c"__newindex", read_only),
        (c"__call", keys),
        (c"__len", size),
        (c"__tostring", to_string),
    ];
    const INDEX: Option<CFunction> = Some(index);
}

unsafe extern "C-unwind" fn read_only(l: L) -> c_int {
    raise_where(l, "a configstore and its entries are changed only by Range and Switch".into())
}

/// configstore.New(name) -> a store
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    let name = string_at(l, 1).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned());
    let Some(name) = name else {
        let given = tostring(l, 1);
        raise_where(l, format!("a configstore needs a name, not {given}"));
    };
    userdata::push(l, Store { name, entries: BTreeMap::new() });
    fresh_environment(l, -1);
    let api = api();
    (api.getfenv)(l, -1);
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, -2, c"entries".as_ptr());
    (api.settop)(l, -2);
    1
}

/// A name at `index` (a non-empty string), or None.
unsafe fn name_at(l: L, index: c_int) -> Option<Vec<u8>> {
    string_at(l, index).filter(|n| !n.is_empty()).map(<[u8]>::to_vec)
}

/// The read-only entry proxy { min, max, guard }, pushed.
unsafe fn push_entry(l: L, min: f64, max: f64, guard: c_int) {
    let api = api();
    (api.createtable)(l, 0, 0);
    (api.createtable)(l, 0, 2);
    (api.createtable)(l, 0, 3);
    (api.pushnumber)(l, min);
    (api.setfield)(l, -2, c"min".as_ptr());
    (api.pushnumber)(l, max);
    (api.setfield)(l, -2, c"max".as_ptr());
    (api.pushvalue)(l, guard);
    (api.setfield)(l, -2, c"guard".as_ptr());
    (api.setfield)(l, -2, c"__index".as_ptr());
    set_function(l, c"__newindex", read_only);
    (api.setmetatable)(l, -2);
}

/// Stores the key at 2 for min..max, guarded by the value at `guard`.
unsafe fn add(l: L, min: Option<f64>, max: Option<f64>, guard: c_int) -> c_int {
    let api = api();
    let store = userdata::check::<Store>(l, 1);
    let name = store.name.clone();
    let Some(key) = name_at(l, 2) else {
        let given = tostring(l, 2);
        raise_where(l, format!("{name}: a key is a name, not {given}"));
    };
    let shown = String::from_utf8_lossy(&key).into_owned();
    if store.entries.contains_key(&key) {
        raise_where(l, format!("{name}: {shown} is stored already"));
    }
    let whole = |n: Option<f64>| n.filter(|n| n.floor() == *n);
    let range = whole(min).zip(whole(max)).filter(|(lo, hi)| lo <= hi);
    let Some((lo, hi)) = range else {
        let (lo, hi) = (tostring(l, 3), tostring(l, 4));
        raise_where(l, format!("{name}: {shown} needs a whole-number range, not {lo} to {hi}"));
    };
    if name_at(l, guard).is_none() {
        let given = tostring(l, guard);
        raise_where(l, format!("{name}: {shown} needs a guard, not {given}"));
    }
    drop(name);
    drop(shown);
    env_field(l, 1, c"entries");
    (api.pushvalue)(l, 2);
    push_entry(l, lo, hi, guard);
    (api.rawset)(l, -3);
    (api.settop)(l, -2);
    userdata::check::<Store>(l, 1).entries.insert(key, Entry { min: lo, max: hi });
    (api.pushvalue)(l, 1);
    1
}

unsafe extern "C-unwind" fn range(l: L) -> c_int {
    (api().settop)(l, 5);
    add(l, number_at(l, 3), number_at(l, 4), 5)
}

unsafe extern "C-unwind" fn switch(l: L) -> c_int {
    (api().settop)(l, 3);
    add(l, Some(0.0), Some(1.0), 3)
}

/// Pushes the entry of the key at `key`, or nil.
unsafe fn push_entry_of(l: L, key: c_int) -> c_int {
    let api = api();
    env_field(l, 1, c"entries");
    (api.pushvalue)(l, key);
    (api.rawget)(l, -2);
    (api.remove)(l, -2);
    1
}

unsafe extern "C-unwind" fn get(l: L) -> c_int {
    userdata::check::<Store>(l, 1);
    (api().settop)(l, 2);
    push_entry_of(l, 2)
}

unsafe extern "C-unwind" fn has(l: L) -> c_int {
    let store = userdata::check::<Store>(l, 1);
    let found = string_at(l, 2).is_some_and(|k| store.entries.contains_key(k));
    boolean(l, found)
}

unsafe extern "C-unwind" fn size(l: L) -> c_int {
    number(l, userdata::check::<Store>(l, 1).entries.len() as f64)
}

/// The walk Keys gives: (store, key) -> the next key in order, its entry.
unsafe extern "C-unwind" fn step(l: L) -> c_int {
    let api = api();
    let store = userdata::check::<Store>(l, 1);
    let after = string_at(l, 2).map(<[u8]>::to_vec);
    let next = match &after {
        None => store.entries.keys().next(),
        Some(k) => store.entries.range::<Vec<u8>, _>((std::ops::Bound::Excluded(k), std::ops::Bound::Unbounded)).map(|(k, _)| k).next(),
    };
    let Some(next) = next.cloned() else { return nothing(l) };
    drop(after);
    (api.pushlstring)(l, next.as_ptr().cast(), next.len());
    drop(next);
    let key = (api.gettop)(l);
    push_entry_of(l, key);
    2
}

unsafe extern "C-unwind" fn keys(l: L) -> c_int {
    let api = api();
    userdata::check::<Store>(l, 1);
    (api.pushcclosure)(l, step, 0);
    (api.pushvalue)(l, 1);
    (api.pushnil)(l);
    3
}

unsafe extern "C-unwind" fn allowed(l: L) -> c_int {
    let api = api();
    userdata::check::<Store>(l, 1);
    (api.settop)(l, 3);
    push_entry_of(l, 2);
    if (api.type_of)(l, -1) == TNIL {
        return boolean(l, false);
    }
    (api.getfield)(l, -1, c"guard".as_ptr());
    let guard = (api.gettop)(l);
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, guard);
    (api.call)(l, 1, 1);
    let yes = (api.type_of)(l, -1) == crate::lua::TBOOLEAN && (api.toboolean)(l, -1) != 0;
    boolean(l, yes)
}

/// Pushes string.format(fmt, ...) of the values at `args`.
unsafe fn format_lua(l: L, fmt: &str, args: &[c_int]) {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"string".as_ptr());
    (api.getfield)(l, -1, c"format".as_ptr());
    (api.remove)(l, -2);
    push_str(l, fmt);
    for &a in args {
        (api.pushvalue)(l, a);
    }
    (api.call)(l, args.len() as c_int + 1, 1);
}

unsafe extern "C-unwind" fn parse(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    let store = userdata::check::<Store>(l, 1);
    let entry = string_at(l, 2).and_then(|k| store.entries.get(k)).map(|e| (e.min, e.max));
    let Some((min, max)) = entry else {
        let (key, name) = (tostring(l, 2), store.name.clone());
        (api.pushnil)(l);
        push_str(l, &format!("{key} is not one of {name}"));
        return 2;
    };
    (api.getfield)(l, GLOBALSINDEX, c"tonumber".as_ptr());
    (api.pushvalue)(l, 3);
    (api.call)(l, 1, 1);
    let Some(n) = number_at(l, -1) else {
        (api.pushnil)(l);
        crate::lua::push_tostring(l, 3);
        let shown = (api.gettop)(l);
        format_lua(l, "%s takes a number, not %q", &[2, shown]);
        (api.remove)(l, shown);
        return 2;
    };
    let value = (n + 0.5).floor();
    if value < min || value > max {
        (api.pushnil)(l);
        let key = tostring(l, 2);
        push_str(l, &format!("{key} takes {} to {}", min as i64, max as i64));
        return 2;
    }
    push_str(l, &format!("{}", value as i64));
    1
}

unsafe extern "C-unwind" fn to_string(l: L) -> c_int {
    let store = userdata::check::<Store>(l, 1);
    let text = format!("configstore {} ({})", store.name, store.entries.len());
    push_str(l, &text);
    1
}

/// store[key]: a method, else the key's entry.
unsafe extern "C-unwind" fn index(l: L) -> c_int {
    let api = api();
    (api.getmetatable)(l, 1);
    (api.pushvalue)(l, 2);
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) != TNIL {
        return 1;
    }
    (api.settop)(l, 2);
    push_entry_of(l, 2)
}

/// Pushes the configstore module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], None);
}
