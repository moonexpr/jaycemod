//! graph.paths, native: crate::paths behind two userdata, a graph and the
//! walks across it, nodes numbered 1..n as Lua counts them. Every answer is
//! a plain Lua table, the work done in the one call.
//!
//! ```lua
//! local g = graph.paths.New(3)              -- nodes 1..3
//! g:Step(1, 2, 100) g:Step(2, 3, 100)       -- one way, a cost each
//! local tree = g:Tree({ 1 })                -- the walk from the starts
//! tree:Path(3)                              -- { 1, 2, 3 }
//! tree:Distances(), tree:Parents()          -- node -> ..., the reached
//! tree:Branches(floor)                      -- { children, weight, roots }
//! tree:Forks(floor, share)                  -- { node, ... }
//! g:Cover(tree, floor, share[, reach])      -- { { nodes, gain }, ... }
//! g:Alternatives(starts, target, k, detour, penalty) -- { { nodes, length }, ... }
//! g:Near(reach)                             -- node -> { node, ... }
//! ```

use crate::lua::{raise_owned, CFunction, L, TNIL};
use crate::module;
use crate::paths::{Paths, Tree};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

pub struct Graph(Paths);

impl Native for Graph {
    const NAME: &'static CStr = c"foundation.graph.paths";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Step", step),
        (c"Nodes", nodes),
        (c"Tree", tree),
        (c"Alternatives", alternatives),
        (c"Near", near),
        (c"Cover", cover),
        (c"__len", nodes),
    ];
}

pub struct Walk(Tree);

impl Native for Walk {
    const NAME: &'static CStr = c"foundation.graph.paths.tree";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Path", path),
        (c"Distance", distance),
        (c"Distances", distances),
        (c"Parents", parents),
        (c"Branches", branches),
        (c"Forks", forks),
    ];
}

/// A node argument, 1..n, as the crate's 0..n; anything else is the caller's mistake.
unsafe fn node_at(l: L, index: c_int, nodes: u32) -> u32 {
    let n = l.checknumber(index);
    if n.fract() != 0.0 || n < 1.0 || n > nodes as f64 {
        raise_owned(l, format!("graph.paths: node {n} of a graph of {nodes} nodes"));
    }
    n as u32 - 1
}

/// The nodes listed in the table at `index` (1, 2, ... until a nil).
unsafe fn nodes_at(l: L, index: c_int, nodes: u32) -> Vec<u32> {
    l.checktype(index, crate::lua::TTABLE);
    let mut list = Vec::new();
    let mut i = 1;
    loop {
        l.rawgeti(index, i);
        if l.type_of(-1) == TNIL {
            l.settop(-2);
            return list;
        }
        list.push(node_at(l, -1, nodes));
        l.settop(-2);
        i += 1;
    }
}

/// The floor of each node from the table at `index` (node -> number; a node
/// missing has none).
unsafe fn floor_at(l: L, index: c_int, nodes: u32) -> Vec<f64> {
    l.checktype(index, crate::lua::TTABLE);
    (0..nodes as c_int)
        .map(|i| {
            l.rawgeti(index, i + 1);
            let v = l.tonumber(-1);
            l.settop(-2);
            v
        })
        .collect()
}

/// Pushes a list of nodes, numbered as Lua counts them.
unsafe fn push_nodes(l: L, list: &[u32]) {
    l.createtable(list.len() as c_int, 0);
    for (i, node) in list.iter().enumerate() {
        l.pushnumber((*node + 1) as f64);
        l.rawseti(-2, i as c_int + 1);
    }
}

/// Pushes { nodes = { ... }, <key> = value }.
unsafe fn push_path(l: L, nodes: &[u32], key: &CStr, value: f64) {
    l.createtable(0, 2);
    push_nodes(l, nodes);
    l.setfield(-2, c"nodes");
    l.pushnumber(value);
    l.setfield(-2, key);
}

/// graph.paths.New(count) -> a graph of nodes 1..count and no steps
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    let count = l.checknumber(1);
    if count.fract() != 0.0 || count < 0.0 || count > u32::MAX as f64 {
        raise_owned(l, format!("graph.paths.New: {count} nodes"));
    }
    userdata::push(l, Graph(Paths::new(count as u32)));
    1
}

/// g:Step(from, to, cost): a step one way
unsafe extern "C-unwind" fn step(l: L) -> c_int {
    let g = userdata::check::<Graph>(l, 1);
    let nodes = g.0.nodes();
    let (from, to) = (node_at(l, 2, nodes), node_at(l, 3, nodes));
    let cost = l.checknumber(4);
    if let Err(e) = g.0.step(from, to, cost) {
        raise_owned(l, format!("graph.paths: {e}"));
    }
    0
}

/// g:Nodes(), #g
unsafe extern "C-unwind" fn nodes(l: L) -> c_int {
    let n = userdata::check::<Graph>(l, 1).0.nodes();
    l.pushnumber(n as f64);
    1
}

/// g:Tree(starts) -> the walk from the starts (Dijkstra; ties to the earlier
/// start, then the earlier push)
unsafe extern "C-unwind" fn tree(l: L) -> c_int {
    let g = userdata::check::<Graph>(l, 1);
    let starts = nodes_at(l, 2, g.0.nodes());
    let walk = g.0.tree(&starts);
    userdata::push(l, Walk(walk));
    1
}

