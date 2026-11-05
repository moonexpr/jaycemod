//! Where a soldier's head looks: IBody::AimHeadTowards as PlayerBody decides it, native,
//! since it runs every tick. Requests come from sources named once in a config, each
//! with its priority, how long a request holds and the reason it logs. The engine's
//! LOOK_AT debug output is the log, written only while someone watches.

use std::collections::VecDeque;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Priority {
    Boring,
    Interesting,
    Important,
    Critical,
    Mandatory,
}

impl Priority {
    pub fn parse(name: &str) -> Option<Priority> {
        match name {
            "BORING" => Some(Priority::Boring),
            "INTERESTING" => Some(Priority::Interesting),
            "IMPORTANT" => Some(Priority::Important),
            "CRITICAL" => Some(Priority::Critical),
            "MANDATORY" => Some(Priority::Mandatory),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Priority::Boring => "BORING",
            Priority::Interesting => "INTERESTING",
            Priority::Important => "IMPORTANT",
            Priority::Critical => "CRITICAL",
            Priority::Mandatory => "MANDATORY",
        }
    }
}

/// What makes a source ask.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    /// While it moves, the way it goes.
    BodyFacing,
    /// Every `every` seconds, a friend within `range`.
    Friend { range: f32, every: f32 },
    /// Only when asked.
    Asked,
}

#[derive(Clone, Debug)]
pub struct Source {
    pub reason: String,
    pub priority: Priority,
    pub seconds: f32,
    pub kind: Kind,
}

/// What a head sees this tick. `friend`: the one found, when friend_range asked.
#[derive(Clone, Copy, Debug)]
pub struct View {
    pub eye: Point,
    pub head: Angles,
    pub friend: Option<Point>,
}

/// The tuning PlayerBody reads from its convars.
#[derive(Clone, Copy, Debug)]
pub struct Tuning {
    /// nb_head_aim_settle_duration: how long a head stays steady before a request of
    /// the same priority may move it.
    pub settle: f32,
    /// nb_head_aim_steady_max_rate: turning slower than this, degrees a second, a head
    /// counts as steady.
    pub steady_rate: f32,
    /// How far a head turns in a second.
    pub turn_rate: f32,
}

pub type Point = [f32; 3];

/// A head's angles, in degrees: Source's, yaw 0 along +x, pitch positive looking down.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Angles {
    pub pitch: f32,
    pub yaw: f32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Entry {
    pub time: f32,
    pub source: usize,
    pub target: Point,
}

const LOG_SIZE: usize = 32;
/// Within this of the point it looks at, a request is the same one, its time renewed.
const SAME_TARGET: f32 = 1.0;
const MIN_SECONDS: f32 = 0.1;
/// Moving less than this in a tick, it is standing.
const MOVED: f32 = 0.5;
/// How far ahead the point stands that it faces.
const FACING_REACH: f32 = 500.0;

/// An angle in (-180, 180].
fn normal(angle: f32) -> f32 {
    let a = angle.rem_euclid(360.0);
    if a > 180.0 {
        a - 360.0
    } else {
        a
    }
}

fn distance(a: Point, b: Point) -> f32 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt()
}

fn angles_to(eye: Point, target: Point) -> Angles {
    let (dx, dy, dz) = (target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]);
    Angles {
        pitch: -dz.atan2((dx * dx + dy * dy).sqrt()).to_degrees(),
        yaw: dy.atan2(dx).to_degrees(),
    }
}

pub struct Look {
    sources: Vec<Source>,
    tuning: Tuning,
    target: Option<Point>,
    priority: Priority,
    expires: f32,
    steady_since: Option<f32>,
    next_friend: f32,
    last_eye: Option<Point>,
    watched: bool,
    log: VecDeque<Entry>,
}

impl Look {
    pub fn new(sources: Vec<Source>, tuning: Tuning) -> Look {
        Look {
            sources,
            tuning,
            target: None,
            priority: Priority::Boring,
            expires: 0.0,
            steady_since: None,
            next_friend: 0.0,
            last_eye: None,
            watched: false,
            log: VecDeque::new(),
        }
    }

    /// A request by source (its place in the config) to look at target. Whether it was
    /// taken: a lower priority waits out the current one, and the same priority waits
    /// for the head to have settled.
    pub fn aim(&mut self, now: f32, source: usize, target: Point) -> bool {
        let (priority, seconds) = {
            let asked = &self.sources[source];
            (asked.priority, asked.seconds.max(MIN_SECONDS))
        };
        if self.target.is_some() {
            if priority == self.priority && !self.settled(now) {
                return false;
            }
            if priority < self.priority && now < self.expires {
                return false;
            }
        }
        self.expires = now + seconds;
        self.priority = priority;
        if self
            .target
            .is_some_and(|held| distance(held, target) < SAME_TARGET)
        {
            return true;
        }
        self.target = Some(target);
        self.steady_since = None;
        if self.watched {
            if self.log.len() == LOG_SIZE {
                self.log.pop_front();
            }
            self.log.push_back(Entry {
                time: now,
                source,
                target,
            });
        }
        true
    }

