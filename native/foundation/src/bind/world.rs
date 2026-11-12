//! world.pairmap, world.lease, world.grid and world.sets, native: the Lua
//! twins' contracts (foundation/world/). What the caller hands in (values,
//! keys, holders, items, members) stays as given, in the userdata's
//! environment: by slot, or in tables keyed by the caller's own values.

use super::slots::{fresh_environment, ValueSlots};
use super::util::{absent, boolean, each_item, env_field, env_table, nothing, number, number_at};
use crate::lua::{raise_at, raise_where, string_at, tostring, CFunction, GLOBALSINDEX, L, TNIL, TTABLE};
use crate::module;
use crate::userdata::{self, Native};
use std::collections::{HashMap, HashSet};
use std::ffi::{c_int, CStr};

// world.pairmap ---------------------------------------------------------------

const SPAN: f64 = 67_108_864.0; // 2^26
const MAX_KEY: f64 = SPAN - 1.0;

#[derive(Default)]
pub struct PairMap {
    keys: HashMap<u64, u32>,
    values: ValueSlots,
    unordered: bool,
}

impl Native for PairMap {
    const NAME: &'static CStr = c"foundation.world.pairmap";
    const METHODS: &'static [(&'static CStr, CFunction)] =
        &[(c"Get", pairmap_get), (c"Set", pairmap_set), (c"Size", pairmap_size), (c"Clear", pairmap_clear)];
}

/// The pair's one key, as the Lua twin's table holds it (-0 and 0 alike); an unordered map puts the
/// pair in order first.
fn pair_key(unordered: bool, a: f64, b: f64) -> u64 {
    let (a, b) = if unordered && a > b { (b, a) } else { (a, b) };
    (a * SPAN + b + 0.0).to_bits()
}

unsafe extern "C-unwind" fn pairmap_new(l: L) -> c_int {
    userdata::push(l, PairMap::default());
    fresh_environment(l, -1);
    1
}

unsafe extern "C-unwind" fn pairmap_unordered(l: L) -> c_int {
    userdata::push(l, PairMap { unordered: true, ..PairMap::default() });
    fresh_environment(l, -1);
    1
}

unsafe extern "C-unwind" fn pairmap_get(l: L) -> c_int {
    let (a, b) = (l.checknumber(2), l.checknumber(3));
    let map = userdata::check::<PairMap>(l, 1);
    match map.keys.get(&pair_key(map.unordered, a, b)) {
        Some(&slot) => {
            ValueSlots::push(l, slot);
            1
        }
        None => nothing(l),
    }
}

unsafe fn pair_part(l: L, index: c_int) -> f64 {
    match number_at(l, index).filter(|k| (0.0..=MAX_KEY).contains(k) && k.fract() == 0.0) {
        Some(key) => key,
        None => {
            let given = tostring(l, index);
            raise_where(l, format!("a pair map's key is a whole number from 0 to {}, not {given}", MAX_KEY as u64));
        }
    }
}

unsafe extern "C-unwind" fn pairmap_set(l: L) -> c_int {
    l.settop(4);
    let (a, b) = (pair_part(l, 2), pair_part(l, 3));
    let map = userdata::check::<PairMap>(l, 1);
    let key = pair_key(map.unordered, a, b);
    if let Some(old) = map.keys.remove(&key) {
        map.values.release(l, old);
    }
    if !absent(l, 4) {
        let slot = map.values.store(l, 4);
        map.keys.insert(key, slot);
    }
    0
}

unsafe extern "C-unwind" fn pairmap_size(l: L) -> c_int {
    number(l, userdata::check::<PairMap>(l, 1).keys.len() as f64)
}

unsafe extern "C-unwind" fn pairmap_clear(l: L) -> c_int {
    let map = userdata::check::<PairMap>(l, 1);
    map.keys.clear();
    map.values.clear(l);
    0
}

// world.bucket -----------------------------------------------------------------

