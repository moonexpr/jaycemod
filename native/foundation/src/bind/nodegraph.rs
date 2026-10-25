//! nodegraph, native: the Lua twin's whole contract (foundation/nodegraph.lua):
//! the node pick and pair searches (one call for a whole map's points where
//! the Lua twin runs for tens of milliseconds between the build's yields),
//! links capped, zones, and the .ain file written and read.

use super::util::each_item;
use crate::lua::{api, field_number, raise_owned, L, TNUMBER, TTABLE};
use std::collections::HashMap;
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

/// nodegraph.SeamPoint(from, to, dir) -> x, y: the middle of the edge two
/// connected areas share (rects { lo = { x, y }, hi = { x, y } })
unsafe extern "C-unwind" fn seam_point(l: L) -> c_int {
    let api = api();
    let rect = |index: c_int| -> [f64; 4] {
        (api.getfield)(l, index, c"lo".as_ptr());
        let lo = (api.gettop)(l);
        (api.getfield)(l, index, c"hi".as_ptr());
        let hi = (api.gettop)(l);
        let r = [
            field_number(l, lo, c"x").unwrap_or(f64::NAN),
            field_number(l, lo, c"y").unwrap_or(f64::NAN),
            field_number(l, hi, c"x").unwrap_or(f64::NAN),
            field_number(l, hi, c"y").unwrap_or(f64::NAN),
        ];
        (api.settop)(l, lo - 1);
        r
    };
    (api.checktype)(l, 1, TTABLE);
    (api.checktype)(l, 2, TTABLE);
    let (from, to) = (rect(1), rect(2));
    let dir = (api.checknumber)(l, 3);
    let (x, y) = if dir == 0.0 || dir == 2.0 {
        let low = if from[0] > to[0] { from[0] } else { to[0] };
        let high = if from[2] < to[2] { from[2] } else { to[2] };
        ((low + high) / 2.0, if dir == 0.0 { from[1] } else { from[3] })
    } else {
        let low = if from[1] > to[1] { from[1] } else { to[1] };
        let high = if from[3] < to[3] { from[3] } else { to[3] };
        (if dir == 3.0 { from[0] } else { from[2] }, (low + high) / 2.0)
    };
    (api.pushnumber)(l, x);
    (api.pushnumber)(l, y);
    2
}

/// The a and b of the link table at `index`.
unsafe fn ends(l: L, index: c_int) -> (f64, f64) {
    (field_number(l, index, c"a").unwrap_or(f64::NAN), field_number(l, index, c"b").unwrap_or(f64::NAN))
}

/// nodegraph.CapLinks(links, limit) -> the shortest links, at most limit a node
unsafe extern "C-unwind" fn cap_links(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    let limit = (api.checknumber)(l, 2);
    (api.createtable)(l, 0, 0);
    let kept = (api.gettop)(l);
    let mut counts: HashMap<u64, f64> = HashMap::new();
    let mut n = 0;
    each_item(l, 1, |l, link| {
        let (a, b) = ends(l, link);
        let (ca, cb) = (counts.get(&a.to_bits()).copied().unwrap_or(0.0), counts.get(&b.to_bits()).copied().unwrap_or(0.0));
        if ca < limit && cb < limit {
            counts.insert(a.to_bits(), counts.get(&a.to_bits()).copied().unwrap_or(0.0) + 1.0);
            counts.insert(b.to_bits(), counts.get(&b.to_bits()).copied().unwrap_or(0.0) + 1.0);
            n += 1;
            (api.pushvalue)(l, link);
            (api.rawseti)(l, kept, n);
        }
    });
    drop(counts);
    1
}

/// nodegraph.Zones(count, links) -> zone per node: SOLO for a node without
/// links, else FIRST_ZONE up for each set of linked nodes, numbered in the
/// order of their lowest node
unsafe extern "C-unwind" fn zones(l: L) -> c_int {
    let api = api();
    let count = (api.checknumber)(l, 1).max(0.0) as usize;
    (api.checktype)(l, 2, TTABLE);
    let mut neighbors: Vec<Vec<usize>> = vec![Vec::new(); count + 1];
    each_item(l, 2, |l, link| {
        let (a, b) = ends(l, link);
        let (a, b) = (a as usize, b as usize);
        if a <= count && b <= count {
            neighbors[a].push(b);
            neighbors[b].push(a);
        }
    });
    let mut zone = vec![ZONE_SOLO; count + 1];
    let mut next = FIRST_ZONE;
    let mut stack = Vec::new();
    for start in 1..=count {
        if neighbors[start].is_empty() || zone[start] != ZONE_SOLO {
            continue;
        }
        zone[start] = next;
        stack.push(start);
        while let Some(n) = stack.pop() {
            for &m in &neighbors[n] {
                if zone[m] == ZONE_SOLO {
                    zone[m] = next;
                    stack.push(m);
                }
            }
        }
        next += 1.0;
    }
    (api.createtable)(l, count as c_int, 0);
    for (i, &z) in zone.iter().enumerate().skip(1) {
        (api.pushnumber)(l, z);
        (api.rawseti)(l, -2, i as c_int);
    }
    drop(zone);
    drop(neighbors);
    drop(stack);
    1
}

