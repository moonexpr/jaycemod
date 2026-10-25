//! graph.search, native: Flood, Components and Distances over a graph the
//! caller describes by callbacks (neighbors, admit, stop, edges), any Lua
//! values as nodes. The walks are the Lua twin's, step for step, so floods
//! come out in the same order; what a node has been is kept in Lua tables
//! keyed by the node itself (seen, reached, the groups, the distances), and
//! Distances numbers its nodes for crate::heap.

use crate::heap::Heap;
use crate::lua::{api, raise, set_function, L, TNIL, TNUMBER, TTABLE};
use std::ffi::c_int;

/// Whether argument `i` is nil or not given at all.
unsafe fn absent(l: L, i: c_int) -> bool {
    (api().type_of)(l, i) <= TNIL
}

/// Calls the function at `f` with the value at `arg`; leaves its one result.
unsafe fn call1(l: L, f: c_int, arg: c_int) {
    let api = api();
    (api.pushvalue)(l, f);
    (api.pushvalue)(l, arg);
    (api.call)(l, 1, 1);
}

/// Whether t[value at `key`] is set (t at `t`).
unsafe fn has(l: L, t: c_int, key: c_int) -> bool {
    let api = api();
    (api.pushvalue)(l, key);
    (api.rawget)(l, t);
    let set = (api.type_of)(l, -1) != TNIL;
    (api.settop)(l, -2);
    set
}

/// t[value at `key`] = the value at `value`.
unsafe fn put(l: L, t: c_int, key: c_int, value: c_int) {
    let api = api();
    (api.pushvalue)(l, key);
    (api.pushvalue)(l, value);
    (api.rawset)(l, t);
}

/// t[value at `key`] = true.
unsafe fn mark(l: L, t: c_int, key: c_int) {
    let api = api();
    (api.pushvalue)(l, key);
    (api.pushboolean)(l, 1);
    (api.rawset)(l, t);
}

/// The list the callback just returned (at the top), checked.
unsafe fn list_at_top(l: L, what: &std::ffi::CStr) -> c_int {
    let api = api();
    if (api.type_of)(l, -1) != TTABLE {
        raise(l, what);
    }
    (api.gettop)(l)
}

/// graph.search.Flood(starts, neighbors, admit, limit[, stop]) -> the nodes
/// reached, breadth first, and whether the flood was cut
unsafe extern "C-unwind" fn flood(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let limit = (api.checknumber)(l, 4);
    let stop = !absent(l, 5);
    (api.settop)(l, 5);
    (api.createtable)(l, 0, 0);
    let seen = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let reached = (api.gettop)(l);
    let mut n: c_int = 0;
    let mut i = 1;
    loop {
        (api.rawgeti)(l, 1, i);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            break;
        }
        let node = (api.gettop)(l);
        if !has(l, seen, node) {
            mark(l, seen, node);
            n += 1;
            (api.pushvalue)(l, node);
            (api.rawseti)(l, reached, n);
        }
        (api.settop)(l, -2);
        i += 1;
    }
    let mut head = 1;
    let mut cut = false;
    'walk: while head <= n {
        (api.rawgeti)(l, reached, head);
        let node = (api.gettop)(l);
        head += 1;
        if stop {
            call1(l, 5, node);
            let stopped = (api.toboolean)(l, -1) != 0;
            (api.settop)(l, -2);
            if stopped {
                cut = true;
                break 'walk;
            }
        }
        call1(l, 2, node);
        let list = list_at_top(l, c"neighbors(node) gave no list");
        let mut k = 1;
        loop {
            (api.rawgeti)(l, list, k);
            if (api.type_of)(l, -1) == TNIL {
                (api.settop)(l, -2);
                break;
            }
            let next = (api.gettop)(l);
            if !has(l, seen, next) {
                mark(l, seen, next);
                call1(l, 3, next);
                let admitted = (api.toboolean)(l, -1) != 0;
                (api.settop)(l, -2);
                if admitted {
                    if n as f64 >= limit {
                        cut = true;
                        break 'walk;
                    }
                    n += 1;
                    (api.pushvalue)(l, next);
                    (api.rawseti)(l, reached, n);
                }
            }
            (api.settop)(l, -2);
            k += 1;
        }
        (api.settop)(l, node - 1);
    }
    (api.pushvalue)(l, reached);
    (api.pushboolean)(l, cut as c_int);
    2
}

