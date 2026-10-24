//! A route search on a `NavMesh`: NavAreaBuildPath (foundation's A*)
//! priced by a `Walker`, with what the walker may enter told three ways:
//! areas and links closed up front (`close`, `close_link`), and the rest
//! asked of `Rules` the first time the search reaches them, the answer kept
//! for the rest of the search. Areas are named by engine id at this face.

use crate::navmesh::NavMesh;
use crate::walker::{Step, Walker, IMPASSABLE, NO_ROOM};
use foundation::astar::{AStar, Costs, Status};
use std::collections::HashMap;
use std::sync::Arc;

const UNKNOWN: u8 = 0;
const OPEN: u8 = 1;
const CLOSED: u8 = 2;

/// What a search asks of whoever runs it about areas and links it has not
/// been told of: once each, with engine ids.
pub trait Rules {
    fn traversable(&mut self, area: u32) -> bool;
    fn crossable(&mut self, from: u32, to: u32) -> bool;
}

/// Rules that open everything not closed up front.
pub struct Open;

impl Rules for Open {
    fn traversable(&mut self, _area: u32) -> bool {
        true
    }
    fn crossable(&mut self, _from: u32, _to: u32) -> bool {
        true
    }
}

#[derive(Debug, PartialEq)]
pub enum SearchError {
    NoSuchArea(u32),
    /// Told something once it had begun.
    Begun,
    /// A step was interrupted (a rule raised a Lua error): its state is lost.
    Spent,
}

impl std::fmt::Display for SearchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SearchError::NoSuchArea(id) => write!(f, "no area {id} in the mesh"),
            SearchError::Begun => write!(f, "the search has begun: close, rooms, penalties and estimates come first"),
            SearchError::Spent => write!(f, "the search was interrupted mid-step and is spent"),
        }
    }
}

pub struct RouteSearch {
    mesh: Arc<NavMesh>,
    walker: Walker,
    goal_pos: [f64; 3],
    start: u32,
    goal: u32,
    max_expanded: u32,
    areas: Vec<u8>,
    links: Vec<u8>,
    rooms: Vec<i32>,
    penalized: Vec<bool>,
    estimates: HashMap<u32, f64>,
    astar: Option<AStar>,
    begun: bool,
}

/// The search's `Costs`: the mesh's data, the per-search tables, the rules.
struct Pricing<'a, R: Rules> {
    mesh: &'a NavMesh,
    walker: &'a Walker,
    goal_pos: [f64; 3],
    areas: &'a mut [u8],
    links: &'a mut [u8],
    rooms: &'a [i32],
    penalized: &'a [bool],
    estimates: &'a HashMap<u32, f64>,
    rules: &'a mut R,
}

impl<R: Rules> Pricing<'_, R> {
    fn crossable(&mut self, from: u32, link: usize, to: u32) -> bool {
        if self.links[link] == UNKNOWN {
            let open = self.rules.crossable(self.mesh.id(from), self.mesh.id(to));
            self.links[link] = if open { OPEN } else { CLOSED };
        }
        self.links[link] == OPEN
    }

    fn traversable(&mut self, area: u32) -> bool {
        if self.areas[area as usize] == UNKNOWN {
            let open = self.rules.traversable(self.mesh.id(area));
            self.areas[area as usize] = if open { OPEN } else { CLOSED };
        }
        self.areas[area as usize] == OPEN
    }
}

impl<R: Rules> Costs for Pricing<'_, R> {
    fn cost(&mut self, from: u32, link: usize, to: u32, so_far: f64) -> f64 {
        if !self.crossable(from, link, to) {
            return IMPASSABLE;
        }
        let traversable = self.traversable(to);
        self.walker.price(&Step {
            traversable,
            room: self.rooms.get(to as usize).copied().unwrap_or(NO_ROOM),
            attributes: self.mesh.attributes(to),
            distance: self.mesh.distance(link),
            rise: self.mesh.rise(link),
            so_far,
            area_id: self.mesh.id(to),
            penalized: self.penalized.get(to as usize).copied().unwrap_or(false),
        })
    }

    fn estimate(&mut self, area: u32) -> f64 {
        if let Some(&estimate) = self.estimates.get(&area) {
            return estimate;
        }
        let (c, g) = (self.mesh.center(area), self.goal_pos);
        let (dx, dy, dz) = (c[0] - g[0], c[1] - g[1], c[2] - g[2]);
        (dx * dx + dy * dy + dz * dz).sqrt()
    }
}

