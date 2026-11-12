//! wetsands.path and its strategies (foundation.wetsands.path.ground, hl2,
//! scatter, tfbot), native: the Lua twins' contracts, their costs formula
//! for formula, so a step prices to the same double. The strategies are
//! parts loaded by name (WS.require), not globals, so the module preloads
//! them into package.loaded, which WS.require reads first.

use foundation::lua::{field_number, field_truthy, set_function, CFunction, GLOBALSINDEX, L, TNIL, TTABLE};
use std::ffi::{c_int, CStr};

const IMPASSABLE: f64 = -1.0;
const JUMP_PENALTY: f64 = 5.0;
const TFBOT_JUMP_PENALTY: f64 = 2.0;
const NAV_MESH_CROUCH: u32 = 0x1;
const NAV_MESH_JUMP: u32 = 0x2;
const STEP_HEIGHT: f64 = 18.0;
const SOLDIER_DROP_HEIGHT: f64 = 1000.0;
const SOLDIER_JUMP_HEIGHT: f64 = 72.0;
const ROUTE_PERIOD: f64 = 10.0;
const PREFERENCE_SPREAD: f64 = 50.0;
const DEFAULT_ROUTE: f64 = 0.0;
const NOBODY: f64 = 0.0;

unsafe fn number(l: L, n: f64) -> c_int {
    l.pushnumber(n);
    1
}

/// A number field of the table at `t`, or `default`.
unsafe fn num(l: L, t: c_int, name: &CStr, default: f64) -> f64 {
    field_number(l, t, name).unwrap_or(default)
}

struct Limits {
    step: f64,
    jump: f64,
    drop: f64,
    crouches: bool,
}

unsafe fn limits_at(l: L, t: c_int) -> Limits {
    Limits {
        step: num(l, t, c"stepHeight", f64::NAN),
        jump: num(l, t, c"jumpHeight", f64::NAN),
        drop: num(l, t, c"deathDropHeight", f64::NAN),
        crouches: field_truthy(l, t, c"crouches"),
    }
}

fn walkable(dz: f64, limits: &Limits) -> bool {
    dz < limits.jump && dz >= -limits.drop
}

/// The step's distance: its ladder, else its length, else the centres'.
unsafe fn distance(l: L, step: c_int) -> f64 {
    if let Some(ladder) = field_number(l, step, c"ladderLength") {
        return ladder;
    }
    let length = num(l, step, c"length", 0.0);
    if length > 0.0 {
        length
    } else {
        num(l, step, c"centerDistance", 0.0)
    }
}

fn preference(ent_index: f64, area_id: f64, now: f64) -> f64 {
    let time_mod = (now / ROUTE_PERIOD).floor() + 1.0;
    1.0 + PREFERENCE_SPREAD * (1.0 + (ent_index * area_id * time_mod).cos())
}

// wetsands.path ---------------------------------------------------------------

/// path.Walkable(deltaZ, limits) -> bool
unsafe extern "C-unwind" fn path_walkable(l: L) -> c_int {
    let dz = l.checknumber(1);
    let limits = limits_at(l, 2);
    l.pushboolean(walkable(dz, &limits) as c_int);
    1
}

/// Pushes Path.Model(limits at `limits`, ...): the limits; the caller adds
/// its fields.
unsafe fn push_model(l: L, limits: c_int) {
    l.createtable(0, 12);
    for key in [c"stepHeight", c"jumpHeight", c"deathDropHeight"] {
        l.getfield(limits, key);
        l.setfield(-2, key);
    }
    for key in [c"crouches", c"ladders"] {
        l.pushboolean(field_truthy(l, limits, key) as c_int);
        l.setfield(-2, key);
    }
}

/// path.Model(limits, fields) -> a walker model
unsafe extern "C-unwind" fn path_model(l: L) -> c_int {
    l.settop(2);
    push_model(l, 1);
    if l.type_of(2) == TTABLE {
        l.pushnil();
        while l.next(2) != 0 {
            l.pushvalue(-2);
            l.insert(-2);
            l.rawset(-4);
        }
    }
    1
}

// path.ground -------------------------------------------------------------------

unsafe fn weighted(l: L, step: c_int, limits: &Limits, pref: f64) -> f64 {
    if !field_truthy(l, step, c"hasFrom") {
        return 0.0;
    }
    if !field_truthy(l, step, c"traversable") {
        return IMPASSABLE;
    }
    let mut dist = distance(l, step);
    let dz = num(l, step, c"heightChange", 0.0);
    if !walkable(dz, limits) {
        return IMPASSABLE;
    }
    if dz >= limits.step {
        dist += JUMP_PENALTY * dist;
    }
    dist * pref + num(l, step, c"fromCostSoFar", 0.0)
}

