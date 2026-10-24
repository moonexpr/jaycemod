//! A nav mesh as a search reads it, fixed once built: each area's id,
//! centre and NAV_MESH_* attributes, and its floor links in
//! GetAdjacentAreas' order, each with the distance between centres and the
//! height change (ComputeAdjacentConnectionHeightChange) the engine gives.
//! Areas are numbered 0..n inside; ids are the engine's.

use foundation::graph::{Builder, Graph, GraphError};
use std::collections::HashMap;

#[derive(Debug, PartialEq)]
pub enum MeshError {
    DuplicateArea(u32),
    NoSuchArea(u32),
    Graph(String),
}

impl std::fmt::Display for MeshError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MeshError::DuplicateArea(id) => write!(f, "area {id} added twice"),
            MeshError::NoSuchArea(id) => write!(f, "no area {id} in the mesh"),
            MeshError::Graph(why) => write!(f, "{why}"),
        }
    }
}

impl From<GraphError> for MeshError {
    fn from(e: GraphError) -> Self {
        MeshError::Graph(e.to_string())
    }
}

pub struct NavMesh {
    ids: Vec<u32>,
    index: HashMap<u32, u32>,
    centers: Vec<[f64; 3]>,
    attributes: Vec<u32>,
    graph: Graph,
    distances: Vec<f64>,
    rises: Vec<f64>,
}

struct Link {
    to: u32,
    distance: f64,
    rise: f64,
}

/// Builds a mesh: every area, then each area's links in order.
#[derive(Default)]
pub struct MeshBuilder {
    ids: Vec<u32>,
    index: HashMap<u32, u32>,
    centers: Vec<[f64; 3]>,
    attributes: Vec<u32>,
    links: Vec<Vec<Link>>,
}

impl MeshBuilder {
    pub fn area(&mut self, id: u32, center: [f64; 3], attributes: u32) -> Result<(), MeshError> {
        let next = self.ids.len() as u32;
        if self.index.insert(id, next).is_some() {
            return Err(MeshError::DuplicateArea(id));
        }
        self.ids.push(id);
        self.centers.push(center);
        self.attributes.push(attributes);
        self.links.push(Vec::new());
        Ok(())
    }

    /// Adds the next link of area `from` (already added) to area `to`
    /// (added before `finish`).
    pub fn link(&mut self, from: u32, to: u32, distance: f64, rise: f64) -> Result<(), MeshError> {
        let &from = self.index.get(&from).ok_or(MeshError::NoSuchArea(from))?;
        self.links[from as usize].push(Link { to, distance, rise });
        Ok(())
    }

    pub fn finish(self) -> Result<NavMesh, MeshError> {
        let mut builder = Builder::default();
        let (mut distances, mut rises) = (Vec::new(), Vec::new());
        for links in &self.links {
            builder.node();
            for link in links {
                let &to = self.index.get(&link.to).ok_or(MeshError::NoSuchArea(link.to))?;
                builder.link(to)?;
                distances.push(link.distance);
                rises.push(link.rise);
            }
        }
        Ok(NavMesh {
            graph: builder.finish()?,
            ids: self.ids,
            index: self.index,
            centers: self.centers,
            attributes: self.attributes,
            distances,
            rises,
        })
    }
}

impl NavMesh {
    pub fn graph(&self) -> &Graph {
        &self.graph
    }

    pub fn areas(&self) -> u32 {
        self.ids.len() as u32
    }

    /// The inside number of area `id`, or None when the mesh lacks it.
    pub fn index_of(&self, id: u32) -> Option<u32> {
        self.index.get(&id).copied()
    }

    pub fn id(&self, area: u32) -> u32 {
        self.ids[area as usize]
    }

    pub fn center(&self, area: u32) -> [f64; 3] {
        self.centers[area as usize]
    }

    pub fn attributes(&self, area: u32) -> u32 {
        self.attributes[area as usize]
    }

    pub fn distance(&self, link: usize) -> f64 {
        self.distances[link]
    }

    pub fn rise(&self, link: usize) -> f64 {
        self.rises[link]
    }

    /// The link from `from` to `to` (inside numbers), if there is one.
    pub fn link_between(&self, from: u32, to: u32) -> Option<usize> {
        self.graph.links_of(from).find(|&link| self.graph.target(link) == to)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_areas_by_id_and_links_in_order() {
        let mut b = MeshBuilder::default();
        b.area(40, [0.0, 0.0, 0.0], 0).unwrap();
        b.area(7, [10.0, 0.0, 0.0], 2).unwrap();
        b.link(40, 7, 10.0, 0.5).unwrap();
        b.link(7, 40, 10.0, -0.5).unwrap();
        let mesh = b.finish().unwrap();
        let (a, c) = (mesh.index_of(40).unwrap(), mesh.index_of(7).unwrap());
        assert_eq!((mesh.id(a), mesh.id(c)), (40, 7));
        assert_eq!(mesh.attributes(c), 2);
        let link = mesh.link_between(c, a).unwrap();
        assert_eq!((mesh.distance(link), mesh.rise(link)), (10.0, -0.5));
        assert_eq!(mesh.index_of(99), None);
    }

    #[test]
    fn refuses_a_link_to_an_area_never_added() {
        let mut b = MeshBuilder::default();
        b.area(1, [0.0; 3], 0).unwrap();
        b.link(1, 2, 1.0, 0.0).unwrap();
        assert_eq!(b.finish().err(), Some(MeshError::NoSuchArea(2)));
        let mut b = MeshBuilder::default();
        assert_eq!(b.link(5, 1, 1.0, 0.0), Err(MeshError::NoSuchArea(5)));
        b.area(1, [0.0; 3], 0).unwrap();
        assert_eq!(b.area(1, [0.0; 3], 0), Err(MeshError::DuplicateArea(1)));
    }
}
