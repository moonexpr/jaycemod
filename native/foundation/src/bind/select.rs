//! list.select, native: the Lua twin's contract (foundation/list/select.lua).
//! The score, the keep test and the order are the caller's Lua functions,
//! called once an item (a pair for the order); Nearest, with no position
//! function, reads the items' points without calling Lua at all. The sorts
//! are written out, not the standard library's, so an error in the caller's
//! function leaves nothing half done in a sort.

use super::math::point_at;
use super::util::absent;
use crate::lua::{raise_where, tostring, CFunction, L, TFUNCTION, TNIL, TNUMBER, TTABLE};
use crate::module;
use std::ffi::{c_int, CStr};

/// How many items the list at `list` has, as ipairs counts: up to the first nil.
unsafe fn count_items(l: L, list: c_int) -> usize {
    let mut n = 0;
    loop {
        l.rawgeti(list, (n + 1) as c_int);
        let end = l.type_of(-1) == TNIL;
        l.settop(-2);
        if end {
            return n;
        }
        n += 1;
    }
}

/// Whether the function at `f` says list[a] goes strictly before list[b].
unsafe fn before(l: L, list: c_int, f: c_int, a: usize, b: usize) -> bool {
    l.pushvalue(f);
    l.rawgeti(list, a as c_int);
    l.rawgeti(list, b as c_int);
    l.call(2, 1);
    let answer = l.toboolean(-1) != 0;
    l.settop(-2);
    answer
}

/// Whether the keep function at `keep` (when there is one) wants the item on top of the stack at `item`, at `place`.
unsafe fn kept(l: L, keep: Option<c_int>, item: c_int, place: usize) -> bool {
    let Some(keep) = keep else { return true };
    l.pushvalue(keep);
    l.pushvalue(item);
    l.pushnumber(place as f64);
    l.call(2, 1);
    let answer = l.toboolean(-1) != 0;
    l.settop(item);
    answer
}

unsafe fn keep_at(l: L, index: c_int) -> Option<c_int> {
    if absent(l, index) {
        return None;
    }
    l.checktype(index, TFUNCTION);
    Some(index)
}

/// Pushes the best item, its measure and its place; three nils for none.
unsafe fn push_best(l: L, best: Option<(usize, f64)>) -> c_int {
    match best {
        None => {
            l.pushnil();
            l.pushnil();
            l.pushnil();
        }
        Some((place, measure)) => {
            l.rawgeti(1, place as c_int);
            l.pushnumber(measure);
            l.pushnumber(place as f64);
        }
    }
    3
}

unsafe fn pick(l: L, highest: bool) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(2, TFUNCTION);
    let keep = keep_at(l, 3);
    let mut best: Option<(usize, f64)> = None;
    let mut place = 1;
    loop {
        l.rawgeti(1, place as c_int);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            break;
        }
        let item = l.gettop();
        if kept(l, keep, item, place) {
            l.pushvalue(2);
            l.pushvalue(item);
            l.call(1, 1);
            if l.type_of(-1) != TNUMBER {
                raise_where(l, "a score is a number".into());
            }
            let score = l.tonumber(-1);
            l.settop(item);
            let better = match best {
                None => true,
                Some((_, held)) => (highest && score > held) || (!highest && score < held),
            };
            if better {
                best = Some((place, score));
            }
        }
        l.settop(item - 1);
        place += 1;
    }
    push_best(l, best)
}

unsafe extern "C-unwind" fn lowest(l: L) -> c_int {
    pick(l, false)
}

unsafe extern "C-unwind" fn highest(l: L) -> c_int {
    pick(l, true)
}

unsafe extern "C-unwind" fn nearest(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let from = point_at(l, 2);
    let position = keep_at(l, 3);
    let keep = keep_at(l, 4);
    let mut best: Option<(usize, f64)> = None;
    let mut place = 1;
    loop {
        l.rawgeti(1, place as c_int);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            break;
        }
        let item = l.gettop();
        if kept(l, keep, item, place) {
            let at = match position {
                None => point_at(l, item),
                Some(f) => {
                    l.pushvalue(f);
                    l.pushvalue(item);
                    l.call(1, 1);
                    let at = point_at(l, l.gettop());
                    l.settop(item);
                    at
                }
            };
            let (dx, dy, dz) = (at[0] - from[0], at[1] - from[1], at[2] - from[2]);
            let distance = (dx * dx + dy * dy + dz * dz).sqrt();
            if best.is_none_or(|(_, held)| distance < held) {
                best = Some((place, distance));
            }
        }
        l.settop(item - 1);
        place += 1;
    }
    push_best(l, best)
}

