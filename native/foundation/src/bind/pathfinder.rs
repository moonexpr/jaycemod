//! graph.pathfinder, native: NavAreaBuildPath's A* (crate::astar) over the
//! caller's graph port, whose Neighbors, Cost and Estimate it calls from
//! inside a step. Nodes are any Lua values usable as keys, numbered in the
//! search's environment: `nodes` (number + 1 -> value) and `index` (value
//! -> number), beside `graph` and `goal`. A port that uses its own search
//! from inside a step is refused, and one that raises leaves the search
//! spent (busy), as the route search's rules do.

use super::slots::fresh_environment;
use crate::astar::{AStar, Costs, Status, NAN_COST};
use crate::lua::{api, raise, raise_owned, set_function, string_at, CFunction, L, TNIL, TNUMBER, TTABLE};
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

/// graph.pathfinder.MAX_EXPANDED: the cap a search takes when given none.
const MAX_EXPANDED: f64 = 4000.0;

pub struct PathSearch {
    astar: Option<AStar>,
    busy: bool,
    nodes: u32,
    max_expanded: f64,
}

impl Native for PathSearch {
    const NAME: &'static CStr = c"foundation.graph.pathfinder";
    const METHODS: &'static [(&'static CStr, CFunction)] =
        &[(c"Step", step), (c"Route", route), (c"CostSoFar", cost_so_far)];
    const INDEX: Option<CFunction> = Some(index);
}

/// A whole-number count for the core from a Lua number: none below zero,
/// none above u32's range (math.huge among them), a fraction rounded up as
/// the Lua twin's `budget > 0` loop counts it.
fn count(n: f64) -> u32 {
    if n.is_nan() || n <= 0.0 {
        0
    } else if n >= u32::MAX as f64 {
        u32::MAX
    } else {
        n.ceil() as u32
    }
}

/// Whether argument `i` is nil or not given at all.
unsafe fn absent(l: L, i: c_int) -> bool {
    (api().type_of)(l, i) <= TNIL
}

/// Pushes the search's environment table (the userdata at `ud`); its index.
unsafe fn environment(l: L, ud: c_int) -> c_int {
    (api().getfenv)(l, ud);
    (api().gettop)(l)
}

/// The number of the node at `value`, numbered now if new.
unsafe fn number_of(l: L, env: c_int, value: c_int, count: &mut u32) -> u32 {
    let api = api();
    let value = if value < 0 { (api.gettop)(l) + value + 1 } else { value };
    (api.getfield)(l, env, c"index".as_ptr());
    (api.pushvalue)(l, value);
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) == TNUMBER {
        let n = (api.tonumber)(l, -1) as u32;
        (api.settop)(l, -3);
        return n;
    }
    (api.settop)(l, -2);
    let n = *count;
    *count += 1;
    (api.pushvalue)(l, value);
    (api.pushnumber)(l, n as f64);
    (api.rawset)(l, -3);
    (api.settop)(l, -2);
    (api.getfield)(l, env, c"nodes".as_ptr());
    (api.pushvalue)(l, value);
    (api.rawseti)(l, -2, n as c_int + 1);
    (api.settop)(l, -2);
    n
}

/// The number of the node at `value` if it has one, numbering nothing.
unsafe fn known(l: L, env: c_int, value: c_int) -> Option<u32> {
    let api = api();
    (api.getfield)(l, env, c"index".as_ptr());
    (api.pushvalue)(l, value);
    (api.rawget)(l, -2);
    let n = ((api.type_of)(l, -1) == TNUMBER).then(|| (api.tonumber)(l, -1) as u32);
    (api.settop)(l, -3);
    n
}

/// Pushes node `n`'s value.
unsafe fn push_node(l: L, env: c_int, n: u32) {
    let api = api();
    (api.getfield)(l, env, c"nodes".as_ptr());
    (api.rawgeti)(l, -1, n as c_int + 1);
    (api.remove)(l, -2);
}

/// The graph port, called through the search's environment at `env`.
struct Port<'a> {
    l: L,
    env: c_int,
    count: &'a mut u32,
}

impl Port<'_> {
    /// Pushes graph[method] and the graph, ready for their arguments.
    unsafe fn method(&self, method: &CStr) {
        let api = api();
        (api.getfield)(self.l, self.env, c"graph".as_ptr());
        (api.getfield)(self.l, -1, method.as_ptr());
        (api.pushvalue)(self.l, -2);
        (api.remove)(self.l, -3);
    }

    /// The number the call just made left on the stack (popped).
    unsafe fn number(&self, method: &str) -> f64 {
        let api = api();
        if (api.type_of)(self.l, -1) != TNUMBER {
            raise_owned(self.l, format!("graph:{method} gave no number"));
        }
        let n = (api.tonumber)(self.l, -1);
        (api.settop)(self.l, -2);
        n
    }
}

