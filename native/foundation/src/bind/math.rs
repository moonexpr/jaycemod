//! math.geometry, scalar, stats, weighted, polynomial, matrix and polyline,
//! native: the Lua twins' contracts (foundation/math/), their arithmetic
//! operation for operation (LuaJIT's x^2 and x^3 are products, so they are
//! here), so the doubles agree.

use super::util::{each_item, nothing, number, number_at};
use crate::lua::{field_number, raise_at, raise_where, tostring, CFunction, L, TTABLE};
use crate::module;
use crate::userdata::{self, Native};
use std::ffi::{c_int, CStr};

type Point = [f64; 3];

/// The point table at `index`: x and y numbers, z a number or 0.
pub(super) unsafe fn point_at(l: L, index: c_int) -> [f64; 3] {
    if !super::util::indexable(l, index) {
        raise_where(l, "a point is a { x, y, z } table or a Vector".into());
    }
    let x = field_number(l, index, c"x");
    let y = field_number(l, index, c"y");
    let (Some(x), Some(y)) = (x, y) else { raise_where(l, "a point needs a number x and y".into()) };
    [x, y, field_number(l, index, c"z").unwrap_or(0.0)]
}

/// Pushes { x, y, z } (z left out when None); one result.
unsafe fn push_point(l: L, x: f64, y: f64, z: Option<f64>) -> c_int {
    l.createtable(0, 3);
    l.pushnumber(x);
    l.setfield(-2, c"x");
    l.pushnumber(y);
    l.setfield(-2, c"y");
    if let Some(z) = z {
        l.pushnumber(z);
        l.setfield(-2, c"z");
    }
    1
}

// math.geometry -------------------------------------------------------------

unsafe extern "C-unwind" fn distance(l: L) -> c_int {
    let (a, b) = (point_at(l, 1), point_at(l, 2));
    let (dx, dy, dz) = (a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    number(l, (dx * dx + dy * dy + dz * dz).sqrt())
}

fn distance_2d(a: &Point, b: &Point) -> f64 {
    let (dx, dy) = (a[0] - b[0], a[1] - b[1]);
    (dx * dx + dy * dy).sqrt()
}

unsafe extern "C-unwind" fn distance2d(l: L) -> c_int {
    number(l, distance_2d(&point_at(l, 1), &point_at(l, 2)))
}

unsafe extern "C-unwind" fn toward(l: L) -> c_int {
    let (from, to) = (point_at(l, 1), point_at(l, 2));
    let d = l.checknumber(3);
    let length = distance_2d(&from, &to);
    if length <= d || length == 0.0 {
        return push_point(l, to[0], to[1], field_number(l, 2, c"z"));
    }
    let t = d / length;
    push_point(l, from[0] + (to[0] - from[0]) * t, from[1] + (to[1] - from[1]) * t, field_number(l, 1, c"z"))
}

unsafe extern "C-unwind" fn add(l: L) -> c_int {
    let (a, b) = (point_at(l, 1), point_at(l, 2));
    push_point(l, a[0] + b[0], a[1] + b[1], Some(a[2] + b[2]))
}

unsafe extern "C-unwind" fn sub(l: L) -> c_int {
    let (a, b) = (point_at(l, 1), point_at(l, 2));
    push_point(l, a[0] - b[0], a[1] - b[1], Some(a[2] - b[2]))
}

unsafe extern "C-unwind" fn scale(l: L) -> c_int {
    let a = point_at(l, 1);
    let s = l.checknumber(2);
    push_point(l, a[0] * s, a[1] * s, Some(a[2] * s))
}

fn dot_of(a: &Point, b: &Point) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

unsafe extern "C-unwind" fn dot(l: L) -> c_int {
    number(l, dot_of(&point_at(l, 1), &point_at(l, 2)))
}

unsafe extern "C-unwind" fn cross(l: L) -> c_int {
    let (a, b) = (point_at(l, 1), point_at(l, 2));
    push_point(l, a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], Some(a[0] * b[1] - a[1] * b[0]))
}

unsafe extern "C-unwind" fn length(l: L) -> c_int {
    let a = point_at(l, 1);
    number(l, dot_of(&a, &a).sqrt())
}

unsafe extern "C-unwind" fn normalize(l: L) -> c_int {
    let a = point_at(l, 1);
    let length = dot_of(&a, &a).sqrt();
    if length == 0.0 {
        return nothing(l);
    }
    let s = 1.0 / length;
    push_point(l, a[0] * s, a[1] * s, Some(a[2] * s))
}

