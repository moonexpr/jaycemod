//! The module's Lua face: `wetsands.navsearch`'s contract (see its Lua twin,
//! foundation/wetsands/navsearch.lua), installed over the Lua one when GMod
//! opens the module, with the nav mesh and the route search as userdata.
//!
//! A search keeps its rules (Lua functions) in its userdata's environment
//! and asks them from inside Step; a rule that uses the search it was asked
//! by is refused (the search is busy), and one that raises leaves the search
//! spent.

use crate::navmesh::{MeshBuilder, NavMesh};
use crate::search::{RouteSearch, Rules};
use crate::walker::{Jump, Limits, Preference, Rooms, Step, Walker};
use foundation::astar::Status;
use foundation::lua::{
    api, each, field_number, field_truthy, push_str, raise, raise_owned, set_function, string_at, CFunction,
    L, TFUNCTION, TNIL, TNUMBER, TTABLE,
};
use foundation::userdata::{self, Native};
use std::ffi::{c_int, CStr};
use std::sync::Arc;

enum Mesh {
    Building(MeshBuilder),
    Sealed(Arc<NavMesh>),
}

struct SearchHandle {
    search: RouteSearch,
    busy: bool,
}

struct WalkerHandle(Walker);

impl Native for Mesh {
    const NAME: &'static CStr = c"foundation.wetsands.native.mesh";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Area", mesh_area),
        (c"Link", mesh_link),
        (c"Seal", mesh_seal),
        (c"Sealed", mesh_sealed),
        (c"Areas", mesh_areas),
    ];
}

impl Native for WalkerHandle {
    const NAME: &'static CStr = c"foundation.wetsands.native.walker";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[(c"Price", walker_price)];
}

impl Native for SearchHandle {
    const NAME: &'static CStr = c"foundation.wetsands.native.search";
    const METHODS: &'static [(&'static CStr, CFunction)] =
        &[(c"Step", search_step), (c"Route", search_route), (c"CostSoFar", search_cost_so_far)];
    const INDEX: Option<CFunction> = Some(search_index);
}

/// The whole number at `index` (an area id, a budget), or a Lua error.
unsafe fn check_whole(l: L, index: c_int) -> u32 {
    let value = (api().checknumber)(l, index);
    if !(0.0..=u32::MAX as f64).contains(&value) || value.fract() != 0.0 {
        raise_owned(l, format!("argument {index}: a whole number from 0 is wanted, not {value}"));
    }
    value as u32
}

unsafe fn push_status(l: L, status: Status) -> c_int {
    push_str(
        l,
        match status {
            Status::Running => "running",
            Status::Found => "found",
            Status::Failed => "failed",
        },
    );
    1
}

unsafe fn number(l: L, value: f64) -> c_int {
    (api().pushnumber)(l, value);
    1
}

// The mesh ------------------------------------------------------------------

/// mesh.New() -> an empty mesh, building.
unsafe extern "C-unwind" fn mesh_new(l: L) -> c_int {
    userdata::push(l, Mesh::Building(MeshBuilder::default()));
    1
}

unsafe fn building<'a>(l: L) -> &'a mut MeshBuilder {
    match userdata::check::<Mesh>(l, 1) {
        Mesh::Building(builder) => builder,
        Mesh::Sealed(_) => raise(l, c"the mesh is sealed: areas and links come before Seal"),
    }
}

unsafe fn sealed(l: L, index: c_int) -> Arc<NavMesh> {
    match userdata::check::<Mesh>(l, index) {
        Mesh::Sealed(mesh) => Arc::clone(mesh),
        Mesh::Building(_) => raise(l, c"the mesh is not sealed yet"),
    }
}

/// mesh:Area(id, x, y, z, attributes)
unsafe extern "C-unwind" fn mesh_area(l: L) -> c_int {
    let api = api();
    let id = check_whole(l, 2);
    let center = [(api.checknumber)(l, 3), (api.checknumber)(l, 4), (api.checknumber)(l, 5)];
    let attributes = check_whole(l, 6);
    if let Err(e) = building(l).area(id, center, attributes) {
        raise_owned(l, e.to_string());
    }
    0
}

