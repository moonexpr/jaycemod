//! NavAreaBuildPath's A* (nav_pathfind.h) over a graph and its prices, both
//! the caller's `Costs`, a few expansions at a time: foundation's Lua
//! `graph.pathfinder` rule for rule, so the same costs give the same route,
//! the same expansions, the same closest node. Nodes are whole numbers from
//! 0; the search's tables grow to the highest it meets.
//!
//! - The open list is ordered by total cost, then by push order: a node
//!   opened or cheapened goes after every node of equal cost.
//! - A step's cost is raised to just above its parent's, so every step costs.
//! - A NaN cost counts as enormous (NAN_COST), a negative one as a dead end.
//! - A closed node reached more cheaply is opened again.
//! - A node expands its neighbours in the graph's order, skipping its parent.

use crate::heap::Heap;

pub const NAN_COST: f64 = 1e30;
const MIN_STEP_SCALE: f64 = 1.00001;
const MIN_STEP_ADD: f64 = 0.00001;
const NONE: u32 = u32::MAX;

/// What a search asks of its caller.
pub trait Costs {
    /// Writes `node`'s neighbours to `out` (emptied first), in the order the
    /// search expands them, each with the number of the link reaching it.
    fn neighbors(&mut self, node: u32, out: &mut Vec<(usize, u32)>);
    /// The total cost of reaching `to` from `from` over `link`, `so_far`
    /// having been spent reaching `from`: negative for no way through.
    fn cost(&mut self, from: u32, link: usize, to: u32, so_far: f64) -> f64;
    /// The straight-line cost left from `node` to the goal.
    fn estimate(&mut self, node: u32) -> f64;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    Running,
    Found,
    Failed,
}

pub struct AStar {
    start: u32,
    goal: u32,
    max_expanded: u32,
    expanded: u32,
    status: Status,
    closest: u32,
    closest_distance: Option<f64>,
    so_far: Vec<f64>,
    parent: Vec<u32>,
    live: Vec<u64>,
    closed: Vec<bool>,
    open: Heap,
    links: Vec<(usize, u32)>,
}

impl AStar {
    /// A search from `start` to `goal`, its frontier opened at the start.
    /// `nodes` is how many to make room for at once (more are made as met).
    pub fn new(nodes: usize, costs: &mut impl Costs, start: u32, goal: u32, max_expanded: u32) -> Self {
        let nodes = nodes.max(start.max(goal) as usize + 1);
        let mut search = AStar {
            start,
            goal,
            max_expanded,
            expanded: 0,
            status: Status::Running,
            closest: start,
            closest_distance: None,
            so_far: vec![f64::NAN; nodes],
            parent: vec![NONE; nodes],
            live: vec![0; nodes],
            closed: vec![false; nodes],
            open: Heap::default(),
            links: Vec::new(),
        };
        if start == goal {
            search.status = Status::Found;
            return search;
        }
        search.so_far[start as usize] = 0.0;
        let estimate = costs.estimate(start);
        search.approach(start, estimate);
        search.open(start, estimate);
        search
    }

    /// Makes room for `node` in the per-node tables.
    fn meet(&mut self, node: u32) {
        let need = node as usize + 1;
        if need > self.so_far.len() {
            self.so_far.resize(need, f64::NAN);
            self.parent.resize(need, NONE);
            self.live.resize(need, 0);
            self.closed.resize(need, false);
        }
    }

    fn approach(&mut self, node: u32, distance: f64) {
        if self.closest_distance.is_none_or(|closest| distance < closest) {
            self.closest = node;
            self.closest_distance = Some(distance);
        }
    }

    fn open(&mut self, node: u32, total: f64) {
        self.live[node as usize] = self.open.push(total, node as f64);
    }

    /// The next live entry's node: an entry superseded by a cheaper push of
    /// its node is skipped.
    fn next(&mut self) -> Option<u32> {
        while let Some((value, _, seq)) = self.open.pop_entry() {
            let node = value as u32;
            if self.live[node as usize] == seq {
                self.live[node as usize] = 0;
                return Some(node);
            }
        }
        None
    }

    fn relax(&mut self, costs: &mut impl Costs, node: u32, link: usize, next: u32) {
        self.meet(next);
        let so_far = self.so_far[node as usize];
        let mut cost = costs.cost(node, link, next, so_far);
        if cost.is_nan() {
            cost = NAN_COST;
        }
        if cost < 0.0 {
            return;
        }
        let floor = so_far * MIN_STEP_SCALE + MIN_STEP_ADD;
        if cost < floor {
            cost = floor;
        }
        let n = next as usize;
        let known = self.live[n] != 0 || self.closed[n];
        if known && self.so_far[n] <= cost {
            return;
        }
        let remaining = costs.estimate(next);
        self.approach(next, remaining);
        self.so_far[n] = cost;
        self.closed[n] = false;
        self.parent[n] = node;
        self.open(next, cost + remaining);
    }