unsafe extern "C-unwind" fn distance_squared(l: L) -> c_int {
    let (a, b) = (point_at(l, 1), point_at(l, 2));
    let (dx, dy, dz) = (a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    number(l, dx * dx + dy * dy + dz * dz)
}

unsafe extern "C-unwind" fn normalize2d(l: L) -> c_int {
    let a = point_at(l, 1);
    let length = (a[0] * a[0] + a[1] * a[1]).sqrt();
    if length == 0.0 {
        return nothing(l);
    }
    push_point(l, a[0] / length, a[1] / length, Some(0.0))
}

unsafe extern "C-unwind" fn left2d(l: L) -> c_int {
    let a = point_at(l, 1);
    push_point(l, -a[1], a[0], Some(0.0))
}

unsafe extern "C-unwind" fn offset2d(l: L) -> c_int {
    let (p, from) = (point_at(l, 1), point_at(l, 2));
    let (along, across) = (l.checknumber(3), l.checknumber(4));
    let (dx, dy) = (p[0] - from[0], p[1] - from[1]);
    let length = (dx * dx + dy * dy).sqrt();
    if length == 0.0 {
        return push_point(l, p[0], p[1], Some(p[2]));
    }
    let (ux, uy) = (dx / length, dy / length);
    push_point(l, p[0] + ux * along + -uy * across, p[1] + uy * along + ux * across, Some(p[2]))
}

unsafe extern "C-unwind" fn closest_on_segment(l: L) -> c_int {
    let (p, a, b) = (point_at(l, 1), point_at(l, 2), point_at(l, 3));
    let (abx, aby, abz) = (b[0] - a[0], b[1] - a[1], b[2] - a[2]);
    let length2 = abx * abx + aby * aby + abz * abz;
    let mut t = 0.0;
    if length2 > 0.0 {
        t = (((p[0] - a[0]) * abx + (p[1] - a[1]) * aby + (p[2] - a[2]) * abz) / length2).clamp(0.0, 1.0);
    }
    push_point(l, a[0] + abx * t, a[1] + aby * t, Some(a[2] + abz * t))
}

fn polar_of(center: &Point, radius: f64, angle: f64) -> Point {
    [center[0] + angle.cos() * radius, center[1] + angle.sin() * radius, center[2]]
}

unsafe extern "C-unwind" fn polar(l: L) -> c_int {
    let center = point_at(l, 1);
    let (radius, angle) = (l.checknumber(2), l.checknumber(3));
    let at = polar_of(&center, radius, angle);
    push_point(l, at[0], at[1], Some(at[2]))
}

unsafe extern "C-unwind" fn circle(l: L) -> c_int {
    let center = point_at(l, 1);
    let (radius, count, start) = (l.checknumber(2), l.checknumber(3), l.checknumber(4));
    if !(count >= 1.0) || count.floor() != count {
        raise_where(l, format!("a circle's count is a whole number of at least 1, not {}", tostring(l, 3)));
    }
    l.createtable(count as c_int, 0);
    for i in 0..count as c_int {
        let at = polar_of(&center, radius, start + (i as f64 * (2.0 * std::f64::consts::PI)) / count);
        push_point(l, at[0], at[1], Some(at[2]));
        l.rawseti(-2, i + 1);
    }
    1
}

/// A whole count of at least 1 at `index`, else raised naming `what`.
unsafe fn count_at(l: L, index: c_int, what: &str) -> c_int {
    let count = l.checknumber(index);
    if !(count >= 1.0) || count.floor() != count {
        raise_where(l, format!("{what} is a whole number of at least 1, not {}", tostring(l, index)));
    }
    count as c_int
}

fn normalized(a: &Point) -> Option<Point> {
    let length = dot_of(a, a).sqrt();
    if length == 0.0 {
        return None;
    }
    let s = 1.0 / length;
    Some([a[0] * s, a[1] * s, a[2] * s])
}

fn crossed(a: &Point, b: &Point) -> Point {
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}

unsafe extern "C-unwind" fn sphere(l: L) -> c_int {
    let center = point_at(l, 1);
    let radius = l.checknumber(2);
    let count = count_at(l, 3, "a sphere's count");
    let golden = std::f64::consts::PI * (3.0 - 5f64.sqrt());
    let n = count as f64;
    l.createtable(count, 0);
    for i in 0..count {
        let z = 1.0 - (2.0 * i as f64 + 1.0) / n;
        let (across, turn) = ((1.0 - z * z).sqrt(), i as f64 * golden);
        push_point(l, center[0] + turn.cos() * across * radius, center[1] + turn.sin() * across * radius, Some(center[2] + z * radius));
        l.rawseti(-2, i + 1);
    }
    1
}

unsafe extern "C-unwind" fn frustum(l: L) -> c_int {
    let (eye, forward) = (point_at(l, 1), point_at(l, 2));
    let (hfov, vfov, range) = (l.checknumber(3), l.checknumber(4), l.checknumber(5));
    let cols = count_at(l, 6, "a frustum's columns");
    let rows = count_at(l, 7, "a frustum's rows");
    let Some(ahead) = normalized(&forward) else { raise_where(l, "a frustum's forward has no direction".into()) };
    let right = normalized(&crossed(&ahead, &[0.0, 0.0, 1.0])).unwrap_or([0.0, -1.0, 0.0]);
    let up = crossed(&right, &ahead);
    let (across, high) = ((hfov / 2.0).tan(), (vfov / 2.0).tan());
    l.createtable(cols * rows, 0);
    let mut at = 0;
    for row in 0..rows {
        let v = if rows == 1 { 0.0 } else { (1.0 - 2.0 * row as f64 / (rows - 1) as f64) * high };
        for col in 0..cols {
            let u = if cols == 1 { 0.0 } else { (-1.0 + 2.0 * col as f64 / (cols - 1) as f64) * across };
            let p: Vec<f64> = (0..3).map(|k| eye[k] + (ahead[k] + right[k] * u + up[k] * v) * range).collect();
            push_point(l, p[0], p[1], Some(p[2]));
            at += 1;
            l.rawseti(-2, at);
        }
    }
    1
}

// math.scalar ---------------------------------------------------------------

unsafe extern "C-unwind" fn clamp(l: L) -> c_int {
    let (value, low, high) = (l.checknumber(1), l.checknumber(2), l.checknumber(3));
    if low > high {
        let (lo, hi) = (tostring(l, 2), tostring(l, 3));
        raise_where(l, format!("an empty range: {lo} above {hi}"));
    }
    number(l, if value < low { low } else if value > high { high } else { value })
}

fn saturate_of(value: f64) -> f64 {
    value.clamp(0.0, 1.0)
}

unsafe extern "C-unwind" fn saturate(l: L) -> c_int {
    number(l, saturate_of(l.checknumber(1)))
}

unsafe extern "C-unwind" fn lerp(l: L) -> c_int {
    let (a, b, t) = (l.checknumber(1), l.checknumber(2), l.checknumber(3));
    number(l, a + (b - a) * t)
}

/// The fraction of the span `a..b` that `value` covers, held to [0, 1]; a span with no length is
/// the caller's mistake, raised at the caller's line.
unsafe fn span_fraction(l: L, value: f64, a_index: c_int) -> f64 {
    let (a, b) = (l.checknumber(a_index), l.checknumber(a_index + 1));
    if a == b {
        let (from, to) = (tostring(l, a_index), tostring(l, a_index + 1));
        raise_where(l, format!("a span with no length: {from} to {to}"));
    }
    saturate_of((value - a) / (b - a))
}

unsafe extern "C-unwind" fn inverse_lerp(l: L) -> c_int {
    let value = l.checknumber(3);
    number(l, span_fraction(l, value, 1))
}

unsafe extern "C-unwind" fn remap(l: L) -> c_int {
    let value = l.checknumber(1);
    let t = span_fraction(l, value, 2);
    let (c, d) = (l.checknumber(4), l.checknumber(5));
    number(l, c + (d - c) * t)
}

// math.interval -------------------------------------------------------------

unsafe extern "C-unwind" fn interval_overlaps(l: L) -> c_int {
    let (alo, ahi, blo, bhi) = (l.checknumber(1), l.checknumber(2), l.checknumber(3), l.checknumber(4));
    super::util::boolean(l, alo <= bhi && blo <= ahi)
}

unsafe extern "C-unwind" fn interval_intersect(l: L) -> c_int {
    let (alo, ahi, blo, bhi) = (l.checknumber(1), l.checknumber(2), l.checknumber(3), l.checknumber(4));
    l.pushnumber(if alo > blo { alo } else { blo });
    l.pushnumber(if ahi < bhi { ahi } else { bhi });
    2
}

// math.box ------------------------------------------------------------------

unsafe extern "C-unwind" fn box_overlaps(l: L) -> c_int {
    let (a_mins, a_maxs, b_mins, b_maxs) = (point_at(l, 1), point_at(l, 2), point_at(l, 3), point_at(l, 4));
    let overlap = (0..3).all(|axis| a_mins[axis] <= b_maxs[axis] && b_mins[axis] <= a_maxs[axis]);
    super::util::boolean(l, overlap)
}

unsafe extern "C-unwind" fn box_contains(l: L) -> c_int {
    let (mins, maxs, p) = (point_at(l, 1), point_at(l, 2), point_at(l, 3));
    super::util::boolean(l, (0..3).all(|axis| p[axis] >= mins[axis] && p[axis] <= maxs[axis]))
}

unsafe extern "C-unwind" fn box_extent(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let mut corners: Option<(Point, Point)> = None;
    each_item(l, 1, |l, p| {
        let at = point_at(l, p);
        match &mut corners {
            None => corners = Some((at, at)),
            Some((lo, hi)) => {
                for axis in 0..3 {
                    if at[axis] < lo[axis] {
                        lo[axis] = at[axis];
                    }
                    if at[axis] > hi[axis] {
                        hi[axis] = at[axis];
                    }
                }
            }
        }
    });
    match corners {
        None => nothing(l),
        Some((lo, hi)) => {
            push_point(l, lo[0], lo[1], Some(lo[2]));
            push_point(l, hi[0], hi[1], Some(hi[2]));
            2
        }
    }
}

unsafe extern "C-unwind" fn box_centered(l: L) -> c_int {
    let half = l.checknumber(1) / 2.0;
    push_point(l, -half, -half, Some(-half));
    push_point(l, half, half, Some(half));
    2
}

unsafe extern "C-unwind" fn box_standing(l: L) -> c_int {
    let (half, height) = (l.checknumber(1) / 2.0, l.checknumber(2));
    push_point(l, -half, -half, Some(0.0));
    push_point(l, half, half, Some(height));
    2
}

unsafe extern "C-unwind" fn box_longest_axis_2d(l: L) -> c_int {
    let (mins, maxs) = (point_at(l, 1), point_at(l, 2));
    crate::lua::push_str(l, if maxs[0] - mins[0] >= maxs[1] - mins[1] { "x" } else { "y" });
    1
}

// math.choice ---------------------------------------------------------------

/// A place from 1 to n, drawn by the function at `source`; an answer outside that is our bug, refused.
unsafe fn place(l: L, source: c_int, n: usize) -> usize {
    l.pushvalue(source);
    l.pushnumber(1.0);
    l.pushnumber(n as f64);
    l.call(2, 1);
    let k = number_at(l, -1).unwrap_or(f64::NAN);
    if !(k >= 1.0 && k <= n as f64) || k.fract() != 0.0 {
        let given = tostring(l, -1);
        raise_where(l, format!("the random source gave {given} for 1 to {n}"));
    }
    l.settop(-2);
    k as usize
}

/// Pushes a new list holding the items of the list at `list` (up to the first nil); its length.
unsafe fn copy_list(l: L, list: c_int) -> usize {
    l.createtable(0, 0);
    let copy = l.gettop();
    let mut n = 0;
    each_item(l, list, |l, item| {
        n += 1;
        l.pushvalue(item);
        l.rawseti(copy, n as c_int);
    });
    n
}

unsafe extern "C-unwind" fn choice_shuffle(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(2, crate::lua::TFUNCTION);
    let mut n = copy_list(l, 1);
    let out = l.gettop();
    while n > 1 {
        let k = place(l, 2, n);
        l.rawgeti(out, n as c_int);
        l.rawgeti(out, k as c_int);
        l.rawseti(out, n as c_int);
        l.rawseti(out, k as c_int);
        n -= 1;
    }
    1
}

unsafe extern "C-unwind" fn choice_draw(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(3, crate::lua::TFUNCTION);
    let count = number_at(l, 2).unwrap_or(f64::NAN);
    if !(count >= 0.0) || count.fract() != 0.0 {
        let given = tostring(l, 2);
        raise_where(l, format!("a draw's count is a whole number of at least 0, not {given}"));
    }
    let mut left = copy_list(l, 1);
    let pool = l.gettop();
    l.createtable(0, 0);
    let out = l.gettop();
    let mut taken = 0usize;
    while left > 0 && (taken as f64) < count {
        let k = place(l, 3, left);
        l.rawgeti(pool, k as c_int);
        taken += 1;
        l.rawseti(out, taken as c_int);
        l.rawgeti(pool, left as c_int);
        l.rawseti(pool, k as c_int);
        l.pushnil();
        l.rawseti(pool, left as c_int);
        left -= 1;
    }
    1
}

// math.stats ----------------------------------------------------------------

/// The numbers of the list at `index`, in order until the first nil.
unsafe fn numbers(l: L, index: c_int) -> Vec<f64> {
    l.checktype(index, TTABLE);
    let mut out = Vec::new();
    each_item(l, index, |l, v| {
        let n = number_at(l, v);
        out.push(n.unwrap_or(f64::NAN));
    });
    out
}

unsafe extern "C-unwind" fn mean(l: L) -> c_int {
    let n = l.objlen(1);
    if n == 0 {
        return number(l, 0.0);
    }
    let values = numbers(l, 1);
    let sum = values.iter().fold(0.0, |sum, v| sum + v);
    drop(values);
    number(l, sum / n as f64)
}

unsafe extern "C-unwind" fn percentile(l: L) -> c_int {
    let p = l.checknumber(2);
    let mut sorted = numbers(l, 1);
    if sorted.is_empty() {
        return number(l, 0.0);
    }
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let rank = (p * sorted.len() as f64).ceil().max(1.0) as usize;
    let value = sorted.get(rank - 1).copied();
    drop(sorted);
    match value {
        Some(v) => number(l, v),
        None => nothing(l),
    }
}

// math.weighted -------------------------------------------------------------

/// Weight(item at `item`), the weight function at 2.
unsafe fn weight(l: L, item: c_int) -> f64 {
    l.pushvalue(2);
    l.pushvalue(item);
    l.call(1, 1);
    let w = l.tonumber(-1);
    l.settop(-2);
    w
}

unsafe extern "C-unwind" fn pick_weighted(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let r = l.checknumber(3);
    l.settop(3);
    let mut total = 0.0;
    each_item(l, 1, |l, item| total += weight(l, item));
    if total <= 0.0 {
        l.rawgeti(1, 1);
        return 1;
    }
    let mut target = r * total;
    let mut picked = 0;
    let mut i = 0;
    each_item(l, 1, |l, item| {
        i += 1;
        if picked == 0 {
            target -= weight(l, item);
            if target < 0.0 {
                picked = i;
            }
        }
    });
    let at = if picked > 0 { picked } else { l.objlen(1) as c_int };
    l.rawgeti(1, at);
    1
}

// math.polynomial -----------------------------------------------------------

const EPSILON: f64 = 1e-12;

unsafe extern "C-unwind" fn evaluate(l: L) -> c_int {
    let x = l.checknumber(2);
    let c = numbers(l, 1);
    let sum = c.iter().rev().fold(0.0, |sum, &ci| sum * x + ci);
    drop(c);
    number(l, sum)
}

unsafe fn push_list(l: L, values: &[f64]) -> c_int {
    l.createtable(values.len() as c_int, 0);
    for (i, &v) in values.iter().enumerate() {
        l.pushnumber(v);
        l.rawseti(-2, i as c_int + 1);
    }
    1
}

unsafe extern "C-unwind" fn derivative(l: L) -> c_int {
    let c = numbers(l, 1);
    let d: Vec<f64> = c.iter().enumerate().skip(1).map(|(i, &ci)| ci * i as f64).collect();
    drop(c);
    let pushed = push_list(l, &d);
    drop(d);
    pushed
}

fn cbrt(x: f64) -> f64 {
    if x < 0.0 {
        -(-x).powf(1.0 / 3.0)
    } else {
        x.powf(1.0 / 3.0)
    }
}

fn quadratic(c0: f64, c1: f64, c2: f64) -> Vec<f64> {
    let disc = c1 * c1 - 4.0 * c2 * c0;
    if disc < 0.0 {
        return vec![];
    }
    if disc == 0.0 {
        return vec![-c1 / (2.0 * c2)];
    }
    let q = -0.5 * (c1 + (if c1 < 0.0 { -1.0 } else { 1.0 }) * disc.sqrt());
    if q == 0.0 {
        return vec![0.0];
    }
    vec![q / c2, c0 / q]
}

fn cube(x: f64) -> f64 {
    x * (x * x)
}

fn cubic(c0: f64, c1: f64, c2: f64, c3: f64) -> Vec<f64> {
    let (a, b, c) = (c2 / c3, c1 / c3, c0 / c3);
    let p = b - a * a / 3.0;
    let q = 2.0 * a * a * a / 27.0 - a * b / 3.0 + c;
    let shift = a / 3.0;
    let half = q / 2.0;
    let third = p / 3.0;
    let disc = half * half + cube(third);
    let scale = 1f64.max(q.abs() * q.abs()).max(cube(p.abs()));
    if disc > EPSILON * scale {
        let root = disc.sqrt();
        return vec![cbrt(-q / 2.0 + root) + cbrt(-q / 2.0 - root) - shift];
    }
    if disc < -EPSILON * scale {
        let r = (-p / 3.0).sqrt();
        let cosine = (-q / (2.0 * r * r * r)).clamp(-1.0, 1.0);
        let phi = cosine.acos();
        return (0..3).map(|k| 2.0 * r * ((phi + 2.0 * std::f64::consts::PI * k as f64) / 3.0).cos() - shift).collect();
    }
    if p.abs() <= EPSILON * scale {
        return vec![-shift];
    }
    vec![3.0 * q / p - shift, -3.0 * q / (2.0 * p) - shift]
}

unsafe extern "C-unwind" fn roots(l: L) -> c_int {
    let c = numbers(l, 1);
    let mut degree = c.len() as i64 - 1;
    while degree > 0 && c[degree as usize] == 0.0 {
        degree -= 1;
    }
    if degree > 3 {
        drop(c);
        raise_where(l, format!("polynomial roots are solved up to cubics, not degree {degree}"));
    }
    let mut roots = match degree {
        i64::MIN..=0 => vec![],
        1 => vec![-c[0] / c[1]],
        2 => quadratic(c[0], c[1], c[2]),
        _ => cubic(c[0], c[1], c[2], c[3]),
    };
    drop(c);
    roots.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let mut distinct = Vec::new();
    let mut last = f64::NEG_INFINITY;
    for root in roots {
        if root - last > EPSILON * 1f64.max(root.abs()) {
            distinct.push(root);
        }
        last = root;
    }
    let pushed = push_list(l, &distinct);
    drop(distinct);
    pushed
}

// math.matrix ---------------------------------------------------------------

const SINGULAR: f64 = 1e-12;

pub struct Matrix {
    rows: usize,
    cols: usize,
    data: Vec<f64>,
}

impl Matrix {
    fn at(&self, i: usize, j: usize) -> f64 {
        self.data[i * self.cols + j]
    }

    fn rows_of(&self) -> Vec<Vec<f64>> {
        (0..self.rows).map(|i| self.data[i * self.cols..(i + 1) * self.cols].to_vec()).collect()
    }
}

impl Native for Matrix {
    const NAME: &'static CStr = c"foundation.math.matrix";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Rows", matrix_rows),
        (c"Cols", matrix_cols),
        (c"Get", matrix_get),
        (c"Transpose", matrix_transpose),
        (c"Multiply", matrix_multiply),
        (c"Determinant", matrix_determinant),
        (c"Inverse", matrix_inverse),
        (c"Solve", matrix_solve),
    ];
}

