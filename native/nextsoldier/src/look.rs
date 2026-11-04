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

#[derive(Clone, Debug)]
pub struct Source {
    pub reason: String,
    pub priority: Priority,
    pub seconds: f32,
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
    pub fn lines(&self, name: &str) -> Vec<String> {
        self.log
            .iter()
            .map(|entry| {
                let source = &self.sources[entry.source];
                format!(
                    "{:.2}: {} Look At ( {}, {}, {} ), Pri = {}, Reason = {}",
                    entry.time,
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

    fn source(reason: &str, priority: Priority, seconds: f32) -> Source {
        Source {
            reason: reason.to_string(),
            priority,
            seconds,
        }
    }

    fn look() -> Look {
        Look::new(
            vec![
                source("Body facing", Priority::Boring, 1.0),
                source("Looking around at friend", Priority::Boring, 2.0),
                source("Looking at threat", Priority::Critical, 1.0),
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
        assert!(look.lines("Coach").is_empty());
    }

    #[test]
    fn watched_it_logs_each_new_point_in_the_engines_words() {
        let mut look = look();
        look.watch(true);
        look.aim(954.6, BODY, [254.0, 5866.0, 2910.5]);
        look.aim(954.7, FRIEND, LEFT);
        assert_eq!(
            look.lines("Ellis"),
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
        let lines = look.lines("Coach");
        assert_eq!(lines.len(), LOG_SIZE);
        assert!(lines[0].contains("( 50, 0, 0 )"), "{}", lines[0]);
        look.watch(false);
        assert!(look.lines("Coach").is_empty());
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
