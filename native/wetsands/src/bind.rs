//! The module's Lua face: `foundation.wetsands.native`, with the nav mesh,
//! the walker model and the route search as userdata.
//!
//! A search's rules are Lua functions passed to each Step, asked from inside
//! it; a rule that uses the search it was asked by is refused (the search is
//! busy), and one that raises leaves the search spent.

use crate::navmesh::{MeshBuilder, NavMesh};
use crate::search::{RouteSearch, Rules};
use crate::walker::{Jump, Limits, Preference, Rooms, Step, Walker};
use foundation::astar::Status;
use foundation::lua::{
    api, field_number, field_truthy, push_str, raise, raise_owned, set_function, CFunction, GLOBALSINDEX, L, TFUNCTION,
    TNUMBER, TTABLE,
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
        (c"Search", mesh_search),
    ];
}

impl Native for WalkerHandle {
    const NAME: &'static CStr = c"foundation.wetsands.native.walker";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[(c"Price", walker_price)];
}

impl Native for SearchHandle {
    const NAME: &'static CStr = c"foundation.wetsands.native.search";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Close", search_close),
        (c"CloseLink", search_close_link),
        (c"Room", search_room),
        (c"Penalize", search_penalize),
        (c"Estimate", search_estimate),
        (c"Step", search_step),
        (c"Status", search_status),
        (c"Expanded", search_expanded),
        (c"MaxExpanded", search_max_expanded),
        (c"Start", search_start),
        (c"Goal", search_goal),
        (c"Closest", search_closest),
        (c"Route", search_route),
        (c"CostSoFar", search_cost_so_far),
        (c"Parents", search_parents),
    ];
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