/// mesh:Link(fromId, toId, distance, rise): from's next link, in order.
unsafe extern "C-unwind" fn mesh_link(l: L) -> c_int {
    let api = api();
    let (from, to) = (check_whole(l, 2), check_whole(l, 3));
    let (distance, rise) = ((api.checknumber)(l, 4), (api.checknumber)(l, 5));
    if let Err(e) = building(l).link(from, to, distance, rise) {
        raise_owned(l, e.to_string());
    }
    0
}

/// mesh:Seal(): no more areas or links; searches may begin.
unsafe extern "C-unwind" fn mesh_seal(l: L) -> c_int {
    let mesh = userdata::check::<Mesh>(l, 1);
    let Mesh::Building(builder) = std::mem::replace(mesh, Mesh::Building(MeshBuilder::default())) else {
        raise(l, c"the mesh is sealed already");
    };
    match builder.finish() {
        Ok(built) => *mesh = Mesh::Sealed(Arc::new(built)),
        Err(e) => raise_owned(l, e.to_string()),
    }
    0
}

/// mesh:Sealed() -> whether searches may begin.
unsafe extern "C-unwind" fn mesh_sealed(l: L) -> c_int {
    let is_sealed = matches!(userdata::check::<Mesh>(l, 1), Mesh::Sealed(_));
    (api().pushboolean)(l, is_sealed as c_int);
    1
}

/// mesh:Areas() -> how many areas a sealed mesh has.
unsafe extern "C-unwind" fn mesh_areas(l: L) -> c_int {
    number(l, sealed(l, 1).areas() as f64)
}

// The walker ----------------------------------------------------------------

unsafe fn required(l: L, index: c_int, name: &CStr) -> f64 {
    field_number(l, index, name).unwrap_or_else(|| {
        raise_owned(l, format!("a walker model needs a number {}", name.to_string_lossy()))
    })
}

/// The walker a model table describes (a strategy's Model(limits, bot)):
/// stepHeight, jumpHeight, deathDropHeight, crouches; jumpAdded or
/// jumpScaled; attributeRule; rooms (team, winners); scatter (entIndex,
/// now); lanePenalty.
unsafe fn walker_from(l: L, index: c_int) -> Walker {
    (api().checktype)(l, index, TTABLE);
    let limits = Limits {
        step_height: required(l, index, c"stepHeight"),
        jump_height: required(l, index, c"jumpHeight"),
        death_drop_height: required(l, index, c"deathDropHeight"),
        crouches: field_truthy(l, index, c"crouches"),
    };
    let jump = match (field_number(l, index, c"jumpAdded"), field_number(l, index, c"jumpScaled")) {
        (Some(added), None) => Jump::Added(added),
        (None, Some(scaled)) => Jump::Scaled(scaled),
        _ => raise(l, c"a walker model has one of jumpAdded and jumpScaled"),
    };
    let rooms = field_truthy(l, index, c"rooms").then(|| Rooms {
        team: field_number(l, index, c"team").map(|team| team as i32),
        winners: field_truthy(l, index, c"winners"),
    });
    let preference = if field_truthy(l, index, c"scatter") {
        Preference::scatter(required(l, index, c"entIndex"), required(l, index, c"now"))
    } else {
        Preference::Even
    };
    Walker {
        limits,
        jump,
        attribute_rule: field_truthy(l, index, c"attributeRule"),
        rooms,
        preference,
        lane_penalty: field_number(l, index, c"lanePenalty"),
    }
}

/// walker.New(model) -> a walker, for pricing single steps (the tests'
/// check against the strategies' Lua Cost).
unsafe extern "C-unwind" fn walker_new(l: L) -> c_int {
    let walker = walker_from(l, 1);
    userdata::push(l, WalkerHandle(walker));
    1
}

/// walker:Price(traversable, room, attributes, distance, rise, soFar, areaId, penalized) -> cost
unsafe extern "C-unwind" fn walker_price(l: L) -> c_int {
    let api = api();
    let step = Step {
        traversable: (api.toboolean)(l, 2) != 0,
        room: (api.checknumber)(l, 3) as i32,
        attributes: check_whole(l, 4),
        distance: (api.checknumber)(l, 5),
        rise: (api.checknumber)(l, 6),
        so_far: (api.checknumber)(l, 7),
        area_id: check_whole(l, 8),
        penalized: (api.toboolean)(l, 9) != 0,
    };
    let cost = userdata::check::<WalkerHandle>(l, 1).0.price(&step);
    number(l, cost)
}