unsafe extern "C-unwind" fn ground_weighted(l: L) -> c_int {
    let limits = limits_at(l, 2);
    let pref = l.checknumber(3);
    number(l, weighted(l, 1, &limits, pref))
}

unsafe extern "C-unwind" fn ground_cost(l: L) -> c_int {
    let limits = limits_at(l, 2);
    number(l, weighted(l, 1, &limits, 1.0))
}

unsafe extern "C-unwind" fn ground_model(l: L) -> c_int {
    push_model(l, 1);
    l.pushnumber(JUMP_PENALTY);
    l.setfield(-2, c"jumpAdded");
    1
}

// path.scatter ------------------------------------------------------------------

unsafe extern "C-unwind" fn scatter_preference(l: L) -> c_int {
    number(l, preference(l.checknumber(1), l.checknumber(2), l.checknumber(3)))
}

unsafe extern "C-unwind" fn scatter_cost(l: L) -> c_int {
    if !field_truthy(l, 1, c"hasFrom") {
        return number(l, 0.0);
    }
    let limits = limits_at(l, 2);
    let pref = preference(num(l, 3, c"entIndex", 0.0), num(l, 1, c"areaId", 0.0), num(l, 3, c"now", 0.0));
    number(l, weighted(l, 1, &limits, pref))
}

unsafe extern "C-unwind" fn scatter_model(l: L) -> c_int {
    ground_model(l);
    l.pushboolean(1);
    l.setfield(-2, c"scatter");
    l.getfield(2, c"entIndex");
    l.setfield(-2, c"entIndex");
    l.getfield(2, c"now");
    l.setfield(-2, c"now");
    1
}

// path.tfbot --------------------------------------------------------------------

unsafe fn in_enemy_spawn_room(l: L, step: c_int, bot: c_int) -> bool {
    let room = num(l, step, c"spawnRoomTeam", NOBODY);
    l.getfield(bot, c"team");
    let team = l.tonumber(-1);
    let has_team = l.type_of(-1) != TNIL;
    l.settop(-2);
    if room == NOBODY || (has_team && room == team) {
        return false;
    }
    let won = field_truthy(l, bot, c"roundWon") && num(l, bot, c"winningTeam", f64::NAN) == team;
    !won
}

unsafe fn tfbot_preference(l: L, step: c_int, bot: c_int) -> f64 {
    if num(l, bot, c"route", f64::NAN) != DEFAULT_ROUTE || field_truthy(l, bot, c"miniBoss") {
        return 1.0;
    }
    preference(num(l, bot, c"entIndex", 0.0), num(l, step, c"areaId", 0.0), num(l, bot, c"now", 0.0))
}

unsafe fn tfbot_price(l: L, step: c_int, limits: &Limits, bot: c_int) -> f64 {
    if !field_truthy(l, step, c"hasFrom") {
        return 0.0;
    }
    if !field_truthy(l, step, c"traversable") || in_enemy_spawn_room(l, step, bot) {
        return IMPASSABLE;
    }
    let mut dist = distance(l, step);
    let dz = num(l, step, c"heightChange", 0.0);
    if !walkable(dz, limits) {
        return IMPASSABLE;
    }
    if dz >= limits.step {
        dist *= TFBOT_JUMP_PENALTY;
    }
    dist * tfbot_preference(l, step, bot) + num(l, step, c"fromCostSoFar", 0.0)
}

unsafe extern "C-unwind" fn tfbot_cost(l: L) -> c_int {
    let limits = limits_at(l, 2);
    number(l, tfbot_price(l, 1, &limits, 3))
}

unsafe fn push_tfbot_model(l: L) {
    push_model(l, 1);
    l.pushnumber(TFBOT_JUMP_PENALTY);
    l.setfield(-2, c"jumpScaled");
    l.pushboolean(1);
    l.setfield(-2, c"rooms");
    l.getfield(2, c"team");
    l.setfield(-2, c"team");
    l.getfield(2, c"team");
    let team = l.tonumber(-1);
    l.settop(-2);
    let winners = field_truthy(l, 2, c"roundWon") && num(l, 2, c"winningTeam", f64::NAN) == team;
    l.pushboolean(winners as c_int);
    l.setfield(-2, c"winners");
    let scatter = num(l, 2, c"route", f64::NAN) == DEFAULT_ROUTE && !field_truthy(l, 2, c"miniBoss");
    l.pushboolean(scatter as c_int);
    l.setfield(-2, c"scatter");
    l.getfield(2, c"entIndex");
    l.setfield(-2, c"entIndex");
    l.getfield(2, c"now");
    l.setfield(-2, c"now");
}

unsafe extern "C-unwind" fn tfbot_model(l: L) -> c_int {
    l.settop(2);
    push_tfbot_model(l);
    1
}

