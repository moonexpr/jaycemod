//! cache.base, cache.lru, cache.expiring and cache.memo, native: the Lua
//! twins' contracts (foundation/cache/). A cache is a class (core.class)
//! whose subclasses fill policy hooks and keep their fields in State(cache),
//! so the native caches keep that shape: the classes are tables of C
//! functions (Class.Extend still subclasses them: reach_memo extends
//! Expiring), and each cache's state is a Lua table in a weak registry
//! table, holding the native list.slots and list.chain and the key and value
//! tables by slot, as the Lua twin's does.

use super::core::{construct_through, extend, port_check, port_new};
use super::util::{boolean, number};
use crate::lua::{api, push_str, raise_at, raise_where, set_function, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TNUMBER, TTABLE};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;
const STATE: &CStr = c"foundation.cache.state";

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

/// Pushes the weak-keyed table of every cache's state.
unsafe fn states(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, STATE.as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.createtable)(l, 0, 0);
    (api.createtable)(l, 0, 1);
    push_str(l, "k");
    (api.setfield)(l, -2, c"__mode".as_ptr());
    (api.setmetatable)(l, -2);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, STATE.as_ptr());
}

/// Pushes the state of the cache at `cache`; its index.
unsafe fn own(l: L, cache: c_int) -> c_int {
    let api = api();
    states(l);
    (api.pushvalue)(l, cache);
    (api.rawget)(l, -2);
    (api.remove)(l, -2);
    (api.gettop)(l)
}

/// Calls obj:name(args...) for the values at `args` (absolute), leaving
/// `results` results.
unsafe fn method(l: L, obj: c_int, name: &CStr, args: &[c_int], results: c_int) {
    let api = api();
    (api.getfield)(l, obj, name.as_ptr());
    (api.pushvalue)(l, obj);
    for &a in args {
        (api.pushvalue)(l, a);
    }
    (api.call)(l, args.len() as c_int + 1, results);
}

/// Calls the hook cache:name(slot), one result left when `results` is 1.
unsafe fn hook(l: L, cache: c_int, name: &CStr, slot: f64, results: c_int) {
    let api = api();
    (api.pushnumber)(l, slot);
    let s = (api.gettop)(l);
    method(l, cache, name, &[s], results);
    (api.remove)(l, s);
}

/// t[k] where t is field `table` of the state at `own`, for the value at
/// `key`; pushed.
unsafe fn own_get(l: L, own: c_int, table: &CStr, key: c_int) {
    let api = api();
    let key = if key < 0 { (api.gettop)(l) + key + 1 } else { key };
    (api.getfield)(l, own, table.as_ptr());
    (api.pushvalue)(l, key);
    (api.rawget)(l, -2);
    (api.remove)(l, -2);
}

/// field `table` of the state at `own`, [value at key] = value at value.
unsafe fn own_set(l: L, own: c_int, table: &CStr, key: c_int, value: c_int) {
    let api = api();
    let top = (api.gettop)(l);
    let key = if key < 0 { top + key + 1 } else { key };
    let value = if value < 0 { top + value + 1 } else { value };
    (api.getfield)(l, own, table.as_ptr());
    (api.pushvalue)(l, key);
    (api.pushvalue)(l, value);
    (api.rawset)(l, -3);
    (api.settop)(l, -2);
}

/// The entry at `slot` out of every structure, its slot freed; then, with a
/// reason, its value released. Leaves the value pushed.
unsafe fn drop_slot(l: L, cache: c_int, own: c_int, slot: f64, reason: Option<&str>) {
    let api = api();
    (api.pushnumber)(l, slot);
    let s = (api.gettop)(l);
    own_get(l, own, c"keys", s);
    let key = (api.gettop)(l);
    own_get(l, own, c"values", s);
    let value = (api.gettop)(l);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    method(l, order, c"Unlink", &[s], 0);
    (api.settop)(l, value);
    (api.pushnil)(l);
    let nil = (api.gettop)(l);
    own_set(l, own, c"slotOf", key, nil);
    own_set(l, own, c"keys", s, nil);
    own_set(l, own, c"values", s, nil);
    (api.settop)(l, value);
    hook(l, cache, c"Dropped", slot, 0);
    (api.getfield)(l, own, c"slots".as_ptr());
    let slots = (api.gettop)(l);
    method(l, slots, c"Free", &[s], 0);
    (api.settop)(l, value);
    if let Some(reason) = reason {
        (api.getfield)(l, own, c"release".as_ptr());
        (api.pushvalue)(l, key);
        (api.pushvalue)(l, value);
        push_str(l, reason);
        (api.call)(l, 3, 0);
    }
    (api.insert)(l, s);
    (api.settop)(l, s);
}