/// graph.search.Components(nodes, neighbors) -> node -> its group's number
unsafe extern "C-unwind" fn components(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.settop)(l, 2);
    (api.createtable)(l, 0, 0);
    let component = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let stack = (api.gettop)(l);
    let mut count = 0.0;
    let mut i = 1;
    loop {
        (api.rawgeti)(l, 1, i);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            break;
        }
        let node = (api.gettop)(l);
        if !has(l, component, node) {
            count += 1.0;
            (api.pushnumber)(l, count);
            let group = (api.gettop)(l);
            put(l, component, node, group);
            (api.pushvalue)(l, node);
            (api.rawseti)(l, stack, 1);
            let mut depth: c_int = 1;
            while depth > 0 {
                (api.rawgeti)(l, stack, depth);
                let n = (api.gettop)(l);
                (api.pushnil)(l);
                (api.rawseti)(l, stack, depth);
                depth -= 1;
                call1(l, 2, n);
                let list = list_at_top(l, c"neighbors(node) gave no list");
                let mut k = 1;
                loop {
                    (api.rawgeti)(l, list, k);
                    if (api.type_of)(l, -1) == TNIL {
                        (api.settop)(l, -2);
                        break;
                    }
                    let m = (api.gettop)(l);
                    if !has(l, component, m) {
                        put(l, component, m, group);
                        depth += 1;
                        (api.pushvalue)(l, m);
                        (api.rawseti)(l, stack, depth);
                    }
                    (api.settop)(l, -2);
                    k += 1;
                }
                (api.settop)(l, n - 1);
            }
            (api.settop)(l, -2);
        }
        (api.settop)(l, -2);
        i += 1;
    }
    (api.pushvalue)(l, component);
    1
}

/// The number of the node at `value` in Distances' numbering (index:
/// value -> number, nodes: number -> value), numbered now if new.
unsafe fn number_of(l: L, index: c_int, nodes: c_int, value: c_int, count: &mut Vec<Option<f64>>) -> usize {
    let api = api();
    (api.pushvalue)(l, value);
    (api.rawget)(l, index);
    if (api.type_of)(l, -1) == TNUMBER {
        let n = (api.tonumber)(l, -1) as usize;
        (api.settop)(l, -2);
        return n;
    }
    (api.settop)(l, -2);
    let n = count.len();
    count.push(None);
    (api.pushvalue)(l, value);
    (api.pushnumber)(l, n as f64);
    (api.rawset)(l, index);
    (api.pushvalue)(l, value);
    (api.rawseti)(l, nodes, n as c_int + 1);
    n
}

/// graph.search.Distances(starts, edges, limit) -> node -> the cheapest walk
/// to it from the nearest start
unsafe extern "C-unwind" fn distances(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let limit = (api.checknumber)(l, 3);
    (api.settop)(l, 3);
    (api.createtable)(l, 0, 0);
    let dist = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let index = (api.gettop)(l);
    (api.createtable)(l, 0, 0);
    let nodes = (api.gettop)(l);
    let mut known: Vec<Option<f64>> = Vec::new();
    let mut queue = Heap::default();
    let mut i = 1;
    loop {
        (api.rawgeti)(l, 1, i);
        if (api.type_of)(l, -1) == TNIL {
            (api.settop)(l, -2);
            break;
        }
        let node = (api.gettop)(l);
        let n = number_of(l, index, nodes, node, &mut known);
        known[n] = Some(0.0);
        (api.pushvalue)(l, node);
        (api.pushnumber)(l, 0.0);
        (api.rawset)(l, dist);
        queue.push(0.0, n as f64);
        (api.settop)(l, -2);
        i += 1;
    }
    while let Some((n, reached)) = queue.pop() {
        let n = n as usize;
        if known[n] != Some(reached) {
            continue;
        }
        (api.rawgeti)(l, nodes, n as c_int + 1);
        let node = (api.gettop)(l);
        call1(l, 2, node);
        let list = list_at_top(l, c"edges(node) gave no list");
        let mut k = 1;
        loop {
            (api.rawgeti)(l, list, k);
            if (api.type_of)(l, -1) == TNIL {
                (api.settop)(l, -2);
                break;
            }
            let edge = (api.gettop)(l);
            (api.getfield)(l, edge, c"cost".as_ptr());
            if (api.type_of)(l, -1) != TNUMBER {
                raise(l, c"an edge's cost is no number");
            }
            let cost = reached + (api.tonumber)(l, -1);
            (api.settop)(l, -2);
            (api.getfield)(l, edge, c"node".as_ptr());
            let to = (api.gettop)(l);
            let m = number_of(l, index, nodes, to, &mut known);
            if cost <= limit && known[m].is_none_or(|was| cost < was) {
                known[m] = Some(cost);
                (api.pushvalue)(l, to);
                (api.pushnumber)(l, cost);
                (api.rawset)(l, dist);
                queue.push(cost, m as f64);
            }
            (api.settop)(l, edge - 1);
            k += 1;
        }
        (api.settop)(l, node - 1);
    }
    drop(known);
    (api.pushvalue)(l, dist);
    1
}

/// Pushes the graph.search module table.
pub unsafe fn push_module(l: L) {
    (api().createtable)(l, 0, 3);
    set_function(l, c"Flood", flood);
    set_function(l, c"Components", components);
    set_function(l, c"Distances", distances);
}