// The search ----------------------------------------------------------------

/// The search at index 1, refused while it is busy inside its own step.
unsafe fn search<'a>(l: L) -> &'a mut RouteSearch {
    let handle = userdata::check::<SearchHandle>(l, 1);
    if handle.busy {
        raise(l, c"the search is busy in a step (a rule may not use its own search), or a rule raised and spent it");
    }
    &mut handle.search
}

/// The area id a told table's key (at -2) or value (at -1) holds.
unsafe fn id_at(l: L, index: c_int, what: &str) -> u32 {
    let api = api();
    let value = if (api.type_of)(l, index) == TNUMBER { (api.tonumber)(l, index) } else { -1.0 };
    if !(0.0..=u32::MAX as f64).contains(&value) || value.fract() != 0.0 {
        raise_owned(l, format!("{what}: area ids are whole numbers"));
    }
    value as u32
}

/// `t[name]` of the table at `index` (absolute), pushed, when it is a table;
/// its absolute index, or None (nothing left pushed).
unsafe fn subtable_at(l: L, index: c_int, name: &CStr) -> Option<c_int> {
    let api = api();
    (api.getfield)(l, index, name.as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        return Some((api.gettop)(l));
    }
    (api.settop)(l, -2);
    None
}

/// Tells the search at `handle` what `told` (a table at `told`) says.
unsafe fn tell(l: L, handle: *mut SearchHandle, told: c_int) {
    let search = &mut (*handle).search;
    if let Some(closed) = subtable_at(l, told, c"closed") {
        each(l, closed, |l| told_ok(l, search.close(id_at(l, -2, "told.closed"))));
        (api().settop)(l, -2);
    }
    if let Some(uncrossable) = subtable_at(l, told, c"uncrossable") {
        each(l, uncrossable, |l| {
            let from = id_at(l, -2, "told.uncrossable");
            if (api().type_of)(l, -1) == TTABLE {
                let tos = (api().gettop)(l);
                each(l, tos, |l| told_ok(l, search.close_link(from, id_at(l, -2, "told.uncrossable"))));
            }
        });
        (api().settop)(l, -2);
    }
    if let Some(rooms) = subtable_at(l, told, c"rooms") {
        each(l, rooms, |l| {
            let team = (api().tonumber)(l, -1) as i32;
            told_ok(l, search.room(id_at(l, -2, "told.rooms"), team));
        });
        (api().settop)(l, -2);
    }
    if let Some(estimates) = subtable_at(l, told, c"estimates") {
        each(l, estimates, |l| {
            let estimate = (api().tonumber)(l, -1);
            told_ok(l, search.estimate(id_at(l, -2, "told.estimates"), estimate));
        });
        (api().settop)(l, -2);
    }
}

unsafe fn told_ok(l: L, result: Result<(), crate::search::SearchError>) {
    if let Err(e) = result {
        raise_owned(l, e.to_string());
    }
}