/// The key at `key`'s live slot, a stale one dropped on the way; or None.
unsafe fn live(l: L, cache: c_int, own: c_int, key: c_int) -> Option<f64> {
    let api = api();
    own_get(l, own, c"slotOf", key);
    let slot = ((api.type_of)(l, -1) == TNUMBER).then(|| (api.tonumber)(l, -1));
    (api.settop)(l, -2);
    let slot = slot?;
    hook(l, cache, c"Stale", slot, 1);
    let stale = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    if stale {
        drop_slot(l, cache, own, slot, Some("expired"));
        (api.settop)(l, -2);
        return None;
    }
    Some(slot)
}

/// Reads the key at `key` (counting a use); pushes the value or nil.
unsafe fn read(l: L, cache: c_int, key: c_int) {
    let api = api();
    let own = own(l, cache);
    match live(l, cache, own, key) {
        None => (api.pushnil)(l),
        Some(slot) => {
            hook(l, cache, c"Touch", slot, 0);
            (api.pushnumber)(l, slot);
            own_get(l, own, c"values", -1);
            (api.remove)(l, -2);
        }
    }
    (api.remove)(l, own);
}

/// Writes the value at `value` under the key at `key` (nil removes).
unsafe fn write(l: L, cache: c_int, key: c_int, value: c_int) {
    let api = api();
    if (api.type_of)(l, key) == TNIL {
        raise_where(l, "a cache keeps no nil key".into());
    }
    let own = own(l, cache);
    let slot = live(l, cache, own, key);
    if (api.type_of)(l, value) == TNIL {
        if let Some(slot) = slot {
            drop_slot(l, cache, own, slot, Some("removed"));
        }
        (api.settop)(l, own - 1);
        return;
    }
    if let Some(slot) = slot {
        (api.pushnumber)(l, slot);
        let s = (api.gettop)(l);
        own_get(l, own, c"values", s);
        let old = (api.gettop)(l);
        own_set(l, own, c"values", s, value);
        hook(l, cache, c"Rewrite", slot, 0);
        if (api.equal)(l, old, value) == 0 {
            (api.getfield)(l, own, c"release".as_ptr());
            (api.pushvalue)(l, key);
            (api.pushvalue)(l, old);
            push_str(l, "replaced");
            (api.call)(l, 3, 0);
        }
        (api.settop)(l, own - 1);
        return;
    }
    method(l, cache, c"Admitting", &[], 0);
    (api.getfield)(l, own, c"slots".as_ptr());
    let slots = (api.gettop)(l);
    method(l, slots, c"Alloc", &[], 1);
    let s = (api.gettop)(l);
    let slot = (api.tonumber)(l, s);
    own_set(l, own, c"slotOf", key, s);
    own_set(l, own, c"keys", s, key);
    own_set(l, own, c"values", s, value);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    method(l, order, c"PushFront", &[s], 0);
    hook(l, cache, c"Admitted", slot, 0);
    (api.getfield)(l, own, c"capacity".as_ptr());
    let capacity = ((api.type_of)(l, -1) == TNUMBER).then(|| (api.tonumber)(l, -1));
    (api.settop)(l, -2);
    if let Some(capacity) = capacity {
        loop {
            method(l, order, c"Size", &[], 1);
            let size = (api.tonumber)(l, -1);
            (api.settop)(l, -2);
            if size <= capacity {
                break;
            }
            method(l, order, c"Back", &[], 1);
            let back = (api.tonumber)(l, -1);
            (api.settop)(l, -2);
            drop_slot(l, cache, own, back, Some("evicted"));
            (api.settop)(l, -2);
        }
    }
    (api.settop)(l, own - 1);
}