    /// Where the head turns this tick, from eye at head toward the point it looks at.
    pub fn turn(&mut self, now: f32, interval: f32, eye: Point, head: Angles) -> Angles {
        let Some(target) = self.target else {
            return head;
        };
        let goal = angles_to(eye, target);
        let (pitch, yaw) = (goal.pitch - head.pitch, normal(goal.yaw - head.yaw));
        let largest = pitch.abs().max(yaw.abs());
        let step = self.tuning.turn_rate * interval;
        let scale = if largest <= step { 1.0 } else { step / largest };
        if largest * scale <= self.tuning.steady_rate * interval {
            self.steady_since.get_or_insert(now);
        } else {
            self.steady_since = None;
        }
        Angles {
            pitch: head.pitch + pitch * scale,
            yaw: normal(head.yaw + yaw * scale),
        }
    }

    fn settled(&self, now: f32) -> bool {
        self.steady_since
            .is_some_and(|since| now - since >= self.tuning.settle)
    }

    fn source_where(&self, is: impl Fn(&Kind) -> bool) -> Option<usize> {
        self.sources.iter().position(|source| is(&source.kind))
    }

    /// How far to look for a friend this tick, when one is due.
    pub fn friend_range(&self, now: f32) -> Option<f32> {
        if now < self.next_friend {
            return None;
        }
        self.sources.iter().find_map(|source| match source.kind {
            Kind::Friend { range, .. } => Some(range),
            _ => None,
        })
    }

    /// One tick: what its sources ask of what it sees, then the head's turn.
    pub fn upkeep(&mut self, now: f32, interval: f32, view: View) -> Angles {
        if self.friend_range(now).is_some() {
            let friendly = self.source_where(|kind| matches!(kind, Kind::Friend { .. }));
            if let Some(source) = friendly {
                if let Kind::Friend { every, .. } = self.sources[source].kind {
                    self.next_friend = now + every;
                }
                if let Some(friend) = view.friend {
                    self.aim(now, source, friend);
                }
            }
        }
        let facing = self.source_where(|kind| *kind == Kind::BodyFacing);
        if let (Some(source), Some(last)) = (facing, self.last_eye) {
            let (dx, dy) = (view.eye[0] - last[0], view.eye[1] - last[1]);
            let moved = (dx * dx + dy * dy).sqrt();
            if moved > MOVED && now >= self.expires {
                let ahead = FACING_REACH / moved;
                let point = [
                    view.eye[0] + dx * ahead,
                    view.eye[1] + dy * ahead,
                    view.eye[2],
                ];
                self.aim(now, source, point);
            }
        }
        self.last_eye = Some(view.eye);
        self.turn(now, interval, view.eye, view.head)
    }

    pub fn target(&self) -> Option<Point> {
        self.target
    }

    /// While watched, each new point it comes to look at is logged; unwatched, the log is let go.
    pub fn watch(&mut self, watched: bool) {
        self.watched = watched;
        if !watched {
            self.log.clear();
        }
    }