/// navsearch.New(mesh, strategy, limits, bot, start, goal, goalPos,
/// maxExpanded[, told[, rules]]) -> a search; goalPos is anything with x
/// and y (and z) to read: a table, or GMod's Vector.
unsafe extern "C-unwind" fn search_new(l: L) -> c_int {
    let api = api();
    userdata::check::<Mesh>(l, 1);
    (api.checktype)(l, 2, TTABLE);
    (api.getfield)(l, 2, c"Model".as_ptr());
    if (api.type_of)(l, -1) != TFUNCTION {
        raise(l, c"the strategy has no Model(limits, bot): it cannot run natively");
    }
    (api.pushvalue)(l, 3);
    (api.pushvalue)(l, 4);
    (api.call)(l, 2, 1);
    let model = (api.gettop)(l);
    let walker = walker_from(l, model);
    let (start, goal, max_expanded) = (check_whole(l, 5), check_whole(l, 6), check_whole(l, 8));
    let goal_pos = [
        required(l, 7, c"x"),
        required(l, 7, c"y"),
        field_number(l, 7, c"z").unwrap_or(0.0),
    ];
    let search = match RouteSearch::new(sealed(l, 1), walker, start, goal, max_expanded, goal_pos) {
        Ok(search) => search,
        Err(e) => raise_owned(l, e.to_string()),
    };
    userdata::push(l, SearchHandle { search, busy: false });
    let ud = (api.gettop)(l);
    let handle: *mut SearchHandle = userdata::check::<SearchHandle>(l, ud);
    if let Some(penalized) = subtable_at(l, model, c"penalized") {
        each(l, penalized, |l| told_ok(l, (*handle).search.penalize(id_at(l, -2, "model.penalized"))));
        (api.settop)(l, -2);
    }
    if (api.type_of)(l, 9) == TTABLE {
        tell(l, handle, 9);
    }
    (api.createtable)(l, 0, 2);
    if (api.type_of)(l, 10) == TTABLE {
        for name in [c"traversable", c"crossable", c"room"] {
            (api.getfield)(l, 10, name.as_ptr());
            if (api.type_of)(l, -1) == TFUNCTION {
                (api.setfield)(l, -2, name.as_ptr());
            } else {
                (api.settop)(l, -2);
            }
        }
    }
    (api.setfenv)(l, ud);
    (api.pushvalue)(l, ud);
    1
}

/// The rules as Lua functions on the stack: traversable(areaId) -> bool,
/// crossable(fromId, toId) -> bool, room(areaId) -> team; an absent one
/// opens everything (rooms: none).
struct LuaRules {
    l: L,
    traversable: Option<c_int>,
    crossable: Option<c_int>,
    room: Option<c_int>,
}

unsafe fn ask_number(l: L, function: c_int, area: u32) -> f64 {
    let api = api();
    (api.pushvalue)(l, function);
    (api.pushnumber)(l, area as f64);
    (api.call)(l, 1, 1);
    let answer = (api.tonumber)(l, -1);
    (api.settop)(l, -2);
    answer
}

unsafe fn ask(l: L, function: c_int, args: &[u32]) -> bool {
    let api = api();
    (api.pushvalue)(l, function);
    for &arg in args {
        (api.pushnumber)(l, arg as f64);
    }
    (api.call)(l, args.len() as c_int, 1);
    let answer = (api.toboolean)(l, -1) != 0;
    (api.settop)(l, -2);
    answer
}

impl Rules for LuaRules {
    fn traversable(&mut self, area: u32) -> bool {
        // SAFETY: the function sits at its index for the whole step.
        self.traversable.is_none_or(|f| unsafe { ask(self.l, f, &[area]) })
    }

    fn crossable(&mut self, from: u32, to: u32) -> bool {
        // SAFETY: as traversable.
        self.crossable.is_none_or(|f| unsafe { ask(self.l, f, &[from, to]) })
    }

    fn room(&mut self, area: u32) -> i32 {
        // SAFETY: as traversable; a nil answer reads as 0, no room.
        self.room.map_or(crate::walker::NO_ROOM, |f| unsafe { ask_number(self.l, f, area) } as i32)
    }
}

/// The rule `name` in the environment table at `env`, pushed; its index
/// when it is a function.
unsafe fn rule(l: L, env: c_int, name: &CStr) -> Option<c_int> {
    let api = api();
    (api.getfield)(l, env, name.as_ptr());
    ((api.type_of)(l, -1) == TFUNCTION).then(|| (api.gettop)(l))
}

/// search:Step(budget) -> "running", "found" or "failed"
unsafe extern "C-unwind" fn search_step(l: L) -> c_int {
    let api = api();
    let budget = check_whole(l, 2);
    search(l);
    (api.settop)(l, 2);
    (api.getfenv)(l, 1);
    let mut rules = LuaRules {
        l,
        traversable: rule(l, 3, c"traversable"),
        crossable: rule(l, 3, c"crossable"),
        room: rule(l, 3, c"room"),
    };
    let handle = userdata::check::<SearchHandle>(l, 1);
    handle.busy = true;
    let result = handle.search.step(budget, &mut rules);
    handle.busy = false;
    match result {
        Ok(status) => push_status(l, status),
        Err(e) => raise_owned(l, e.to_string()),
    }
}

