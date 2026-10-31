//! Weighted directed graphs and the paths across them: the shortest-path
//! tree from a set of starts, paths read off it, alternative paths by the
//! penalty method, each node's ground within a reach, a tree's branch
//! weights and forks, and maximum coverage by paths along a tree.
//!
//! Nodes are 0..n; a step goes one way at a cost, and a node's steps keep
//! the order they were added, which breaks ties. The walks are
//! `.devtools/bin/incursion.py`'s, step for step: Dijkstra with ties to the
//! earlier start and then the earlier push.

use std::cmp::{Ordering, Reverse};
use std::collections::{BinaryHeap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Step {
    pub to: u32,
    pub cost: f64,
}

#[derive(Debug, PartialEq)]
pub enum PathsError {
    /// A step names a node the graph does not have.
    NoSuchNode { node: u32, nodes: u32 },
    /// A cost below zero, or not a number.
    BadCost { from: u32, to: u32 },
}

impl std::fmt::Display for PathsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PathsError::NoSuchNode { node, nodes } => write!(f, "node {node} of a graph of {nodes} nodes"),
            PathsError::BadCost { from, to } => write!(f, "the step from {from} to {to} costs less than nothing"),
        }
    }
}

/// A heap entry: lowest cost first, then the earliest pushed.
#[derive(PartialEq)]
struct Entry(f64, u64, u32);

impl Eq for Entry {}

impl PartialOrd for Entry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Entry {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.total_cmp(&other.0).then(self.1.cmp(&other.1))
    }
}

pub struct Paths {
    steps: Vec<Vec<Step>>,
}

/// A walk from a set of starts: each node's distance (infinite when
/// unreached) and the node before it.
#[derive(Clone, Debug)]
pub struct Tree {
    pub distance: Vec<f64>,
    pub parent: Vec<Option<u32>>,
}

/// A path and its length (its own steps' costs).
#[derive(Clone, Debug, PartialEq)]
pub struct Route {
    pub nodes: Vec<u32>,
    pub length: f64,
}

/// A tree's branches: each reached node's children (ascending) and the
/// floor of it and everything reached through it.
#[derive(Clone, Debug)]
pub struct Branches {
    pub children: Vec<Vec<u32>>,
    pub weight: Vec<f64>,
    pub roots: Vec<u32>,
}

/// A path chosen for coverage, and the floor it adds.
#[derive(Clone, Debug, PartialEq)]
pub struct Breach {
    pub nodes: Vec<u32>,
    pub gain: f64,
}

impl Paths {
    pub fn new(nodes: u32) -> Paths {
        Paths { steps: vec![Vec::new(); nodes as usize] }
    }

    pub fn nodes(&self) -> u32 {
        self.steps.len() as u32
    }

    /// Adds a step from one node to another at a cost, one way.
    pub fn step(&mut self, from: u32, to: u32, cost: f64) -> Result<(), PathsError> {
        let nodes = self.nodes();
        for node in [from, to] {
            if node >= nodes {
                return Err(PathsError::NoSuchNode { node, nodes });
            }
        }
        if !(cost >= 0.0) {
            return Err(PathsError::BadCost { from, to });
        }
        self.steps[from as usize].push(Step { to, cost });
        Ok(())
    }

    pub fn steps(&self, node: u32) -> &[Step] {
        &self.steps[node as usize]
    }

    /// The walk from the starts, each step costing weight(from, step).
    pub fn tree_by(&self, starts: &[u32], weight: impl Fn(u32, &Step) -> f64) -> Tree {
        let n = self.steps.len();
        let mut distance = vec![f64::INFINITY; n];
        let mut parent = vec![None; n];
        let mut heap = BinaryHeap::new();
        let mut order = 0u64;
        for &s in starts {
            if distance[s as usize] > 0.0 {
                distance[s as usize] = 0.0;
            }
            heap.push(Reverse(Entry(0.0, order, s)));
            order += 1;
        }
        while let Some(Reverse(Entry(d, _, node))) = heap.pop() {
            if d > distance[node as usize] {
                continue;
            }
            for step in &self.steps[node as usize] {
                let nd = d + weight(node, step);
                if nd < distance[step.to as usize] {
                    distance[step.to as usize] = nd;
                    parent[step.to as usize] = Some(node);
                    heap.push(Reverse(Entry(nd, order, step.to)));
                    order += 1;
                }
            }
        }
        Tree { distance, parent }
    }

    /// The walk from the starts at the steps' own costs.
    pub fn tree(&self, starts: &[u32]) -> Tree {
        self.tree_by(starts, |_, step| step.cost)
    }