/// The places of list's items, in the order the function at `f` gives: a bottom-up merge sort that
/// keeps the earlier of two that tie first.
unsafe fn order_places(l: L, list: c_int, f: c_int) -> Vec<usize> {
    let n = count_items(l, list);
    let mut order: Vec<usize> = (1..=n).collect();
    let mut spare = vec![0usize; n];
    let mut width = 1;
    while width < n {
        let mut start = 0;
        while start < n {
            let middle = (start + width).min(n);
            let stop = (start + 2 * width).min(n);
            let (mut a, mut b, mut out) = (start, middle, start);
            while a < middle && b < stop {
                if before(l, list, f, order[b], order[a]) {
                    spare[out] = order[b];
                    b += 1;
                } else {
                    spare[out] = order[a];
                    a += 1;
                }
                out += 1;
            }
            while a < middle {
                spare[out] = order[a];
                a += 1;
                out += 1;
            }
            while b < stop {
                spare[out] = order[b];
                b += 1;
                out += 1;
            }
            start += 2 * width;
        }
        std::mem::swap(&mut order, &mut spare);
        width *= 2;
    }
    order
}

unsafe extern "C-unwind" fn order(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(2, TFUNCTION);
    let places = order_places(l, 1, 2);
    l.createtable(places.len() as c_int, 0);
    for (i, place) in places.iter().enumerate() {
        l.pushnumber(*place as f64);
        l.rawseti(-2, (i + 1) as c_int);
    }
    1
}

unsafe extern "C-unwind" fn ranks(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(2, TFUNCTION);
    let places = order_places(l, 1, 2);
    l.createtable(places.len() as c_int, 0);
    for (rank, place) in places.iter().enumerate() {
        l.pushnumber((rank + 1) as f64);
        l.rawseti(-2, *place as c_int);
    }
    1
}

unsafe extern "C-unwind" fn top_k(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(3, TFUNCTION);
    let wanted = if l.type_of(2) == TNUMBER { l.tonumber(2) } else { f64::NAN };
    if !(wanted >= 0.0) || wanted.fract() != 0.0 {
        raise_where(l, format!("TopK takes a whole number of at least 0, not {}", tostring(l, 2)));
    }
    let k = wanted as usize;
    if k == 0 {
        // The first none: the list is not read, nor `before` called.
        l.createtable(0, 0);
        return 1;
    }
    let mut top: Vec<usize> = Vec::new();
    let mut place = 1;
    loop {
        l.rawgeti(1, place as c_int);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            break;
        }
        let item = l.gettop();
        let (mut low, mut high) = (0, top.len());
        while low < high {
            let middle = (low + high) / 2;
            l.pushvalue(3);
            l.pushvalue(item);
            l.rawgeti(1, top[middle] as c_int);
            l.call(2, 1);
            let goes_before = l.toboolean(-1) != 0;
            l.settop(item);
            if goes_before {
                high = middle;
            } else {
                low = middle + 1;
            }
        }
        if low < k {
            top.insert(low, place);
            top.truncate(k);
        }
        l.settop(item - 1);
        place += 1;
    }
    l.createtable(top.len() as c_int, 0);
    for (i, place) in top.iter().enumerate() {
        l.rawgeti(1, *place as c_int);
        l.rawseti(-2, (i + 1) as c_int);
    }
    1
}

/// Pushes the `list.select` table.
pub unsafe fn push_module(l: L) {
    let functions: &[(&CStr, CFunction)] =
        &[(c"Lowest", lowest), (c"Highest", highest), (c"Nearest", nearest), (c"TopK", top_k), (c"Order", order), (c"Ranks", ranks)];
    module::push(l, functions, None);
}