const VERSION: f64 = 37.0;
const NUM_HULLS: usize = 10;
const NODE_GROUND: f64 = 2.0;
const ZONE_SOLO: f64 = 1.0;
const FIRST_ZONE: f64 = 4.0;

/// The number t[key] of the table at `t` (or `default`), t[key] absent.
unsafe fn field_or(l: L, t: c_int, key: &std::ffi::CStr, default: f64) -> f64 {
    field_number(l, t, key).unwrap_or(default)
}

/// t[i] of the table at `t`, a number, or `default`.
unsafe fn index_or(l: L, t: c_int, i: c_int, default: f64) -> f64 {
    let api = api();
    if (api.type_of)(l, t) != TTABLE {
        return default;
    }
    (api.rawgeti)(l, t, i);
    let v = number_or(l, -1, default);
    (api.settop)(l, -2);
    v
}

unsafe fn number_or(l: L, index: c_int, default: f64) -> f64 {
    let api = api();
    if (api.type_of)(l, index) == TNUMBER {
        (api.tonumber)(l, index)
    } else {
        default
    }
}

unsafe fn refuse_byte(l: L) -> ! {
    crate::lua::raise_where(l, "bad argument #1 to 'char' (invalid value)".into())
}

/// nodegraph.Encode(graph) -> the .ain file's bytes
unsafe extern "C-unwind" fn encode(l: L) -> c_int {
    use super::codec::{float32, int16, int32};
    let api = api();
    (api.checktype)(l, 1, TTABLE);
    (api.getfield)(l, 1, c"nodes".as_ptr());
    let nodes = (api.gettop)(l);
    (api.getfield)(l, 1, c"links".as_ptr());
    let links = (api.gettop)(l);
    let map_version = field_number(l, 1, c"mapVersion").unwrap_or(0.0);
    let mut out = Vec::new();
    out.extend(int32(VERSION));
    out.extend(int32(map_version));
    out.extend(int32((api.objlen)(l, nodes) as f64));
    let mut hammer = Vec::new();
    let mut i = 0.0;
    let mut bad = None;
    each_item(l, nodes, |l, node| {
        i += 1.0;
        (api.getfield)(l, node, c"pos".as_ptr());
        let pos = (api.gettop)(l);
        for key in [c"x", c"y", c"z"] {
            out.extend(float32(field_or(l, pos, key, 0.0)));
        }
        out.extend(float32(field_or(l, node, c"yaw", 0.0)));
        (api.getfield)(l, node, c"offsets".as_ptr());
        let offsets = (api.gettop)(l);
        for hull in 0..NUM_HULLS {
            out.extend(float32(index_or(l, offsets, hull as c_int, 0.0)));
        }
        let kind = field_or(l, node, c"type", NODE_GROUND);
        if !(0.0..256.0).contains(&kind) && bad.is_none() {
            bad = Some(kind);
        }
        out.push(kind as u8);
        out.extend(int16(field_or(l, node, c"info", 0.0)));
        out.extend(int16(field_or(l, node, c"zone", ZONE_SOLO)));
        hammer.push(field_or(l, node, c"hammerId", i));
    });
    if bad.is_some() {
        drop(out);
        drop(hammer);
        refuse_byte(l);
    }
    out.extend(int32((api.objlen)(l, links) as f64));
    each_item(l, links, |l, link| {
        let (a, b) = ends(l, link);
        out.extend(int16(a - 1.0));
        out.extend(int16(b - 1.0));
        (api.getfield)(l, link, c"moves".as_ptr());
        let moves = (api.gettop)(l);
        for hull in 0..NUM_HULLS {
            out.push(index_or(l, moves, hull as c_int, 0.0) as u8);
        }
    });
    for id in &hammer {
        out.extend(int32(*id));
    }
    drop(hammer);
    (api.pushlstring)(l, out.as_ptr().cast(), out.len());
    drop(out);
    1
}

