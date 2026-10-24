//! The route cost of a walker on the nav mesh, as data: the strategies of
//! `foundation.wetsands.path` (ground, scatter, tfbot, hl2, and the lanes'
//! penalty on hl2) are one formula with parameters, which each strategy's
//! `Model(limits, bot)` fills in. A step prices to the same double as the
//! strategy's Lua `Cost`, operation for operation.

use crate::source::nav::{NAV_MESH_CROUCH, NAV_MESH_JUMP};

pub const IMPASSABLE: f64 = -1.0;
/// TEAM_UNASSIGNED: an area in no spawn room.
pub const NO_ROOM: i32 = 0;

const ROUTE_PERIOD: f64 = 10.0;
const PREFERENCE_SPREAD: f64 = 50.0;

pub struct Limits {
    pub step_height: f64,
    pub jump_height: f64,
    pub death_drop_height: f64,
    pub crouches: bool,
}

/// How a jump up (a rise of at least a step) weighs a step's distance.
pub enum Jump {
    /// distance + penalty * distance: the zombie's and the Hatman's.
    Added(f64),
    /// distance * penalty: TF2's bots'.
    Scaled(f64),
}

/// The weight on a step's distance.
pub enum Preference {
    Even,
    /// CZombiePathCost's spread: each bot favours different areas, the same
    /// ones for ROUTE_PERIOD seconds.
    Scatter { ent_index: f64, time_mod: f64 },
}

impl Preference {
    pub fn scatter(ent_index: f64, now: f64) -> Self {
        Preference::Scatter { ent_index, time_mod: (now / ROUTE_PERIOD).floor() + 1.0 }
    }

    fn weight(&self, area_id: u32) -> f64 {
        match *self {
            Preference::Even => 1.0,
            Preference::Scatter { ent_index, time_mod } => {
                1.0 + PREFERENCE_SPREAD * (1.0 + (ent_index * area_id as f64 * time_mod).cos())
            }
        }
    }
}

/// The spawn-room rule (CTFBotLocomotion::IsAreaTraversable): another
/// team's room is closed, unless the walker's team won the round.
pub struct Rooms {
    /// The walker's team; None matches no room.
    pub team: Option<i32>,
    pub winners: bool,
}

impl Rooms {
    fn closes(&self, room: i32) -> bool {
        room != NO_ROOM && Some(room) != self.team && !self.winners
    }
}

pub struct Walker {
    pub limits: Limits,
    pub jump: Jump,
    /// hl2's rule: a crouch area is closed unless the walker crouches, a
    /// jump area unless it jumps higher than a step.
    pub attribute_rule: bool,
    pub rooms: Option<Rooms>,
    pub preference: Preference,
    /// The lanes' rule: a step into a penalised area costs this many times
    /// as much.
    pub lane_penalty: Option<f64>,
}

/// The move into an area, as the search sees it.
pub struct Step {
    pub traversable: bool,
    pub room: i32,
    pub attributes: u32,
    pub distance: f64,
    pub rise: f64,
    pub so_far: f64,
    pub area_id: u32,
    pub penalized: bool,
}

impl Walker {
    fn uncrossable(&self, attributes: u32) -> bool {
        let attributes = i64::from(attributes);
        if attributes & NAV_MESH_CROUCH != 0 && !self.limits.crouches {
            return true;
        }
        attributes & NAV_MESH_JUMP != 0 && self.limits.jump_height <= self.limits.step_height
    }

    fn walkable(&self, rise: f64) -> bool {
        rise < self.limits.jump_height && rise >= -self.limits.death_drop_height
    }

    /// The total cost of the step, or IMPASSABLE.
    pub fn price(&self, step: &Step) -> f64 {
        let cost = self.base(step);
        match self.lane_penalty {
            Some(penalty) if cost != IMPASSABLE && step.penalized => step.so_far + (cost - step.so_far) * penalty,
            _ => cost,
        }
    }