unsafe fn push_matrix(l: L, rows: usize, cols: usize, data: Vec<f64>) -> c_int {
    userdata::push(l, Matrix { rows, cols, data });
    1
}

unsafe extern "C-unwind" fn matrix_new(l: L) -> c_int {
    if l.type_of(1) != TTABLE || l.objlen(1) == 0 {
        raise_where(l, "a matrix needs at least one row".into());
    }
    let rows = l.objlen(1);
    l.rawgeti(1, 1);
    let cols = if l.type_of(-1) == TTABLE { l.objlen(-1) } else { 0 };
    l.settop(-2);
    let mut data = Vec::with_capacity(rows * cols);
    let mut ragged = None;
    for i in 1..=rows {
        l.rawgeti(1, i as c_int);
        let row = l.gettop();
        let len = if l.type_of(row) == TTABLE { l.objlen(row) } else { 0 };
        if len != cols || cols == 0 {
            ragged = Some((i, len));
            l.settop(-2);
            break;
        }
        for j in 1..=cols {
            l.rawgeti(row, j as c_int);
            data.push(l.tonumber(-1));
            l.settop(-2);
        }
        l.settop(-2);
    }
    if let Some((i, len)) = ragged {
        drop(data);
        raise_where(l, format!("matrix row {i} has {len} entries, not {cols}"));
    }
    push_matrix(l, rows, cols, data)
}