/// The search's fields (graph.pathfinder's): status, expanded, maxExpanded,
/// start, goal, closest, parent; its methods first.
unsafe extern "C-unwind" fn search_index(l: L) -> c_int {
    let api = api();
    (api.getmetatable)(l, 1);
    (api.pushvalue)(l, 2);
    (api.rawget)(l, -2);
    if (api.type_of)(l, -1) != TNIL {
        return 1;
    }
    let Some(key) = string_at(l, 2) else {
        (api.pushnil)(l);
        return 1;
    };
    let search = search(l);
    match key {
        b"status" => push_status(l, search.status()),
        b"expanded" => number(l, search.expanded() as f64),
        b"maxExpanded" => number(l, search.max_expanded() as f64),
        b"start" => number(l, search.start() as f64),
        b"goal" => number(l, search.goal() as f64),
        b"closest" => number(l, search.closest() as f64),
        b"parent" => push_parents(l, search),
        _ => {
            (api.pushnil)(l);
            1
        }
    }
}

/// search:Route([lastId]) -> the area ids from the start
unsafe extern "C-unwind" fn search_route(l: L) -> c_int {
    let api = api();
    let last = ((api.type_of)(l, 2) == TNUMBER).then(|| check_whole(l, 2));
    let route = match search(l).route(last) {
        Ok(route) => route,
        Err(e) => raise_owned(l, e.to_string()),
    };
    (api.createtable)(l, route.len() as c_int, 0);
    for (i, &id) in route.iter().enumerate() {
        (api.pushnumber)(l, id as f64);
        (api.rawseti)(l, -2, i as c_int + 1);
    }
    drop(route);
    1
}

/// search:CostSoFar(id) -> the cost of its best way, or nil
unsafe extern "C-unwind" fn search_cost_so_far(l: L) -> c_int {
    let id = check_whole(l, 2);
    match search(l).cost_so_far(id) {
        Ok(Some(cost)) => number(l, cost),
        Ok(None) => {
            (api().pushnil)(l);
            1
        }
        Err(e) => raise_owned(l, e.to_string()),
    }
}

/// areaId -> the id of the area it was reached from
unsafe fn push_parents(l: L, search: &RouteSearch) -> c_int {
    let api = api();
    let parents = search.parents();
    (api.createtable)(l, 0, parents.len() as c_int);
    for &(id, parent) in &parents {
        (api.pushnumber)(l, parent as f64);
        (api.rawseti)(l, -2, id as c_int);
    }
    drop(parents);
    1
}

// Opening -------------------------------------------------------------------

// Walks ----------------------------------------------------------------------

/// The whole number at `index`, or None for any other value.
unsafe fn whole_at(l: L, index: c_int) -> Option<u32> {
    let api = api();
    if (api.type_of)(l, index) != TNUMBER {
        return None;
    }
    let value = (api.tonumber)(l, index);
    ((0.0..=u32::MAX as f64).contains(&value) && value.fract() == 0.0).then_some(value as u32)
}

/// The walks Distances answers, (area id, walk), read from its arguments:
/// the mesh (1), starts (2), told (`told`, a table index, if any).
unsafe fn walks_of(l: L, limit: f64, jump: f64, drop: f64, told: Option<c_int>) -> Result<Vec<(u32, f64)>, String> {
    let api = api();
    let mesh = match userdata::check::<Mesh>(l, 1) {
        Mesh::Sealed(mesh) => Arc::clone(mesh),
        Mesh::Building(_) => return Err("the mesh is not sealed yet".into()),
    };
    let mut starts = Vec::new();
    for i in 1..=(api.objlen)(l, 2) {
        (api.rawgeti)(l, 2, i as c_int);
        let id = whole_at(l, -1);
        (api.settop)(l, -2);
        let start = id.and_then(|id| mesh.index_of(id));
        starts.push(start.ok_or_else(|| format!("no area {} in the mesh", id.map_or("?".into(), |id| id.to_string())))?);
    }
    let mut refused = vec![false; mesh.graph().links()];
    if let Some(uncrossable) = told.and_then(|told| subtable_at(l, told, c"uncrossable")) {
        each(l, uncrossable, |l| {
            let from = whole_at(l, -2).and_then(|id| mesh.index_of(id));
            if from.is_none() || (api.type_of)(l, -1) != TTABLE {
                return;
            }
            let tos = (api.gettop)(l);
            each(l, tos, |l| {
                let to = whole_at(l, -2).and_then(|id| mesh.index_of(id));
                if let (Some(from), Some(to)) = (from, to) {
                    if (api.toboolean)(l, -1) != 0 {
                        if let Some(link) = mesh.link_between(from, to) {
                            refused[link] = true;
                        }
                    }
                }
            });
        });
        (api.settop)(l, -2);
    }
    let walks = crate::walks::distances(&mesh, &starts, limit, |rise| rise < jump && rise >= -drop, |link| !refused[link]);
    Ok(walks.iter().enumerate().filter_map(|(area, walk)| walk.map(|walk| (mesh.id(area as u32), walk))).collect())
}