impl Costs for Port<'_> {
    fn neighbors(&mut self, node: u32, out: &mut Vec<(usize, u32)>) {
        out.clear();
        // SAFETY: called inside step, with the search's environment at env.
        unsafe {
            let api = api();
            self.method(c"Neighbors");
            push_node(self.l, self.env, node);
            (api.call)(self.l, 2, 1);
            if (api.type_of)(self.l, -1) != TTABLE {
                raise(self.l, c"graph:Neighbors gave no list");
            }
            let list = (api.gettop)(self.l);
            let mut i = 1;
            loop {
                (api.rawgeti)(self.l, list, i);
                if (api.type_of)(self.l, -1) == TNIL {
                    (api.settop)(self.l, -2);
                    break;
                }
                let n = number_of(self.l, self.env, -1, self.count);
                (api.settop)(self.l, -2);
                out.push((i as usize - 1, n));
                i += 1;
            }
            (api.settop)(self.l, -2);
        }
    }

    fn cost(&mut self, from: u32, _link: usize, to: u32, so_far: f64) -> f64 {
        // SAFETY: as neighbors.
        unsafe {
            self.method(c"Cost");
            push_node(self.l, self.env, from);
            push_node(self.l, self.env, to);
            (api().pushnumber)(self.l, so_far);
            (api().call)(self.l, 4, 1);
            self.number("Cost")
        }
    }

    fn estimate(&mut self, node: u32) -> f64 {
        // SAFETY: as neighbors.
        unsafe {
            self.method(c"Estimate");
            push_node(self.l, self.env, node);
            (api().getfield)(self.l, self.env, c"goal".as_ptr());
            (api().call)(self.l, 3, 1);
            self.number("Estimate")
        }
    }
}

/// The search at index 1, refused while busy in a step.
unsafe fn search<'a>(l: L) -> &'a mut PathSearch {
    let search = userdata::check::<PathSearch>(l, 1);
    if search.busy {
        raise(l, c"the search is busy in a step (a graph port may not use its own search), or its port raised and spent it");
    }
    search
}

unsafe fn push_status(l: L, status: Status) {
    crate::lua::push_str(
        l,
        match status {
            Status::Running => "running",
            Status::Found => "found",
            Status::Failed => "failed",
        },
    );
}

/// Pushes a new search over the graph at 1 from 2 to 3, capped by 4.
unsafe fn push_search(l: L) {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    if absent(l, 2) || absent(l, 3) {
        raise(l, c"a search needs a start and a goal");
    }
    let max_expanded = if absent(l, 4) { MAX_EXPANDED } else { (api.checknumber)(l, 4) };
    userdata::push(l, PathSearch { astar: None, busy: false, nodes: 0, max_expanded });
    let ud = (api.gettop)(l);
    fresh_environment(l, ud);
    let env = environment(l, ud);
    (api.pushvalue)(l, 1);
    (api.setfield)(l, env, c"graph".as_ptr());
    (api.pushvalue)(l, 3);
    (api.setfield)(l, env, c"goal".as_ptr());
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, env, c"nodes".as_ptr());
    (api.createtable)(l, 0, 0);
    (api.setfield)(l, env, c"index".as_ptr());
    let search = userdata::check::<PathSearch>(l, ud);
    let start = number_of(l, env, 2, &mut search.nodes);
    let goal = number_of(l, env, 3, &mut search.nodes);
    search.busy = true;
    let cap = count(max_expanded);
    let astar = AStar::new(search.nodes as usize, &mut Port { l, env, count: &mut search.nodes }, start, goal, cap);
    search.astar = Some(astar);
    search.busy = false;
    (api.settop)(l, ud);
}

/// graph.pathfinder.New(graph, start, goal[, maxExpanded]) -> a search
unsafe extern "C-unwind" fn new(l: L) -> c_int {
    push_search(l);
    1
}

/// Runs the search at `ud` up to `budget` expansions; its status.
unsafe fn run(l: L, ud: c_int, budget: u32) -> Status {
    let search = userdata::check::<PathSearch>(l, ud);
    if search.busy {
        raise(l, c"the search is busy in a step (a graph port may not use its own search), or its port raised and spent it");
    }
    let env = environment(l, ud);
    search.busy = true;
    let PathSearch { astar, nodes, .. } = search;
    let status = astar.as_mut().map_or(Status::Failed, |astar| astar.step(&mut Port { l, env, count: nodes }, budget));
    search.busy = false;
    (api().settop)(l, env - 1);
    status
}