/// cache[key]: a method along the cache's classes, else the value.
unsafe extern "C-unwind" fn index(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    if (api.getmetatable)(l, 1) == 0 {
        (api.pushnil)(l);
    }
    while (api.type_of)(l, -1) == TTABLE {
        (api.pushvalue)(l, 2);
        (api.rawget)(l, -2);
        if (api.type_of)(l, -1) != TNIL {
            return 1;
        }
        (api.settop)(l, -2);
        if (api.getmetatable)(l, -1) == 0 {
            (api.pushnil)(l);
        }
        (api.remove)(l, -2);
    }
    (api.settop)(l, 2);
    read(l, 1, 2);
    1
}

unsafe extern "C-unwind" fn newindex(l: L) -> c_int {
    (api().settop)(l, 3);
    write(l, 1, 2, 3);
    0
}

/// The walk cache() gives: upvalue 1 the cache's state, 2 the next slot.
unsafe extern "C-unwind" fn entry_step(l: L) -> c_int {
    let api = api();
    if (api.type_of)(l, upvalue(2)) != TNUMBER {
        (api.pushnil)(l);
        return 1;
    }
    let own = upvalue(1);
    (api.pushvalue)(l, upvalue(2));
    let slot = (api.gettop)(l);
    own_get(l, own, c"keys", slot);
    own_get(l, own, c"values", slot);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    method(l, order, c"After", &[slot], 1);
    (api.replace)(l, upvalue(2));
    (api.settop)(l, order - 1);
    2
}

/// cache(): an iterator over the entries, newest first.
unsafe extern "C-unwind" fn entries(l: L) -> c_int {
    let api = api();
    let own = own(l, 1);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    method(l, order, c"Front", &[], 1);
    let front = (api.gettop)(l);
    (api.pushvalue)(l, own);
    (api.pushvalue)(l, front);
    (api.pushcclosure)(l, entry_step, 2);
    1
}

unsafe fn size_of(l: L, cache: c_int) -> f64 {
    let api = api();
    let own = own(l, cache);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    method(l, order, c"Size", &[], 1);
    let size = (api.tonumber)(l, -1);
    (api.settop)(l, own - 1);
    size
}

unsafe extern "C-unwind" fn length(l: L) -> c_int {
    number(l, size_of(l, 1))
}

unsafe extern "C-unwind" fn to_string(l: L) -> c_int {
    let api = api();
    (api.getfield)(l, 1, c"kind".as_ptr());
    let kind = tostring(l, -1);
    let size = size_of(l, 1);
    let own = own(l, 1);
    (api.getfield)(l, own, c"capacity".as_ptr());
    let mut text = format!("{kind}: {}", size as i64);
    if (api.type_of)(l, -1) == TNUMBER {
        text.push_str(&format!(" of {}", tostring(l, -1)));
    }
    push_str(l, &text);
    1
}

/// Init's refusal, blaming New's caller (Init, Construct, New: three up).
unsafe fn refuse(l: L, why: &str, value: c_int) -> ! {
    let given = tostring(l, value);
    raise_at(l, 3, format!("a cache's {why}, not {given}"))
}

unsafe extern "C-unwind" fn owned(_l: L) -> c_int {
    0
}

unsafe extern "C-unwind" fn init(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.getfield)(l, 2, c"capacity".as_ptr());
    let capacity = (api.gettop)(l);
    (api.getfield)(l, 2, c"release".as_ptr());
    let release = (api.gettop)(l);
    if (api.type_of)(l, capacity) != TNIL {
        let ok = (api.type_of)(l, capacity) == TNUMBER && {
            let c = (api.tonumber)(l, capacity);
            c >= 1.0 && c.floor() == c
        };
        if !ok {
            refuse(l, "capacity is a whole number of at least 1", capacity);
        }
    }
    if (api.type_of)(l, release) != TNIL && (api.type_of)(l, release) != TFUNCTION {
        refuse(l, "release is a function", release);
    }
    states(l);
    (api.pushvalue)(l, 1);
    (api.createtable)(l, 0, 7);
    let own = (api.gettop)(l);
    (api.pushvalue)(l, capacity);
    (api.setfield)(l, own, c"capacity".as_ptr());
    if (api.type_of)(l, release) == TNIL {
        (api.pushcclosure)(l, owned, 0);
    } else {
        (api.pushvalue)(l, release);
    }
    (api.setfield)(l, own, c"release".as_ptr());
    for (field, namespace, module) in [(c"slots", c"list", c"slots"), (c"order", c"list", c"chain")] {
        (api.getfield)(l, GLOBALSINDEX, namespace.as_ptr());
        (api.getfield)(l, -1, module.as_ptr());
        (api.getfield)(l, -1, c"New".as_ptr());
        (api.call)(l, 0, 1);
        (api.setfield)(l, own, field.as_ptr());
        (api.settop)(l, own);
    }
    for field in [c"slotOf", c"keys", c"values"] {
        (api.createtable)(l, 0, 0);
        (api.setfield)(l, own, field.as_ptr());
    }
    (api.rawset)(l, -3);
    0
}