    /// A path's own length, step by step (the cheapest step between each
    /// pair); None when two of its nodes are not joined.
    pub fn length(&self, path: &[u32]) -> Option<f64> {
        let mut total = 0.0;
        for pair in path.windows(2) {
            let cheapest = self.steps[pair[0] as usize]
                .iter()
                .filter(|s| s.to == pair[1])
                .map(|s| s.cost)
                .fold(f64::INFINITY, f64::min);
            if cheapest.is_infinite() {
                return None;
            }
            total += cheapest;
        }
        Some(total)
    }

    /// The paths from the starts to target: the shortest, then each found by
    /// walking again with the nodes the paths before it took made `penalty`
    /// times as costly to step into, kept while it is a new path and no more
    /// than `detour` (a share) longer than the shortest, up to `k` in all.
    pub fn alternatives(&self, starts: &[u32], target: u32, k: usize, detour: f64, penalty: f64) -> Vec<Route> {
        let first = self.tree(starts);
        let Some(path) = first.path(target) else { return Vec::new() };
        let mut routes = vec![Route { nodes: path, length: first.distance[target as usize] }];
        let ends: HashSet<u32> = starts.iter().copied().chain([target]).collect();
        let mut taken: HashSet<u32> = routes[0].nodes.iter().copied().filter(|n| !ends.contains(n)).collect();
        while routes.len() < k {
            let walk = self.tree_by(starts, |_, s| if taken.contains(&s.to) { s.cost * penalty } else { s.cost });
            let Some(path) = walk.path(target) else { break };
            let length = self.length(&path).unwrap_or(f64::INFINITY);
            if routes.iter().any(|r| r.nodes == path) || length > (1.0 + detour) * routes[0].length {
                break;
            }
            taken.extend(path.iter().copied().filter(|n| !ends.contains(n)));
            routes.push(Route { nodes: path, length });
        }
        routes
    }

    /// Each node's ground: the nodes its walk reaches within reach, itself
    /// included, ascending.
    pub fn near(&self, reach: f64) -> Vec<Vec<u32>> {
        (0..self.nodes())
            .map(|node| {
                let mut distance = std::collections::HashMap::from([(node, 0.0f64)]);
                let mut heap = BinaryHeap::from([Reverse(Entry(0.0, 0, node))]);
                let mut order = 1u64;
                while let Some(Reverse(Entry(d, _, at))) = heap.pop() {
                    if d > distance[&at] {
                        continue;
                    }
                    for step in &self.steps[at as usize] {
                        let nd = d + step.cost;
                        if nd <= reach && nd < *distance.get(&step.to).unwrap_or(&f64::INFINITY) {
                            distance.insert(step.to, nd);
                            heap.push(Reverse(Entry(nd, order, step.to)));
                            order += 1;
                        }
                    }
                }
                let mut ground: Vec<u32> = distance.into_keys().collect();
                ground.sort_unstable();
                ground
            })
            .collect()
    }
}

impl Tree {
    pub fn reached(&self, node: u32) -> bool {
        self.distance[node as usize].is_finite()
    }

    /// The path from a start to end, start first; None if the walk never
    /// reached it.
    pub fn path(&self, end: u32) -> Option<Vec<u32>> {
        if !self.reached(end) {
            return None;
        }
        let mut path = vec![end];
        while let Some(up) = self.parent[*path.last().unwrap() as usize] {
            path.push(up);
        }
        path.reverse();
        Some(path)
    }

    /// The branches, weighted by floor (one a node).
    pub fn branches(&self, floor: &[f64]) -> Branches {
        let n = self.distance.len();
        let mut reached: Vec<u32> = (0..n as u32).filter(|&a| self.reached(a)).collect();
        reached.sort_by(|&a, &b| self.distance[a as usize].total_cmp(&self.distance[b as usize]).then(a.cmp(&b)));
        let mut children = vec![Vec::new(); n];
        for &a in &reached {
            if let Some(p) = self.parent[a as usize] {
                children[p as usize].push(a);
            }
        }
        for kids in children.iter_mut() {
            kids.sort_unstable();
        }
        let mut weight = vec![0.0; n];
        for &a in reached.iter().rev() {
            weight[a as usize] = floor[a as usize] + children[a as usize].iter().map(|&k| weight[k as usize]).sum::<f64>();
        }
        let mut roots: Vec<u32> = reached.iter().copied().filter(|&a| self.parent[a as usize].is_none()).collect();
        roots.sort_unstable();
        Branches { children, weight, roots }
    }
}

impl Branches {
    fn total(&self) -> f64 {
        self.roots.iter().map(|&r| self.weight[r as usize]).sum()
    }