/// navsearch.Distances(mesh, starts, limit, limits[, told]) -> area id ->
/// the cheapest walk to it from the nearest start
unsafe extern "C-unwind" fn distances(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 2, TTABLE);
    let limit = (api.checknumber)(l, 3);
    (api.checktype)(l, 4, TTABLE);
    let jump = field_number(l, 4, c"jumpHeight").unwrap_or_else(|| raise(l, c"limits need a number jumpHeight"));
    let drop = field_number(l, 4, c"deathDropHeight").unwrap_or_else(|| raise(l, c"limits need a number deathDropHeight"));
    let told = ((api.type_of)(l, 5) == TTABLE).then_some(5);
    let walks = match walks_of(l, limit, jump, drop, told) {
        Ok(walks) => walks,
        Err(message) => raise_owned(l, message),
    };
    (api.createtable)(l, 0, walks.len() as c_int);
    for &(id, walk) in &walks {
        (api.pushnumber)(l, walk);
        (api.rawseti)(l, -2, id as c_int);
    }
    1
}

/// Pushes the module's table: navsearch's contract (Mesh, New, Distances)
/// and Walker, a single model's pricing for the tests.
unsafe fn module(l: L) {
    let api = api();
    (api.createtable)(l, 0, 4);
    set_function(l, c"Mesh", mesh_new);
    set_function(l, c"New", search_new);
    set_function(l, c"Distances", distances);
    set_function(l, c"Walker", walker_new);
    (api.pushnumber)(l, crate::walker::NO_ROOM as f64);
    (api.setfield)(l, -2, c"NO_ROOM".as_ptr());
}

/// GMod's entry point: provides the module at `wetsands.navsearch` before
/// foundation's indexes run, where the index's Twin keeps it.
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(l: L) -> c_int {
    if foundation::lua::open().is_err() {
        return 0;
    }
    module(l);
    foundation::module::provide(l, Some(c"wetsands"), c"navsearch");
    crate::path_bind::push_path(l);
    foundation::module::provide(l, Some(c"wetsands"), c"path");
    crate::path_bind::preload(l);
    0
}

#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_close(_l: L) -> c_int {
    0
}

/// Stock Lua's entry point (`package.loadlib`), for the LuaJIT tests:
/// returns the module's table laid out as the globals (`.wetsands.navsearch`),
/// installing nothing, so the Lua twin stays
/// beside it as the oracle.
#[no_mangle]
pub unsafe extern "C-unwind" fn luaopen_wetsands(l: L) -> c_int {
    if foundation::lua::open().is_err() {
        return 0;
    }
    let api = api();
    (api.createtable)(l, 0, 2);
    (api.createtable)(l, 0, 2);
    module(l);
    (api.setfield)(l, -2, c"navsearch".as_ptr());
    crate::path_bind::push_path(l);
    (api.setfield)(l, -2, c"path".as_ptr());
    (api.setfield)(l, -2, c"wetsands".as_ptr());
    // the parts WS.require loads by name, for package.loaded
    (api.createtable)(l, 0, crate::path_bind::PARTS.len() as c_int);
    for (i, name) in crate::path_bind::PARTS.iter().enumerate() {
        crate::path_bind::push_part(l, i);
        (api.setfield)(l, -2, name.as_ptr());
    }
    (api.setfield)(l, -2, c"preload".as_ptr());
    1
}