pub struct Bucket {
    capacity: f64,
    seconds: f64,
    tokens: f64,
    at: f64,
}

impl Native for Bucket {
    const NAME: &'static CStr = c"foundation.world.bucket";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[(c"Take", bucket_take), (c"Tokens", bucket_tokens)];
}

impl Bucket {
    /// Brings the tokens up to now, never past the capacity.
    fn refill(&mut self, now: f64) -> f64 {
        let tokens = self.tokens + (now - self.at) * self.capacity / self.seconds;
        self.tokens = if tokens > self.capacity { self.capacity } else { tokens };
        self.at = now;
        self.tokens
    }
}

unsafe extern "C-unwind" fn bucket_new(l: L) -> c_int {
    let (capacity, seconds, now) = (number_at(l, 1), number_at(l, 2), number_at(l, 3));
    match capacity {
        Some(c) if c >= 1.0 => {}
        _ => {
            let given = tostring(l, 1);
            raise_where(l, format!("a bucket's capacity is a number of at least 1, not {given}"));
        }
    }
    match seconds {
        Some(s) if s > 0.0 => {}
        _ => {
            let given = tostring(l, 2);
            raise_where(l, format!("a bucket's seconds are a number above 0, not {given}"));
        }
    }
    let Some(now) = now else {
        let given = tostring(l, 3);
        raise_where(l, format!("a bucket starts at a time, not {given}"));
    };
    let capacity = capacity.unwrap_or(1.0);
    userdata::push(l, Bucket { capacity, seconds: seconds.unwrap_or(1.0), tokens: capacity, at: now });
    1
}

unsafe extern "C-unwind" fn bucket_take(l: L) -> c_int {
    let now = l.checknumber(2);
    let bucket = userdata::check::<Bucket>(l, 1);
    let tokens = bucket.refill(now);
    if tokens < 1.0 {
        return boolean(l, false);
    }
    bucket.tokens = tokens - 1.0;
    boolean(l, true)
}

unsafe extern "C-unwind" fn bucket_tokens(l: L) -> c_int {
    let now = l.checknumber(2);
    number(l, userdata::check::<Bucket>(l, 1).refill(now))
}

// world.lease ------------------------------------------------------------------

/// Leases: env.holders (key -> holder) and env.expires (key -> time).
pub struct Leases;

impl Native for Leases {
    const NAME: &'static CStr = c"foundation.world.lease";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Holder", lease_holder),
        (c"FreeFor", lease_free_for),
        (c"Take", lease_take),
        (c"Release", lease_release),
        (c"ReleaseAll", lease_release_all),
    ];
}

unsafe extern "C-unwind" fn lease_new(l: L) -> c_int {
    userdata::push(l, Leases);
    fresh_environment(l, -1);
    let ud = l.gettop();
    env_table(l, ud, c"holders");
    env_table(l, ud, c"expires");
    1
}

/// Pushes the live holder of the key at 2 at time `now`, or nil.
unsafe fn push_holder(l: L, now: f64) {
    env_field(l, 1, c"holders");
    l.pushvalue(2);
    l.rawget(-2);
    if l.type_of(-1) != TNIL {
        env_field(l, 1, c"expires");
        l.pushvalue(2);
        l.rawget(-2);
        let expires = l.tonumber(-1);
        l.settop(-3);
        if now >= expires {
            l.settop(-2);
            l.pushnil();
        }
    }
    l.remove(-2);
}

unsafe extern "C-unwind" fn lease_holder(l: L) -> c_int {
    userdata::check::<Leases>(l, 1);
    let now = l.checknumber(3);
    l.settop(3);
    push_holder(l, now);
    1
}

/// Whether the key at 2 is free for the holder at 3 at time `now`.
unsafe fn free_for(l: L, now: f64) -> bool {
    push_holder(l, now);
    let free = l.type_of(-1) == TNIL || l.equal(-1, 3) != 0;
    l.settop(-2);
    free
}

