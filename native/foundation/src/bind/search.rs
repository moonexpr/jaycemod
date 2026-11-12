//! graph.search, native: Flood, Components and Distances over a graph the
//! caller describes by callbacks (neighbors, admit, stop, edges), any Lua
//! values as nodes. The walks are the Lua twin's, step for step, so floods
//! come out in the same order; what a node has been is kept in Lua tables
//! keyed by the node itself (seen, reached, the groups, the distances), and
//! Distances numbers its nodes for crate::heap.

use crate::heap::Heap;
use crate::lua::{raise, set_function, L, TNIL, TNUMBER, TTABLE};
use std::ffi::c_int;

/// Whether argument `i` is nil or not given at all.
unsafe fn absent(l: L, i: c_int) -> bool {
    l.type_of(i) <= TNIL
}

/// Calls the function at `f` with the value at `arg`; leaves its one result.
unsafe fn call1(l: L, f: c_int, arg: c_int) {
    l.pushvalue(f);
    l.pushvalue(arg);
    l.call(1, 1);
}

/// Whether t[value at `key`] is set (t at `t`).
unsafe fn has(l: L, t: c_int, key: c_int) -> bool {
    l.pushvalue(key);
    l.rawget(t);
    let set = l.type_of(-1) != TNIL;
    l.settop(-2);
    set
}

/// t[value at `key`] = the value at `value`.
unsafe fn put(l: L, t: c_int, key: c_int, value: c_int) {
    l.pushvalue(key);
    l.pushvalue(value);
    l.rawset(t);
}

/// t[value at `key`] = true.
unsafe fn mark(l: L, t: c_int, key: c_int) {
    l.pushvalue(key);
    l.pushboolean(1);
    l.rawset(t);
}

/// The list the callback just returned (at the top), checked.
unsafe fn list_at_top(l: L, what: &std::ffi::CStr) -> c_int {
    if l.type_of(-1) != TTABLE {
        raise(l, what);
    }
    l.gettop()
}

/// graph.search.Flood(starts, neighbors, admit, limit[, stop]) -> the nodes
/// reached, breadth first, and whether the flood was cut
unsafe extern "C-unwind" fn flood(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let limit = l.checknumber(4);
    let stop = !absent(l, 5);
    l.settop(5);
    l.createtable(0, 0);
    let seen = l.gettop();
    l.createtable(0, 0);
    let reached = l.gettop();
    let mut n: c_int = 0;
    let mut i = 1;
    loop {
        l.rawgeti(1, i);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            break;
        }
        let node = l.gettop();
        if !has(l, seen, node) {
            mark(l, seen, node);
            n += 1;
            l.pushvalue(node);
            l.rawseti(reached, n);
        }
        l.settop(-2);
        i += 1;
    }
    let mut head = 1;
    let mut cut = false;
    'walk: while head <= n {
        l.rawgeti(reached, head);
        let node = l.gettop();
        head += 1;
        if stop {
            call1(l, 5, node);
            let stopped = l.toboolean(-1) != 0;
            l.settop(-2);
            if stopped {
                cut = true;
                break 'walk;
            }
        }
        call1(l, 2, node);
        let list = list_at_top(l, c"neighbors(node) gave no list");
        let mut k = 1;
        loop {
            l.rawgeti(list, k);
            if l.type_of(-1) == TNIL {
                l.settop(-2);
                break;
            }
            let next = l.gettop();
            if !has(l, seen, next) {
                mark(l, seen, next);
                call1(l, 3, next);
                let admitted = l.toboolean(-1) != 0;
                l.settop(-2);
                if admitted {
                    if n as f64 >= limit {
                        cut = true;
                        break 'walk;
                    }
                    n += 1;
                    l.pushvalue(next);
                    l.rawseti(reached, n);
                }
            }
            l.settop(-2);
            k += 1;
        }
        l.settop(node - 1);
    }
    l.pushvalue(reached);
    l.pushboolean(cut as c_int);
    2
}