unsafe fn sealed(l: L) -> Arc<NavMesh> {
    match userdata::check::<Mesh>(l, 1) {
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
    number(l, sealed(l).areas() as f64)
}

/// mesh:Search(model, startId, goalId, maxExpanded, goalX, goalY, goalZ) -> a search
unsafe extern "C-unwind" fn mesh_search(l: L) -> c_int {
    let api = api();
    let mesh = sealed(l);
    let walker = walker_from(l, 2);
    let (start, goal, max_expanded) = (check_whole(l, 3), check_whole(l, 4), check_whole(l, 5));
    let goal_pos = [(api.checknumber)(l, 6), (api.checknumber)(l, 7), (api.checknumber)(l, 8)];
    match RouteSearch::new(mesh, walker, start, goal, max_expanded, goal_pos) {
        Ok(search) => userdata::push(l, SearchHandle { search, busy: false }),
        Err(e) => raise_owned(l, e.to_string()),
    }
    1
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

macro_rules! told {
    ($l:expr, $result:expr) => {
        if let Err(e) = $result {
            raise_owned($l, e.to_string());
        }
    };
}

/// search:Close(id)
unsafe extern "C-unwind" fn search_close(l: L) -> c_int {
    let id = check_whole(l, 2);
    told!(l, search(l).close(id));
    0
}

/// search:CloseLink(fromId, toId)
unsafe extern "C-unwind" fn search_close_link(l: L) -> c_int {
    let (from, to) = (check_whole(l, 2), check_whole(l, 3));
    told!(l, search(l).close_link(from, to));
    0
}

/// search:Room(id, team)
unsafe extern "C-unwind" fn search_room(l: L) -> c_int {
    let (id, team) = (check_whole(l, 2), (api().checknumber)(l, 3) as i32);
    told!(l, search(l).room(id, team));
    0
}

/// search:Penalize(id)
unsafe extern "C-unwind" fn search_penalize(l: L) -> c_int {
    let id = check_whole(l, 2);
    told!(l, search(l).penalize(id));
    0
}

/// search:Estimate(id, estimate)
unsafe extern "C-unwind" fn search_estimate(l: L) -> c_int {
    let (id, estimate) = (check_whole(l, 2), (api().checknumber)(l, 3));
    told!(l, search(l).estimate(id, estimate));
    0
}

/// The rules as Lua functions on the stack: traversable(areaId) -> bool,
/// crossable(fromId, toId) -> bool; an absent one opens everything.
struct LuaRules {
    l: L,
    traversable: Option<c_int>,
    crossable: Option<c_int>,
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
}

unsafe fn optional_function(l: L, index: c_int) -> Option<c_int> {
    match (api().type_of)(l, index) {
        TFUNCTION => Some(index),
        t if t <= 0 => None,
        _ => raise_owned(l, format!("argument {index}: a rule function or nil is wanted")),
    }
}

/// search:Step(budget[, traversable[, crossable]]) -> "running", "found" or "failed"
unsafe extern "C-unwind" fn search_step(l: L) -> c_int {
    let budget = check_whole(l, 2);
    let mut rules = LuaRules { l, traversable: optional_function(l, 3), crossable: optional_function(l, 4) };
    search(l);
    let handle = userdata::check::<SearchHandle>(l, 1);
    handle.busy = true;
    let result = handle.search.step(budget, &mut rules);
    handle.busy = false;
    match result {
        Ok(status) => push_status(l, status),
        Err(e) => raise_owned(l, e.to_string()),
    }
}

unsafe extern "C-unwind" fn search_status(l: L) -> c_int {
    let status = search(l).status();
    push_status(l, status)
}

unsafe extern "C-unwind" fn search_expanded(l: L) -> c_int {
    number(l, search(l).expanded() as f64)
}

unsafe extern "C-unwind" fn search_max_expanded(l: L) -> c_int {
    number(l, search(l).max_expanded() as f64)
}

unsafe extern "C-unwind" fn search_start(l: L) -> c_int {
    number(l, search(l).start() as f64)
}

unsafe extern "C-unwind" fn search_goal(l: L) -> c_int {
    number(l, search(l).goal() as f64)
}

unsafe extern "C-unwind" fn search_closest(l: L) -> c_int {
    number(l, search(l).closest() as f64)
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

/// search:Parents() -> areaId -> the id of the area it was reached from
unsafe extern "C-unwind" fn search_parents(l: L) -> c_int {
    let api = api();
    let parents = search(l).parents();
    (api.createtable)(l, 0, parents.len() as c_int);
    for &(id, parent) in &parents {
        (api.pushnumber)(l, parent as f64);
        (api.rawseti)(l, -2, id as c_int);
    }
    drop(parents);
    1
}

// Opening -------------------------------------------------------------------

unsafe fn library(l: L, name: &CStr, functions: &[(&CStr, CFunction)]) {
    let api = api();
    (api.createtable)(l, 0, functions.len() as c_int);
    for (function_name, function) in functions {
        set_function(l, function_name, *function);
    }
    (api.setfield)(l, -2, name.as_ptr());
}

/// `t[name]`, made a table when absent, pushed (t at `index`, absolute).
unsafe fn subtable(l: L, index: c_int, name: &CStr) {
    let api = api();
    (api.getfield)(l, index, name.as_ptr());
    if (api.type_of)(l, -1) != TTABLE {
        (api.settop)(l, -2);
        (api.createtable)(l, 0, 1);
        (api.pushvalue)(l, -1);
        (api.setfield)(l, index, name.as_ptr());
    }
}

/// Builds `foundation.wetsands.native` and leaves it on the stack, above
/// `foundation` and `foundation.wetsands`.
unsafe fn open(l: L) {
    let api = api();
    subtable(l, GLOBALSINDEX, c"foundation");
    let foundation = (api.gettop)(l);
    subtable(l, foundation, c"wetsands");
    (api.createtable)(l, 0, 2);
    library(l, c"mesh", &[(c"New", mesh_new)]);
    library(l, c"walker", &[(c"New", walker_new)]);
    (api.pushvalue)(l, -1);
    (api.setfield)(l, -3, c"native".as_ptr());
}

/// GMod's entry point.
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(l: L) -> c_int {
    if foundation::lua::open().is_err() {
        return 0;
    }
    open(l);
    (api().settop)(l, -4);
    0
}

#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_close(_l: L) -> c_int {
    0
}

/// Stock Lua's entry point (`package.loadlib`), for the LuaJIT tests:
/// returns `foundation.wetsands.native`.
#[no_mangle]
pub unsafe extern "C-unwind" fn luaopen_wetsands(l: L) -> c_int {
    if foundation::lua::open().is_err() {
        return 0;
    }
    open(l);
    1
}
