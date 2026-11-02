//! The engine's path search priced by a walker: the consumer a NextBot's
//! `Path:Compute` calls for each move it considers (IPathCost), over what
//! a team's computations know of the mesh (`Known`, made once while it
//! holds). Areas are named by engine id at this face.

use crate::navmesh::NavMesh;
use crate::walker::{Step, Walker, IMPASSABLE, NO_ROOM};
use std::sync::Arc;

#[derive(Debug, PartialEq)]
pub enum CalculatorError {
    NoSuchArea(u32),
    NoSuchLink(u32, u32),
}

impl std::fmt::Display for CalculatorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CalculatorError::NoSuchArea(id) => write!(f, "no area {id} in the mesh"),
            CalculatorError::NoSuchLink(from, to) => write!(f, "no link {from} -> {to} in the mesh"),
        }
    }
}

/// What a team's computations know: the areas closed to it, the links it
/// may not cross, the spawn rooms.
pub struct Known {
    mesh: Arc<NavMesh>,
    closed: Vec<bool>,
    uncrossable: Vec<bool>,
    rooms: Vec<i32>,
}

impl Known {
    pub fn new(mesh: Arc<NavMesh>) -> Self {
        let (areas, links) = (mesh.areas() as usize, mesh.graph().links());
        Known { mesh, closed: vec![false; areas], uncrossable: vec![false; links], rooms: vec![NO_ROOM; areas] }
    }

    fn area(&self, id: u32) -> Result<u32, CalculatorError> {
        self.mesh.index_of(id).ok_or(CalculatorError::NoSuchArea(id))
    }

    fn link(&self, from: u32, to: u32) -> Result<usize, CalculatorError> {
        let (a, b) = (self.area(from)?, self.area(to)?);
        self.mesh.link_between(a, b).ok_or(CalculatorError::NoSuchLink(from, to))
    }

    pub fn close(&mut self, id: u32) -> Result<(), CalculatorError> {
        let area = self.area(id)? as usize;
        self.closed[area] = true;
        Ok(())
    }

    pub fn close_link(&mut self, from: u32, to: u32) -> Result<(), CalculatorError> {
        let link = self.link(from, to)?;
        self.uncrossable[link] = true;
        Ok(())
    }

    pub fn room(&mut self, id: u32, team: i32) -> Result<(), CalculatorError> {
        let area = self.area(id)? as usize;
        self.rooms[area] = team;
        Ok(())
    }

    pub fn mesh(&self) -> &Arc<NavMesh> {
        &self.mesh
    }

    /// Area index -> closed to the team.
    pub fn closed(&self) -> &[bool] {
        &self.closed
    }

    /// Link index -> not to be crossed.
    pub fn uncrossable(&self) -> &[bool] {
        &self.uncrossable
    }

    /// Area index -> the team whose spawn room it lies in, or NO_ROOM.
    pub fn rooms(&self) -> &[i32] {
        &self.rooms
    }
}

/// A move the engine asks the price of.
pub enum Move {
    /// Across a floor link; `length` is the engine's (above 0, the step's
    /// length; else the link's distance).
    Floor { length: f64 },
    /// Up or down a ladder, of its length, changing height by `rise`.
    Ladder { length: f64, rise: f64 },
}

pub struct Calculator {
    known: Arc<Known>,
    walker: Walker,
    penalized: Vec<bool>,
}

impl Calculator {
    pub fn new(known: Arc<Known>, walker: Walker) -> Self {
        Calculator { known, walker, penalized: Vec::new() }
    }

    /// A step into area `id` takes the walker's lane penalty.
    pub fn penalize(&mut self, id: u32) -> Result<(), CalculatorError> {
        let area = self.known.area(id)? as usize;
        if self.penalized.is_empty() {
            self.penalized = vec![false; self.known.mesh.areas() as usize];
        }
        self.penalized[area] = true;
        Ok(())
    }

    /// The total cost of moving from area `from` into `to` with `so_far`
    /// spent, or IMPASSABLE. `fits` is the caller's collision-hull verdict.
    pub fn price(
        &self,
        from: u32,
        to: u32,
        so_far: f64,
        step: Move,
        fits: bool,
    ) -> Result<f64, CalculatorError> {
        let known = &*self.known;
        let (distance, rise) = match step {
            Move::Floor { length } => {
                let link = known.link(from, to)?;
                if known.uncrossable[link] {
                    return Ok(IMPASSABLE);
                }
                let distance = if length > 0.0 { length } else { known.mesh.distance(link) };
                (distance, known.mesh.rise(link))
            }
            Move::Ladder { length, rise } => (length, rise),
        };
        let area = known.area(to)?;
        let index = area as usize;
        if !fits {
            return Ok(IMPASSABLE);
        }
        Ok(self.walker.price(&Step {
            traversable: !known.closed[index],
            room: known.rooms[index],
            attributes: known.mesh.attributes(area),
            distance,
            rise,
            so_far,
            area_id: to,
            penalized: self.penalized.get(index).copied().unwrap_or(false),
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::navmesh::MeshBuilder;
    use crate::walker::{Jump, Limits, Preference};

    fn mesh() -> Arc<NavMesh> {
        let mut b = MeshBuilder::default();
        for (id, x) in [(1, 0.0), (2, 100.0), (3, 200.0)] {
            b.area(id, [x, 0.0, 0.0], 0).unwrap();
        }
        b.link(1, 2, 100.0, 0.0).unwrap();
        b.link(2, 3, 100.0, 30.0).unwrap();
        Arc::new(b.finish().unwrap())
    }

    fn walker() -> Walker {
        Walker {
            limits: Limits { step_height: 18.0, jump_height: 56.0, death_drop_height: 1000.0, crouches: true },
            jump: Jump::Scaled(2.0),
            attribute_rule: false,
            rooms: None,
            preference: Preference::Even,
            lane_penalty: None,
        }
    }

    #[test]
    fn prices_floor_moves_by_the_mesh_and_refuses_what_it_lacks() {
        let mut known = Known::new(mesh());
        known.close_link(2, 3).unwrap();
        let calculator = Calculator::new(Arc::new(known), walker());
        assert_eq!(
            calculator.price(1, 2, 5.0, Move::Floor { length: -1.0 }, true),
            Ok(105.0)
        );
        assert_eq!(
            calculator.price(1, 2, 5.0, Move::Floor { length: 40.0 }, true),
            Ok(45.0)
        );
        assert_eq!(
            calculator.price(2, 3, 0.0, Move::Floor { length: -1.0 }, true),
            Ok(IMPASSABLE)
        );
        assert_eq!(
            calculator.price(1, 2, 0.0, Move::Floor { length: -1.0 }, false),
            Ok(IMPASSABLE)
        );
        assert_eq!(
            calculator.price(1, 3, 0.0, Move::Floor { length: -1.0 }, true),
            Err(CalculatorError::NoSuchLink(1, 3))
        );
        assert_eq!(
            calculator.price(1, 3, 0.0, Move::Ladder { length: 50.0, rise: 30.0 }, true),
            Ok(100.0)
        );
    }

    #[test]
    fn refuses_told_areas_and_links_the_mesh_lacks() {
        let mut known = Known::new(mesh());
        assert_eq!(known.close(9), Err(CalculatorError::NoSuchArea(9)));
        assert_eq!(known.close_link(1, 3), Err(CalculatorError::NoSuchLink(1, 3)));
        assert_eq!(known.room(9, 2), Err(CalculatorError::NoSuchArea(9)));
    }
}