    fn expand(&mut self, costs: &mut impl Costs, node: u32) {
        let parent = self.parent[node as usize];
        costs.neighbors(node, &mut self.links);
        for i in 0..self.links.len() {
            let (link, next) = self.links[i];
            if next != parent && next != node {
                self.relax(costs, node, link, next);
            }
        }
        self.closed[node as usize] = true;
    }

    /// Runs up to `budget` expansions and returns the status.
    pub fn step(&mut self, costs: &mut impl Costs, mut budget: u32) -> Status {
        while self.status == Status::Running && budget > 0 {
            match self.next() {
                None => self.status = Status::Failed,
                Some(node) if node == self.goal => {
                    self.closest = node;
                    self.status = Status::Found;
                }
                Some(_) if self.expanded >= self.max_expanded => self.status = Status::Failed,
                Some(node) => {
                    self.expanded += 1;
                    budget -= 1;
                    self.expand(costs, node);
                }
            }
        }
        self.status
    }

    /// The nodes from the start to `last` (default: the goal once found,
    /// else the node that came closest), both included.
    pub fn route(&self, last: Option<u32>) -> Vec<u32> {
        let mut node = last.unwrap_or(self.closest);
        let mut route = vec![node];
        while let Some(parent) = self.parent(node) {
            node = parent;
            route.push(node);
        }
        route.reverse();
        route
    }

    pub fn status(&self) -> Status {
        self.status
    }

    pub fn expanded(&self) -> u32 {
        self.expanded
    }

    pub fn max_expanded(&self) -> u32 {
        self.max_expanded
    }

    pub fn start(&self) -> u32 {
        self.start
    }

    pub fn goal(&self) -> u32 {
        self.goal
    }

    pub fn closest(&self) -> u32 {
        self.closest
    }

    /// The node `node` was reached from by its best way, or None.
    pub fn parent(&self, node: u32) -> Option<u32> {
        let parent = *self.parent.get(node as usize)?;
        (parent != NONE).then_some(parent)
    }