    fn base(&self, step: &Step) -> f64 {
        if self.attribute_rule && self.uncrossable(step.attributes) {
            return IMPASSABLE;
        }
        if !step.traversable || self.rooms.as_ref().is_some_and(|rooms| rooms.closes(step.room)) {
            return IMPASSABLE;
        }
        let mut distance = step.distance;
        if !self.walkable(step.rise) {
            return IMPASSABLE;
        }
        if step.rise >= self.limits.step_height {
            distance = match self.jump {
                Jump::Added(penalty) => distance + penalty * distance,
                Jump::Scaled(penalty) => distance * penalty,
            };
        }
        distance * self.preference.weight(step.area_id) + step.so_far
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CROUCH: u32 = NAV_MESH_CROUCH as u32;
    const JUMP: u32 = NAV_MESH_JUMP as u32;
    const LIMITS: Limits = Limits { step_height: 18.0, jump_height: 56.0, death_drop_height: 1000.0, crouches: true };

    fn soldier() -> Walker {
        Walker {
            limits: LIMITS,
            jump: Jump::Scaled(2.0),
            attribute_rule: true,
            rooms: Some(Rooms { team: Some(2), winners: false }),
            preference: Preference::Even,
            lane_penalty: None,
        }
    }

    fn step() -> Step {
        Step { traversable: true, room: NO_ROOM, attributes: 0, distance: 100.0, rise: 0.0, so_far: 50.0, area_id: 7, penalized: false }
    }

    #[test]
    fn a_flat_step_costs_its_distance_on_top_of_the_way_so_far() {
        assert_eq!(soldier().price(&step()), 150.0);
    }

    #[test]
    fn a_closed_area_or_an_enemy_room_is_impassable() {
        assert_eq!(soldier().price(&Step { traversable: false, ..step() }), IMPASSABLE);
        assert_eq!(soldier().price(&Step { room: 3, ..step() }), IMPASSABLE);
        assert_eq!(soldier().price(&Step { room: 2, ..step() }), 150.0);
    }

    #[test]
    fn the_round_winners_cross_the_losers_room() {
        let walker = Walker { rooms: Some(Rooms { team: Some(2), winners: true }), ..soldier() };
        assert_eq!(walker.price(&Step { room: 3, ..step() }), 150.0);
    }

    #[test]
    fn a_walker_of_no_team_finds_every_room_closed() {
        let walker = Walker { rooms: Some(Rooms { team: None, winners: false }), ..soldier() };
        assert_eq!(walker.price(&Step { room: 2, ..step() }), IMPASSABLE);
    }

    #[test]
    fn a_jump_up_weighs_the_distance_by_the_walkers_rule() {
        assert_eq!(soldier().price(&Step { rise: 18.0, ..step() }), 250.0);
        let zombie = Walker { jump: Jump::Added(5.0), rooms: None, attribute_rule: false, ..soldier() };
        assert_eq!(zombie.price(&Step { rise: 18.0, ..step() }), 650.0);
    }

    #[test]
    fn a_rise_beyond_the_jump_or_a_drop_beyond_the_fall_is_impassable() {
        assert_eq!(soldier().price(&Step { rise: 56.0, ..step() }), IMPASSABLE);
        assert_eq!(soldier().price(&Step { rise: -1000.0, ..step() }), 150.0);
        assert_eq!(soldier().price(&Step { rise: -1000.5, ..step() }), IMPASSABLE);
    }

    #[test]
    fn hl2s_attribute_rule_closes_crouch_areas_to_a_walker_that_cannot_crouch() {
        let engine_npc = Walker {
            limits: Limits { step_height: 18.0, jump_height: 18.0, death_drop_height: 18.0, crouches: false },
            ..soldier()
        };
        assert_eq!(engine_npc.price(&Step { attributes: CROUCH, ..step() }), IMPASSABLE);
        assert_eq!(engine_npc.price(&Step { attributes: JUMP, ..step() }), IMPASSABLE);
        assert_eq!(soldier().price(&Step { attributes: CROUCH | JUMP, ..step() }), 150.0);
    }

    #[test]
    fn the_lane_penalty_multiplies_only_the_steps_own_cost_into_penalised_areas() {
        let planner = Walker { lane_penalty: Some(4.0), ..soldier() };
        assert_eq!(planner.price(&Step { penalized: true, ..step() }), 50.0 + 100.0 * 4.0);
        assert_eq!(planner.price(&step()), 150.0);
        assert_eq!(planner.price(&Step { penalized: true, traversable: false, ..step() }), IMPASSABLE);
    }

    #[test]
    fn the_scatter_preference_follows_the_bot_the_area_and_the_period() {
        let walker = Walker { preference: Preference::scatter(3.0, 25.0), ..soldier() };
        let weight = 1.0 + 50.0 * (1.0 + (3.0f64 * 7.0 * 3.0).cos());
        assert_eq!(walker.price(&step()), 100.0 * weight + 50.0);
    }
}
