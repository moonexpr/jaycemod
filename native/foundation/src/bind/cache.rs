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
use crate::lua::{push_str, raise_at, raise_where, set_function, tostring, CFunction, GLOBALSINDEX, L, TFUNCTION, TNIL, TNUMBER, TTABLE};
use std::ffi::{c_int, CStr};

const REGISTRY: c_int = -10000;
const STATE: &CStr = c"foundation.cache.state";

fn upvalue(i: c_int) -> c_int {
    GLOBALSINDEX - i
}

/// Pushes the weak-keyed table of every cache's state.
unsafe fn states(l: L) {
    l.getfield(REGISTRY, STATE);
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    l.createtable(0, 0);
    l.createtable(0, 1);
    push_str(l, "k");
    l.setfield(-2, c"__mode");
    l.setmetatable(-2);
    l.pushvalue(-1);
    l.setfield(REGISTRY, STATE);
}

/// Pushes the state of the cache at `cache`; its index.
unsafe fn own(l: L, cache: c_int) -> c_int {
    states(l);
    l.pushvalue(cache);
    l.rawget(-2);
    l.remove(-2);
    l.gettop()
}

/// Calls obj:name(args...) for the values at `args` (absolute), leaving
/// `results` results.
unsafe fn method(l: L, obj: c_int, name: &CStr, args: &[c_int], results: c_int) {
    l.getfield(obj, name);
    l.pushvalue(obj);
    for &a in args {
        l.pushvalue(a);
    }
    l.call(args.len() as c_int + 1, results);
}

/// Calls the hook cache:name(slot), one result left when `results` is 1.
unsafe fn hook(l: L, cache: c_int, name: &CStr, slot: f64, results: c_int) {
    l.pushnumber(slot);
    let s = l.gettop();
    method(l, cache, name, &[s], results);
    l.remove(s);
}

/// t[k] where t is field `table` of the state at `own`, for the value at
/// `key`; pushed.
unsafe fn own_get(l: L, own: c_int, table: &CStr, key: c_int) {
    let key = if key < 0 { l.gettop() + key + 1 } else { key };
    l.getfield(own, table);
    l.pushvalue(key);
    l.rawget(-2);
    l.remove(-2);
}

/// field `table` of the state at `own`, [value at key] = value at value.
unsafe fn own_set(l: L, own: c_int, table: &CStr, key: c_int, value: c_int) {
    let top = l.gettop();
    let key = if key < 0 { top + key + 1 } else { key };
    let value = if value < 0 { top + value + 1 } else { value };
    l.getfield(own, table);
    l.pushvalue(key);
    l.pushvalue(value);
    l.rawset(-3);
    l.settop(-2);
}

/// The entry at `slot` out of every structure, its slot freed; then, with a
/// reason, its value released. Leaves the value pushed.
unsafe fn drop_slot(l: L, cache: c_int, own: c_int, slot: f64, reason: Option<&str>) {
    l.pushnumber(slot);
    let s = l.gettop();
    own_get(l, own, c"keys", s);
    let key = l.gettop();
    own_get(l, own, c"values", s);
    let value = l.gettop();
    l.getfield(own, c"order");
    let order = l.gettop();
    method(l, order, c"Unlink", &[s], 0);
    l.settop(value);
    l.pushnil();
    let nil = l.gettop();
    own_set(l, own, c"slotOf", key, nil);
    own_set(l, own, c"keys", s, nil);
    own_set(l, own, c"values", s, nil);
    l.settop(value);
    hook(l, cache, c"Dropped", slot, 0);
    l.getfield(own, c"slots");
    let slots = l.gettop();
    method(l, slots, c"Free", &[s], 0);
    l.settop(value);
    if let Some(reason) = reason {
        l.getfield(own, c"release");
        l.pushvalue(key);
        l.pushvalue(value);
        push_str(l, reason);
        l.call(3, 0);
    }
    l.insert(s);
    l.settop(s);
}

