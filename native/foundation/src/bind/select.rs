//! list.select, native: the Lua twin's contract (foundation/list/select.lua).
//! The score, the keep test and the order are the caller's Lua functions,
//! called once an item (a pair for the order); Nearest, with no position
//! function, reads the items' points without calling Lua at all. The sorts
//! are written out, not the standard library's, so an error in the caller's
//! function leaves nothing half done in a sort.

use super::math::point_at;
use super::util::absent;
use crate::lua::{api, raise_where, tostring, CFunction, L, TFUNCTION, TNIL, TNUMBER, TTABLE};
use crate::module;
use std::ffi::{c_int, CStr};

/// How many items the list at `list` has, as ipairs counts: up to the first nil.
unsafe fn count_items(l: L, list: c_int) -> usize {
    let api = api();
    let mut n = 0;
    loop {
        (api.rawgeti)(l, list, (n + 1) as c_int);
        let end = (api.type_of)(l, -1) == TNIL;
        (api.settop)(l, -2);
        if end {
            return n;
        }
        n += 1;
    }
}

/// Whether the function at `f` says list[a] goes strictly before list[b].
unsafe fn before(l: L, list: c_int, f: c_int, a: usize, b: usize) -> bool {
    let api = api();
    (api.pushvalue)(l, f);
    (api.rawgeti)(l, list, a as c_int);
    (api.rawgeti)(l, list, b as c_int);
    (api.call)(l, 2, 1);
    let answer = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    answer
}

/// Whether the keep function at `keep` (when there is one) wants the item on top of the stack at `item`, at `place`.
unsafe fn kept(l: L, keep: Option<c_int>, item: c_int, place: usize) -> bool {
    let Some(keep) = keep else { return true };
    let api = api();
    (api.pushvalue)(l, keep);
    (api.pushvalue)(l, item);
    (api.pushnumber)(l, place as f64);
    (api.call)(l, 2, 1);
    let answer = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, item);
    answer
}

unsafe fn keep_at(l: L, index: c_int) -> Option<c_int> {
    if absent(l, index) {
        return None;
    }
    (api().checktype)(l, index, TFUNCTION);
    Some(index)
}

/// Pushes the best item, its measure and its place; three nils for none.
unsafe fn push_best(l: L, best: Option<(usize, f64)>) -> c_int {
    let api = api();
    match best {
        None => {
            (api.pushnil)(l);
            (api.pushnil)(l);
            (api.pushnil)(l);
        }
        Some((place, measure)) => {
            (api.rawgeti)(l, 1, place as c_int);
            (api.pushnumber)(l, measure);
            (api.pushnumber)(l, place as f64);
        }
    }
    3
}

unsafe fn pick(l: L, highest: bool) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 2, TFUNCTION);
    let keep = keep_at(l, 3);
    let mut best: Option<(usize, f64)> = None;
    let mut place = 1;
    loop {
        (api.rawgeti)(l, 1, place as c_int);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            break;
        }
        let item = (api.gettop)(l);
        if kept(l, keep, item, place) {
            (api.pushvalue)(l, 2);
            (api.pushvalue)(l, item);
            (api.call)(l, 1, 1);
            if (api.type_of)(l, -1) != TNUMBER {
                raise_where(l, "a score is a number".into());
            }
            let score = (api.tonumber)(l, -1);
            (api.settop)(l, item);
            let better = match best {
                None => true,
                Some((_, held)) => (highest && score > held) || (!highest && score < held),
            };
            if better {
                best = Some((place, score));
            }
        }
        (api.settop)(l, item - 1);
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
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let from = point_at(l, 2);
    let position = keep_at(l, 3);
    let keep = keep_at(l, 4);
    let mut best: Option<(usize, f64)> = None;
    let mut place = 1;
    loop {
        (api.rawgeti)(l, 1, place as c_int);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            break;
        }
        let item = (api.gettop)(l);
        if kept(l, keep, item, place) {
            let at = match position {
                None => point_at(l, item),
                Some(f) => {
                    (api.pushvalue)(l, f);
                    (api.pushvalue)(l, item);
                    (api.call)(l, 1, 1);
                    let at = point_at(l, (api.gettop)(l));
                    (api.settop)(l, item);
                    at
                }
            };
            let (dx, dy, dz) = (at[0] - from[0], at[1] - from[1], at[2] - from[2]);
            let distance = (dx * dx + dy * dy + dz * dz).sqrt();
            if best.map_or(true, |(_, held)| distance < held) {
                best = Some((place, distance));
            }
        }
        (api.settop)(l, item - 1);
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
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 2, TFUNCTION);
    let places = order_places(l, 1, 2);
    (api.createtable)(l, places.len() as c_int, 0);
    for (i, place) in places.iter().enumerate() {
        (api.pushnumber)(l, *place as f64);
        (api.rawseti)(l, -2, (i + 1) as c_int);
    }
    1
}

unsafe extern "C-unwind" fn ranks(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 2, TFUNCTION);
    let places = order_places(l, 1, 2);
    (api.createtable)(l, places.len() as c_int, 0);
    for (rank, place) in places.iter().enumerate() {
        (api.pushnumber)(l, (rank + 1) as f64);
        (api.rawseti)(l, -2, *place as c_int);
    }
    1
}

unsafe extern "C-unwind" fn top_k(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 3, TFUNCTION);
    let wanted = if (api.type_of)(l, 2) == TNUMBER { (api.tonumber)(l, 2) } else { f64::NAN };
    if !(wanted >= 0.0) || wanted.fract() != 0.0 {
        raise_where(l, format!("TopK takes a whole number of at least 0, not {}", tostring(l, 2)));
    }
    let k = wanted as usize;
    let mut top: Vec<usize> = Vec::new();
    let mut place = 1;
    while k > 0 {
        (api.rawgeti)(l, 1, place as c_int);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            break;
        }
        let item = (api.gettop)(l);
        let (mut low, mut high) = (0, top.len());
        while low < high {
            let middle = (low + high) / 2;
            (api.pushvalue)(l, 3);
            (api.pushvalue)(l, item);
            (api.rawgeti)(l, 1, top[middle] as c_int);
            (api.call)(l, 2, 1);
            let goes_before = (api.toboolean)(l, -1) != 0;
            (api.settop)(l, item);
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
        (api.settop)(l, item - 1);
        place += 1;
    }
    (api.createtable)(l, top.len() as c_int, 0);
    for (i, place) in top.iter().enumerate() {
        (api.rawgeti)(l, 1, *place as c_int);
        (api.rawseti)(l, -2, (i + 1) as c_int);
    }
    1
}

/// Pushes the `list.select` table.
pub unsafe fn push_module(l: L) {
    let functions: &[(&CStr, CFunction)] =
        &[(c"Lowest", lowest), (c"Highest", highest), (c"Nearest", nearest), (c"TopK", top_k), (c"Order", order), (c"Ranks", ranks)];
    module::push(l, functions, None);
}