/// nodegraph.Decode(data[, headerOnly]) -> the graph, or nil and why
unsafe extern "C-unwind" fn decode(l: L) -> c_int {
    let api = api();
    let Some(data) = crate::lua::string_at(l, 1) else {
        (api.checktype)(l, 1, crate::lua::TSTRING);
        return 0;
    };
    let header_only = (api.toboolean)(l, 2) != 0;
    let fail = |l: L, why: &str| -> c_int {
        (api.pushnil)(l);
        crate::lua::push_str(l, why);
        2
    };
    if data.len() < 12 {
        return fail(l, "too short");
    }
    let mut at = 0usize;
    let int32 = |at: &mut usize| -> Option<f64> {
        let b = data.get(*at..*at + 4)?;
        *at += 4;
        let n = b[0] as f64 + b[1] as f64 * 256.0 + b[2] as f64 * 65536.0 + b[3] as f64 * 16_777_216.0;
        Some(if n >= 2_147_483_648.0 { n - 4_294_967_296.0 } else { n })
    };
    let uint16 = |at: &mut usize| -> Option<f64> {
        let b = data.get(*at..*at + 2)?;
        *at += 2;
        Some(b[0] as f64 + b[1] as f64 * 256.0)
    };
    let byte = |at: &mut usize| -> Option<f64> {
        let b = *data.get(*at)?;
        *at += 1;
        Some(b as f64)
    };
    let float = |at: &mut usize| -> Option<f64> {
        let b = data.get(*at..*at + 4)?;
        *at += 4;
        let (a, b2, c, d) = (b[0], b[1], b[2], b[3]);
        let sign = if d >= 128 { -1.0 } else { 1.0 };
        let exponent = (d % 128) as i32 * 2 + (c / 128) as i32;
        let mantissa = (c % 128) as f64 * 65536.0 + b2 as f64 * 256.0 + a as f64;
        Some(if exponent == 0 {
            if mantissa == 0.0 {
                0.0
            } else {
                sign * mantissa * 2f64.powi(-149)
            }
        } else if exponent == 255 {
            sign * f64::INFINITY
        } else {
            sign * (mantissa + 8_388_608.0) * 2f64.powi(exponent - 150)
        })
    };
    let (Some(version), Some(map_version), Some(node_count)) = (int32(&mut at), int32(&mut at), int32(&mut at)) else {
        return fail(l, "too short");
    };
    (api.createtable)(l, 0, 5);
    let graph = (api.gettop)(l);
    for (key, value) in [(c"version", version), (c"mapVersion", map_version), (c"nodeCount", node_count)] {
        (api.pushnumber)(l, value);
        (api.setfield)(l, graph, key.as_ptr());
    }
    (api.createtable)(l, 0, 0);
    let nodes = (api.gettop)(l);
    (api.pushvalue)(l, nodes);
    (api.setfield)(l, graph, c"nodes".as_ptr());
    (api.createtable)(l, 0, 0);
    let links = (api.gettop)(l);
    (api.pushvalue)(l, links);
    (api.setfield)(l, graph, c"links".as_ptr());
    if header_only {
        (api.settop)(l, graph);
        return 1;
    }
    if version != VERSION {
        let why = format!("version {}", crate::lua::tostring(l, {
            (api.pushnumber)(l, version);
            -1
        }));
        return fail(l, &why);
    }
    let read = (|| -> Option<()> {
        for i in 1..=node_count.max(0.0) as c_int {
            (api.createtable)(l, 0, 8);
            let node = (api.gettop)(l);
            (api.createtable)(l, 0, 3);
            for key in [c"x", c"y", c"z"] {
                (api.pushnumber)(l, float(&mut at)?);
                (api.setfield)(l, -2, key.as_ptr());
            }
            (api.setfield)(l, node, c"pos".as_ptr());
            (api.pushnumber)(l, float(&mut at)?);
            (api.setfield)(l, node, c"yaw".as_ptr());
            (api.createtable)(l, 0, NUM_HULLS as c_int);
            for hull in 0..NUM_HULLS {
                (api.pushnumber)(l, float(&mut at)?);
                (api.rawseti)(l, -2, hull as c_int);
            }
            (api.setfield)(l, node, c"offsets".as_ptr());
            (api.pushnumber)(l, byte(&mut at)?);
            (api.setfield)(l, node, c"type".as_ptr());
            (api.pushnumber)(l, uint16(&mut at)?);
            (api.setfield)(l, node, c"info".as_ptr());
            let zone = uint16(&mut at)?;
            (api.pushnumber)(l, if zone >= 32768.0 { zone - 65536.0 } else { zone });
            (api.setfield)(l, node, c"zone".as_ptr());
            (api.rawseti)(l, nodes, i);
        }
        let link_count = int32(&mut at)?;
        for i in 1..=link_count.max(0.0) as c_int {
            (api.createtable)(l, 0, 3);
            let link = (api.gettop)(l);
            for key in [c"a", c"b"] {
                let n = uint16(&mut at)?;
                (api.pushnumber)(l, if n >= 32768.0 { n - 65536.0 } else { n } + 1.0);
                (api.setfield)(l, link, key.as_ptr());
            }
            (api.createtable)(l, 0, NUM_HULLS as c_int);
            for hull in 0..NUM_HULLS {
                (api.pushnumber)(l, byte(&mut at)?);
                (api.rawseti)(l, -2, hull as c_int);
            }
            (api.setfield)(l, link, c"moves".as_ptr());
            (api.rawseti)(l, links, i);
        }
        for i in 1..=node_count.max(0.0) as c_int {
            (api.rawgeti)(l, nodes, i);
            (api.pushnumber)(l, int32(&mut at)?);
            (api.setfield)(l, -2, c"hammerId".as_ptr());
            (api.settop)(l, -2);
        }
        Some(())
    })();
    if read.is_none() || at != data.len() {
        return fail(l, "trailing or missing bytes");
    }
    (api.settop)(l, graph);
    1
}

