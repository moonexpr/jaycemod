//! Nearest-neighbour searches over points on a spatial hash of the ground
//! plane: foundation's nodegraph pair searches (`Candidates`, `Bridges`) and
//! its spaced node pick (`PickNodes`), in the Lua twin's arithmetic and
//! order, ties included.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

pub type Point = [f64; 3];

/// A pair of points by index (a < b) and the distance between them.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pair {
    pub a: usize,
    pub b: usize,
    pub distance: f64,
}

/// The Lua twin's Distance: the same operations in the same order, so the
/// same double.
pub fn distance(p: &Point, q: &Point) -> f64 {
    let (dx, dy, dz) = (p[0] - q[0], p[1] - q[1], p[2] - q[2]);
    (dx * dx + dy * dy + dz * dz).sqrt()
}

/// A cell's hash: one multiply-and-rotate a word (FxHash's), since a cell
/// key is two integers that need no defence against chosen collisions.
#[derive(Default)]
struct CellHasher(u64);

impl Hasher for CellHasher {
    fn write(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.write_u64(byte as u64);
        }
    }

    fn write_i64(&mut self, word: i64) {
        self.write_u64(word as u64);
    }

    fn write_u64(&mut self, word: u64) {
        self.0 = (self.0.rotate_left(5) ^ word).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    }

    fn finish(&self) -> u64 {
        self.0
    }
}

/// Indexes bucketed by the square cell of the ground plane under them, as
/// world.grid buckets them.
struct Grid {
    size: f64,
    cells: HashMap<(i64, i64), Vec<usize>, BuildHasherDefault<CellHasher>>,
}

impl Grid {
    fn new(size: f64) -> Self {
        Self { size, cells: HashMap::default() }
    }

    fn cell(&self, p: &Point) -> (i64, i64) {
        ((p[0] / self.size).floor() as i64, (p[1] / self.size).floor() as i64)
    }

    fn put(&mut self, p: &Point, item: usize) {
        let cell = self.cell(p);
        self.cells.entry(cell).or_default().push(item);
    }

    /// Whether visit answers true for an item in p's cell or the eight
    /// around it, stopping at the first.
    fn near(&self, p: &Point, mut visit: impl FnMut(usize) -> bool) -> bool {
        let (cx, cy) = self.cell(p);
        for dx in -1..=1 {
            for dy in -1..=1 {
                if let Some(items) = self.cells.get(&(cx + dx, cy + dy)) {
                    if items.iter().any(|&item| visit(item)) {
                        return true;
                    }
                }
            }
        }
        false
    }
}

/// Each point's `per_node` nearest within `max_distance` that `admit(i, j)`
/// lets it pair with, each pair once, nearest first; ties go to the nearer,
/// then the lower index, and links by distance, a, then b.
pub fn nearest_pairs(points: &[Point], max_distance: f64, per_node: usize, admit: impl Fn(usize, usize) -> bool) -> Vec<Pair> {
    let mut grid = Grid::new(max_distance);
    for (i, p) in points.iter().enumerate() {
        grid.put(p, i);
    }
    let mut out = Vec::new();
    let mut near: Vec<(f64, usize)> = Vec::new();
    for (i, p) in points.iter().enumerate() {
        near.clear();
        grid.near(p, |j| {
            if admit(i, j) {
                let d = distance(p, &points[j]);
                if d <= max_distance {
                    near.push((d, j));
                }
            }
            false
        });
        let nearer = |x: &(f64, usize), y: &(f64, usize)| (x.0.to_bits(), x.1).cmp(&(y.0.to_bits(), y.1));
        if per_node == 0 {
            continue;
        }
        if near.len() > per_node {
            near.select_nth_unstable_by(per_node - 1, nearer);
            near.truncate(per_node);
        }
        near.sort_unstable_by(nearer);
        for &(d, j) in near.iter() {
            let (a, b) = if i < j { (i, j) } else { (j, i) };
            out.push(Pair { a, b, distance: d });
        }
    }
    // a distance is a square root of a sum of squares, +0 or more, and such
    // doubles order as their bits do; a pair found from both ends has the
    // same distance either way, so its copies sort side by side
    out.sort_unstable_by_key(|pair| (pair.distance.to_bits(), pair.a, pair.b));
    out.dedup_by(|x, y| x.a == y.a && x.b == y.b);
    out
}

/// The indexes of the points picked largest first (equal sizes in index
/// order), none within `spacing` of another, at most `limit`.
pub fn pick_spaced(points: &[Point], sizes: &[f64], spacing: f64, limit: f64) -> Vec<usize> {
    let mut order: Vec<usize> = (0..points.len()).collect();
    order.sort_unstable_by(|&x, &y| {
        let (sx, sy) = (sizes[x], sizes[y]);
        if sx > sy {
            Ordering::Less
        } else if sx < sy {
            Ordering::Greater
        } else {
            x.cmp(&y)
        }
    });
    let mut grid = Grid::new(spacing);
    let mut chosen = Vec::new();
    for i in order {
        if chosen.len() as f64 >= limit {
            break;
        }
        let p = &points[i];
        if !grid.near(p, |other| distance(&points[other], p) < spacing) {
            chosen.push(i);
            grid.put(p, i);
        }
    }
    chosen
}

#[cfg(test)]
mod tests {
    use super::*;

    const SQUARE: [Point; 4] = [[0.0, 0.0, 0.0], [100.0, 0.0, 0.0], [0.0, 100.0, 0.0], [100.0, 100.0, 0.0]];

    fn names(pairs: &[Pair]) -> Vec<(usize, usize)> {
        pairs.iter().map(|p| (p.a, p.b)).collect()
    }

    #[test]
    fn equal_distances_break_by_the_lower_index() {
        let one = nearest_pairs(&SQUARE, 150.0, 1, |i, j| i != j);
        assert_eq!(names(&one), vec![(0, 1), (0, 2), (1, 3)]);
        let two = nearest_pairs(&SQUARE, 150.0, 2, |i, j| i != j);
        assert_eq!(names(&two), vec![(0, 1), (0, 2), (1, 3), (2, 3)]);
    }

    #[test]
    fn the_range_is_inclusive() {
        let points = [[0.0, 0.0, 0.0], [300.0, 0.0, 0.0], [600.5, 0.0, 0.0]];
        assert_eq!(names(&nearest_pairs(&points, 300.0, 4, |i, j| i != j)), vec![(0, 1)]);
    }

    #[test]
    fn admit_filters_the_pairs() {
        let zones = [4, 4, 5, 5];
        let bridges = nearest_pairs(&SQUARE, 720.0, 1, |i, j| zones[i] != zones[j]);
        assert_eq!(names(&bridges), vec![(0, 2), (1, 3)]);
    }

    #[test]
    fn the_largest_are_picked_first_and_spaced() {
        let points = [[0.0, 0.0, 0.0], [50.0, 0.0, 0.0], [500.0, 0.0, 0.0], [520.0, 0.0, 0.0]];
        let sizes = [5.0, 5.0, 9.0, 9.0];
        assert_eq!(pick_spaced(&points, &sizes, 100.0, f64::INFINITY), vec![2, 0]);
        assert_eq!(pick_spaced(&points, &sizes, 100.0, 1.0), vec![2]);
    }
}