unsafe extern "C-unwind" fn matrix_identity(l: L) -> c_int {
    let n = l.checknumber(1).max(0.0) as usize;
    let data = (0..n * n).map(|k| if k / n == k % n { 1.0 } else { 0.0 }).collect();
    push_matrix(l, n, n, data)
}

unsafe extern "C-unwind" fn matrix_rows(l: L) -> c_int {
    number(l, userdata::check::<Matrix>(l, 1).rows as f64)
}

unsafe extern "C-unwind" fn matrix_cols(l: L) -> c_int {
    number(l, userdata::check::<Matrix>(l, 1).cols as f64)
}

unsafe extern "C-unwind" fn matrix_get(l: L) -> c_int {
    let m = userdata::check::<Matrix>(l, 1);
    let (i, j) = (l.checknumber(2), l.checknumber(3));
    let inside = i >= 1.0 && j >= 1.0 && i.fract() == 0.0 && j.fract() == 0.0 && (i as usize) <= m.rows && (j as usize) <= m.cols;
    if !inside {
        return nothing(l);
    }
    number(l, m.at(i as usize - 1, j as usize - 1))
}

unsafe extern "C-unwind" fn matrix_transpose(l: L) -> c_int {
    let m = userdata::check::<Matrix>(l, 1);
    let data = (0..m.cols * m.rows).map(|k| m.at(k % m.rows, k / m.rows)).collect();
    let (rows, cols) = (m.cols, m.rows);
    push_matrix(l, rows, cols, data)
}