// path.hl2 ----------------------------------------------------------------------

fn uncrossable(attributes: u32, limits: &Limits) -> bool {
    if attributes & NAV_MESH_CROUCH != 0 && !limits.crouches {
        return true;
    }
    attributes & NAV_MESH_JUMP != 0 && limits.jump <= limits.step
}

unsafe extern "C-unwind" fn hl2_must_crouch(l: L) -> c_int {
    let attributes = l.checknumber(1) as u32;
    l.pushboolean((attributes & NAV_MESH_CROUCH != 0) as c_int);
    1
}

unsafe extern "C-unwind" fn hl2_cost(l: L) -> c_int {
    let limits = limits_at(l, 2);
    if field_truthy(l, 1, c"hasFrom") && uncrossable(num(l, 1, c"attributes", 0.0) as u32, &limits) {
        return number(l, IMPASSABLE);
    }
    number(l, tfbot_price(l, 1, &limits, 3))
}

unsafe extern "C-unwind" fn hl2_model(l: L) -> c_int {
    l.settop(2);
    push_tfbot_model(l);
    l.pushboolean(1);
    l.setfield(-2, c"attributeRule");
    1
}

unsafe fn push_limits(l: L, step: f64, jump: f64, drop: f64, soldier: bool) {
    l.createtable(0, 5);
    for (key, value) in [(c"stepHeight", step), (c"jumpHeight", jump), (c"deathDropHeight", drop)] {
        l.pushnumber(value);
        l.setfield(-2, key);
    }
    if soldier {
        for key in [c"crouches", c"ladders"] {
            l.pushboolean(1);
            l.setfield(-2, key);
        }
    }
}

unsafe fn module(l: L, functions: &[(&CStr, CFunction)], numbers: &[(&CStr, f64)]) {
    l.createtable(0, (functions.len() + numbers.len()) as c_int);
    for (name, f) in functions {
        set_function(l, name, *f);
    }
    for (name, n) in numbers {
        l.pushnumber(*n);
        l.setfield(-2, name);
    }
}

/// Pushes wetsands.path.
pub unsafe fn push_path(l: L) {
    module(l, &[(c"Walkable", path_walkable), (c"Model", path_model)], &[(c"IMPASSABLE", IMPASSABLE), (c"JUMP_PENALTY", JUMP_PENALTY)]);
}

/// The strategy parts, by the names WS.require loads them by.
pub const PARTS: &[&CStr] = &[
    c"foundation.wetsands.path.ground",
    c"foundation.wetsands.path.scatter",
    c"foundation.wetsands.path.tfbot",
    c"foundation.wetsands.path.hl2",
];

/// Pushes the part named PARTS[i].
pub unsafe fn push_part(l: L, i: usize) {
    match i {
        0 => module(l, &[(c"Weighted", ground_weighted), (c"Cost", ground_cost), (c"Model", ground_model)], &[]),
        1 => module(l, &[(c"Preference", scatter_preference), (c"Cost", scatter_cost), (c"Model", scatter_model)], &[]),
        2 => module(
            l,
            &[(c"Cost", tfbot_cost), (c"Model", tfbot_model)],
            &[(c"DEFAULT_ROUTE", 0.0), (c"FASTEST_ROUTE", 1.0), (c"SAFEST_ROUTE", 2.0), (c"RETREAT_ROUTE", 3.0)],
        ),
        _ => {
            module(
                l,
                &[(c"MustCrouch", hl2_must_crouch), (c"Cost", hl2_cost), (c"Model", hl2_model)],
                &[
                    (c"NAV_MESH_CROUCH", NAV_MESH_CROUCH as f64),
                    (c"NAV_MESH_JUMP", NAV_MESH_JUMP as f64),
                    (c"SOLDIER_DROP_HEIGHT", SOLDIER_DROP_HEIGHT),
                    (c"SOLDIER_JUMP_HEIGHT", SOLDIER_JUMP_HEIGHT),
                ],
            );
            push_limits(l, STEP_HEIGHT, STEP_HEIGHT, STEP_HEIGHT, false);
            l.setfield(-2, c"LIMITS");
            push_limits(l, STEP_HEIGHT, SOLDIER_JUMP_HEIGHT, SOLDIER_DROP_HEIGHT, true);
            l.setfield(-2, c"SOLDIER_LIMITS");
        }
    }
}

/// Preloads each part into package.loaded, unless already loaded there.
pub unsafe fn preload(l: L) {
    l.getfield(GLOBALSINDEX, c"package");
    l.getfield(-1, c"loaded");
    for (i, name) in PARTS.iter().enumerate() {
        push_part(l, i);
        l.setfield(-2, name);
    }
    l.settop(-3);
}
