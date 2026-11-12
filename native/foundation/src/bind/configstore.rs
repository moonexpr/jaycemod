//! configstore, native: named whole-number values held to ranges and
//! guarded, the Lua twin's contract (foundation/configstore.lua). The keys
//! and ranges are Rust's; each entry is a read-only proxy table kept in the
//! store's environment (env.entries), so store[key] gives the same entry
//! each time. Parse reads numbers with Lua's own tonumber and quotes with
//! its %q, so refusals read as the Lua twin's.

use super::slots::fresh_environment;
use super::util::{boolean, env_field, nothing, number, number_at};
use crate::lua::{push_str, raise_where, set_function, string_at, tostring, CFunction, GLOBALSINDEX, L, TNIL};
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
    l.getfenv(-1);
    l.createtable(0, 0);
    l.setfield(-2, c"entries");
    l.settop(-2);
    1
}

/// A name at `index` (a non-empty string), or None.
unsafe fn name_at(l: L, index: c_int) -> Option<Vec<u8>> {
    string_at(l, index).filter(|n| !n.is_empty()).map(<[u8]>::to_vec)
}

/// The read-only entry proxy { min, max, guard }, pushed.
unsafe fn push_entry(l: L, min: f64, max: f64, guard: c_int) {
    l.createtable(0, 0);
    l.createtable(0, 2);
    l.createtable(0, 3);
    l.pushnumber(min);
    l.setfield(-2, c"min");
    l.pushnumber(max);
    l.setfield(-2, c"max");
    l.pushvalue(guard);
    l.setfield(-2, c"guard");
    l.setfield(-2, c"__index");
    set_function(l, c"__newindex", read_only);
    l.setmetatable(-2);
}

/// Stores the key at 2 for min..max, guarded by the value at `guard`.
unsafe fn add(l: L, min: Option<f64>, max: Option<f64>, guard: c_int) -> c_int {
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
    l.pushvalue(2);
    push_entry(l, lo, hi, guard);
    l.rawset(-3);
    l.settop(-2);
    userdata::check::<Store>(l, 1).entries.insert(key, Entry { min: lo, max: hi });
    l.pushvalue(1);
    1
}

unsafe extern "C-unwind" fn range(l: L) -> c_int {
    l.settop(5);
    add(l, number_at(l, 3), number_at(l, 4), 5)
}

unsafe extern "C-unwind" fn switch(l: L) -> c_int {
    l.settop(3);
    add(l, Some(0.0), Some(1.0), 3)
}

/// Pushes the entry of the key at `key`, or nil.
unsafe fn push_entry_of(l: L, key: c_int) -> c_int {
    env_field(l, 1, c"entries");
    l.pushvalue(key);
    l.rawget(-2);
    l.remove(-2);
    1
}

unsafe extern "C-unwind" fn get(l: L) -> c_int {
    userdata::check::<Store>(l, 1);
    l.settop(2);
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
    let store = userdata::check::<Store>(l, 1);
    let after = string_at(l, 2).map(<[u8]>::to_vec);
    let next = match &after {
        None => store.entries.keys().next(),
        Some(k) => store.entries.range::<Vec<u8>, _>((std::ops::Bound::Excluded(k), std::ops::Bound::Unbounded)).map(|(k, _)| k).next(),
    };
    let Some(next) = next.cloned() else { return nothing(l) };
    drop(after);
    l.pushlstring(next.as_ptr().cast(), next.len());
    drop(next);
    let key = l.gettop();
    push_entry_of(l, key);
    2
}

unsafe extern "C-unwind" fn keys(l: L) -> c_int {
    userdata::check::<Store>(l, 1);
    l.pushcclosure(step, 0);
    l.pushvalue(1);
    l.pushnil();
    3
}

unsafe extern "C-unwind" fn allowed(l: L) -> c_int {
    userdata::check::<Store>(l, 1);
    l.settop(3);
    push_entry_of(l, 2);
    if l.type_of(-1) == TNIL {
        return boolean(l, false);
    }
    l.getfield(-1, c"guard");
    let guard = l.gettop();
    l.pushvalue(3);
    l.pushvalue(guard);
    l.call(1, 1);
    let yes = l.type_of(-1) == crate::lua::TBOOLEAN && l.toboolean(-1) != 0;
    boolean(l, yes)
}

/// Pushes string.format(fmt, ...) of the values at `args`.
unsafe fn format_lua(l: L, fmt: &str, args: &[c_int]) {
    l.getfield(GLOBALSINDEX, c"string");
    l.getfield(-1, c"format");
    l.remove(-2);
    push_str(l, fmt);
    for &a in args {
        l.pushvalue(a);
    }
    l.call(args.len() as c_int + 1, 1);
}

unsafe extern "C-unwind" fn parse(l: L) -> c_int {
    l.settop(3);
    let store = userdata::check::<Store>(l, 1);
    let entry = string_at(l, 2).and_then(|k| store.entries.get(k)).map(|e| (e.min, e.max));
    let Some((min, max)) = entry else {
        let (key, name) = (tostring(l, 2), store.name.clone());
        l.pushnil();
        push_str(l, &format!("{key} is not one of {name}"));
        return 2;
    };
    l.getfield(GLOBALSINDEX, c"tonumber");
    l.pushvalue(3);
    l.call(1, 1);
    let Some(n) = number_at(l, -1) else {
        l.pushnil();
        crate::lua::push_tostring(l, 3);
        let shown = l.gettop();
        format_lua(l, "%s takes a number, not %q", &[2, shown]);
        l.remove(shown);
        return 2;
    };
    let value = (n + 0.5).floor();
    if value < min || value > max {
        l.pushnil();
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
    l.getmetatable(1);
    l.pushvalue(2);
    l.rawget(-2);
    if l.type_of(-1) != TNIL {
        return 1;
    }
    l.settop(2);
    push_entry_of(l, 2)
}

/// Pushes the configstore module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], None);
}