unsafe extern "C-unwind" fn lease_free_for(l: L) -> c_int {
    userdata::check::<Leases>(l, 1);
    let now = l.checknumber(4);
    l.settop(4);
    boolean(l, free_for(l, now))
}

unsafe extern "C-unwind" fn lease_take(l: L) -> c_int {
    userdata::check::<Leases>(l, 1);
    let now = l.checknumber(4);
    let term = l.checknumber(5);
    l.settop(5);
    if !free_for(l, now) {
        return boolean(l, false);
    }
    env_field(l, 1, c"holders");
    l.pushvalue(2);
    l.pushvalue(3);
    l.rawset(-3);
    env_field(l, 1, c"expires");
    l.pushvalue(2);
    l.pushnumber(now + term);
    l.rawset(-3);
    l.settop(5);
    boolean(l, true)
}

/// Clears the lease of the key at `key` (absolute).
unsafe fn clear_lease(l: L, key: c_int) {
    for name in [c"holders", c"expires"] {
        env_field(l, 1, name);
        l.pushvalue(key);
        l.pushnil();
        l.rawset(-3);
        l.settop(-2);
    }
}

unsafe extern "C-unwind" fn lease_release(l: L) -> c_int {
    userdata::check::<Leases>(l, 1);
    l.settop(3);
    env_field(l, 1, c"holders");
    l.pushvalue(2);
    l.rawget(-2);
    let own = l.type_of(-1) != TNIL && l.equal(-1, 3) != 0;
    l.settop(3);
    if own {
        clear_lease(l, 2);
    }
    0
}

unsafe extern "C-unwind" fn lease_release_all(l: L) -> c_int {
    userdata::check::<Leases>(l, 1);
    l.settop(2);
    env_field(l, 1, c"holders");
    let holders = l.gettop();
    l.createtable(0, 0);
    let own = l.gettop();
    let mut n = 0;
    l.pushnil();
    while l.next(holders) != 0 {
        if l.equal(-1, 2) != 0 {
            n += 1;
            l.pushvalue(-2);
            l.rawseti(own, n);
        }
        l.settop(-2);
    }
    each_item(l, own, |l, key| clear_lease(l, key));
    0
}

// world.grid --------------------------------------------------------------------

const OFFSET: f64 = 1_048_576.0; // 2^20
const GRID_SPAN: f64 = 2_097_152.0; // 2^21

pub struct Grid {
    size: f64,
}

impl Native for Grid {
    const NAME: &'static CStr = c"foundation.world.grid";
    const METHODS: &'static [(&'static CStr, CFunction)] =
        &[(c"Put", grid_put), (c"PutBox", grid_put_box), (c"Near", grid_near), (c"Buckets", grid_buckets)];
}

fn cell_key(cx: f64, cy: f64) -> f64 {
    (cx + OFFSET) * GRID_SPAN + (cy + OFFSET)
}

unsafe fn cell_size(l: L, index: c_int) -> f64 {
    match number_at(l, index).filter(|&s| s > 0.0) {
        Some(size) => size,
        None => {
            let given = tostring(l, index);
            raise_where(l, format!("a grid's cell size is a positive number, not {given}"));
        }
    }
}

unsafe extern "C-unwind" fn grid_new(l: L) -> c_int {
    let size = cell_size(l, 1);
    userdata::push(l, Grid { size });
    fresh_environment(l, -1);
    let ud = l.gettop();
    env_table(l, ud, c"cells");
    1
}

/// The x and y of the point table at `index`.
unsafe fn xy(l: L, index: c_int) -> (f64, f64) {
    if !super::util::indexable(l, index) {
        raise_where(l, "a position is a { x, y } table or a Vector".into());
    }
    let x = crate::lua::field_number(l, index, c"x").unwrap_or(f64::NAN);
    let y = crate::lua::field_number(l, index, c"y").unwrap_or(f64::NAN);
    (x, y)
}