/// graph.search.Components(nodes, neighbors) -> node -> its group's number
unsafe extern "C-unwind" fn components(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.settop(2);
    l.createtable(0, 0);
    let component = l.gettop();
    l.createtable(0, 0);
    let stack = l.gettop();
    let mut count = 0.0;
    let mut i = 1;
    loop {
        l.rawgeti(1, i);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            break;
        }
        let node = l.gettop();
        if !has(l, component, node) {
            count += 1.0;
            l.pushnumber(count);
            let group = l.gettop();
            put(l, component, node, group);
            l.pushvalue(node);
            l.rawseti(stack, 1);
            let mut depth: c_int = 1;
            while depth > 0 {
                l.rawgeti(stack, depth);
                let n = l.gettop();
                l.pushnil();
                l.rawseti(stack, depth);
                depth -= 1;
                call1(l, 2, n);
                let list = list_at_top(l, c"neighbors(node) gave no list");
                let mut k = 1;
                loop {
                    l.rawgeti(list, k);
                    if l.type_of(-1) == TNIL {
                        l.settop(-2);
                        break;
                    }
                    let m = l.gettop();
                    if !has(l, component, m) {
                        put(l, component, m, group);
                        depth += 1;
                        l.pushvalue(m);
                        l.rawseti(stack, depth);
                    }
                    l.settop(-2);
                    k += 1;
                }
                l.settop(n - 1);
            }
            l.settop(-2);
        }
        l.settop(-2);
        i += 1;
    }
    l.pushvalue(component);
    1
}

/// The number of the node at `value` in Distances' numbering (index:
/// value -> number, nodes: number -> value), numbered now if new.
unsafe fn number_of(l: L, index: c_int, nodes: c_int, value: c_int, count: &mut Vec<Option<f64>>) -> usize {
    l.pushvalue(value);
    l.rawget(index);
    if l.type_of(-1) == TNUMBER {
        let n = l.tonumber(-1) as usize;
        l.settop(-2);
        return n;
    }
    l.settop(-2);
    let n = count.len();
    count.push(None);
    l.pushvalue(value);
    l.pushnumber(n as f64);
    l.rawset(index);
    l.pushvalue(value);
    l.rawseti(nodes, n as c_int + 1);
    n
}

/// graph.search.Distances(starts, edges, limit) -> node -> the cheapest walk
/// to it from the nearest start
unsafe extern "C-unwind" fn distances(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let limit = l.checknumber(3);
    l.settop(3);
    l.createtable(0, 0);
    let dist = l.gettop();
    l.createtable(0, 0);
    let index = l.gettop();
    l.createtable(0, 0);
    let nodes = l.gettop();
    let mut known: Vec<Option<f64>> = Vec::new();
    let mut queue = Heap::default();
    let mut i = 1;
    loop {
        l.rawgeti(1, i);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            break;
        }
        let node = l.gettop();
        let n = number_of(l, index, nodes, node, &mut known);
        known[n] = Some(0.0);
        l.pushvalue(node);
        l.pushnumber(0.0);
        l.rawset(dist);
        queue.push(0.0, n as f64);
        l.settop(-2);
        i += 1;
    }
    while let Some((n, reached)) = queue.pop() {
        let n = n as usize;
        if known[n] != Some(reached) {
            continue;
        }
        l.rawgeti(nodes, n as c_int + 1);
        let node = l.gettop();
        call1(l, 2, node);
        let list = list_at_top(l, c"edges(node) gave no list");
        let mut k = 1;
        loop {
            l.rawgeti(list, k);
            if l.type_of(-1) == TNIL {
                l.settop(-2);
                break;
            }
            let edge = l.gettop();
            l.getfield(edge, c"cost");
            if l.type_of(-1) != TNUMBER {
                raise(l, c"an edge's cost is no number");
            }
            let cost = reached + l.tonumber(-1);
            l.settop(-2);
            l.getfield(edge, c"node");
            let to = l.gettop();
            let m = number_of(l, index, nodes, to, &mut known);
            if cost <= limit && known[m].is_none_or(|was| cost < was) {
                known[m] = Some(cost);
                l.pushvalue(to);
                l.pushnumber(cost);
                l.rawset(dist);
                queue.push(cost, m as f64);
            }
            l.settop(edge - 1);
            k += 1;
        }
        l.settop(node - 1);
    }
    drop(known);
    l.pushvalue(dist);
    1
}

/// Pushes the graph.search module table.
pub unsafe fn push_module(l: L) {
    l.createtable(0, 3);
    set_function(l, c"Flood", flood);
    set_function(l, c"Components", components);
    set_function(l, c"Distances", distances);
}