unsafe extern "C-unwind" fn matrix_multiply(l: L) -> c_int {
    // Shared borrows: `m:Multiply(m)` passes one matrix as both.
    let a = userdata::get::<Matrix>(l, 1);
    let b = userdata::get::<Matrix>(l, 2);
    if a.cols != b.rows {
        let text = format!("cannot multiply {}x{} by {}x{}", a.rows, a.cols, b.rows, b.cols);
        raise_where(l, text);
    }
    let mut data = Vec::with_capacity(a.rows * b.cols);
    for i in 0..a.rows {
        for j in 0..b.cols {
            let mut sum = 0.0;
            for k in 0..a.cols {
                sum += a.at(i, k) * b.at(k, j);
            }
            data.push(sum);
        }
    }
    let (rows, cols) = (a.rows, b.cols);
    push_matrix(l, rows, cols, data)
}

/// Refuses a matrix that is not square, blaming the caller of the method.
unsafe fn square(l: L, m: &Matrix, what: &str) {
    if m.rows != m.cols {
        raise_at(l, 1, format!("{what} needs a square matrix, not {}x{}", m.rows, m.cols));
    }
}

/// The Lua twin's Gauss-Jordan on rows [a | extra]: the determinant, 0 when
/// singular (the rows left part-reduced).
fn eliminate(a: &mut [Vec<f64>], n: usize) -> f64 {
    let mut det = 1.0;
    for col in 0..n {
        let mut pivot = col;
        for r in col + 1..n {
            if a[r][col].abs() > a[pivot][col].abs() {
                pivot = r;
            }
        }
        if a[pivot][col].abs() < SINGULAR {
            return 0.0;
        }
        if pivot != col {
            a.swap(pivot, col);
            det = -det;
        }
        let lead = a[col][col];
        det *= lead;
        let width = a[col].len();
        for v in &mut a[col][col..width] {
            *v /= lead;
        }
        let row = a[col].clone();
        for (r, other) in a.iter_mut().enumerate().take(n) {
            if r != col && other[col] != 0.0 {
                let factor = other[col];
                for j in col..width {
                    other[j] -= factor * row[j];
                }
            }
        }
    }
    det
}