unsafe extern "C-unwind" fn no_op(_l: L) -> c_int {
    0
}

unsafe extern "C-unwind" fn never_stale(l: L) -> c_int {
    boolean(l, false)
}

unsafe extern "C-unwind" fn drop_slot_method(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    let slot = (api.checknumber)(l, 2);
    let reason = crate::lua::string_at(l, 3).map(|r| String::from_utf8_lossy(r).into_owned());
    let own = own(l, 1);
    drop_slot(l, 1, own, slot, reason.as_deref());
    drop(reason);
    1
}

unsafe extern "C-unwind" fn get(l: L) -> c_int {
    (api().settop)(l, 2);
    read(l, 1, 2);
    1
}

unsafe extern "C-unwind" fn put(l: L) -> c_int {
    (api().settop)(l, 3);
    if (api().type_of)(l, 3) == TNIL {
        raise_where(l, "a cache keeps no nil value: Remove removes".into());
    }
    write(l, 1, 2, 3);
    0
}

unsafe extern "C-unwind" fn remove(l: L) -> c_int {
    (api().settop)(l, 2);
    (api().pushnil)(l);
    write(l, 1, 2, 3);
    0
}

unsafe extern "C-unwind" fn peek(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let own = own(l, 1);
    match live(l, 1, own, 2) {
        Some(slot) => {
            (api.pushnumber)(l, slot);
            own_get(l, own, c"values", -1);
        }
        None => (api.pushnil)(l),
    }
    1
}

unsafe extern "C-unwind" fn take(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let own = own(l, 1);
    match live(l, 1, own, 2) {
        Some(slot) => drop_slot(l, 1, own, slot, None),
        None => (api.pushnil)(l),
    }
    1
}

/// Every entry dropped first, then each value released, front to back, so
/// a release that puts finds the cache already empty.
unsafe fn empty(l: L, reason: &str) {
    let api = api();
    let own = own(l, 1);
    (api.createtable)(l, 0, 0);
    let keys = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let values = (api.gettop)(l);
    entries(l);
    let step = (api.gettop)(l);
    let mut n = 0;
    loop {
        (api.pushvalue)(l, step);
        (api.call)(l, 0, 2);
        if (api.type_of)(l, -2) == TNIL {
            (api.settop)(l, step);
            break;
        }
        n += 1;
        (api.rawseti)(l, values, n);
        (api.rawseti)(l, keys, n);
    }
    for i in 1..=n {
        (api.rawgeti)(l, keys, i);
        own_get(l, own, c"slotOf", -1);
        let slot = (api.tonumber)(l, -1);
        (api.settop)(l, step);
        drop_slot(l, 1, own, slot, None);
        (api.settop)(l, step);
    }
    for i in 1..=n {
        (api.getfield)(l, own, c"release".as_ptr());
        (api.rawgeti)(l, keys, i);
        (api.rawgeti)(l, values, i);
        push_str(l, reason);
        (api.call)(l, 3, 0);
    }
    (api.settop)(l, own - 1);
}

unsafe extern "C-unwind" fn clear(l: L) -> c_int {
    (api().settop)(l, 1);
    empty(l, "cleared");
    0
}

unsafe extern "C-unwind" fn keys(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.createtable)(l, 0, 0);
    let list = (api.gettop)(l);
    // cache() through the class's own __call (an expiring cache prunes first)
    (api.getmetatable)(l, 1);
    (api.getfield)(l, -1, c"__call".as_ptr());
    (api.pushvalue)(l, 1);
    (api.call)(l, 1, 1);
    let step = (api.gettop)(l);
    let mut n = 0;
    loop {
        (api.pushvalue)(l, step);
        (api.call)(l, 0, 1);
        if (api.type_of)(l, -1) == TNIL {
            break;
        }
        n += 1;
        (api.rawseti)(l, list, n);
    }
    (api.settop)(l, list);
    1
}

