//! nodegraph's pair searches and node pick, native: patched over the Lua
//! module's functions of the same names, one call for a whole map's points
//! where the Lua twin runs for tens of milliseconds between the build's
//! yields.

use crate::lua::{api, field_number, raise_owned, CFunction, L, TNUMBER, TTABLE};
use crate::nearest::{self, Pair, Point};
use std::ffi::c_int;

/// The point in the table at the top of the stack (popped): its x, y and z.
unsafe fn point_at_top(l: L, what: &str, i: usize) -> Result<Point, String> {
    let api = api();
    let top = (api.gettop)(l);
    if (api.type_of)(l, top) != TTABLE {
        (api.settop)(l, -2);
        return Err(format!("{what} {i} is no {{ x, y, z }} table"));
    }
    let point = (field_number(l, top, c"x"), field_number(l, top, c"y"), field_number(l, top, c"z"));
    (api.settop)(l, -2);
    match point {
        (Some(x), Some(y), Some(z)) => Ok([x, y, z]),
        _ => Err(format!("{what} {i} needs a number x, y and z")),
    }
}

/// The list of points at `index` (absolute).
unsafe fn points(l: L, index: c_int) -> Result<Vec<Point>, String> {
    let api = api();
    let n = (api.objlen)(l, index);
    let mut out = Vec::with_capacity(n);
    for i in 1..=n {
        (api.rawgeti)(l, index, i as c_int);
        out.push(point_at_top(l, "position", i)?);
    }
    Ok(out)
}

/// The list of numbers at `index` (absolute), `n` long.
unsafe fn numbers(l: L, index: c_int, n: usize, what: &str) -> Result<Vec<f64>, String> {
    let api = api();
    let mut out = Vec::with_capacity(n);
    for i in 1..=n {
        (api.rawgeti)(l, index, i as c_int);
        let number = ((api.type_of)(l, -1) == TNUMBER).then(|| (api.tonumber)(l, -1));
        (api.settop)(l, -2);
        out.push(number.ok_or_else(|| format!("{what} {i} is no number"))?);
    }
    Ok(out)
}

/// The areas at `index` (absolute): each { pos, size }.
unsafe fn areas(l: L, index: c_int) -> Result<(Vec<Point>, Vec<f64>), String> {
    let api = api();
    let n = (api.objlen)(l, index);
    let (mut positions, mut sizes) = (Vec::with_capacity(n), Vec::with_capacity(n));
    for i in 1..=n {
        (api.rawgeti)(l, index, i as c_int);
        let area = (api.gettop)(l);
        if (api.type_of)(l, area) != TTABLE {
            (api.settop)(l, -2);
            return Err(format!("area {i} is no {{ pos, size }} table"));
        }
        let size = field_number(l, area, c"size");
        (api.getfield)(l, area, c"pos".as_ptr());
        let pos = point_at_top(l, "area", i);
        (api.settop)(l, -2);
        positions.push(pos?);
        sizes.push(size.ok_or_else(|| format!("area {i} has no number size"))?);
    }
    Ok((positions, sizes))
}

/// A whole-number count from a Lua number: none below zero.
fn count(n: f64) -> usize {
    if n > 0.0 {
        n.floor() as usize
    } else {
        0
    }
}

/// Pushes the pairs as the Lua twin returns them: { a, b, distance }s, 1-based.
unsafe fn push_pairs(l: L, pairs: &[Pair]) {
    let api = api();
    (api.createtable)(l, pairs.len() as c_int, 0);
    for (k, pair) in pairs.iter().enumerate() {
        (api.createtable)(l, 0, 3);
        (api.pushnumber)(l, (pair.a + 1) as f64);
        (api.setfield)(l, -2, c"a".as_ptr());
        (api.pushnumber)(l, (pair.b + 1) as f64);
        (api.setfield)(l, -2, c"b".as_ptr());
        (api.pushnumber)(l, pair.distance);
        (api.setfield)(l, -2, c"distance".as_ptr());
        (api.rawseti)(l, -2, (k + 1) as c_int);
    }
}

/// nodegraph.Candidates(positions, maxDistance, perNode) -> { a, b, distance }s
unsafe extern "C-unwind" fn candidates(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let max_distance = (api.checknumber)(l, 2);
    let per_node = count((api.checknumber)(l, 3));
    let pairs = match points(l, 1) {
        Ok(points) => nearest::nearest_pairs(&points, max_distance, per_node, |i, j| i != j),
        Err(message) => raise_owned(l, message),
    };
    push_pairs(l, &pairs);
    1
}

/// nodegraph.Bridges(positions, zones, maxDistance, perNode) -> { a, b, distance }s
unsafe extern "C-unwind" fn bridges(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 2, TTABLE);
    let max_distance = (api.checknumber)(l, 3);
    let per_node = count((api.checknumber)(l, 4));
    let read = points(l, 1).and_then(|points| Ok((numbers(l, 2, points.len(), "zone")?, points)));
    let pairs = match read {
        Ok((zones, points)) => nearest::nearest_pairs(&points, max_distance, per_node, |i, j| zones[i] != zones[j]),
        Err(message) => raise_owned(l, message),
    };
    push_pairs(l, &pairs);
    1
}

/// nodegraph.PickNodes(areas, spacing, limit) -> the chosen areas, in order
unsafe extern "C-unwind" fn pick_nodes(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let spacing = (api.checknumber)(l, 2);
    let limit = (api.checknumber)(l, 3);
    let chosen = match areas(l, 1) {
        Ok((positions, sizes)) => nearest::pick_spaced(&positions, &sizes, spacing, limit),
        Err(message) => raise_owned(l, message),
    };
    (api.createtable)(l, chosen.len() as c_int, 0);
    for (k, &i) in chosen.iter().enumerate() {
        (api.rawgeti)(l, 1, (i + 1) as c_int);
        (api.rawseti)(l, -2, (k + 1) as c_int);
    }
    1
}

pub const FUNCTIONS: &[(&std::ffi::CStr, CFunction)] =
    &[(c"Candidates", candidates), (c"Bridges", bridges), (c"PickNodes", pick_nodes)];