unsafe extern "C-unwind" fn matrix_determinant(l: L) -> c_int {
    let m = userdata::check::<Matrix>(l, 1);
    square(l, &m, "a determinant");
    let mut a = m.rows_of();
    let det = eliminate(&mut a, m.rows);
    drop(a);
    number(l, det)
}

unsafe extern "C-unwind" fn matrix_inverse(l: L) -> c_int {
    let m = userdata::check::<Matrix>(l, 1);
    square(l, &m, "an inverse");
    let n = m.rows;
    let mut a = m.rows_of();
    for (i, row) in a.iter_mut().enumerate() {
        row.extend((0..n).map(|j| if i == j { 1.0 } else { 0.0 }));
    }
    if eliminate(&mut a, n) == 0.0 {
        drop(a);
        return nothing(l);
    }
    let data = a.iter().flat_map(|row| row[n..].iter().copied()).collect();
    drop(a);
    push_matrix(l, n, n, data)
}

unsafe extern "C-unwind" fn matrix_solve(l: L) -> c_int {
    let m = userdata::check::<Matrix>(l, 1);
    square(l, &m, "solving");
    let n = m.rows;
    l.checktype(2, TTABLE);
    let given = l.objlen(2);
    if given != n {
        raise_where(l, format!("solving needs {n} right-hand values, not {given}"));
    }
    let b = numbers(l, 2);
    let mut a = m.rows_of();
    for (row, &bi) in a.iter_mut().zip(&b) {
        row.push(bi);
    }
    drop(b);
    if eliminate(&mut a, n) == 0.0 {
        drop(a);
        return nothing(l);
    }
    let x: Vec<f64> = a.iter().map(|row| row[n]).collect();
    drop(a);
    let pushed = push_list(l, &x);
    drop(x);
    pushed
}