/// Appends the value at `item` to the cell `key` of the cells at `cells`.
unsafe fn add(l: L, cells: c_int, key: f64, item: c_int) {
    l.pushnumber(key);
    l.rawget(cells);
    if l.type_of(-1) != TTABLE {
        l.settop(-2);
        l.createtable(1, 0);
        l.pushnumber(key);
        l.pushvalue(-2);
        l.rawset(cells);
    }
    let n = l.objlen(-1) as c_int;
    l.pushvalue(item);
    l.rawseti(-2, n + 1);
    l.settop(-2);
}

unsafe extern "C-unwind" fn grid_put(l: L) -> c_int {
    l.settop(3);
    let size = userdata::check::<Grid>(l, 1).size;
    let (x, y) = xy(l, 2);
    env_field(l, 1, c"cells");
    add(l, 4, cell_key((x / size).floor(), (y / size).floor()), 3);
    0
}

unsafe extern "C-unwind" fn grid_put_box(l: L) -> c_int {
    l.settop(4);
    let size = userdata::check::<Grid>(l, 1).size;
    let (lx, ly) = xy(l, 2);
    let (hx, hy) = xy(l, 3);
    env_field(l, 1, c"cells");
    let (x0, x1, y0, y1) = ((lx / size).floor(), (hx / size).floor(), (ly / size).floor(), (hy / size).floor());
    let mut cx = x0;
    while cx <= x1 {
        let mut cy = y0;
        while cy <= y1 {
            add(l, 5, cell_key(cx, cy), 4);
            cy += 1.0;
        }
        cx += 1.0;
    }
    0
}

unsafe extern "C-unwind" fn grid_near(l: L) -> c_int {
    l.settop(3);
    let size = userdata::check::<Grid>(l, 1).size;
    let (x, y) = xy(l, 2);
    env_field(l, 1, c"cells");
    let cells = l.gettop();
    let (cx, cy) = ((x / size).floor(), (y / size).floor());
    for dx in [-1.0, 0.0, 1.0] {
        for dy in [-1.0, 0.0, 1.0] {
            l.pushnumber(cell_key(cx + dx, cy + dy));
            l.rawget(cells);
            if l.type_of(-1) == TTABLE {
                let list = l.gettop();
                let mut hit = false;
                each_item(l, list, |l, item| {
                    if !hit {
                        l.pushvalue(3);
                        l.pushvalue(item);
                        l.call(1, 1);
                        hit = l.toboolean(-1) != 0;
                    }
                });
                if hit {
                    return boolean(l, true);
                }
            }
            l.settop(cells);
        }
    }
    boolean(l, false)
}

unsafe extern "C-unwind" fn grid_buckets(l: L) -> c_int {
    userdata::check::<Grid>(l, 1);
    l.getfield(GLOBALSINDEX, c"next");
    env_field(l, 1, c"cells");
    l.pushnil();
    3
}

/// world.grid.Thin(points, size) -> the first of points in each cube
unsafe extern "C-unwind" fn grid_thin(l: L) -> c_int {
    let size = cell_size(l, 2);
    l.checktype(1, TTABLE);
    l.createtable(0, 0);
    let kept = l.gettop();
    let mut taken = HashSet::new();
    let mut n = 0;
    each_item(l, 1, |l, p| {
        let x = crate::lua::field_number(l, p, c"x").unwrap_or(f64::NAN);
        let y = crate::lua::field_number(l, p, c"y").unwrap_or(f64::NAN);
        let z = crate::lua::field_number(l, p, c"z").unwrap_or(0.0);
        let cube = ((x / size).floor() as i64, (y / size).floor() as i64, (z / size).floor() as i64);
        if taken.insert(cube) {
            n += 1;
            l.pushvalue(p);
            l.rawseti(kept, n);
        }
    });
    drop(taken);
    l.settop(kept);
    1
}

