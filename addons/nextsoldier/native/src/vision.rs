//! What a soldier knows of the others about it, as IVision keeps it. The engine is asked
//! where they are (`crate::engine`); which of them matters is decided here.

use crate::body::look::Point;

/// IVision::GetClosestKnown: the nearest of `known` to `eye`, nearer than `range`. Of
/// those exactly as near, the first.
pub fn closest_known(eye: Point, known: &[Point], range: f32) -> Option<Point> {
    let mut best = None;
    let mut nearest = range;
    for &at in known {
        let far =
            ((at[0] - eye[0]).powi(2) + (at[1] - eye[1]).powi(2) + (at[2] - eye[2]).powi(2)).sqrt();
        if far < nearest {
            nearest = far;
            best = Some(at);
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    const EYE: Point = [0.0, 0.0, 64.0];

    #[test]
    fn test_closest_known_none_when_nobody_is_known() {
        assert_eq!(closest_known(EYE, &[], 500.0), None);
    }

    #[test]
    fn test_closest_known_picks_the_nearest() {
        let known = [[300.0, 0.0, 64.0], [0.0, 100.0, 64.0], [0.0, 0.0, 400.0]];
        assert_eq!(closest_known(EYE, &known, 500.0), Some([0.0, 100.0, 64.0]));
    }

    #[test]
    fn test_closest_known_measures_height_too() {
        let known = [[0.0, 0.0, 264.0], [150.0, 0.0, 64.0]];
        assert_eq!(closest_known(EYE, &known, 500.0), Some([150.0, 0.0, 64.0]));
    }

    #[test]
    fn test_closest_known_ignores_one_at_or_beyond_range() {
        assert_eq!(closest_known(EYE, &[[100.0, 0.0, 64.0]], 100.0), None);
        assert_eq!(
            closest_known(EYE, &[[99.0, 0.0, 64.0]], 100.0),
            Some([99.0, 0.0, 64.0])
        );
    }

    #[test]
    fn test_closest_known_ties_go_to_the_first() {
        let known = [[0.0, 50.0, 64.0], [50.0, 0.0, 64.0]];
        assert_eq!(closest_known(EYE, &known, 500.0), Some([0.0, 50.0, 64.0]));
    }
}