unsafe extern "C-unwind" fn destroy_cache(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    empty(l, "destroyed");
    states(l);
    (api.pushvalue)(l, 1);
    (api.pushnil)(l);
    (api.rawset)(l, -3);
    0
}

/// cache.base.State(cache) -> its state table
unsafe extern "C-unwind" fn state(l: L) -> c_int {
    own(l, 1);
    1
}

/// Pushes the Cache class.
unsafe fn cache_class(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.cache.Cache".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.createtable)(l, 0, 24);
    push_str(l, "cache");
    (api.setfield)(l, -2, c"kind".as_ptr());
    let functions: &[(&CStr, CFunction)] = &[
        (c"__index", index),
        (c"__newindex", newindex),
        (c"__call", entries),
        (c"__len", length),
        (c"__tostring", to_string),
        (c"Init", init),
        (c"Touch", no_op),
        (c"Rewrite", no_op),
        (c"Admitting", no_op),
        (c"Admitted", no_op),
        (c"Stale", never_stale),
        (c"Dropped", no_op),
        (c"DropSlot", drop_slot_method),
        (c"Get", get),
        (c"Put", put),
        (c"Remove", remove),
        (c"Peek", peek),
        (c"Take", take),
        (c"Clear", clear),
        (c"Size", length),
        (c"Keys", keys),
        (c"Destroy", destroy_cache),
    ];
    for (name, f) in functions {
        set_function(l, name, *f);
    }
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.cache.Cache".as_ptr());
}

/// Pushes Class.Extend(parent at `parent`, fields at the top (popped)).
unsafe fn subclass(l: L, parent: c_int) {
    let api = api();
    let fields = (api.gettop)(l);
    (api.pushcclosure)(l, extend, 0);
    (api.pushvalue)(l, parent);
    (api.pushvalue)(l, fields);
    (api.call)(l, 2, 1);
    (api.remove)(l, fields);
}

/// A New for a class kept in the registry under `key`: constructs through
/// core.class.Construct.
unsafe fn new_of(l: L, key: &CStr) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, REGISTRY, key.as_ptr());
    (api.insert)(l, 1);
    construct_through(l, 1, 2)
}

unsafe extern "C-unwind" fn base_new(l: L) -> c_int {
    cache_class(l);
    (api().settop)(l, -2);
    new_of(l, c"foundation.cache.Cache")
}

// cache.lru ---------------------------------------------------------------------

/// Touch and Rewrite: the entry to the front.
unsafe extern "C-unwind" fn recent(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let own = own(l, 1);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    method(l, order, c"MoveFront", &[2], 0);
    0
}

unsafe extern "C-unwind" fn lru_init(l: L) -> c_int {
    let api = api();
    (api.getfield)(l, 2, c"capacity".as_ptr());
    if (api.type_of)(l, -1) == TNIL {
        raise_at(l, 3, "an LRU cache needs a capacity".into());
    }
    0
}

unsafe fn lru_class(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.cache.Lru".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    cache_class(l);
    let parent = (api.gettop)(l);
    (api.createtable)(l, 0, 4);
    push_str(l, "lru cache");
    (api.setfield)(l, -2, c"kind".as_ptr());
    set_function(l, c"Init", lru_init);
    set_function(l, c"Touch", recent);
    set_function(l, c"Rewrite", recent);
    subclass(l, parent);
    (api.remove)(l, parent);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.cache.Lru".as_ptr());
}

unsafe extern "C-unwind" fn lru_new(l: L) -> c_int {
    lru_class(l);
    (api().settop)(l, -2);
    new_of(l, c"foundation.cache.Lru")
}

// cache.expiring ------------------------------------------------------------------

/// clock:Now() of the state at `own`.
unsafe fn clock_now(l: L, own: c_int) -> f64 {
    let api = api();
    (api.getfield)(l, own, c"clock".as_ptr());
    let clock = (api.gettop)(l);
    method(l, clock, c"Now", &[], 1);
    let now = (api.tonumber)(l, -1);
    (api.settop)(l, clock - 1);
    now
}