/// world.grid.Spread(items, spacing[, limit[, position]]) -> the items, in order, that are not within
/// spacing of one kept before them
unsafe extern "C-unwind" fn grid_spread(l: L) -> c_int {
    scan(l, false)
}

/// world.grid.Isolated(items, spacing[, limit[, position]]) -> the items, in order, with no item
/// before them in the list within spacing, kept or not (TF2's SelectSeparatedShuffleSet)
unsafe extern "C-unwind" fn grid_isolated(l: L) -> c_int {
    scan(l, true)
}

/// The scan both share; `everyone`: every item seen is remembered for the next, not only those kept.
unsafe fn scan(l: L, everyone: bool) -> c_int {
    let spacing = cell_size(l, 2);
    l.checktype(1, TTABLE);
    let limit = if absent(l, 3) {
        None
    } else {
        match number_at(l, 3).filter(|n| *n >= 0.0 && (n.fract() == 0.0 || n.is_infinite())) {
            Some(n) => Some(n as usize),
            None => {
                let given = tostring(l, 3);
                raise_where(l, format!("a spread's limit is a whole number of at least 0, not {given}"));
            }
        }
    };
    let position = if absent(l, 4) {
        None
    } else {
        l.checktype(4, crate::lua::TFUNCTION);
        Some(4)
    };
    let mut cells: HashMap<(i64, i64), Vec<[f64; 3]>> = HashMap::new();
    let mut places: Vec<c_int> = Vec::new();
    let mut place: c_int = 0;
    let mut done = limit == Some(0);
    each_item(l, 1, |l, item| {
        place += 1;
        if done {
            return;
        }
        let at = match position {
            None => super::math::point_at(l, item),
            Some(f) => {
                l.pushvalue(f);
                l.pushvalue(item);
                l.call(1, 1);
                let at = super::math::point_at(l, l.gettop());
                l.settop(item);
                at
            }
        };
        let cell = ((at[0] / spacing).floor() as i64, (at[1] / spacing).floor() as i64);
        let crowded = (-1..=1).any(|dx| {
            (-1..=1).any(|dy| {
                cells.get(&(cell.0 + dx, cell.1 + dy)).is_some_and(|list| {
                    list.iter().any(|o| {
                        let (ox, oy, oz) = (at[0] - o[0], at[1] - o[1], at[2] - o[2]);
                        (ox * ox + oy * oy + oz * oz).sqrt() < spacing
                    })
                })
            })
        });
        if everyone || !crowded {
            cells.entry(cell).or_default().push(at);
        }
        if !crowded {
            places.push(place);
            if limit.is_some_and(|n| places.len() >= n) {
                done = true;
            }
        }
    });
    l.createtable(places.len() as c_int, 0);
    for (i, p) in places.iter().enumerate() {
        l.rawgeti(1, *p);
        l.rawseti(-2, i as c_int + 1);
    }
    1
}

// world.sets --------------------------------------------------------------------

/// A named set: env.name, env.list (the members in order), env.has.
pub struct NamedSet;

impl Native for NamedSet {
    const NAME: &'static CStr = c"foundation.world.sets.named";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Has", set_has),
        (c"Check", set_check),
        (c"Match", set_match),
        (c"Members", set_members),
        (c"Name", set_name),
    ];
}