// math.polyline -------------------------------------------------------------

pub struct Polyline {
    points: Vec<Point>,
    at: Vec<f64>,
    total: f64,
}

impl Native for Polyline {
    const NAME: &'static CStr = c"foundation.math.polyline";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Length", polyline_length),
        (c"Leg", polyline_leg),
        (c"PointAt", polyline_point_at),
        (c"Offset", polyline_offset),
        (c"DistanceOf", polyline_distance_of),
    ];
}

impl Polyline {
    /// The leg (0-based) holding distance d, and how far along it.
    fn leg(&self, d: f64) -> (usize, f64) {
        if d <= 0.0 || self.points.len() == 1 {
            return (0, 0.0);
        }
        for i in 1..self.points.len() {
            if d <= self.at[i] {
                let length = self.at[i] - self.at[i - 1];
                return (i - 1, if length > 0.0 { (d - self.at[i - 1]) / length } else { 0.0 });
            }
        }
        (self.points.len() - 2, 1.0)
    }

    fn ends(&self, i: usize) -> (Point, Point) {
        let a = self.points[i];
        (a, *self.points.get(i + 1).unwrap_or(&a))
    }

    fn point_at(&self, d: f64) -> Point {
        let (i, t) = self.leg(d);
        let (a, b) = self.ends(i);
        [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
    }
}

unsafe extern "C-unwind" fn polyline_new(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let mut points = Vec::new();
    each_item(l, 1, |l, p| points.push(point_at(l, p)));
    let mut at = vec![0.0];
    let mut total = 0.0;
    for w in points.windows(2) {
        let (dx, dy, dz) = (w[1][0] - w[0][0], w[1][1] - w[0][1], w[1][2] - w[0][2]);
        total += (dx * dx + dy * dy + dz * dz).sqrt();
        at.push(total);
    }
    userdata::push(l, Polyline { points, at, total });
    1
}

unsafe extern "C-unwind" fn polyline_length(l: L) -> c_int {
    number(l, userdata::check::<Polyline>(l, 1).total)
}

unsafe extern "C-unwind" fn polyline_leg(l: L) -> c_int {
    let d = l.checknumber(2);
    let (i, t) = userdata::check::<Polyline>(l, 1).leg(d);
    l.pushnumber((i + 1) as f64);
    l.pushnumber(t);
    2
}

unsafe extern "C-unwind" fn polyline_point_at(l: L) -> c_int {
    let d = l.checknumber(2);
    let p = userdata::check::<Polyline>(l, 1).point_at(d);
    push_point(l, p[0], p[1], Some(p[2]))
}

unsafe extern "C-unwind" fn polyline_offset(l: L) -> c_int {
    let (d, lateral) = (l.checknumber(2), l.checknumber(3));
    let line = userdata::check::<Polyline>(l, 1);
    let mut p = line.point_at(d);
    let (a, b) = line.ends(line.leg(d).0);
    let (dx, dy) = (b[0] - a[0], b[1] - a[1]);
    let length = (dx * dx + dy * dy).sqrt();
    if length != 0.0 {
        p[0] -= dy / length * lateral;
        p[1] += dx / length * lateral;
    }
    push_point(l, p[0], p[1], Some(p[2]))
}

unsafe extern "C-unwind" fn polyline_distance_of(l: L) -> c_int {
    let p = point_at(l, 2);
    let line = userdata::check::<Polyline>(l, 1);
    if line.points.len() == 1 {
        return number(l, 0.0);
    }
    let (mut best, mut best_sq) = (0.0, None);
    for i in 0..line.points.len() - 1 {
        let (a, b) = (line.points[i], line.points[i + 1]);
        let (dx, dy, dz) = (b[0] - a[0], b[1] - a[1], b[2] - a[2]);
        let length_sq = dx * dx + dy * dy + dz * dz;
        let mut t = 0.0;
        if length_sq > 0.0 {
            t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy + (p[2] - a[2]) * dz) / length_sq;
            t = t.clamp(0.0, 1.0);
        }
        let (nx, ny, nz) = (a[0] + dx * t - p[0], a[1] + dy * t - p[1], a[2] + dz * t - p[2]);
        let d_sq = nx * nx + ny * ny + nz * nz;
        if best_sq.is_none_or(|b| d_sq < b) {
            best = line.at[i] + (line.at[i + 1] - line.at[i]) * t;
            best_sq = Some(d_sq);
        }
    }
    number(l, best)
}

