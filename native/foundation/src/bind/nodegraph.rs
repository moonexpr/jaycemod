//! nodegraph, native: the Lua twin's whole contract (foundation/nodegraph.lua):
//! the node pick and pair searches (one call for a whole map's points where
//! the Lua twin runs for tens of milliseconds between the build's yields),
//! links capped, zones, and the .ain file written and read.

use super::util::each_item;
use crate::lua::{field_number, raise_owned, L, TNUMBER, TTABLE};
use std::collections::HashMap;
use crate::nearest::{self, Pair, Point};
use std::ffi::c_int;

/// The point in the table at the top of the stack (popped): its x, y and z.
unsafe fn point_at_top(l: L, what: &str, i: usize) -> Result<Point, String> {
    let top = l.gettop();
    if !super::util::indexable(l, top) {
        l.settop(-2);
        return Err(format!("{what} {i} is no {{ x, y, z }} table or Vector"));
    }
    let point = (field_number(l, top, c"x"), field_number(l, top, c"y"), field_number(l, top, c"z"));
    l.settop(-2);
    match point {
        (Some(x), Some(y), Some(z)) => Ok([x, y, z]),
        _ => Err(format!("{what} {i} needs a number x, y and z")),
    }
}

/// The list of points at `index` (absolute).
unsafe fn points(l: L, index: c_int) -> Result<Vec<Point>, String> {
    let n = l.objlen(index);
    let mut out = Vec::with_capacity(n);
    for i in 1..=n {
        l.rawgeti(index, i as c_int);
        out.push(point_at_top(l, "position", i)?);
    }
    Ok(out)
}

/// The list of numbers at `index` (absolute), `n` long.
unsafe fn numbers(l: L, index: c_int, n: usize, what: &str) -> Result<Vec<f64>, String> {
    let mut out = Vec::with_capacity(n);
    for i in 1..=n {
        l.rawgeti(index, i as c_int);
        let number = (l.type_of(-1) == TNUMBER).then(|| l.tonumber(-1));
        l.settop(-2);
        out.push(number.ok_or_else(|| format!("{what} {i} is no number"))?);
    }
    Ok(out)
}

