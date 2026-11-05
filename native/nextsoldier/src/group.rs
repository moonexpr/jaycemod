//! The root of the tree a soldier runs beside its main one, as L4D2's survivors run their
//! legs: GroupIdentityBehavior. It runs what its config starts it on; what it holds of a
//! soldier's group grows here, in Rust, since it runs every update.

/// How near a teammate pushes, and how far above or below one no longer does.
pub const SPACING: f32 = 72.0;
pub const SPACING_HEIGHT: f32 = 64.0;
/// Nearer than this, no direction between them can be trusted.
const TOGETHER: f32 = 1.0;
/// Radians: successive whole numbers fall well apart around a circle.
const GOLDEN_ANGLE: f32 = 2.399_963;

/// Which way, and how hard from 0 to 1, a soldier at `me` is pushed by the teammates at
/// `others`, across the ground: boids' separation, harder the nearer. `tie` tells apart those
/// standing exactly together, whom no direction separates otherwise.
pub fn separation(me: [f32; 3], others: &[[f32; 3]], tie: u32) -> [f32; 2] {
    let (mut x, mut y) = (0.0, 0.0);
    for other in others {
        if (other[2] - me[2]).abs() > SPACING_HEIGHT {
            continue;
        }
        let (dx, dy) = (me[0] - other[0], me[1] - other[1]);
        let distance = (dx * dx + dy * dy).sqrt();
        if distance >= SPACING {
            continue;
        }
        let strength = 1.0 - distance / SPACING;
        let (away_x, away_y) = if distance < TOGETHER {
            let angle = tie as f32 * GOLDEN_ANGLE;
            (angle.cos(), angle.sin())
        } else {
            (dx / distance, dy / distance)
        };
        x += away_x * strength;
        y += away_y * strength;
    }
    let length = (x * x + y * y).sqrt();
    if length > 1.0 {
        [x / length, y / length]
    } else {
        [x, y]
    }
}

#[cfg(all(windows, target_arch = "x86_64"))]
pub(crate) use hooks::KIND;

#[cfg(all(windows, target_arch = "x86_64"))]
mod hooks {
    use crate::engine::{self, Kind};
    use crate::layout::*;
    use foundation::lua::{api, raise_where, L, TTABLE};
    use std::ffi::{c_int, c_void, CStr};

    const NAME: &CStr = c"GroupIdentityBehavior";

    pub(crate) const KIND: Kind = Kind {
        name: NAME,
        slots,
        init,
        constructor,
    };

    fn slots() -> Vec<(usize, usize)> {
        vec![(INITIAL_CONTAINED, initial_contained as *const () as usize)]
    }

    unsafe fn init(_l: L, _config: c_int) -> u64 {
        0
    }

    /// engine.GroupIdentityBehavior{ initial } -> the root, for engine.InsertGroup: `initial`
    /// the action it runs first.
    unsafe extern "C-unwind" fn constructor(l: L) -> c_int {
        let api = api();
        (api.settop)(l, 1);
        (api.checktype)(l, 1, TTABLE);
        (api.getfield)(l, 1, c"initial".as_ptr());
        if (api.type_of)(l, -1) != TTABLE {
            raise_where(
                l,
                "GroupIdentityBehavior needs the action it runs first".into(),
            );
        }
        (api.settop)(l, 1);
        engine::mark_config(l, NAME);
        1
    }

    unsafe extern "win64" fn initial_contained(
        this: *mut LuaAction,
        _me: *mut c_void,
    ) -> *mut Action {
        engine::with_config(this, |l| {
            (api().getfield)(l, -1, c"initial".as_ptr());
            engine::action_from_top(l, this)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ME: [f32; 3] = [0.0, 0.0, 0.0];

    fn length(push: [f32; 2]) -> f32 {
        (push[0] * push[0] + push[1] * push[1]).sqrt()
    }

    #[test]
    fn nobody_near_pushes_nothing() {
        assert_eq!(separation(ME, &[], 1), [0.0, 0.0]);
        assert_eq!(separation(ME, &[[SPACING + 1.0, 0.0, 0.0]], 1), [0.0, 0.0]);
    }

    #[test]
    fn a_teammate_pushes_it_away() {
        let push = separation(ME, &[[10.0, 0.0, 0.0]], 1);
        assert!(push[0] < 0.0, "{push:?}");
        assert!(push[1].abs() < 0.001, "{push:?}");
    }

    #[test]
    fn the_nearer_the_harder() {
        let near = separation(ME, &[[10.0, 0.0, 0.0]], 1);
        let far = separation(ME, &[[60.0, 0.0, 0.0]], 1);
        assert!(length(near) > length(far), "{near:?} {far:?}");
    }

    #[test]
    fn it_never_pushes_harder_than_one() {
        let crowd = [
            [5.0, 0.0, 0.0],
            [6.0, 1.0, 0.0],
            [5.0, -1.0, 0.0],
            [7.0, 0.0, 0.0],
        ];
        assert!(length(separation(ME, &crowd, 1)) <= 1.0 + 0.001);
    }

    #[test]
    fn teammates_either_side_cancel() {
        let push = separation(ME, &[[20.0, 0.0, 0.0], [-20.0, 0.0, 0.0]], 1);
        assert!(length(push) < 0.001, "{push:?}");
    }

    #[test]
    fn one_on_another_floor_does_not_push() {
        assert_eq!(
            separation(ME, &[[0.0, 5.0, SPACING_HEIGHT + 1.0]], 1),
            [0.0, 0.0]
        );
    }

    #[test]
    fn two_on_the_same_spot_go_different_ways() {
        let a = separation(ME, &[ME], 1);
        let b = separation(ME, &[ME], 2);
        assert!(length(a) > 0.5, "pushed, not stuck together: {a:?}");
        assert!(
            a[0] * b[0] + a[1] * b[1] < length(a) * length(b) * 0.99,
            "{a:?} {b:?}"
        );
    }
}