    /// Every node reached from another, with the node it was reached from.
    pub fn parents(&self) -> impl Iterator<Item = (u32, u32)> + '_ {
        self.parent.iter().enumerate().filter(|(_, &p)| p != NONE).map(|(node, &p)| (node as u32, p))
    }

    /// What reaching `node` cost by its best way, or None if never reached.
    pub fn cost_so_far(&self, node: u32) -> Option<f64> {
        let cost = *self.so_far.get(node as usize)?;
        (!cost.is_nan()).then_some(cost)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graph::{Builder, Graph};
    use std::collections::HashMap;

    type Price = Box<dyn Fn(&str, &str, f64) -> Option<f64>>;
    type Estimate = Box<dyn Fn(&str) -> f64>;

    /// Named nodes at 2D positions, edges both ways; a step costs its length
    /// unless `price` says otherwise; the estimate is the straight line.
    struct Plane {
        names: Vec<&'static str>,
        at: Vec<(f64, f64)>,
        graph: Graph,
        blocked: Vec<(&'static str, &'static str)>,
        goal: u32,
        price: Option<Price>,
        estimate: Option<Estimate>,
    }

    impl Plane {
        fn new(nodes: &[(&'static str, f64, f64)], edges: &[(&'static str, &'static str)]) -> Self {
            let names: Vec<_> = nodes.iter().map(|n| n.0).collect();
            Self::ordered(nodes, &Self::both_ways(&names, edges))
        }

        fn both_ways(names: &[&'static str], edges: &[(&'static str, &'static str)]) -> HashMap<&'static str, Vec<&'static str>> {
            let mut adjacent: HashMap<_, Vec<_>> = names.iter().map(|&n| (n, vec![])).collect();
            for &(a, b) in edges {
                adjacent.get_mut(a).unwrap().push(b);
                adjacent.get_mut(b).unwrap().push(a);
            }
            adjacent
        }

        fn ordered(nodes: &[(&'static str, f64, f64)], adjacent: &HashMap<&'static str, Vec<&'static str>>) -> Self {
            let names: Vec<_> = nodes.iter().map(|n| n.0).collect();
            let index = |name: &str| names.iter().position(|&n| n == name).unwrap() as u32;
            let mut b = Builder::default();
            for &name in &names {
                b.node();
                for to in &adjacent[name] {
                    b.link(index(to)).unwrap();
                }
            }
            Plane {
                at: nodes.iter().map(|n| (n.1, n.2)).collect(),
                graph: b.finish().unwrap(),
                names,
                blocked: vec![],
                goal: 0,
                price: None,
                estimate: None,
            }
        }

        fn id(&self, name: &str) -> u32 {
            self.names.iter().position(|&n| n == name).unwrap() as u32
        }

        fn distance(&self, a: u32, b: u32) -> f64 {
            let (p, q) = (self.at[a as usize], self.at[b as usize]);
            ((p.0 - q.0).powi(2) + (p.1 - q.1).powi(2)).sqrt()
        }

        fn search(&mut self, start: &str, goal: &str, max: u32) -> AStar {
            let (start, goal) = (self.id(start), self.id(goal));
            self.goal = goal;
            let mut search = AStar::new(self.graph.nodes() as usize, self, start, goal, max);
            while search.step(self, max + 1) == Status::Running {}
            search
        }

        fn find(&mut self, start: &str, goal: &str) -> (Option<String>, String) {
            let search = self.search(start, goal, 4000);
            let route = self.joined(&search.route(None));
            (if search.status() == Status::Found { Some(route.clone()) } else { None }, route)
        }

        fn joined(&self, route: &[u32]) -> String {
            route.iter().map(|&n| self.names[n as usize]).collect::<Vec<_>>().join(" ")
        }
    }

    impl Costs for Plane {
        fn neighbors(&mut self, node: u32, out: &mut Vec<(usize, u32)>) {
            out.clear();
            out.extend(self.graph.links_of(node).map(|link| (link, self.graph.target(link))));
        }

        fn cost(&mut self, from: u32, _link: usize, to: u32, so_far: f64) -> f64 {
            let (a, b) = (self.names[from as usize], self.names[to as usize]);
            if let Some(price) = &self.price {
                if let Some(cost) = price(a, b, so_far) {
                    return cost;
                }
            }
            if self.blocked.iter().any(|&(x, y)| (x, y) == (a, b) || (x, y) == (b, a)) {
                return -1.0;
            }
            so_far + self.distance(from, to)
        }

        fn estimate(&mut self, node: u32) -> f64 {
            match &self.estimate {
                Some(estimate) => estimate(self.names[node as usize]),
                None => self.distance(node, self.goal),
            }
        }
    }

    //  a - b - c
    //  |       |
    //  d - e - f
    fn ring() -> Plane {
        Plane::new(
            &[("a", 0.0, 0.0), ("b", 1.0, 0.0), ("c", 2.0, 0.0), ("d", 0.0, 1.0), ("e", 1.0, 1.0), ("f", 2.0, 1.0)],
            &[("a", "b"), ("b", "c"), ("a", "d"), ("d", "e"), ("e", "f"), ("c", "f")],
        )
    }

    #[test]
    fn the_route_runs_along_the_cheapest_edges() {
        let mut plane = ring();
        assert_eq!(plane.find("a", "c").0.as_deref(), Some("a b c"));
        assert_eq!(plane.find("d", "f").0.as_deref(), Some("d e f"));
    }

    #[test]
    fn an_impassable_edge_sends_the_route_the_long_way_round() {
        let mut plane = ring();
        plane.blocked = vec![("b", "c")];
        assert_eq!(plane.find("a", "c").0.as_deref(), Some("a d e f c"));
    }

    #[test]
    fn a_start_that_is_the_goal_is_a_route_of_one_node() {
        let mut plane = ring();
        let search = plane.search("e", "e", 4000);
        assert_eq!(search.status(), Status::Found);
        assert_eq!(search.expanded(), 0);
        assert_eq!(plane.joined(&search.route(None)), "e");
    }

    #[test]
    fn no_route_when_the_goal_cannot_be_reached_but_the_closest_one() {
        let mut plane = ring();
        plane.blocked = vec![("b", "c"), ("e", "f")];
        assert_eq!(plane.find("a", "c"), (None, "a b".to_string()));
    }

    #[test]
    fn a_found_route_is_its_own_closest_route() {
        let (route, closest) = ring().find("a", "c");
        assert_eq!(route, Some(closest));
    }

    #[test]
    fn a_search_that_expands_more_nodes_than_its_limit_gives_up() {
        let nodes: Vec<_> = (1..=50).map(|i| (&*Box::leak(format!("n{i}").into_boxed_str()), i as f64, 0.0)).collect();
        let edges: Vec<_> = nodes.windows(2).map(|w| (w[0].0, w[1].0)).collect();
        let mut plane = Plane::new(&nodes, &edges);
        assert_eq!(plane.search("n1", "n50", 10).status(), Status::Failed);
        let search = plane.search("n1", "n50", 100);
        assert_eq!(search.status(), Status::Found);
        assert_eq!(search.route(None).len(), 50);
    }

    #[test]
    fn a_cheaper_way_to_a_node_found_later_replaces_the_first() {
        let mut plane = Plane::new(
            &[("s", 0.0, 0.0), ("x", 1.0, 0.0), ("m", 2.0, 0.0), ("g", 3.0, 0.0)],
            &[("s", "m"), ("s", "x"), ("x", "m"), ("m", "g")],
        );
        plane.price = Some(Box::new(|a, b, so_far| ((a, b) == ("s", "m")).then_some(so_far + 10.0)));
        assert_eq!(plane.find("s", "g").0.as_deref(), Some("s x m g"));
    }

    #[test]
    fn equal_routes_go_by_the_neighbour_listed_first() {
        //  a - b
        //  |   |
        //  c - d
        let nodes = [("a", 0.0, 0.0), ("b", 1.0, 0.0), ("c", 0.0, 1.0), ("d", 1.0, 1.0)];
        let edges = [("a", "b"), ("a", "c"), ("b", "d"), ("c", "d")];
        assert_eq!(Plane::new(&nodes, &edges).find("a", "d").0.as_deref(), Some("a b d"));
        let mut adjacent = Plane::both_ways(&["a", "b", "c", "d"], &edges);
        adjacent.insert("a", vec!["c", "b"]);
        assert_eq!(Plane::ordered(&nodes, &adjacent).find("a", "d").0.as_deref(), Some("a c d"));
    }

    #[test]
    fn a_search_run_a_few_expansions_at_a_time_finds_what_one_run_does() {
        let mut plane = ring();
        plane.blocked = vec![("b", "c")];
        let (start, goal) = (plane.id("a"), plane.id("c"));
        plane.goal = goal;
        let mut search = AStar::new(plane.graph.nodes() as usize, &mut plane, start, goal, 4000);
        let mut steps = 0;
        while search.step(&mut plane, 1) == Status::Running {
            steps += 1;
        }
        assert_eq!(search.status(), Status::Found);
        assert_eq!(plane.joined(&search.route(None)), "a d e f c");
        assert!(steps > 2);
    }

    #[test]
    fn a_cost_below_the_parents_is_raised_just_above_it() {
        let mut plane = Plane::new(&[("s", 0.0, 0.0), ("m", 1.0, 0.0), ("g", 2.0, 0.0)], &[("s", "m"), ("m", "g")]);
        plane.price = Some(Box::new(|_, b, so_far| Some(if b == "m" { 10.0 } else { so_far - 5.0 })));
        let search = plane.search("s", "g", 10);
        assert_eq!(search.status(), Status::Found);
        let g = plane.id("g");
        assert!((search.cost_so_far(g).unwrap() - (10.0 * 1.00001 + 0.00001)).abs() < 1e-9);
    }

    #[test]
    fn a_closed_node_reached_more_cheaply_is_opened_again() {
        let mut plane = Plane::new(
            &[("s", 0.0, 0.0), ("x", 1.0, 0.0), ("y", 2.0, 0.0), ("g", 3.0, 0.0)],
            &[("s", "x"), ("s", "y"), ("x", "y"), ("y", "g")],
        );
        plane.price = Some(Box::new(|a, b, so_far| {
            let edge = |p: &str, q: &str| (a, b) == (p, q) || (a, b) == (q, p);
            let step = if edge("s", "x") { 1.0 } else if edge("s", "y") { 10.0 } else if edge("x", "y") { 1.0 } else { 100.0 };
            Some(so_far + step)
        }));
        plane.estimate = Some(Box::new(|node| if node == "x" { 50.0 } else { 0.0 }));
        assert_eq!(plane.find("s", "g").0.as_deref(), Some("s x y g"));
    }

    #[test]
    fn a_cost_that_is_not_a_number_counts_as_enormous() {
        let mut plane = ring();
        plane.price = Some(Box::new(|a, b, so_far| Some(if (a, b) == ("b", "c") { f64::NAN } else { so_far + 1.0 })));
        assert_eq!(plane.find("a", "c").0.as_deref(), Some("a d e f c"));
    }
}