/// The key at `key`'s live slot, a stale one dropped on the way; or None.
unsafe fn live(l: L, cache: c_int, own: c_int, key: c_int) -> Option<f64> {
    own_get(l, own, c"slotOf", key);
    let slot = (l.type_of(-1) == TNUMBER).then(|| l.tonumber(-1));
    l.settop(-2);
    let slot = slot?;
    hook(l, cache, c"Stale", slot, 1);
    let stale = l.toboolean(-1) != 0;
    l.settop(-2);
    if stale {
        drop_slot(l, cache, own, slot, Some("expired"));
        l.settop(-2);
        return None;
    }
    Some(slot)
}

/// Reads the key at `key` (counting a use); pushes the value or nil.
unsafe fn read(l: L, cache: c_int, key: c_int) {
    let own = own(l, cache);
    match live(l, cache, own, key) {
        None => l.pushnil(),
        Some(slot) => {
            hook(l, cache, c"Touch", slot, 0);
            l.pushnumber(slot);
            own_get(l, own, c"values", -1);
            l.remove(-2);
        }
    }
    l.remove(own);
}

/// Writes the value at `value` under the key at `key` (nil removes).
unsafe fn write(l: L, cache: c_int, key: c_int, value: c_int) {
    if l.type_of(key) == TNIL {
        raise_where(l, "a cache keeps no nil key".into());
    }
    let own = own(l, cache);
    let slot = live(l, cache, own, key);
    if l.type_of(value) == TNIL {
        if let Some(slot) = slot {
            drop_slot(l, cache, own, slot, Some("removed"));
        }
        l.settop(own - 1);
        return;
    }
    if let Some(slot) = slot {
        l.pushnumber(slot);
        let s = l.gettop();
        own_get(l, own, c"values", s);
        let old = l.gettop();
        own_set(l, own, c"values", s, value);
        hook(l, cache, c"Rewrite", slot, 0);
        if l.equal(old, value) == 0 {
            l.getfield(own, c"release");
            l.pushvalue(key);
            l.pushvalue(old);
            push_str(l, "replaced");
            l.call(3, 0);
        }
        l.settop(own - 1);
        return;
    }
    method(l, cache, c"Admitting", &[], 0);
    l.getfield(own, c"slots");
    let slots = l.gettop();
    method(l, slots, c"Alloc", &[], 1);
    let s = l.gettop();
    let slot = l.tonumber(s);
    own_set(l, own, c"slotOf", key, s);
    own_set(l, own, c"keys", s, key);
    own_set(l, own, c"values", s, value);
    l.getfield(own, c"order");
    let order = l.gettop();
    method(l, order, c"PushFront", &[s], 0);
    hook(l, cache, c"Admitted", slot, 0);
    l.getfield(own, c"capacity");
    let capacity = (l.type_of(-1) == TNUMBER).then(|| l.tonumber(-1));
    l.settop(-2);
    if let Some(capacity) = capacity {
        loop {
            method(l, order, c"Size", &[], 1);
            let size = l.tonumber(-1);
            l.settop(-2);
            if size <= capacity {
                break;
            }
            method(l, order, c"Back", &[], 1);
            let back = l.tonumber(-1);
            l.settop(-2);
            drop_slot(l, cache, own, back, Some("evicted"));
            l.settop(-2);
        }
    }
    l.settop(own - 1);
}

/// cache[key]: a method along the cache's classes, else the value.
unsafe extern "C-unwind" fn index(l: L) -> c_int {
    l.settop(2);
    if l.getmetatable(1) == 0 {
        l.pushnil();
    }
    while l.type_of(-1) == TTABLE {
        l.pushvalue(2);
        l.rawget(-2);
        if l.type_of(-1) != TNIL {
            return 1;
        }
        l.settop(-2);
        if l.getmetatable(-1) == 0 {
            l.pushnil();
        }
        l.remove(-2);
    }
    l.settop(2);
    read(l, 1, 2);
    1
}

unsafe extern "C-unwind" fn newindex(l: L) -> c_int {
    l.settop(3);
    write(l, 1, 2, 3);
    0
}

/// The walk cache() gives: upvalue 1 the cache's state, 2 the next slot.
unsafe extern "C-unwind" fn entry_step(l: L) -> c_int {
    if l.type_of(upvalue(2)) != TNUMBER {
        l.pushnil();
        return 1;
    }
    let own = upvalue(1);
    l.pushvalue(upvalue(2));
    let slot = l.gettop();
    own_get(l, own, c"keys", slot);
    own_get(l, own, c"values", slot);
    l.getfield(own, c"order");
    let order = l.gettop();
    method(l, order, c"After", &[slot], 1);
    l.replace(upvalue(2));
    l.settop(order - 1);
    2
}

