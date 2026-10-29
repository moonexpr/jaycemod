//! wetsands.path and its strategies (foundation.wetsands.path.ground, hl2,
//! scatter, tfbot), native: the Lua twins' contracts, their costs formula
//! for formula, so a step prices to the same double. The strategies are
//! parts loaded by name (WS.require), not globals, so the module preloads
//! them into package.loaded, which WS.require reads first.

use foundation::lua::{api, field_number, field_truthy, set_function, CFunction, GLOBALSINDEX, L, TNIL, TTABLE};
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
    (api().pushnumber)(l, n);
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
    let dz = (api().checknumber)(l, 1);
    let limits = limits_at(l, 2);
    (api().pushboolean)(l, walkable(dz, &limits) as c_int);
    1
}

/// Pushes Path.Model(limits at `limits`, ...): the limits; the caller adds
/// its fields.
unsafe fn push_model(l: L, limits: c_int) {
    let api = api();
    (api.createtable)(l, 0, 12);
    for key in [c"stepHeight", c"jumpHeight", c"deathDropHeight"] {
        (api.getfield)(l, limits, key.as_ptr());
        (api.setfield)(l, -2, key.as_ptr());
    }
    (api.pushboolean)(l, field_truthy(l, limits, c"crouches") as c_int);
    (api.setfield)(l, -2, c"crouches".as_ptr());
}

/// path.Model(limits, fields) -> a walker model
unsafe extern "C-unwind" fn path_model(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    push_model(l, 1);
    if (api.type_of)(l, 2) == TTABLE {
        (api.pushnil)(l);
        while (api.next)(l, 2) != 0 {
            (api.pushvalue)(l, -2);
            (api.insert)(l, -2);
            (api.rawset)(l, -4);
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
    let pref = (api().checknumber)(l, 3);
    number(l, weighted(l, 1, &limits, pref))
}

unsafe extern "C-unwind" fn ground_cost(l: L) -> c_int {
    let limits = limits_at(l, 2);
    number(l, weighted(l, 1, &limits, 1.0))
}

unsafe extern "C-unwind" fn ground_model(l: L) -> c_int {
    push_model(l, 1);
    (api().pushnumber)(l, JUMP_PENALTY);
    (api().setfield)(l, -2, c"jumpAdded".as_ptr());
    1
}

// path.scatter ------------------------------------------------------------------

unsafe extern "C-unwind" fn scatter_preference(l: L) -> c_int {
    let api = api();
    number(l, preference((api.checknumber)(l, 1), (api.checknumber)(l, 2), (api.checknumber)(l, 3)))
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
    let api = api();
    ground_model(l);
    (api.pushboolean)(l, 1);
    (api.setfield)(l, -2, c"scatter".as_ptr());
    (api.getfield)(l, 2, c"entIndex".as_ptr());
    (api.setfield)(l, -2, c"entIndex".as_ptr());
    (api.getfield)(l, 2, c"now".as_ptr());
    (api.setfield)(l, -2, c"now".as_ptr());
    1
}

// path.tfbot --------------------------------------------------------------------

unsafe fn in_enemy_spawn_room(l: L, step: c_int, bot: c_int) -> bool {
    let api = api();
    let room = num(l, step, c"spawnRoomTeam", NOBODY);
    (api.getfield)(l, bot, c"team".as_ptr());
    let team = (api.tonumber)(l, -1);
    let has_team = (api.type_of)(l, -1) != TNIL;
    (api.settop)(l, -2);
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
    let api = api();
    push_model(l, 1);
    (api.pushnumber)(l, TFBOT_JUMP_PENALTY);
    (api.setfield)(l, -2, c"jumpScaled".as_ptr());
    (api.pushboolean)(l, 1);
    (api.setfield)(l, -2, c"rooms".as_ptr());
    (api.getfield)(l, 2, c"team".as_ptr());
    (api.setfield)(l, -2, c"team".as_ptr());
    (api.getfield)(l, 2, c"team".as_ptr());
    let team = (api.tonumber)(l, -1);
    (api.settop)(l, -2);
    let winners = field_truthy(l, 2, c"roundWon") && num(l, 2, c"winningTeam", f64::NAN) == team;
    (api.pushboolean)(l, winners as c_int);
    (api.setfield)(l, -2, c"winners".as_ptr());
    let scatter = num(l, 2, c"route", f64::NAN) == DEFAULT_ROUTE && !field_truthy(l, 2, c"miniBoss");
    (api.pushboolean)(l, scatter as c_int);
    (api.setfield)(l, -2, c"scatter".as_ptr());
    (api.getfield)(l, 2, c"entIndex".as_ptr());
    (api.setfield)(l, -2, c"entIndex".as_ptr());
    (api.getfield)(l, 2, c"now".as_ptr());
    (api.setfield)(l, -2, c"now".as_ptr());
}

unsafe extern "C-unwind" fn tfbot_model(l: L) -> c_int {
    (api().settop)(l, 2);
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
    let attributes = (api().checknumber)(l, 1) as u32;
    (api().pushboolean)(l, (attributes & NAV_MESH_CROUCH != 0) as c_int);
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
    (api().settop)(l, 2);
    push_tfbot_model(l);
    (api().pushboolean)(l, 1);
    (api().setfield)(l, -2, c"attributeRule".as_ptr());
    1
}

unsafe fn push_limits(l: L, step: f64, jump: f64, drop: f64, crouches: bool) {
    let api = api();
    (api.createtable)(l, 0, 4);
    for (key, value) in [(c"stepHeight", step), (c"jumpHeight", jump), (c"deathDropHeight", drop)] {
        (api.pushnumber)(l, value);
        (api.setfield)(l, -2, key.as_ptr());
    }
    if crouches {
        (api.pushboolean)(l, 1);
        (api.setfield)(l, -2, c"crouches".as_ptr());
    }
}

unsafe fn module(l: L, functions: &[(&CStr, CFunction)], numbers: &[(&CStr, f64)]) {
    let api = api();
    (api.createtable)(l, 0, (functions.len() + numbers.len()) as c_int);
    for (name, f) in functions {
        set_function(l, name, *f);
    }
    for (name, n) in numbers {
        (api.pushnumber)(l, *n);
        (api.setfield)(l, -2, name.as_ptr());
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
    let api = api();
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
            (api.setfield)(l, -2, c"LIMITS".as_ptr());
            push_limits(l, STEP_HEIGHT, SOLDIER_JUMP_HEIGHT, SOLDIER_DROP_HEIGHT, true);
            (api.setfield)(l, -2, c"SOLDIER_LIMITS".as_ptr());
        }
    }
}

/// Preloads each part into package.loaded, unless already loaded there.
pub unsafe fn preload(l: L) {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"package".as_ptr());
    (api.getfield)(l, -1, c"loaded".as_ptr());
    for (i, name) in PARTS.iter().enumerate() {
        push_part(l, i);
        (api.setfield)(l, -2, name.as_ptr());
    }
    (api.settop)(l, -3);
}
