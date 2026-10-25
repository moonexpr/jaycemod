//! Walks over a nav mesh snapshot: graph.search's Distances (Dijkstra from
//! several starts) on the mesh's own links, the walkable rise and the
//! uncrossable links given as data, so a lane plan's walks ask Lua nothing.

use crate::navmesh::NavMesh;
use foundation::heap::Heap;

/// The cheapest walk to each area (by inside number) from the nearest of
/// `starts`, None where none reaches: along the links `walkable(rise)`
/// allows and `crossable(link)` does not refuse, at the link's distance; a
/// walk beyond `limit` is not followed. The Lua twin's arithmetic and rules:
/// a start is 0, a link relaxes when it is cheaper and within the limit.
pub fn distances(
    mesh: &NavMesh,
    starts: &[u32],
    limit: f64,
    walkable: impl Fn(f64) -> bool,
    crossable: impl Fn(usize) -> bool,
) -> Vec<Option<f64>> {
    let graph = mesh.graph();
    let mut dist: Vec<Option<f64>> = vec![None; mesh.areas() as usize];
    let mut queue = Heap::default();
    for &start in starts {
        dist[start as usize] = Some(0.0);
        queue.push(0.0, start as f64);
    }
    while let Some((node, reached)) = queue.pop() {
        let node = node as u32;
        if dist[node as usize] != Some(reached) {
            continue;
        }
        for link in graph.links_of(node) {
            if !walkable(mesh.rise(link)) || !crossable(link) {
                continue;
            }
            let to = graph.target(link);
            let cost = reached + mesh.distance(link);
            let cheaper = match dist[to as usize] {
                None => true,
                Some(known) => cost < known,
            };
            if cost <= limit && cheaper {
                dist[to as usize] = Some(cost);
                queue.push(cost, to as f64);
            }
        }
    }
    dist
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::navmesh::MeshBuilder;

    //  0 - 1 - 2 - 3, and 0 - 4 - 2 the long way
    fn mesh(rises: [f64; 2]) -> NavMesh {
        let mut b = MeshBuilder::default();
        for id in 0..5 {
            b.area(id, [id as f64 * 100.0, 0.0, 0.0], 0).unwrap();
        }
        for (from, to, distance, rise) in [
            (0, 1, 100.0, rises[0]),
            (1, 0, 100.0, 0.0),
            (1, 2, 100.0, rises[1]),
            (2, 1, 100.0, 0.0),
            (2, 3, 100.0, 0.0),
            (3, 2, 100.0, 0.0),
            (0, 4, 200.0, 0.0),
            (4, 0, 200.0, 0.0),
            (4, 2, 200.0, 0.0),
            (2, 4, 200.0, 0.0),
        ] {
            b.link(from, to, distance, rise).unwrap();
        }
        b.finish().unwrap()
    }

    #[test]
    fn walks_from_the_nearest_start_within_the_limit() {
        let m = mesh([0.0, 0.0]);
        let all = distances(&m, &[0], f64::INFINITY, |_| true, |_| true);
        assert_eq!(all, vec![Some(0.0), Some(100.0), Some(200.0), Some(300.0), Some(200.0)]);
        let two = distances(&m, &[0, 3], f64::INFINITY, |_| true, |_| true);
        assert_eq!(two[2], Some(100.0));
        let near = distances(&m, &[0], 200.0, |_| true, |_| true);
        assert_eq!(near[3], None);
    }

    #[test]
    fn keeps_to_walkable_and_crossable_links() {
        let m = mesh([0.0, 99.0]);
        let walks = distances(&m, &[0], f64::INFINITY, |rise| rise < 50.0, |_| true);
        assert_eq!(walks[2], Some(400.0), "the long way round the climb");
        let a = m.index_of(0).unwrap();
        let to_one = m.link_between(a, m.index_of(1).unwrap()).unwrap();
        let walks = distances(&m, &[0], f64::INFINITY, |_| true, |link| link != to_one);
        assert_eq!(walks[1], Some(500.0), "round by 4 and 2");
    }
}