    /// The nodes where a branch splits into ways each carrying at least
    /// share of the tree's floor, ascending.
    pub fn forks(&self, share: f64) -> Vec<u32> {
        let floor = share * self.total();
        (0..self.children.len() as u32)
            .filter(|&a| self.children[a as usize].iter().filter(|&&k| self.weight[k as usize] >= floor).count() >= 2)
            .collect()
    }

    /// The fewest paths from the roots, along the tree to a leaf, covering at
    /// least cover (a share) of the floor it reaches, the one covering most
    /// first. A path covers its nodes and, given near, the ground within
    /// reach of them; paths are taken greedily by the floor each adds,
    /// lazily, a tie to the lesser path.
    pub fn cover(&self, tree: &Tree, cover: f64, near: Option<&[Vec<u32>]>) -> Vec<Breach> {
        let n = self.children.len();
        let own: Vec<f64> = (0..n)
            .map(|a| self.weight[a] - self.children[a].iter().map(|&k| self.weight[k as usize]).sum::<f64>())
            .collect();
        let reached = |a: u32| tree.reached(a);
        let total: f64 = (0..n as u32).filter(|&a| reached(a)).map(|a| own[a as usize]).sum();
        let leaves: Vec<u32> = (0..n as u32).filter(|&a| reached(a) && self.children[a as usize].is_empty()).collect();
        let candidates: Vec<Vec<u32>> = leaves.iter().map(|&leaf| tree.path(leaf).unwrap()).collect();
        let ground: Vec<Vec<u32>> = candidates
            .iter()
            .map(|path| {
                let mut g: Vec<u32> = match near {
                    Some(near) => path.iter().flat_map(|&a| near[a as usize].iter().copied()).filter(|&a| reached(a)).collect(),
                    None => path.clone(),
                };
                g.sort_unstable();
                g.dedup();
                g
            })
            .collect();
        let mut covered = vec![false; n];
        let gain = |i: usize, covered: &[bool]| ground[i].iter().filter(|&&a| !covered[a as usize]).map(|&a| own[a as usize]).sum::<f64>();
        // lazy greedy: (gain, the path, reversed so the lesser path wins a tie)
        let mut heap: BinaryHeap<(OrdF64, Reverse<Vec<u32>>, usize)> = (0..candidates.len())
            .map(|i| (OrdF64(gain(i, &covered)), Reverse(candidates[i].clone()), i))
            .collect();
        let (mut chosen, mut gained) = (Vec::new(), 0.0);
        while gained < cover * total {
            let Some((_, path, i)) = heap.pop() else { break };
            let now = gain(i, &covered);
            if let Some((top, _, _)) = heap.peek() {
                if now < top.0 {
                    heap.push((OrdF64(now), path, i));
                    continue;
                }
            }
            if now <= 0.0 {
                break;
            }
            for &a in &ground[i] {
                covered[a as usize] = true;
            }
            gained += now;
            chosen.push(Breach { nodes: path.0, gain: now });
        }
        chosen
    }
}

#[derive(Clone, Copy, PartialEq)]
struct OrdF64(f64);

impl Eq for OrdF64 {}