unsafe fn expired(l: L, own: c_int, slot: c_int) -> bool {
    let api = api();
    let now = clock_now(l, own);
    own_get(l, own, c"written", slot);
    let written = (api.tonumber)(l, -1);
    (api.settop)(l, -2);
    (api.getfield)(l, own, c"term".as_ptr());
    let term = (api.tonumber)(l, -1);
    (api.settop)(l, -2);
    now - written > term
}

unsafe extern "C-unwind" fn expiring_stale(l: L) -> c_int {
    (api().settop)(l, 2);
    let own = own(l, 1);
    boolean(l, expired(l, own, 2))
}

unsafe extern "C-unwind" fn stamp(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let own = own(l, 1);
    let now = clock_now(l, own);
    (api.pushnumber)(l, now);
    own_set(l, own, c"written", 2, -1);
    0
}

unsafe extern "C-unwind" fn expiring_rewrite(l: L) -> c_int {
    stamp(l);
    recent(l)
}

unsafe extern "C-unwind" fn expiring_dropped(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let own = own(l, 1);
    (api.pushnil)(l);
    own_set(l, own, c"written", 2, -1);
    0
}

unsafe extern "C-unwind" fn prune(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    let own = own(l, 1);
    (api.getfield)(l, own, c"order".as_ptr());
    let order = (api.gettop)(l);
    loop {
        method(l, order, c"Back", &[], 1);
        let back = (api.gettop)(l);
        if (api.type_of)(l, back) != TNUMBER || !expired(l, own, back) {
            break;
        }
        push_str(l, "expired");
        let reason = (api.gettop)(l);
        method(l, 1, c"DropSlot", &[back, reason], 0);
        (api.settop)(l, order);
    }
    0
}

unsafe extern "C-unwind" fn expiring_call(l: L) -> c_int {
    (api().settop)(l, 1);
    prune(l);
    (api().settop)(l, 1);
    entries(l)
}

unsafe extern "C-unwind" fn expiring_init(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.getfield)(l, 2, c"term".as_ptr());
    let term = (api.gettop)(l);
    let ok = (api.type_of)(l, term) == TNUMBER && (api.tonumber)(l, term) > 0.0;
    if !ok {
        let given = tostring(l, term);
        raise_at(l, 3, format!("an expiring cache's term is a number of seconds above 0, not {given}"));
    }
    let own = own(l, 1);
    (api.getfield)(l, REGISTRY, c"foundation.cache.CLOCK".as_ptr());
    let clock_port = (api.gettop)(l);
    (api.getfield)(l, 2, c"clock".as_ptr());
    let given = (api.gettop)(l);
    (api.pushcclosure)(l, port_check, 0);
    (api.pushvalue)(l, clock_port);
    (api.pushvalue)(l, given);
    (api.call)(l, 2, 1);
    (api.setfield)(l, own, c"clock".as_ptr());
    (api.pushvalue)(l, term);
    (api.setfield)(l, own, c"term".as_ptr());
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, own, c"written".as_ptr());
    0
}

/// Pushes the clock port, made the first time.
unsafe fn clock_port(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.cache.CLOCK".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    (api.pushcclosure)(l, port_new, 0);
    push_str(l, "clock");
    (api.createtable)(l, 1, 0);
    push_str(l, "Now");
    (api.rawseti)(l, -2, 1);
    (api.call)(l, 2, 1);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.cache.CLOCK".as_ptr());
}

unsafe fn expiring_class(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.cache.Expiring".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    clock_port(l);
    (api.settop)(l, -2);
    cache_class(l);
    let parent = (api.gettop)(l);
    (api.createtable)(l, 0, 10);
    push_str(l, "expiring cache");
    (api.setfield)(l, -2, c"kind".as_ptr());
    set_function(l, c"__call", expiring_call);
    set_function(l, c"Init", expiring_init);
    set_function(l, c"Admitting", prune);
    set_function(l, c"Admitted", stamp);
    set_function(l, c"Rewrite", expiring_rewrite);
    set_function(l, c"Stale", expiring_stale);
    set_function(l, c"Dropped", expiring_dropped);
    set_function(l, c"Prune", prune);
    subclass(l, parent);
    (api.remove)(l, parent);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.cache.Expiring".as_ptr());
}