    /// The LOOK_AT layer's lines, oldest first, in the engine's own words.
    pub fn lines(&self, name: &str, time_offset: f32) -> Vec<String> {
        self.log
            .iter()
            .map(|entry| {
                let source = &self.sources[entry.source];
                format!(
                    "{:.2}: {} Look At ( {}, {}, {} ), Pri = {}, Reason = {}",
                    entry.time + time_offset,
                    name,
                    entry.target[0],
                    entry.target[1],
                    entry.target[2],
                    source.priority.name(),
                    source.reason
                )
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TUNING: Tuning = Tuning {
        settle: 0.3,
        steady_rate: 100.0,
        turn_rate: 720.0,
    };
    const BODY: usize = 0;
    const FRIEND: usize = 1;
    const THREAT: usize = 2;
    const FAR: Point = [1000.0, 0.0, 0.0];
    const LEFT: Point = [0.0, 1000.0, 0.0];
    const EYE: Point = [0.0, 0.0, 0.0];
    const AHEAD: Angles = Angles {
        pitch: 0.0,
        yaw: 0.0,
    };

    fn source(reason: &str, priority: Priority, seconds: f32, kind: Kind) -> Source {
        Source {
            reason: reason.to_string(),
            priority,
            seconds,
            kind,
        }
    }

    fn view(eye: Point, head: Angles, friend: Option<Point>) -> View {
        View { eye, head, friend }
    }

    fn look() -> Look {
        Look::new(
            vec![
                source("Body facing", Priority::Boring, 1.0, Kind::BodyFacing),
                source(
                    "Looking around at friend",
                    Priority::Boring,
                    2.0,
                    Kind::Friend {
                        range: 600.0,
                        every: 5.0,
                    },
                ),
                source("Looking at threat", Priority::Critical, 1.0, Kind::Asked),
            ],
            TUNING,
        )
    }

    /// A head left to turn on target until it has held still past the settle time.
    fn settled(look: &mut Look, mut now: f32) -> f32 {
        let mut head = AHEAD;
        for _ in 0..60 {
            head = look.turn(now, 0.015, EYE, head);
            now += 0.015;
        }
        now
    }

    #[test]
    fn a_first_request_is_taken() {
        let mut look = look();
        assert!(look.aim(0.0, BODY, FAR));
        assert_eq!(look.target(), Some(FAR));
    }

    #[test]
    fn a_higher_priority_takes_over_at_once() {
        let mut look = look();
        look.aim(0.0, BODY, FAR);
        assert!(look.aim(0.01, THREAT, LEFT));
        assert_eq!(look.target(), Some(LEFT));
    }

    #[test]
    fn a_lower_priority_waits_for_the_higher_to_run_out() {
        let mut look = look();
        look.aim(0.0, THREAT, LEFT);
        assert!(!look.aim(0.5, BODY, FAR), "still held");
        assert_eq!(look.target(), Some(LEFT));
        assert!(look.aim(1.5, BODY, FAR), "its second has passed");
    }

    #[test]
    fn the_same_priority_waits_for_the_head_to_settle() {
        let mut look = look();
        look.aim(0.0, BODY, FAR);
        assert!(
            !look.aim(0.01, FRIEND, LEFT),
            "the head is still on its way"
        );
        let now = settled(&mut look, 0.01);
        assert!(look.aim(now, FRIEND, LEFT), "it has settled");
    }

    #[test]
    fn the_same_target_renews_its_time_and_priority() {
        let mut look = look();
        look.aim(0.0, BODY, FAR);
        assert!(look.aim(0.01, THREAT, [1000.5, 0.0, 0.0]));
        assert_eq!(look.target(), Some(FAR), "the head need not move");
        assert!(!look.aim(0.5, BODY, LEFT), "at the higher priority now");
    }

    #[test]
    fn the_head_turns_no_faster_than_its_rate() {
        let mut look = look();
        look.aim(0.0, BODY, LEFT);
        let head = look.turn(0.0, 0.015, EYE, AHEAD);
        assert!((head.yaw - 720.0 * 0.015).abs() < 0.001, "{head:?}");
    }

    #[test]
    fn the_head_arrives_and_stays() {
        let mut look = look();
        look.aim(0.0, BODY, LEFT);
        let mut head = AHEAD;
        for tick in 0..60 {
            head = look.turn(tick as f32 * 0.015, 0.015, EYE, head);
        }
        assert!((head.yaw - 90.0).abs() < 0.001, "{head:?}");
    }

    #[test]
    fn it_turns_the_short_way_round() {
        let mut look = look();
        look.aim(0.0, BODY, [-1000.0, -100.0, 0.0]);
        let head = look.turn(
            0.0,
            0.015,
            EYE,
            Angles {
                pitch: 0.0,
                yaw: 170.0,
            },
        );
        assert!(
            (normal(head.yaw - 170.0) - 720.0 * 0.015).abs() < 0.001,
            "through 180, not back through 0: {head:?}"
        );
    }

    #[test]
    fn looking_below_is_a_positive_pitch() {
        let mut look = look();
        look.aim(0.0, BODY, [100.0, 0.0, -100.0]);
        let mut head = AHEAD;
        for tick in 0..60 {
            head = look.turn(tick as f32 * 0.015, 0.015, EYE, head);
        }
        assert!((head.pitch - 45.0).abs() < 0.001, "{head:?}");
    }

    #[test]
    fn with_nothing_to_look_at_the_head_stays() {
        let mut look = look();
        let head = look.turn(
            0.0,
            0.015,
            EYE,
            Angles {
                pitch: 5.0,
                yaw: 30.0,
            },
        );
        assert_eq!(
            head,
            Angles {
                pitch: 5.0,
                yaw: 30.0
            }
        );
    }

    #[test]
    fn unwatched_it_logs_nothing() {
        let mut look = look();
        look.aim(0.0, BODY, FAR);
        assert!(look.lines("Coach", 0.0).is_empty());
    }

    #[test]
    fn watched_it_logs_each_new_point_in_the_engines_words() {
        let mut look = look();
        look.watch(true);
        look.aim(954.6, BODY, [254.0, 5866.0, 2910.5]);
        look.aim(954.7, FRIEND, LEFT);
        assert_eq!(
            look.lines("Ellis", 0.0),
            vec!["954.60: Ellis Look At ( 254, 5866, 2910.5 ), Pri = BORING, Reason = Body facing"],
            "the refused one is not logged"
        );
    }

    #[test]
    fn its_log_keeps_the_newest_and_goes_when_unwatched() {
        let mut look = look();
        look.watch(true);
        let mut now = 0.0;
        for i in 0..(LOG_SIZE + 5) {
            assert!(look.aim(now, THREAT, [i as f32 * 10.0, 0.0, 0.0]));
            now = settled(&mut look, now);
        }
        let lines = look.lines("Coach", 0.0);
        assert_eq!(lines.len(), LOG_SIZE);
        assert!(lines[0].contains("( 50, 0, 0 )"), "{}", lines[0]);
        look.watch(false);
        assert!(look.lines("Coach", 0.0).is_empty());
    }

    #[test]
    fn walking_it_faces_the_way_it_goes() {
        let mut look = look();
        look.upkeep(0.0, 0.015, view(EYE, AHEAD, None));
        let head = look.upkeep(0.015, 0.015, view([0.0, 3.0, 0.0], AHEAD, None));
        assert!(head.yaw > 0.0, "turning to +y: {head:?}");
        let target = look.target().expect("a point ahead of it");
        assert!(target[1] > 100.0 && target[0].abs() < 0.001, "{target:?}");
        assert_eq!(target[2], 0.0, "level with its eyes");
    }

    #[test]
    fn standing_still_it_keeps_looking_where_it_was() {
        let mut look = look();
        look.upkeep(0.0, 0.015, view(EYE, AHEAD, None));
        look.upkeep(0.015, 0.015, view(EYE, AHEAD, None));
        assert_eq!(look.target(), None);
    }

    #[test]
    fn facing_waits_out_what_it_looks_at() {
        let mut look = look();
        look.aim(0.0, THREAT, LEFT);
        look.upkeep(0.0, 0.015, view(EYE, AHEAD, None));
        look.upkeep(0.5, 0.015, view([3.0, 0.0, 0.0], AHEAD, None));
        assert_eq!(look.target(), Some(LEFT), "held a second");
    }

    #[test]
    fn it_asks_for_a_friend_when_one_is_due() {
        let mut look = look();
        assert_eq!(look.friend_range(0.0), Some(600.0), "at once");
        look.upkeep(0.0, 0.015, view(EYE, AHEAD, Some(FAR)));
        assert_eq!(look.target(), Some(FAR), "looks at them");
        assert_eq!(look.friend_range(1.0), None, "not again so soon");
        assert_eq!(
            look.friend_range(5.1),
            Some(600.0),
            "its time has come round"
        );
    }

    #[test]
    fn with_no_friend_near_it_looks_for_one_again_later() {
        let mut look = look();
        look.upkeep(0.0, 0.015, view(EYE, AHEAD, None));
        assert_eq!(look.friend_range(1.0), None, "not every tick");
    }

    #[test]
    fn a_friend_is_not_looked_away_from_by_walking() {
        let mut look = look();
        look.upkeep(0.0, 0.015, view(EYE, AHEAD, Some(FAR)));
        look.upkeep(1.0, 0.015, view([0.0, 3.0, 0.0], AHEAD, None));
        assert_eq!(look.target(), Some(FAR), "two seconds it holds");
    }

    #[test]
    fn with_no_source_for_it_nothing_is_asked() {
        let mut look = Look::new(vec![], TUNING);
        assert_eq!(look.friend_range(0.0), None);
        let head = look.upkeep(0.0, 0.015, view(EYE, AHEAD, Some(FAR)));
        assert_eq!(head, AHEAD);
    }

    #[test]
    fn its_log_reads_in_the_games_time() {
        let mut look = look();
        look.watch(true);
        look.aim(10.0, BODY, FAR);
        assert!(
            look.lines("Coach", 100.0)[0].starts_with("110.00:"),
            "{:?}",
            look.lines("Coach", 100.0)
        );
    }

    #[test]
    fn priorities_are_read_by_name_and_refuse_others() {
        assert_eq!(Priority::parse("CRITICAL"), Some(Priority::Critical));
        assert_eq!(Priority::parse("boring"), None);
        assert!(
            Priority::Mandatory > Priority::Critical && Priority::Interesting > Priority::Boring
        );
    }
}