impl PartialOrd for OrdF64 {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for OrdF64 {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.total_cmp(&other.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CELL: f64 = 100.0;

    /// Nodes 0..n in a row, each joined both ways to the next, a cell apart.
    fn line(n: u32) -> Paths {
        let mut g = Paths::new(n);
        for i in 0..n - 1 {
            g.step(i, i + 1, CELL).unwrap();
            g.step(i + 1, i, CELL).unwrap();
        }
        g
    }

    #[test]
    fn the_walk_is_from_the_nearest_start() {
        let g = line(5);
        assert_eq!(g.tree(&[0]).distance[4], 4.0 * CELL);
        assert_eq!(g.tree(&[0, 3]).distance[4], CELL);
    }

    #[test]
    fn a_path_runs_from_the_start_to_the_node_or_is_none() {
        let mut g = Paths::new(6);
        for i in 0..4 {
            g.step(i, i + 1, CELL).unwrap();
        }
        let tree = g.tree(&[0]);
        assert_eq!(tree.path(3), Some(vec![0, 1, 2, 3]));
        assert_eq!(tree.path(5), None, "never reached");
    }

    #[test]
    fn a_step_goes_one_way() {
        let mut g = line(5);
        g.step(0, 4, CELL).unwrap(); // a drop from 0 straight to 4
        assert_eq!(g.tree(&[0]).path(4), Some(vec![0, 4]));
        assert_eq!(g.tree(&[4]).path(0), Some(vec![4, 3, 2, 1, 0]), "no climbing the drop");
    }

    #[test]
    fn steps_out_of_the_graph_or_costing_less_than_nothing_are_refused() {
        let mut g = Paths::new(2);
        assert_eq!(g.step(0, 2, 1.0), Err(PathsError::NoSuchNode { node: 2, nodes: 2 }));
        assert_eq!(g.step(0, 1, -1.0), Err(PathsError::BadCost { from: 0, to: 1 }));
        assert_eq!(g.step(0, 1, f64::NAN), Err(PathsError::BadCost { from: 0, to: 1 }));
    }

    /// Starts 0 and 1 joined straight through 2 (two cells each side), and by
    /// detours: a node each, making the way that much longer.
    fn ways(detours: &[f64]) -> Paths {
        let mut g = Paths::new(3 + detours.len() as u32);
        let half = 5.0 * CELL;
        for (a, b) in [(0, 2), (2, 1)] {
            g.step(a, b, half).unwrap();
            g.step(b, a, half).unwrap();
        }
        for (i, d) in detours.iter().enumerate() {
            let node = 3 + i as u32;
            for (a, b) in [(0, node), (node, 1)] {
                g.step(a, b, half * (1.0 + d)).unwrap();
                g.step(b, a, half * (1.0 + d)).unwrap();
            }
        }
        g
    }

    #[test]
    fn a_way_a_little_longer_is_an_alternative() {
        let routes = ways(&[0.2]).alternatives(&[0], 1, 4, 0.5, 3.0);
        assert_eq!(routes.iter().map(|r| r.nodes.clone()).collect::<Vec<_>>(), vec![vec![0, 2, 1], vec![0, 3, 1]]);
        assert!((routes[1].length - 10.0 * CELL * 1.2).abs() < 1e-9, "its own length, not the penalised");
    }

    #[test]
    fn a_way_far_longer_is_none_and_no_more_than_k() {
        assert_eq!(ways(&[0.7]).alternatives(&[0], 1, 4, 0.5, 3.0).len(), 1);
        assert_eq!(ways(&[0.1; 6]).alternatives(&[0], 1, 4, 0.5, 3.0).len(), 4);
    }

    /// 0 the spawn, 1 a hall, from it two ways: 2-3 and 4.
    fn fork() -> Paths {
        let mut g = Paths::new(5);
        for (a, b) in [(0, 1), (1, 2), (2, 3), (1, 4)] {
            g.step(a, b, CELL).unwrap();
            g.step(b, a, CELL).unwrap();
        }
        g
    }

    #[test]
    fn a_branch_weighs_the_floor_reached_through_it() {
        let tree = fork().tree(&[0]);
        let b = tree.branches(&[1.0; 5]);
        assert_eq!(b.children[1], vec![2, 4]);
        assert_eq!((b.weight[0], b.weight[1], b.weight[2], b.weight[4]), (5.0, 4.0, 2.0, 1.0));
        assert_eq!(b.roots, vec![0]);
    }

    #[test]
    fn each_start_is_a_root_and_ties_go_to_the_earlier() {
        let tree = line(5).tree(&[0, 4]);
        let b = tree.branches(&[1.0; 5]);
        assert_eq!(b.roots, vec![0, 4]);
        assert_eq!((b.weight[0], b.weight[4]), (3.0, 2.0), "the middle to the earlier start");
    }

    #[test]
    fn forks_split_into_ways_of_a_share() {
        let tree = fork().tree(&[0]);
        let b = tree.branches(&[1.0; 5]);
        assert_eq!(b.forks(0.2), vec![1]);
        assert_eq!(b.forks(0.3), Vec::<u32>::new());
    }

    #[test]
    fn the_fewest_paths_covering_the_share_the_most_first_each_counting_what_it_adds() {
        let tree = fork().tree(&[0]);
        let b = tree.branches(&[1.0; 5]);
        let all = b.cover(&tree, 1.0, None);
        assert_eq!(all, vec![Breach { nodes: vec![0, 1, 2, 3], gain: 4.0 }, Breach { nodes: vec![0, 1, 4], gain: 1.0 }]);
        assert_eq!(b.cover(&tree, 0.8, None).len(), 1);
    }

    #[test]
    fn ground_within_reach_of_a_path_is_covered_by_it() {
        let g = fork();
        let tree = g.tree(&[0]);
        let b = tree.branches(&[1.0; 5]);
        let near = g.near(CELL);
        let found = b.cover(&tree, 1.0, Some(&near));
        assert_eq!(found, vec![Breach { nodes: vec![0, 1, 2, 3], gain: 5.0 }], "4 lies within reach of 1");
    }

    #[test]
    fn near_is_the_ground_within_reach_itself_included() {
        assert_eq!(line(5).near(CELL)[2], vec![1, 2, 3]);
        assert_eq!(line(5).near(0.0)[2], vec![2]);
    }
}