/// g:Alternatives(starts, target, k, detour, penalty) -> { { nodes, length } },
/// the shortest first; empty when the target is never reached
unsafe extern "C-unwind" fn alternatives(l: L) -> c_int {
    let g = userdata::check::<Graph>(l, 1);
    let nodes = g.0.nodes();
    let starts = nodes_at(l, 2, nodes);
    let target = node_at(l, 3, nodes);
    let k = l.checknumber(4) as usize;
    let (detour, penalty) = (l.checknumber(5), l.checknumber(6));
    let routes = g.0.alternatives(&starts, target, k, detour, penalty);
    l.createtable(routes.len() as c_int, 0);
    for (i, route) in routes.iter().enumerate() {
        push_path(l, &route.nodes, c"length", route.length);
        l.rawseti(-2, i as c_int + 1);
    }
    1
}

/// g:Near(reach) -> node -> the nodes its walk reaches within reach, itself
/// included, ascending
unsafe extern "C-unwind" fn near(l: L) -> c_int {
    let g = userdata::check::<Graph>(l, 1);
    let reach = l.checknumber(2);
    let near = g.0.near(reach);
    l.createtable(near.len() as c_int, 0);
    for (i, ground) in near.iter().enumerate() {
        push_nodes(l, ground);
        l.rawseti(-2, i as c_int + 1);
    }
    1
}

/// g:Cover(tree, floor, share[, reach]) -> { { nodes, gain } }: the fewest
/// paths from the tree's roots to its leaves covering share of its floor,
/// the ground within reach of a path covered by it (none: the path alone)
unsafe extern "C-unwind" fn cover(l: L) -> c_int {
    let g = userdata::check::<Graph>(l, 1);
    let nodes = g.0.nodes();
    let walk = userdata::check::<Walk>(l, 2);
    let floor = floor_at(l, 3, nodes);
    let share = l.checknumber(4);
    let near = if l.type_of(5) <= TNIL { None } else { Some(g.0.near(l.checknumber(5))) };
    let branches = walk.0.branches(&floor);
    let breaches = branches.cover(&walk.0, share, near.as_deref());
    l.createtable(breaches.len() as c_int, 0);
    for (i, breach) in breaches.iter().enumerate() {
        push_path(l, &breach.nodes, c"gain", breach.gain);
        l.rawseti(-2, i as c_int + 1);
    }
    1
}

/// tree:Path(node) -> { start, ..., node }, or nil if the walk never reached it
unsafe extern "C-unwind" fn path(l: L) -> c_int {
    let walk = userdata::check::<Walk>(l, 1);
    let node = node_at(l, 2, walk.0.distance.len() as u32);
    match walk.0.path(node) {
        Some(path) => push_nodes(l, &path),
        None => l.pushnil(),
    }
    1
}

/// tree:Distance(node) -> the walk to it, or nil if never reached
unsafe extern "C-unwind" fn distance(l: L) -> c_int {
    let walk = userdata::check::<Walk>(l, 1);
    let node = node_at(l, 2, walk.0.distance.len() as u32);
    if walk.0.reached(node) {
        l.pushnumber(walk.0.distance[node as usize]);
    } else {
        l.pushnil();
    }
    1
}

/// tree:Distances() -> node -> the walk to it, the reached only
unsafe extern "C-unwind" fn distances(l: L) -> c_int {
    let walk = userdata::check::<Walk>(l, 1);
    l.createtable(walk.0.distance.len() as c_int, 0);
    for (i, d) in walk.0.distance.iter().enumerate() {
        if d.is_finite() {
            l.pushnumber(*d);
            l.rawseti(-2, i as c_int + 1);
        }
    }
    1
}

/// tree:Parents() -> node -> the node before it on the walk (a start has none)
unsafe extern "C-unwind" fn parents(l: L) -> c_int {
    let walk = userdata::check::<Walk>(l, 1);
    l.createtable(0, walk.0.parent.len() as c_int);
    for (i, p) in walk.0.parent.iter().enumerate() {
        if let Some(p) = p {
            l.pushnumber((*p + 1) as f64);
            l.rawseti(-2, i as c_int + 1);
        }
    }
    1
}

/// tree:Branches(floor) -> { children = node -> { ... }, weight = node ->
/// the floor of it and all reached through it, roots = { ... } }
unsafe extern "C-unwind" fn branches(l: L) -> c_int {
    let walk = userdata::check::<Walk>(l, 1);
    let nodes = walk.0.distance.len() as u32;
    let b = walk.0.branches(&floor_at(l, 2, nodes));
    l.createtable(0, 3);
    l.createtable(nodes as c_int, 0);
    l.createtable(nodes as c_int, 0);
    for node in 0..nodes {
        if walk.0.reached(node) {
            push_nodes(l, &b.children[node as usize]);
            l.rawseti(-3, node as c_int + 1);
            l.pushnumber(b.weight[node as usize]);
            l.rawseti(-2, node as c_int + 1);
        }
    }
    l.setfield(-3, c"weight");
    l.setfield(-2, c"children");
    push_nodes(l, &b.roots);
    l.setfield(-2, c"roots");
    1
}

/// tree:Forks(floor, share) -> the nodes where a branch splits into ways each
/// carrying share of the tree's floor, ascending
unsafe extern "C-unwind" fn forks(l: L) -> c_int {
    let walk = userdata::check::<Walk>(l, 1);
    let nodes = walk.0.distance.len() as u32;
    let floor = floor_at(l, 2, nodes);
    let share = l.checknumber(3);
    push_nodes(l, &walk.0.branches(&floor).forks(share));
    1
}

/// Pushes the graph.paths module table.
pub unsafe fn push_module(l: L) {
    module::push(l, &[(c"New", new)], None);
}