/// Pushes the nodegraph module: its functions and constants, HULLS as the
/// Lua twin lays it out.
pub unsafe fn push_module(l: L) {
    let api = api();
    crate::module::push(
        l,
        &[
            (c"PickNodes", pick_nodes),
            (c"SeamPoint", seam_point),
            (c"Candidates", candidates),
            (c"Bridges", bridges),
            (c"CapLinks", cap_links),
            (c"Zones", zones),
            (c"Encode", encode),
            (c"Decode", decode),
        ],
        None,
    );
    for (name, value) in [
        (c"VERSION", VERSION),
        (c"NUM_HULLS", NUM_HULLS as f64),
        (c"MAX_NODES", 1500.0),
        (c"MAX_NODE_LINKS", 30.0),
        (c"MAX_LINK_DISTANCE", 720.0),
        (c"NODE_GROUND", NODE_GROUND),
        (c"ZONE_SOLO", ZONE_SOLO),
        (c"FIRST_ZONE", FIRST_ZONE),
        (c"CAP_MOVE_GROUND", 1.0),
        (c"NODE_HEIGHT", 8.0),
        (c"NO_NODE", -1.0),
    ] {
        (api.pushnumber)(l, value);
        (api.setfield)(l, -2, name.as_ptr());
    }
    let hulls: [(&str, [f64; 3], [f64; 3], bool); NUM_HULLS] = [
        ("human", [-13.0, -13.0, 0.0], [13.0, 13.0, 72.0], true),
        ("small centered", [-20.0, -20.0, -20.0], [20.0, 20.0, 20.0], false),
        ("wide human", [-15.0, -15.0, 0.0], [15.0, 15.0, 72.0], true),
        ("tiny", [-12.0, -12.0, 0.0], [12.0, 12.0, 24.0], true),
        ("wide short", [-35.0, -35.0, 0.0], [35.0, 35.0, 32.0], true),
        ("medium", [-16.0, -16.0, 0.0], [16.0, 16.0, 64.0], true),
        ("tiny centered", [-8.0, -8.0, -4.0], [8.0, 8.0, 4.0], false),
        ("large", [-40.0, -40.0, 0.0], [40.0, 40.0, 100.0], true),
        ("large centered", [-38.0, -38.0, -38.0], [38.0, 38.0, 38.0], false),
        ("medium tall", [-18.0, -18.0, 0.0], [18.0, 18.0, 100.0], true),
    ];
    (api.createtable)(l, NUM_HULLS as c_int, 0);
    for (i, (name, mins, maxs, ground)) in hulls.iter().enumerate() {
        (api.createtable)(l, 0, 4);
        crate::lua::push_str(l, name);
        (api.setfield)(l, -2, c"name".as_ptr());
        for (key, v) in [(c"mins", mins), (c"maxs", maxs)] {
            (api.createtable)(l, 3, 0);
            for (k, &x) in v.iter().enumerate() {
                (api.pushnumber)(l, x);
                (api.rawseti)(l, -2, k as c_int + 1);
            }
            (api.setfield)(l, -2, key.as_ptr());
        }
        (api.pushboolean)(l, *ground as c_int);
        (api.setfield)(l, -2, c"ground".as_ptr());
        (api.rawseti)(l, -2, i as c_int);
    }
    (api.setfield)(l, -2, c"HULLS".as_ptr());
}