/// cache(): an iterator over the entries, newest first.
unsafe extern "C-unwind" fn entries(l: L) -> c_int {
    let own = own(l, 1);
    l.getfield(own, c"order");
    let order = l.gettop();
    method(l, order, c"Front", &[], 1);
    let front = l.gettop();
    l.pushvalue(own);
    l.pushvalue(front);
    l.pushcclosure(entry_step, 2);
    1
}

unsafe fn size_of(l: L, cache: c_int) -> f64 {
    let own = own(l, cache);
    l.getfield(own, c"order");
    let order = l.gettop();
    method(l, order, c"Size", &[], 1);
    let size = l.tonumber(-1);
    l.settop(own - 1);
    size
}

unsafe extern "C-unwind" fn length(l: L) -> c_int {
    number(l, size_of(l, 1))
}

unsafe extern "C-unwind" fn to_string(l: L) -> c_int {
    l.getfield(1, c"kind");
    let kind = tostring(l, -1);
    let size = size_of(l, 1);
    let own = own(l, 1);
    l.getfield(own, c"capacity");
    let mut text = format!("{kind}: {}", size as i64);
    if l.type_of(-1) == TNUMBER {
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
    l.settop(2);
    l.getfield(2, c"capacity");
    let capacity = l.gettop();
    l.getfield(2, c"release");
    let release = l.gettop();
    if l.type_of(capacity) != TNIL {
        let ok = l.type_of(capacity) == TNUMBER && {
            let c = l.tonumber(capacity);
            c >= 1.0 && c.floor() == c
        };
        if !ok {
            refuse(l, "capacity is a whole number of at least 1", capacity);
        }
    }
    if l.type_of(release) != TNIL && l.type_of(release) != TFUNCTION {
        refuse(l, "release is a function", release);
    }
    states(l);
    l.pushvalue(1);
    l.createtable(0, 7);
    let own = l.gettop();
    l.pushvalue(capacity);
    l.setfield(own, c"capacity");
    if l.type_of(release) == TNIL {
        l.pushcclosure(owned, 0);
    } else {
        l.pushvalue(release);
    }
    l.setfield(own, c"release");
    for (field, namespace, module) in [(c"slots", c"list", c"slots"), (c"order", c"list", c"chain")] {
        l.getfield(GLOBALSINDEX, namespace);
        l.getfield(-1, module);
        l.getfield(-1, c"New");
        l.call(0, 1);
        l.setfield(own, field);
        l.settop(own);
    }
    for field in [c"slotOf", c"keys", c"values"] {
        l.createtable(0, 0);
        l.setfield(own, field);
    }
    l.rawset(-3);
    0
}

unsafe extern "C-unwind" fn no_op(_l: L) -> c_int {
    0
}

unsafe extern "C-unwind" fn never_stale(l: L) -> c_int {
    boolean(l, false)
}

unsafe extern "C-unwind" fn drop_slot_method(l: L) -> c_int {
    l.settop(3);
    let slot = l.checknumber(2);
    let reason = crate::lua::string_at(l, 3).map(|r| String::from_utf8_lossy(r).into_owned());
    let own = own(l, 1);
    drop_slot(l, 1, own, slot, reason.as_deref());
    drop(reason);
    1
}

unsafe extern "C-unwind" fn get(l: L) -> c_int {
    l.settop(2);
    read(l, 1, 2);
    1
}

unsafe extern "C-unwind" fn put(l: L) -> c_int {
    l.settop(3);
    if l.type_of(3) == TNIL {
        raise_where(l, "a cache keeps no nil value: Remove removes".into());
    }
    write(l, 1, 2, 3);
    0
}

unsafe extern "C-unwind" fn remove(l: L) -> c_int {
    l.settop(2);
    l.pushnil();
    write(l, 1, 2, 3);
    0
}

unsafe extern "C-unwind" fn peek(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    match live(l, 1, own, 2) {
        Some(slot) => {
            l.pushnumber(slot);
            own_get(l, own, c"values", -1);
        }
        None => l.pushnil(),
    }
    1
}

unsafe extern "C-unwind" fn take(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    match live(l, 1, own, 2) {
        Some(slot) => drop_slot(l, 1, own, slot, None),
        None => l.pushnil(),
    }
    1
}

/// Every entry dropped first, then each value released, front to back, so
/// a release that puts finds the cache already empty.
unsafe fn empty(l: L, reason: &str) {
    let own = own(l, 1);
    l.createtable(0, 0);
    let keys = l.gettop();
    l.createtable(0, 0);
    let values = l.gettop();
    entries(l);
    let step = l.gettop();
    let mut n = 0;
    loop {
        l.pushvalue(step);
        l.call(0, 2);
        if l.type_of(-2) == TNIL {
            l.settop(step);
            break;
        }
        n += 1;
        l.rawseti(values, n);
        l.rawseti(keys, n);
    }
    for i in 1..=n {
        l.rawgeti(keys, i);
        own_get(l, own, c"slotOf", -1);
        let slot = l.tonumber(-1);
        l.settop(step);
        drop_slot(l, 1, own, slot, None);
        l.settop(step);
    }
    for i in 1..=n {
        l.getfield(own, c"release");
        l.rawgeti(keys, i);
        l.rawgeti(values, i);
        push_str(l, reason);
        l.call(3, 0);
    }
    l.settop(own - 1);
}

unsafe extern "C-unwind" fn clear(l: L) -> c_int {
    l.settop(1);
    empty(l, "cleared");
    0
}

unsafe extern "C-unwind" fn keys(l: L) -> c_int {
    l.settop(1);
    l.createtable(0, 0);
    let list = l.gettop();
    // cache() through the class's own __call (an expiring cache prunes first)
    l.getmetatable(1);
    l.getfield(-1, c"__call");
    l.pushvalue(1);
    l.call(1, 1);
    let step = l.gettop();
    let mut n = 0;
    loop {
        l.pushvalue(step);
        l.call(0, 1);
        if l.type_of(-1) == TNIL {
            break;
        }
        n += 1;
        l.rawseti(list, n);
    }
    l.settop(list);
    1
}

unsafe extern "C-unwind" fn destroy_cache(l: L) -> c_int {
    l.settop(1);
    empty(l, "destroyed");
    states(l);
    l.pushvalue(1);
    l.pushnil();
    l.rawset(-3);
    0
}

/// cache.base.State(cache) -> its state table
unsafe extern "C-unwind" fn state(l: L) -> c_int {
    own(l, 1);
    1
}

/// Pushes the Cache class.
unsafe fn cache_class(l: L) {
    l.getfield(REGISTRY, c"foundation.cache.Cache");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    l.createtable(0, 24);
    push_str(l, "cache");
    l.setfield(-2, c"kind");
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
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.cache.Cache");
}

/// Pushes Class.Extend(parent at `parent`, fields at the top (popped)).
unsafe fn subclass(l: L, parent: c_int) {
    let fields = l.gettop();
    l.pushcclosure(extend, 0);
    l.pushvalue(parent);
    l.pushvalue(fields);
    l.call(2, 1);
    l.remove(fields);
}

/// A New for a class kept in the registry under `key`: constructs through
/// core.class.Construct.
unsafe fn new_of(l: L, key: &CStr) -> c_int {
    l.settop(1);
    l.getfield(REGISTRY, key);
    l.insert(1);
    construct_through(l, 1, 2)
}

unsafe extern "C-unwind" fn base_new(l: L) -> c_int {
    cache_class(l);
    l.settop(-2);
    new_of(l, c"foundation.cache.Cache")
}

// cache.lru ---------------------------------------------------------------------

/// Touch and Rewrite: the entry to the front.
unsafe extern "C-unwind" fn recent(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    l.getfield(own, c"order");
    let order = l.gettop();
    method(l, order, c"MoveFront", &[2], 0);
    0
}

unsafe extern "C-unwind" fn lru_init(l: L) -> c_int {
    l.getfield(2, c"capacity");
    if l.type_of(-1) == TNIL {
        raise_at(l, 3, "an LRU cache needs a capacity".into());
    }
    0
}

unsafe fn lru_class(l: L) {
    l.getfield(REGISTRY, c"foundation.cache.Lru");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    cache_class(l);
    let parent = l.gettop();
    l.createtable(0, 4);
    push_str(l, "lru cache");
    l.setfield(-2, c"kind");
    set_function(l, c"Init", lru_init);
    set_function(l, c"Touch", recent);
    set_function(l, c"Rewrite", recent);
    subclass(l, parent);
    l.remove(parent);
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.cache.Lru");
}

unsafe extern "C-unwind" fn lru_new(l: L) -> c_int {
    lru_class(l);
    l.settop(-2);
    new_of(l, c"foundation.cache.Lru")
}

// cache.expiring ------------------------------------------------------------------

/// clock:Now() of the state at `own`.
unsafe fn clock_now(l: L, own: c_int) -> f64 {
    l.getfield(own, c"clock");
    let clock = l.gettop();
    method(l, clock, c"Now", &[], 1);
    let now = l.tonumber(-1);
    l.settop(clock - 1);
    now
}

unsafe fn expired(l: L, own: c_int, slot: c_int) -> bool {
    let now = clock_now(l, own);
    own_get(l, own, c"written", slot);
    let written = l.tonumber(-1);
    l.settop(-2);
    l.getfield(own, c"term");
    let term = l.tonumber(-1);
    l.settop(-2);
    now - written > term
}

unsafe extern "C-unwind" fn expiring_stale(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    boolean(l, expired(l, own, 2))
}

unsafe extern "C-unwind" fn stamp(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    let now = clock_now(l, own);
    l.pushnumber(now);
    own_set(l, own, c"written", 2, -1);
    0
}

unsafe extern "C-unwind" fn expiring_rewrite(l: L) -> c_int {
    stamp(l);
    recent(l)
}

unsafe extern "C-unwind" fn expiring_dropped(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    l.pushnil();
    own_set(l, own, c"written", 2, -1);
    0
}

unsafe extern "C-unwind" fn prune(l: L) -> c_int {
    l.settop(1);
    let own = own(l, 1);
    l.getfield(own, c"order");
    let order = l.gettop();
    loop {
        method(l, order, c"Back", &[], 1);
        let back = l.gettop();
        if l.type_of(back) != TNUMBER || !expired(l, own, back) {
            break;
        }
        push_str(l, "expired");
        let reason = l.gettop();
        method(l, 1, c"DropSlot", &[back, reason], 0);
        l.settop(order);
    }
    0
}

unsafe extern "C-unwind" fn expiring_call(l: L) -> c_int {
    l.settop(1);
    prune(l);
    l.settop(1);
    entries(l)
}

unsafe extern "C-unwind" fn expiring_init(l: L) -> c_int {
    l.settop(2);
    l.getfield(2, c"term");
    let term = l.gettop();
    let ok = l.type_of(term) == TNUMBER && l.tonumber(term) > 0.0;
    if !ok {
        let given = tostring(l, term);
        raise_at(l, 3, format!("an expiring cache's term is a number of seconds above 0, not {given}"));
    }
    let own = own(l, 1);
    l.getfield(REGISTRY, c"foundation.cache.CLOCK");
    let clock_port = l.gettop();
    l.getfield(2, c"clock");
    let given = l.gettop();
    l.pushcclosure(port_check, 0);
    l.pushvalue(clock_port);
    l.pushvalue(given);
    l.call(2, 1);
    l.setfield(own, c"clock");
    l.pushvalue(term);
    l.setfield(own, c"term");
    l.createtable(0, 0);
    l.setfield(own, c"written");
    0
}

/// Pushes the clock port, made the first time.
unsafe fn clock_port(l: L) {
    l.getfield(REGISTRY, c"foundation.cache.CLOCK");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    l.pushcclosure(port_new, 0);
    push_str(l, "clock");
    l.createtable(1, 0);
    push_str(l, "Now");
    l.rawseti(-2, 1);
    l.call(2, 1);
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.cache.CLOCK");
}

unsafe fn expiring_class(l: L) {
    l.getfield(REGISTRY, c"foundation.cache.Expiring");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    clock_port(l);
    l.settop(-2);
    cache_class(l);
    let parent = l.gettop();
    l.createtable(0, 10);
    push_str(l, "expiring cache");
    l.setfield(-2, c"kind");
    set_function(l, c"__call", expiring_call);
    set_function(l, c"Init", expiring_init);
    set_function(l, c"Admitting", prune);
    set_function(l, c"Admitted", stamp);
    set_function(l, c"Rewrite", expiring_rewrite);
    set_function(l, c"Stale", expiring_stale);
    set_function(l, c"Dropped", expiring_dropped);
    set_function(l, c"Prune", prune);
    subclass(l, parent);
    l.remove(parent);
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.cache.Expiring");
}

unsafe extern "C-unwind" fn expiring_new(l: L) -> c_int {
    expiring_class(l);
    l.settop(-2);
    new_of(l, c"foundation.cache.Expiring")
}

// cache.memo -----------------------------------------------------------------------

unsafe extern "C-unwind" fn unstamp(l: L) -> c_int {
    l.settop(2);
    let own = own(l, 1);
    l.pushnil();
    own_set(l, own, c"stamps", 2, -1);
    0
}

unsafe extern "C-unwind" fn memo_init(l: L) -> c_int {
    l.settop(1);
    let own = own(l, 1);
    l.createtable(0, 0);
    l.setfield(own, c"stamps");
    0
}

unsafe extern "C-unwind" fn fetch(l: L) -> c_int {
    l.settop(4);
    if l.type_of(3) == TNIL {
        raise_where(l, "a memo's stamp is anything but nil".into());
    }
    let own = own(l, 1);
    own_get(l, own, c"slotOf", 2);
    let slot = l.gettop();
    if l.type_of(slot) == TNUMBER {
        own_get(l, own, c"stamps", slot);
        let same = l.equal(-1, 3) != 0;
        l.settop(slot);
        if same {
            method(l, 1, c"Get", &[2], 1);
            return 1;
        }
    }
    l.settop(own);
    l.pushvalue(4);
    l.pushvalue(2);
    l.call(1, 1);
    let value = l.gettop();
    method(l, 1, c"Put", &[2, value], 0);
    own_get(l, own, c"slotOf", 2);
    let slot = l.gettop();
    own_set(l, own, c"stamps", slot, 3);
    l.pushvalue(value);
    1
}

unsafe fn memo_class(l: L) {
    l.getfield(REGISTRY, c"foundation.cache.Memo");
    if l.type_of(-1) == TTABLE {
        return;
    }
    l.settop(-2);
    cache_class(l);
    let parent = l.gettop();
    l.createtable(0, 5);
    push_str(l, "memo");
    l.setfield(-2, c"kind");
    set_function(l, c"Init", memo_init);
    set_function(l, c"Rewrite", unstamp);
    set_function(l, c"Dropped", unstamp);
    set_function(l, c"Fetch", fetch);
    subclass(l, parent);
    l.remove(parent);
    l.pushvalue(-1);
    l.setfield(REGISTRY, c"foundation.cache.Memo");
}

unsafe extern "C-unwind" fn memo_new(l: L) -> c_int {
    memo_class(l);
    l.settop(-2);
    new_of(l, c"foundation.cache.Memo")
}

/// Pushes the base module table.
unsafe fn push_base_module(l: L) {
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
        l.setfield(-2, name);
    }
    cache_class(l);
    l.setfield(-2, c"Cache");
}

/// Pushes the lru module table.
unsafe fn push_lru_module(l: L) {
    crate::module::push(l, &[(c"New", lru_new)], None);
    lru_class(l);
    l.setfield(-2, c"Lru");
}

/// Pushes the expiring module table.
unsafe fn push_expiring_module(l: L) {
    crate::module::push(l, &[(c"New", expiring_new)], None);
    expiring_class(l);
    l.setfield(-2, c"Expiring");
    clock_port(l);
    l.setfield(-2, c"CLOCK");
}

/// Pushes the memo module table.
unsafe fn push_memo_module(l: L) {
    crate::module::push(l, &[(c"New", memo_new)], None);
    memo_class(l);
    l.setfield(-2, c"Memo");
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[
    (c"base", push_base_module),
    (c"lru", push_lru_module),
    (c"expiring", push_expiring_module),
    (c"memo", push_memo_module),
];