/// The areas at `index` (absolute): each { pos, size }.
unsafe fn areas(l: L, index: c_int) -> Result<(Vec<Point>, Vec<f64>), String> {
    let n = l.objlen(index);
    let (mut positions, mut sizes) = (Vec::with_capacity(n), Vec::with_capacity(n));
    for i in 1..=n {
        l.rawgeti(index, i as c_int);
        let area = l.gettop();
        if l.type_of(area) != TTABLE {
            l.settop(-2);
            return Err(format!("area {i} is no {{ pos, size }} table"));
        }
        let size = field_number(l, area, c"size");
        l.getfield(area, c"pos");
        let pos = point_at_top(l, "area", i);
        l.settop(-2);
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
    l.createtable(pairs.len() as c_int, 0);
    for (k, pair) in pairs.iter().enumerate() {
        l.createtable(0, 3);
        l.pushnumber((pair.a + 1) as f64);
        l.setfield(-2, c"a");
        l.pushnumber((pair.b + 1) as f64);
        l.setfield(-2, c"b");
        l.pushnumber(pair.distance);
        l.setfield(-2, c"distance");
        l.rawseti(-2, (k + 1) as c_int);
    }
}

/// nodegraph.Candidates(positions, maxDistance, perNode) -> { a, b, distance }s
unsafe extern "C-unwind" fn candidates(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let max_distance = l.checknumber(2);
    let per_node = count(l.checknumber(3));
    let pairs = match points(l, 1) {
        Ok(points) => nearest::nearest_pairs(&points, max_distance, per_node, |i, j| i != j),
        Err(message) => raise_owned(l, message),
    };
    push_pairs(l, &pairs);
    1
}

/// nodegraph.Bridges(positions, zones, maxDistance, perNode) -> { a, b, distance }s
unsafe extern "C-unwind" fn bridges(l: L) -> c_int {
    l.checktype(1, TTABLE);
    l.checktype(2, TTABLE);
    let max_distance = l.checknumber(3);
    let per_node = count(l.checknumber(4));
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
    l.checktype(1, TTABLE);
    let spacing = l.checknumber(2);
    let limit = l.checknumber(3);
    let chosen = match areas(l, 1) {
        Ok((positions, sizes)) => nearest::pick_spaced(&positions, &sizes, spacing, limit),
        Err(message) => raise_owned(l, message),
    };
    l.createtable(chosen.len() as c_int, 0);
    for (k, &i) in chosen.iter().enumerate() {
        l.rawgeti(1, (i + 1) as c_int);
        l.rawseti(-2, (k + 1) as c_int);
    }
    1
}

/// nodegraph.SeamPoint(from, to, dir) -> x, y: the middle of the edge two
/// connected areas share (rects { lo = { x, y }, hi = { x, y } })
unsafe extern "C-unwind" fn seam_point(l: L) -> c_int {
    let rect = |index: c_int| -> [f64; 4] {
        l.getfield(index, c"lo");
        let lo = l.gettop();
        l.getfield(index, c"hi");
        let hi = l.gettop();
        let r = [
            field_number(l, lo, c"x").unwrap_or(f64::NAN),
            field_number(l, lo, c"y").unwrap_or(f64::NAN),
            field_number(l, hi, c"x").unwrap_or(f64::NAN),
            field_number(l, hi, c"y").unwrap_or(f64::NAN),
        ];
        l.settop(lo - 1);
        r
    };
    l.checktype(1, TTABLE);
    l.checktype(2, TTABLE);
    let (from, to) = (rect(1), rect(2));
    let dir = l.checknumber(3);
    let (x, y) = if dir == 0.0 || dir == 2.0 {
        let low = if from[0] > to[0] { from[0] } else { to[0] };
        let high = if from[2] < to[2] { from[2] } else { to[2] };
        ((low + high) / 2.0, if dir == 0.0 { from[1] } else { from[3] })
    } else {
        let low = if from[1] > to[1] { from[1] } else { to[1] };
        let high = if from[3] < to[3] { from[3] } else { to[3] };
        (if dir == 3.0 { from[0] } else { from[2] }, (low + high) / 2.0)
    };
    l.pushnumber(x);
    l.pushnumber(y);
    2
}

/// The a and b of the link table at `index`.
unsafe fn ends(l: L, index: c_int) -> (f64, f64) {
    (field_number(l, index, c"a").unwrap_or(f64::NAN), field_number(l, index, c"b").unwrap_or(f64::NAN))
}

/// nodegraph.CapLinks(links, limit) -> the shortest links, at most limit a node
unsafe extern "C-unwind" fn cap_links(l: L) -> c_int {
    l.checktype(1, TTABLE);
    let limit = l.checknumber(2);
    l.createtable(0, 0);
    let kept = l.gettop();
    let mut counts: HashMap<u64, f64> = HashMap::new();
    let mut n = 0;
    each_item(l, 1, |l, link| {
        let (a, b) = ends(l, link);
        let (ca, cb) = (counts.get(&a.to_bits()).copied().unwrap_or(0.0), counts.get(&b.to_bits()).copied().unwrap_or(0.0));
        if ca < limit && cb < limit {
            counts.insert(a.to_bits(), counts.get(&a.to_bits()).copied().unwrap_or(0.0) + 1.0);
            counts.insert(b.to_bits(), counts.get(&b.to_bits()).copied().unwrap_or(0.0) + 1.0);
            n += 1;
            l.pushvalue(link);
            l.rawseti(kept, n);
        }
    });
    drop(counts);
    1
}

/// nodegraph.Zones(count, links) -> zone per node: SOLO for a node without
/// links, else FIRST_ZONE up for each set of linked nodes, numbered in the
/// order of their lowest node
unsafe extern "C-unwind" fn zones(l: L) -> c_int {
    let count = l.checknumber(1).max(0.0) as usize;
    l.checktype(2, TTABLE);
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
    l.createtable(count as c_int, 0);
    for (i, &z) in zone.iter().enumerate().skip(1) {
        l.pushnumber(z);
        l.rawseti(-2, i as c_int);
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
    if l.type_of(t) != TTABLE {
        return default;
    }
    l.rawgeti(t, i);
    let v = number_or(l, -1, default);
    l.settop(-2);
    v
}

unsafe fn number_or(l: L, index: c_int, default: f64) -> f64 {
    if l.type_of(index) == TNUMBER {
        l.tonumber(index)
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
    l.checktype(1, TTABLE);
    l.getfield(1, c"nodes");
    let nodes = l.gettop();
    l.getfield(1, c"links");
    let links = l.gettop();
    let map_version = field_number(l, 1, c"mapVersion").unwrap_or(0.0);
    let mut out = Vec::new();
    out.extend(int32(VERSION));
    out.extend(int32(map_version));
    out.extend(int32(l.objlen(nodes) as f64));
    let mut hammer = Vec::new();
    let mut i = 0.0;
    let mut bad = None;
    each_item(l, nodes, |l, node| {
        i += 1.0;
        l.getfield(node, c"pos");
        let pos = l.gettop();
        for key in [c"x", c"y", c"z"] {
            out.extend(float32(field_or(l, pos, key, 0.0)));
        }
        out.extend(float32(field_or(l, node, c"yaw", 0.0)));
        l.getfield(node, c"offsets");
        let offsets = l.gettop();
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
    out.extend(int32(l.objlen(links) as f64));
    each_item(l, links, |l, link| {
        let (a, b) = ends(l, link);
        out.extend(int16(a - 1.0));
        out.extend(int16(b - 1.0));
        l.getfield(link, c"moves");
        let moves = l.gettop();
        for hull in 0..NUM_HULLS {
            out.push(index_or(l, moves, hull as c_int, 0.0) as u8);
        }
    });
    for id in &hammer {
        out.extend(int32(*id));
    }
    drop(hammer);
    l.pushlstring(out.as_ptr().cast(), out.len());
    drop(out);
    1
}

/// nodegraph.Decode(data[, headerOnly]) -> the graph, or nil and why
unsafe extern "C-unwind" fn decode(l: L) -> c_int {
    let Some(data) = crate::lua::string_at(l, 1) else {
        l.checktype(1, crate::lua::TSTRING);
        return 0;
    };
    let header_only = l.toboolean(2) != 0;
    let fail = |l: L, why: &str| -> c_int {
        l.pushnil();
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
    l.createtable(0, 5);
    let graph = l.gettop();
    for (key, value) in [(c"version", version), (c"mapVersion", map_version), (c"nodeCount", node_count)] {
        l.pushnumber(value);
        l.setfield(graph, key);
    }
    l.createtable(0, 0);
    let nodes = l.gettop();
    l.pushvalue(nodes);
    l.setfield(graph, c"nodes");
    l.createtable(0, 0);
    let links = l.gettop();
    l.pushvalue(links);
    l.setfield(graph, c"links");
    if header_only {
        l.settop(graph);
        return 1;
    }
    if version != VERSION {
        let why = format!("version {}", crate::lua::tostring(l, {
            l.pushnumber(version);
            -1
        }));
        return fail(l, &why);
    }
    let read = (|| -> Option<()> {
        for i in 1..=node_count.max(0.0) as c_int {
            l.createtable(0, 8);
            let node = l.gettop();
            l.createtable(0, 3);
            for key in [c"x", c"y", c"z"] {
                l.pushnumber(float(&mut at)?);
                l.setfield(-2, key);
            }
            l.setfield(node, c"pos");
            l.pushnumber(float(&mut at)?);
            l.setfield(node, c"yaw");
            l.createtable(0, NUM_HULLS as c_int);
            for hull in 0..NUM_HULLS {
                l.pushnumber(float(&mut at)?);
                l.rawseti(-2, hull as c_int);
            }
            l.setfield(node, c"offsets");
            l.pushnumber(byte(&mut at)?);
            l.setfield(node, c"type");
            l.pushnumber(uint16(&mut at)?);
            l.setfield(node, c"info");
            let zone = uint16(&mut at)?;
            l.pushnumber(if zone >= 32768.0 { zone - 65536.0 } else { zone });
            l.setfield(node, c"zone");
            l.rawseti(nodes, i);
        }
        let link_count = int32(&mut at)?;
        for i in 1..=link_count.max(0.0) as c_int {
            l.createtable(0, 3);
            let link = l.gettop();
            for key in [c"a", c"b"] {
                let n = uint16(&mut at)?;
                l.pushnumber(if n >= 32768.0 { n - 65536.0 } else { n } + 1.0);
                l.setfield(link, key);
            }
            l.createtable(0, NUM_HULLS as c_int);
            for hull in 0..NUM_HULLS {
                l.pushnumber(byte(&mut at)?);
                l.rawseti(-2, hull as c_int);
            }
            l.setfield(link, c"moves");
            l.rawseti(links, i);
        }
        for i in 1..=node_count.max(0.0) as c_int {
            l.rawgeti(nodes, i);
            l.pushnumber(int32(&mut at)?);
            l.setfield(-2, c"hammerId");
            l.settop(-2);
        }
        Some(())
    })();
    if read.is_none() || at != data.len() {
        return fail(l, "trailing or missing bytes");
    }
    l.settop(graph);
    1
}

/// Pushes the nodegraph module: its functions and constants, HULLS as the
/// Lua twin lays it out.
pub unsafe fn push_module(l: L) {
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
        l.pushnumber(value);
        l.setfield(-2, name);
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
    l.createtable(NUM_HULLS as c_int, 0);
    for (i, (name, mins, maxs, ground)) in hulls.iter().enumerate() {
        l.createtable(0, 4);
        crate::lua::push_str(l, name);
        l.setfield(-2, c"name");
        for (key, v) in [(c"mins", mins), (c"maxs", maxs)] {
            l.createtable(3, 0);
            for (k, &x) in v.iter().enumerate() {
                l.pushnumber(x);
                l.rawseti(-2, k as c_int + 1);
            }
            l.setfield(-2, key);
        }
        l.pushboolean(*ground as c_int);
        l.setfield(-2, c"ground");
        l.rawseti(-2, i as c_int);
    }
    l.setfield(-2, c"HULLS");
}