impl RouteSearch {
    /// A search from area `start` to area `goal` (engine ids), estimated
    /// toward `goal_pos`; it begins at its first step.
    pub fn new(mesh: Arc<NavMesh>, walker: Walker, start: u32, goal: u32, max_expanded: u32, goal_pos: [f64; 3]) -> Result<Self, SearchError> {
        let start = mesh.index_of(start).ok_or(SearchError::NoSuchArea(start))?;
        let goal = mesh.index_of(goal).ok_or(SearchError::NoSuchArea(goal))?;
        let (areas, links) = (mesh.areas() as usize, mesh.graph().links());
        Ok(RouteSearch {
            mesh,
            walker,
            goal_pos,
            start,
            goal,
            max_expanded,
            areas: vec![UNKNOWN; areas],
            links: vec![UNKNOWN; links],
            rooms: Vec::new(),
            penalized: Vec::new(),
            estimates: HashMap::new(),
            astar: None,
            begun: false,
        })
    }

    fn area(&self, id: u32) -> Result<u32, SearchError> {
        if self.begun {
            return Err(SearchError::Begun);
        }
        self.mesh.index_of(id).ok_or(SearchError::NoSuchArea(id))
    }

    /// Area `id` is closed to the walker.
    pub fn close(&mut self, id: u32) -> Result<(), SearchError> {
        let area = self.area(id)?;
        self.areas[area as usize] = CLOSED;
        Ok(())
    }

    /// The link from `from` to `to` is closed; a pair the mesh does not link
    /// closes nothing.
    pub fn close_link(&mut self, from: u32, to: u32) -> Result<(), SearchError> {
        let (from, to) = (self.area(from)?, self.area(to)?);
        if let Some(link) = self.mesh.link_between(from, to) {
            self.links[link] = CLOSED;
        }
        Ok(())
    }

    /// Area `id` lies in `team`'s spawn room.
    pub fn room(&mut self, id: u32, team: i32) -> Result<(), SearchError> {
        let area = self.area(id)? as usize;
        if self.rooms.is_empty() {
            self.rooms = vec![NO_ROOM; self.mesh.areas() as usize];
        }
        self.rooms[area] = team;
        Ok(())
    }

    /// A step into area `id` takes the walker's lane penalty.
    pub fn penalize(&mut self, id: u32) -> Result<(), SearchError> {
        let area = self.area(id)? as usize;
        if self.penalized.is_empty() {
            self.penalized = vec![false; self.mesh.areas() as usize];
        }
        self.penalized[area] = true;
        Ok(())
    }

    /// Area `id`'s estimate is `estimate`, not its centre's distance.
    pub fn estimate(&mut self, id: u32, estimate: f64) -> Result<(), SearchError> {
        let area = self.area(id)?;
        self.estimates.insert(area, estimate);
        Ok(())
    }

    /// Runs up to `budget` expansions and returns the status.
    pub fn step(&mut self, budget: u32, rules: &mut impl Rules) -> Result<Status, SearchError> {
        let mesh = Arc::clone(&self.mesh);
        let mut astar = if self.begun {
            self.astar.take().ok_or(SearchError::Spent)?
        } else {
            self.begun = true;
            let (start, goal, max_expanded) = (self.start, self.goal, self.max_expanded);
            AStar::new(mesh.graph(), &mut self.pricing(&mesh, rules), start, goal, max_expanded)
        };
        let status = astar.step(mesh.graph(), &mut self.pricing(&mesh, rules), budget);
        self.astar = Some(astar);
        Ok(status)
    }