/// world.sets.Named(name, members) -> a named set
unsafe extern "C-unwind" fn sets_named(l: L) -> c_int {
    l.settop(2);
    let name = string_at(l, 1).filter(|n| !n.is_empty()).map(|n| String::from_utf8_lossy(n).into_owned());
    let Some(name) = name else {
        let given = tostring(l, 1);
        raise_where(l, format!("named set {given}: needs a name"));
    };
    if l.type_of(2) != TTABLE || l.objlen(2) == 0 {
        raise_where(l, format!("named set {name}: {name}: lists no members"));
    }
    userdata::push(l, NamedSet);
    fresh_environment(l, -1);
    let ud = l.gettop();
    l.getfenv(ud);
    let env = l.gettop();
    l.pushvalue(1);
    l.setfield(env, c"name");
    l.createtable(0, 0);
    let list = l.gettop();
    l.createtable(0, 0);
    let has = l.gettop();
    let mut twice = None;
    let mut n = 0;
    each_item(l, 2, |l, member| {
        if twice.is_some() {
            return;
        }
        l.pushvalue(member);
        l.rawget(has);
        let seen = l.type_of(-1) != TNIL;
        l.settop(-2);
        if seen {
            twice = Some(tostring(l, member));
            return;
        }
        l.pushvalue(member);
        l.pushboolean(1);
        l.rawset(has);
        n += 1;
        l.pushvalue(member);
        l.rawseti(list, n);
    });
    if let Some(member) = twice {
        raise_where(l, format!("named set {name}: {name}: lists {member} twice"));
    }
    drop(name);
    l.pushvalue(has);
    l.setfield(env, c"has");
    l.pushvalue(list);
    l.setfield(env, c"list");
    l.settop(ud);
    1
}

/// Whether the value at 2 is a member of the set at 1.
unsafe fn member(l: L) -> bool {
    if l.type_of(2) <= TNIL {
        return false;
    }
    env_field(l, 1, c"has");
    l.pushvalue(2);
    l.rawget(-2);
    let has = l.toboolean(-1) != 0;
    l.settop(-3);
    has
}

unsafe extern "C-unwind" fn set_has(l: L) -> c_int {
    userdata::check::<NamedSet>(l, 1);
    l.settop(2);
    boolean(l, member(l))
}

unsafe extern "C-unwind" fn set_check(l: L) -> c_int {
    userdata::check::<NamedSet>(l, 1);
    l.settop(2);
    if !member(l) {
        env_field(l, 1, c"name");
        let name = tostring(l, -1);
        let given = tostring(l, 2);
        raise_at(l, 2, format!("{name}: unknown {given}"));
    }
    l.pushvalue(2);
    1
}

unsafe extern "C-unwind" fn set_match(l: L) -> c_int {
    userdata::check::<NamedSet>(l, 1);
    l.checktype(2, crate::lua::TSTRING);
    let wanted = string_at(l, 2).unwrap_or_default().to_ascii_uppercase();
    if wanted.is_empty() {
        return nothing(l);
    }
    env_field(l, 1, c"list");
    let list = l.gettop();
    let (mut found, mut i) = (None, 0);
    each_item(l, list, |l, m| {
        i += 1;
        if found.is_none() {
            let text = tostring(l, m);
            let head = text.as_bytes().get(..wanted.len().min(text.len())).unwrap_or_default().to_ascii_uppercase();
            if head == wanted {
                found = Some(i);
            }
        }
    });
    drop(wanted);
    match found {
        Some(i) => {
            l.rawgeti(list, i);
            1
        }
        None => nothing(l),
    }
}

unsafe extern "C-unwind" fn set_members(l: L) -> c_int {
    userdata::check::<NamedSet>(l, 1);
    env_field(l, 1, c"list");
    let list = l.gettop();
    l.createtable(0, 0);
    let copy = l.gettop();
    let mut n = 0;
    each_item(l, list, |l, m| {
        n += 1;
        l.pushvalue(m);
        l.rawseti(copy, n);
    });
    1
}

unsafe extern "C-unwind" fn set_name(l: L) -> c_int {
    userdata::check::<NamedSet>(l, 1);
    env_field(l, 1, c"name");
    1
}

/// Each key of the table at `t` (absolute), pushed for `visit` at the top.
unsafe fn each_key(l: L, t: c_int, mut visit: impl FnMut(L, c_int)) {
    l.pushnil();
    while l.next(t) != 0 {
        l.settop(-2);
        let key = l.gettop();
        visit(l, key);
        l.settop(key);
    }
}