/// Pushes the geometry module table.
unsafe fn push_geometry_module(l: L) {
    module::push(
        l,
        &[
            (c"Distance", distance),
            (c"Distance2D", distance2d),
            (c"Toward", toward),
            (c"Add", add),
            (c"Sub", sub),
            (c"Scale", scale),
            (c"Dot", dot),
            (c"Cross", cross),
            (c"Length", length),
            (c"Normalize", normalize),
            (c"DistanceSquared", distance_squared),
            (c"Normalize2D", normalize2d),
            (c"Left2D", left2d),
            (c"Offset2D", offset2d),
            (c"ClosestOnSegment", closest_on_segment),
            (c"Polar", polar),
            (c"Circle", circle),
            (c"Sphere", sphere),
            (c"Frustum", frustum),
        ],
        None,
    );
}

/// Pushes the scalar module table.
unsafe fn push_scalar_module(l: L) {
    module::push(
        l,
        &[
            (c"Clamp", clamp),
            (c"Saturate", saturate),
            (c"Lerp", lerp),
            (c"InverseLerp", inverse_lerp),
            (c"Remap", remap),
        ],
        None,
    );
}

/// Pushes the stats module table.
unsafe fn push_stats_module(l: L) {
    module::push(l, &[(c"Mean", mean), (c"Percentile", percentile)], None);
}

/// Pushes the weighted module table.
unsafe fn push_weighted_module(l: L) {
    module::push(l, &[(c"PickWeighted", pick_weighted)], None);
}

/// Pushes the polynomial module table.
unsafe fn push_polynomial_module(l: L) {
    module::push(l, &[(c"Evaluate", evaluate), (c"Derivative", derivative), (c"Roots", roots)], None);
}

/// Pushes the matrix module table.
unsafe fn push_matrix_module(l: L) {
    module::push(l, &[(c"New", matrix_new), (c"Identity", matrix_identity)], None);
}

/// Pushes the polyline module table.
unsafe fn push_polyline_module(l: L) {
    module::push(l, &[(c"New", polyline_new)], None);
}

/// Pushes the interval module table.
unsafe fn push_interval_module(l: L) {
    module::push(l, &[(c"Overlaps", interval_overlaps), (c"Intersect", interval_intersect)], None);
}

/// Pushes the box module table.
unsafe fn push_box_module(l: L) {
    module::push(
        l,
        &[
            (c"Overlaps", box_overlaps),
            (c"Contains", box_contains),
            (c"Extent", box_extent),
            (c"LongestAxis2D", box_longest_axis_2d),
            (c"Centered", box_centered),
            (c"Standing", box_standing),
        ],
        None,
    );
}

/// Pushes the choice module table.
unsafe fn push_choice_module(l: L) {
    module::push(l, &[(c"Shuffle", choice_shuffle), (c"Draw", choice_draw)], None);
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[
    (c"geometry", push_geometry_module),
    (c"scalar", push_scalar_module),
    (c"stats", push_stats_module),
    (c"weighted", push_weighted_module),
    (c"polynomial", push_polynomial_module),
    (c"matrix", push_matrix_module),
    (c"polyline", push_polyline_module),
    (c"interval", push_interval_module),
    (c"box", push_box_module),
    (c"choice", push_choice_module),
];