    fn pricing<'a, R: Rules>(&'a mut self, mesh: &'a NavMesh, rules: &'a mut R) -> Pricing<'a, R> {
        Pricing {
            mesh,
            walker: &self.walker,
            goal_pos: self.goal_pos,
            areas: &mut self.areas,
            links: &mut self.links,
            rooms: &self.rooms,
            penalized: &self.penalized,
            estimates: &self.estimates,
            rules,
        }
    }

    fn astar(&self) -> Result<&AStar, SearchError> {
        self.astar.as_ref().ok_or(if self.begun { SearchError::Spent } else { SearchError::Begun })
    }

    /// The status: running until begun.
    pub fn status(&self) -> Status {
        match &self.astar {
            Some(astar) => astar.status(),
            None if self.start == self.goal => Status::Found,
            None => Status::Running,
        }
    }

    pub fn expanded(&self) -> u32 {
        self.astar.as_ref().map_or(0, AStar::expanded)
    }

    pub fn max_expanded(&self) -> u32 {
        self.max_expanded
    }

    pub fn start(&self) -> u32 {
        self.mesh.id(self.start)
    }

    pub fn goal(&self) -> u32 {
        self.mesh.id(self.goal)
    }

    /// The area that came closest to the goal (the goal once found).
    pub fn closest(&self) -> u32 {
        self.astar.as_ref().map_or(self.start(), |astar| self.mesh.id(astar.closest()))
    }

    /// The route from the start to `last` (default: the goal once found,
    /// else the closest area), as engine ids.
    pub fn route(&self, last: Option<u32>) -> Result<Vec<u32>, SearchError> {
        let Some(astar) = &self.astar else {
            return match last {
                Some(id) if id != self.start() => Err(SearchError::NoSuchArea(id)),
                _ => Ok(vec![self.start()]),
            };
        };
        let last = match last {
            Some(id) => Some(self.mesh.index_of(id).ok_or(SearchError::NoSuchArea(id))?),
            None => None,
        };
        Ok(astar.route(last).into_iter().map(|area| self.mesh.id(area)).collect())
    }

    /// What reaching area `id` cost by its best way, or None.
    pub fn cost_so_far(&self, id: u32) -> Result<Option<f64>, SearchError> {
        let area = self.mesh.index_of(id).ok_or(SearchError::NoSuchArea(id))?;
        Ok(self.astar()?.cost_so_far(area))
    }

    /// Every reached area's (id, parent id).
    pub fn parents(&self) -> Vec<(u32, u32)> {
        let Some(astar) = &self.astar else { return Vec::new() };
        (0..self.mesh.areas())
            .filter_map(|area| astar.parent(area).map(|parent| (self.mesh.id(area), self.mesh.id(parent))))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::navmesh::MeshBuilder;
    use crate::walker::{Jump, Limits, Preference};

    /// Areas 1..=n in a row 100 apart, linked both ways, flat.
    fn row(n: u32) -> Arc<NavMesh> {
        let mut b = MeshBuilder::default();
        for id in 1..=n {
            b.area(id, [id as f64 * 100.0, 0.0, 0.0], 0).unwrap();
        }
        for id in 1..=n {
            if id > 1 {
                b.link(id, id - 1, 100.0, 0.0).unwrap();
            }
            if id < n {
                b.link(id, id + 1, 100.0, 0.0).unwrap();
            }
        }
        Arc::new(b.finish().unwrap())
    }

    fn walker() -> Walker {
        Walker {
            limits: Limits { step_height: 18.0, jump_height: 56.0, death_drop_height: 1000.0, crouches: true },
            jump: Jump::Scaled(2.0),
            attribute_rule: true,
            rooms: None,
            preference: Preference::Even,
            lane_penalty: None,
        }
    }

    fn run(search: &mut RouteSearch, rules: &mut impl Rules) -> Status {
        loop {
            let status = search.step(1, rules).unwrap();
            if status != Status::Running {
                return status;
            }
        }
    }

    #[test]
    fn walks_the_row_to_the_goal() {
        let mut search = RouteSearch::new(row(5), walker(), 1, 5, 100, [500.0, 0.0, 0.0]).unwrap();
        assert_eq!(run(&mut search, &mut Open), Status::Found);
        assert_eq!(search.route(None).unwrap(), vec![1, 2, 3, 4, 5]);
        assert_eq!(search.cost_so_far(5).unwrap(), Some(400.0));
    }

    #[test]
    fn a_closed_area_cuts_the_row_and_the_closest_is_before_it() {
        let mut search = RouteSearch::new(row(5), walker(), 1, 5, 100, [500.0, 0.0, 0.0]).unwrap();
        search.close(4).unwrap();
        assert_eq!(run(&mut search, &mut Open), Status::Failed);
        assert_eq!(search.route(None).unwrap(), vec![1, 2, 3]);
        assert_eq!(search.parents(), vec![(2, 1), (3, 2)]);
    }

    #[test]
    fn a_closed_link_cuts_one_way_only() {
        let mut search = RouteSearch::new(row(3), walker(), 1, 3, 100, [300.0, 0.0, 0.0]).unwrap();
        search.close_link(2, 3).unwrap();
        assert_eq!(run(&mut search, &mut Open), Status::Failed);
        let mut back = RouteSearch::new(row(3), walker(), 3, 1, 100, [100.0, 0.0, 0.0]).unwrap();
        back.close_link(2, 3).unwrap();
        assert_eq!(run(&mut back, &mut Open), Status::Found);
    }

    /// Rules that count their questions and close what they are told.
    struct Counting {
        closed: Vec<u32>,
        asked: Vec<u32>,
        crossings: usize,
    }

    impl Rules for Counting {
        fn traversable(&mut self, area: u32) -> bool {
            self.asked.push(area);
            !self.closed.contains(&area)
        }
        fn crossable(&mut self, _from: u32, _to: u32) -> bool {
            self.crossings += 1;
            true
        }
    }

    #[test]
    fn rules_are_asked_once_an_area_and_a_link() {
        let mut rules = Counting { closed: vec![4], asked: vec![], crossings: 0 };
        let mut search = RouteSearch::new(row(5), walker(), 1, 5, 100, [500.0, 0.0, 0.0]).unwrap();
        assert_eq!(run(&mut search, &mut rules), Status::Failed);
        assert_eq!(rules.asked, vec![2, 3, 4]);
        assert_eq!(rules.crossings, 3);
    }

    #[test]
    fn nothing_is_told_once_begun_and_unknown_areas_are_refused() {
        let mut search = RouteSearch::new(row(3), walker(), 1, 3, 100, [300.0, 0.0, 0.0]).unwrap();
        assert_eq!(search.close(9), Err(SearchError::NoSuchArea(9)));
        search.step(1, &mut Open).unwrap();
        assert_eq!(search.close(2), Err(SearchError::Begun));
        assert!(matches!(RouteSearch::new(row(3), walker(), 1, 9, 100, [0.0; 3]), Err(SearchError::NoSuchArea(9))));
    }

    #[test]
    fn a_start_that_is_the_goal_is_found_at_once() {
        let mut search = RouteSearch::new(row(3), walker(), 2, 2, 100, [200.0, 0.0, 0.0]).unwrap();
        assert_eq!(search.status(), Status::Found);
        assert_eq!(search.step(1, &mut Open).unwrap(), Status::Found);
        assert_eq!(search.route(None).unwrap(), vec![2]);
    }

    #[test]
    fn rooms_and_penalties_reach_the_walker() {
        let mut planner = walker();
        planner.lane_penalty = Some(3.0);
        let mut search = RouteSearch::new(row(3), planner, 1, 3, 100, [300.0, 0.0, 0.0]).unwrap();
        search.penalize(2).unwrap();
        run(&mut search, &mut Open);
        assert_eq!(search.cost_so_far(3).unwrap(), Some(400.0));
        let mut guarded = walker();
        guarded.rooms = Some(crate::walker::Rooms { team: Some(2), winners: false });
        let mut search = RouteSearch::new(row(3), guarded, 1, 3, 100, [300.0, 0.0, 0.0]).unwrap();
        search.room(2, 3).unwrap();
        assert_eq!(run(&mut search, &mut Open), Status::Failed);
    }
}