unsafe extern "C-unwind" fn expiring_new(l: L) -> c_int {
    expiring_class(l);
    (api().settop)(l, -2);
    new_of(l, c"foundation.cache.Expiring")
}

// cache.memo -----------------------------------------------------------------------

unsafe extern "C-unwind" fn unstamp(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    let own = own(l, 1);
    (api.pushnil)(l);
    own_set(l, own, c"stamps", 2, -1);
    0
}

unsafe extern "C-unwind" fn memo_init(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    let own = own(l, 1);
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, own, c"stamps".as_ptr());
    0
}

unsafe extern "C-unwind" fn fetch(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 4);
    if (api.type_of)(l, 3) == TNIL {
        raise_where(l, "a memo's stamp is anything but nil".into());
    }
    let own = own(l, 1);
    own_get(l, own, c"slotOf", 2);
    let slot = (api.gettop)(l);
    if (api.type_of)(l, slot) == TNUMBER {
        own_get(l, own, c"stamps", slot);
        let same = (api.equal)(l, -1, 3) != 0;
        (api.settop)(l, slot);
        if same {
            method(l, 1, c"Get", &[2], 1);
            return 1;
        }
    }
    (api.settop)(l, own);
    (api.pushvalue)(l, 4);
    (api.pushvalue)(l, 2);
    (api.call)(l, 1, 1);
    let value = (api.gettop)(l);
    method(l, 1, c"Put", &[2, value], 0);
    own_get(l, own, c"slotOf", 2);
    let slot = (api.gettop)(l);
    own_set(l, own, c"stamps", slot, 3);
    (api.pushvalue)(l, value);
    1
}

unsafe fn memo_class(l: L) {
    let api = api();
    (api.getfield)(l, REGISTRY, c"foundation.cache.Memo".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return;
    }
    (api.settop)(l, -2);
    cache_class(l);
    let parent = (api.gettop)(l);
    (api.createtable)(l, 0, 5);
    push_str(l, "memo");
    (api.setfield)(l, -2, c"kind".as_ptr());
    set_function(l, c"Init", memo_init);
    set_function(l, c"Rewrite", unstamp);
    set_function(l, c"Dropped", unstamp);
    set_function(l, c"Fetch", fetch);
    subclass(l, parent);
    (api.remove)(l, parent);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, REGISTRY, c"foundation.cache.Memo".as_ptr());
}

unsafe extern "C-unwind" fn memo_new(l: L) -> c_int {
    memo_class(l);
    (api().settop)(l, -2);
    new_of(l, c"foundation.cache.Memo")
}

/// Pushes the cache namespace's native modules into the table at the top.
pub unsafe fn push_modules(l: L) {
    let api = api();
    crate::module::push(l, &[(c"New", base_new), (c"State", state)], None);
    for (name, value) in [
        (c"EVICTED", "evicted"),
        (c"EXPIRED", "expired"),
        (c"REPLACED", "replaced"),
        (c"REMOVED", "removed"),
        (c"CLEARED", "cleared"),
        (c"DESTROYED", "destroyed"),
    ] {
        push_str(l, value);
        (api.setfield)(l, -2, name.as_ptr());
    }
    cache_class(l);
    (api.setfield)(l, -2, c"Cache".as_ptr());
    (api.setfield)(l, -2, c"base".as_ptr());
    crate::module::push(l, &[(c"New", lru_new)], None);
    lru_class(l);
    (api.setfield)(l, -2, c"Lru".as_ptr());
    (api.setfield)(l, -2, c"lru".as_ptr());
    crate::module::push(l, &[(c"New", expiring_new)], None);
    expiring_class(l);
    (api.setfield)(l, -2, c"Expiring".as_ptr());
    clock_port(l);
    (api.setfield)(l, -2, c"CLOCK".as_ptr());
    (api.setfield)(l, -2, c"expiring".as_ptr());
    crate::module::push(l, &[(c"New", memo_new)], None);
    memo_class(l);
    (api.setfield)(l, -2, c"Memo".as_ptr());
    (api.setfield)(l, -2, c"memo".as_ptr());
}

pub const NAMES: &[&CStr] = &[c"base", c"lru", c"expiring", c"memo"];