/// set[value at `value`] = true, the set at `set`.
unsafe fn add_member(l: L, set: c_int, value: c_int) {
    l.pushvalue(value);
    l.pushboolean(1);
    l.rawset(set);
}

unsafe fn new_set(l: L) -> c_int {
    l.createtable(0, 0);
    l.gettop()
}

unsafe extern "C-unwind" fn sets_of(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let set = new_set(l);
    each_item(l, 1, |l, v| add_member(l, set, v));
    1
}

unsafe extern "C-unwind" fn sets_copy(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let set = new_set(l);
    each_key(l, 1, |l, k| add_member(l, set, k));
    1
}

unsafe extern "C-unwind" fn sets_union(l: L) -> c_int {
    let n = l.gettop();
    let set = new_set(l);
    for i in 1..=n {
        l.checktype(i, TTABLE);
        each_key(l, i, |l, k| add_member(l, set, k));
    }
    1
}

/// Whether b[value at `key`] is truthy, b at `b`.
unsafe fn holds(l: L, b: c_int, key: c_int) -> bool {
    l.pushvalue(key);
    l.gettable(b);
    let truthy = l.toboolean(-1) != 0;
    l.settop(-2);
    truthy
}

unsafe extern "C-unwind" fn sets_intersect(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.settop(2);
    let set = new_set(l);
    each_key(l, 1, |l, k| {
        if holds(l, 2, k) {
            add_member(l, set, k);
        }
    });
    1
}

unsafe extern "C-unwind" fn sets_subtract(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.settop(2);
    let set = new_set(l);
    each_key(l, 1, |l, k| {
        if !holds(l, 2, k) {
            add_member(l, set, k);
        }
    });
    1
}

unsafe extern "C-unwind" fn sets_count(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let mut n = 0;
    each_key(l, 1, |_, _| n += 1);
    number(l, n as f64)
}

unsafe extern "C-unwind" fn sets_sorted(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let list = new_set(l);
    let mut n = 0;
    each_key(l, 1, |l, k| {
        n += 1;
        l.pushvalue(k);
        l.rawseti(list, n);
    });
    l.getfield(GLOBALSINDEX, c"table");
    l.getfield(-1, c"sort");
    l.pushvalue(list);
    l.call(1, 0);
    l.settop(list);
    1
}

/// Pushes the pairmap module table.
unsafe fn push_pairmap_module(l: L) {
    module::push(l, &[(c"New", pairmap_new), (c"Unordered", pairmap_unordered)], None);
    l.pushnumber(MAX_KEY);
    l.setfield(-2, c"MAX_KEY");
}

/// Pushes the lease module table.
unsafe fn push_lease_module(l: L) {
    module::push(l, &[(c"New", lease_new)], None);
}

/// Pushes the grid module table.
unsafe fn push_grid_module(l: L) {
    module::push(l, &[(c"New", grid_new), (c"Thin", grid_thin), (c"Spread", grid_spread), (c"Isolated", grid_isolated)], None);
}

/// Pushes the sets module table.
unsafe fn push_sets_module(l: L) {
    module::push(
        l,
        &[
            (c"Named", sets_named),
            (c"Of", sets_of),
            (c"Copy", sets_copy),
            (c"Union", sets_union),
            (c"Intersect", sets_intersect),
            (c"Subtract", sets_subtract),
            (c"Count", sets_count),
            (c"Sorted", sets_sorted),
        ],
        None,
    );
}

/// Pushes the bucket module table.
unsafe fn push_bucket_module(l: L) {
    module::push(l, &[(c"New", bucket_new)], None);
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[
    (c"pairmap", push_pairmap_module),
    (c"lease", push_lease_module),
    (c"grid", push_grid_module),
    (c"sets", push_sets_module),
    (c"bucket", push_bucket_module),
];