/// search:Step(budget) -> the status
unsafe extern "C-unwind" fn step(l: L) -> c_int {
    let budget = count((api().checknumber)(l, 2));
    search(l);
    let status = run(l, 1, budget);
    push_status(l, status);
    1
}

/// Pushes the route of the search at `ud` to `last` (a node number, or the
/// closest), as node values.
unsafe fn push_route(l: L, ud: c_int, last: Option<u32>) {
    let api = api();
    let env = environment(l, ud);
    let search = userdata::check::<PathSearch>(l, ud);
    let route = search.astar.as_ref().map(|astar| astar.route(last)).unwrap_or_default();
    (api.createtable)(l, route.len() as c_int, 0);
    for (i, &n) in route.iter().enumerate() {
        push_node(l, env, n);
        (api.rawseti)(l, -2, i as c_int + 1);
    }
    drop(route);
    (api.remove)(l, env);
}

/// search:Route([last]) -> the nodes from the start to last (or the closest)
unsafe extern "C-unwind" fn route(l: L) -> c_int {
    let api = api();
    search(l);
    if absent(l, 2) {
        push_route(l, 1, None);
        return 1;
    }
    let env = environment(l, 1);
    let last = known(l, env, 2);
    (api.settop)(l, env - 1);
    match last {
        Some(n) => push_route(l, 1, Some(n)),
        None => {
            (api.createtable)(l, 1, 0);
            (api.pushvalue)(l, 2);
            (api.rawseti)(l, -2, 1);
        }
    }
    1
}

/// search:CostSoFar(node) -> the cost of its best way yet, or nil
unsafe extern "C-unwind" fn cost_so_far(l: L) -> c_int {
    let api = api();
    let search = search(l);
    let env = environment(l, 1);
    let cost = known(l, env, 2).and_then(|n| search.astar.as_ref()?.cost_so_far(n));
    match cost {
        Some(cost) => (api.pushnumber)(l, cost),
        None => (api.pushnil)(l),
    }
    1
}

/// The search's fields: status, expanded, maxExpanded, start, goal,
/// closest, parent (node -> the node it was reached from); its methods first.
unsafe extern "C-unwind" fn index(l: L) -> c_int {
    let api = api();
    (api.getmetatable)(l, 1);
    (api.pushvalue)(l, 2);
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) != TNIL {
        return 1;
    }
    let Some(key) = string_at(l, 2) else {
        (api.pushnil)(l);
        return 1;
    };
    let search = userdata::check::<PathSearch>(l, 1);
    let Some(astar) = search.astar.as_ref() else {
        (api.pushnil)(l);
        return 1;
    };
    let env = environment(l, 1);
    match key {
        b"status" => push_status(l, astar.status()),
        b"expanded" => (api.pushnumber)(l, astar.expanded() as f64),
        b"maxExpanded" => (api.pushnumber)(l, search.max_expanded),
        b"start" => push_node(l, env, astar.start()),
        b"goal" => push_node(l, env, astar.goal()),
        b"closest" => push_node(l, env, astar.closest()),
        b"parent" => {
            (api.createtable)(l, 0, 0);
            for (node, parent) in astar.parents() {
                push_node(l, env, node);
                push_node(l, env, parent);
                (api.rawset)(l, -3);
            }
        }
        _ => (api.pushnil)(l),
    }
    1
}

/// graph.pathfinder.Find(graph, start, goal[, maxExpanded]) -> the route to
/// the goal or nil, and the route to the node that came closest
unsafe extern "C-unwind" fn find(l: L) -> c_int {
    let api = api();
    push_search(l);
    let ud = (api.gettop)(l);
    let budget = count(userdata::check::<PathSearch>(l, ud).max_expanded + 1.0);
    while run(l, ud, budget) == Status::Running {}
    let found = userdata::check::<PathSearch>(l, ud).astar.as_ref().map(AStar::status) == Some(Status::Found);
    push_route(l, ud, None);
    if found {
        (api.pushvalue)(l, -1);
    } else {
        (api.pushnil)(l);
        (api.pushvalue)(l, -2);
    }
    2
}

/// Pushes the graph.pathfinder module table.
pub unsafe fn push_module(l: L) {
    let api = api();
    (api.createtable)(l, 0, 7);
    set_function(l, c"New", new);
    set_function(l, c"Find", find);
    for (name, value) in [(c"RUNNING", "running"), (c"FOUND", "found"), (c"FAILED", "failed")] {
        crate::lua::push_str(l, value);
        (api.setfield)(l, -2, name.as_ptr());
    }
    (api.pushnumber)(l, MAX_EXPANDED);
    (api.setfield)(l, -2, c"MAX_EXPANDED".as_ptr());
    (api.pushnumber)(l, NAN_COST);
    (api.setfield)(l, -2, c"NAN_COST".as_ptr());
}
