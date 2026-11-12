//! The module's Lua face: `wetsands.navsearch`'s contract (see its Lua twin,
//! foundation/wetsands/navsearch.lua), installed over the Lua one when GMod
//! opens the module, with the nav mesh and the route search as userdata.
//!
//! A search keeps its rules (Lua functions) in its userdata's environment
//! and asks them from inside Step; a rule that uses the search it was asked
//! by is refused (the search is busy), and one that raises leaves the search
//! spent.

use crate::calculator::{Calculator, Known, Move};
use crate::navmesh::{MeshBuilder, NavMesh};
use crate::search::{RouteSearch, Rules};
use crate::walker::{Jump, Limits, Preference, Rooms, Step, Walker};
use foundation::astar::Status;
use foundation::lua::{
    each, field_number, field_truthy, push_str, raise, raise_owned, set_function, string_at, CFunction,
    L, TFUNCTION, TNIL, TNUMBER, TTABLE, TUSERDATA,
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

struct KnownHandle(Arc<Known>);

struct CalculatorHandle(Calculator);

impl Native for KnownHandle {
    const NAME: &'static CStr = c"foundation.wetsands.native.told";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[];
}

impl Native for CalculatorHandle {
    const NAME: &'static CStr = c"foundation.wetsands.native.calculator";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[];
}

impl Native for Mesh {
    const NAME: &'static CStr = c"foundation.wetsands.native.mesh";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Area", mesh_area),
        (c"Link", mesh_link),
        (c"Ladder", mesh_ladder),
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
    let value = l.checknumber(index);
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
    l.pushnumber(value);
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
    let id = check_whole(l, 2);
    let center = [l.checknumber(3), l.checknumber(4), l.checknumber(5)];
    let attributes = check_whole(l, 6);
    if let Err(e) = building(l).area(id, center, attributes) {
        raise_owned(l, e.to_string());
    }
    0
}

/// mesh:Link(fromId, toId, distance, rise): from's next link, in order.
unsafe extern "C-unwind" fn mesh_link(l: L) -> c_int {
    let (from, to) = (check_whole(l, 2), check_whole(l, 3));
    let (distance, rise) = (l.checknumber(4), l.checknumber(5));
    if let Err(e) = building(l).link(from, to, distance, rise) {
        raise_owned(l, e.to_string());
    }
    0
}

/// mesh:Ladder(fromId, toId, length): a nav ladder from one area to another.
unsafe extern "C-unwind" fn mesh_ladder(l: L) -> c_int {
    let (from, to) = (check_whole(l, 2), check_whole(l, 3));
    let length = l.checknumber(4);
    if let Err(e) = building(l).ladder(from, to, length) {
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
    l.pushboolean(is_sealed as c_int);
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
/// stepHeight, jumpHeight, deathDropHeight, crouches, ladders; jumpAdded or
/// jumpScaled; attributeRule; rooms (team, winners); scatter (entIndex,
/// now); lanePenalty.
unsafe fn walker_from(l: L, index: c_int) -> Walker {
    l.checktype(index, TTABLE);
    let limits = Limits {
        step_height: required(l, index, c"stepHeight"),
        jump_height: required(l, index, c"jumpHeight"),
        death_drop_height: required(l, index, c"deathDropHeight"),
        crouches: field_truthy(l, index, c"crouches"),
        ladders: field_truthy(l, index, c"ladders"),
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
    let step = Step {
        traversable: l.toboolean(2) != 0,
        room: l.checknumber(3) as i32,
        attributes: check_whole(l, 4),
        distance: l.checknumber(5),
        rise: l.checknumber(6),
        so_far: l.checknumber(7),
        area_id: check_whole(l, 8),
        penalized: l.toboolean(9) != 0,
        ladder: false,
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
    let value = if l.type_of(index) == TNUMBER { l.tonumber(index) } else { -1.0 };
    if !(0.0..=u32::MAX as f64).contains(&value) || value.fract() != 0.0 {
        raise_owned(l, format!("{what}: area ids are whole numbers"));
    }
    value as u32
}

/// `t[name]` of the table at `index` (absolute), pushed, when it is a table;
/// its absolute index, or None (nothing left pushed).
unsafe fn subtable_at(l: L, index: c_int, name: &CStr) -> Option<c_int> {
    l.getfield(index, name);
    if l.type_of(-1) == TTABLE {
        return Some(l.gettop());
    }
    l.settop(-2);
    None
}

/// Tells the search at `handle` what `told` (a table at `told`) says.
unsafe fn tell(l: L, handle: *mut SearchHandle, told: c_int) {
    let search = &mut (*handle).search;
    if let Some(closed) = subtable_at(l, told, c"closed") {
        each(l, closed, |l| told_ok(l, search.close(id_at(l, -2, "told.closed"))));
        l.settop(-2);
    }
    if let Some(uncrossable) = subtable_at(l, told, c"uncrossable") {
        each(l, uncrossable, |l| {
            let from = id_at(l, -2, "told.uncrossable");
            if l.type_of(-1) == TTABLE {
                let tos = l.gettop();
                each(l, tos, |l| told_ok(l, search.close_link(from, id_at(l, -2, "told.uncrossable"))));
            }
        });
        l.settop(-2);
    }
    if let Some(rooms) = subtable_at(l, told, c"rooms") {
        each(l, rooms, |l| {
            let team = l.tonumber(-1) as i32;
            told_ok(l, search.room(id_at(l, -2, "told.rooms"), team));
        });
        l.settop(-2);
    }
    if let Some(estimates) = subtable_at(l, told, c"estimates") {
        each(l, estimates, |l| {
            let estimate = l.tonumber(-1);
            told_ok(l, search.estimate(id_at(l, -2, "told.estimates"), estimate));
        });
        l.settop(-2);
    }
}

unsafe fn told_ok(l: L, result: Result<(), crate::search::SearchError>) {
    if let Err(e) = result {
        raise_owned(l, e.to_string());
    }
}

/// navsearch.New(mesh, strategy, limits, bot, start, goal, goalPos,
/// maxExpanded[, told[, rules]]) -> a search; told is a table or a Told of
/// the same mesh; goalPos is anything with x and y (and z) to read: a
/// table, or GMod's Vector.
unsafe extern "C-unwind" fn search_new(l: L) -> c_int {
    userdata::check::<Mesh>(l, 1);
    l.checktype(2, TTABLE);
    l.getfield(2, c"Model");
    if l.type_of(-1) != TFUNCTION {
        raise(l, c"the strategy has no Model(limits, bot): it cannot run natively");
    }
    l.pushvalue(3);
    l.pushvalue(4);
    l.call(2, 1);
    let model = l.gettop();
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
    let ud = l.gettop();
    let handle: *mut SearchHandle = userdata::check::<SearchHandle>(l, ud);
    if let Some(penalized) = subtable_at(l, model, c"penalized") {
        each(l, penalized, |l| told_ok(l, (*handle).search.penalize(id_at(l, -2, "model.penalized"))));
        l.settop(-2);
    }
    match l.type_of(9) {
        TTABLE => tell(l, handle, 9),
        TUSERDATA => {
            let known = Arc::clone(&userdata::check::<KnownHandle>(l, 9).0);
            told_ok(l, (*handle).search.know(&known));
        }
        _ => {}
    }
    l.createtable(0, 2);
    if l.type_of(10) == TTABLE {
        for name in [c"traversable", c"crossable", c"room"] {
            l.getfield(10, name);
            if l.type_of(-1) == TFUNCTION {
                l.setfield(-2, name);
            } else {
                l.settop(-2);
            }
        }
    }
    l.setfenv(ud);
    l.pushvalue(ud);
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
    l.pushvalue(function);
    l.pushnumber(area as f64);
    l.call(1, 1);
    let answer = l.tonumber(-1);
    l.settop(-2);
    answer
}

unsafe fn ask(l: L, function: c_int, args: &[u32]) -> bool {
    l.pushvalue(function);
    for &arg in args {
        l.pushnumber(arg as f64);
    }
    l.call(args.len() as c_int, 1);
    let answer = l.toboolean(-1) != 0;
    l.settop(-2);
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
    l.getfield(env, name);
    (l.type_of(-1) == TFUNCTION).then(|| l.gettop())
}

/// search:Step(budget) -> "running", "found" or "failed"
unsafe extern "C-unwind" fn search_step(l: L) -> c_int {
    let budget = check_whole(l, 2);
    search(l);
    l.settop(2);
    l.getfenv(1);
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
    l.getmetatable(1);
    l.pushvalue(2);
    l.rawget(-2);
    if l.type_of(-1) != TNIL {
        return 1;
    }
    let Some(key) = string_at(l, 2) else {
        l.pushnil();
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
            l.pushnil();
            1
        }
    }
}

/// search:Route([lastId]) -> the area ids from the start
unsafe extern "C-unwind" fn search_route(l: L) -> c_int {
    let last = (l.type_of(2) == TNUMBER).then(|| check_whole(l, 2));
    let route = match search(l).route(last) {
        Ok(route) => route,
        Err(e) => raise_owned(l, e.to_string()),
    };
    l.createtable(route.len() as c_int, 0);
    for (i, &id) in route.iter().enumerate() {
        l.pushnumber(id as f64);
        l.rawseti(-2, i as c_int + 1);
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
            l.pushnil();
            1
        }
        Err(e) => raise_owned(l, e.to_string()),
    }
}

/// areaId -> the id of the area it was reached from
unsafe fn push_parents(l: L, search: &RouteSearch) -> c_int {
    let parents = search.parents();
    l.createtable(0, parents.len() as c_int);
    for &(id, parent) in &parents {
        l.pushnumber(parent as f64);
        l.rawseti(-2, id as c_int);
    }
    drop(parents);
    1
}

// Opening -------------------------------------------------------------------

// Walks ----------------------------------------------------------------------

/// The whole number at `index`, or None for any other value.
unsafe fn whole_at(l: L, index: c_int) -> Option<u32> {
    if l.type_of(index) != TNUMBER {
        return None;
    }
    let value = l.tonumber(index);
    ((0.0..=u32::MAX as f64).contains(&value) && value.fract() == 0.0).then_some(value as u32)
}

/// The walks Distances answers, (area id, walk), read from its arguments:
/// the mesh (1), starts (2), told (`told`, a table index, if any).
unsafe fn walks_of(l: L, limit: f64, limits: (f64, f64, bool), told: Option<c_int>) -> Result<Vec<(u32, f64)>, String> {
    let (jump, drop, ladders) = limits;
    let mesh = match userdata::check::<Mesh>(l, 1) {
        Mesh::Sealed(mesh) => Arc::clone(mesh),
        Mesh::Building(_) => return Err("the mesh is not sealed yet".into()),
    };
    let mut starts = Vec::new();
    for i in 1..=l.objlen(2) {
        l.rawgeti(2, i as c_int);
        let id = whole_at(l, -1);
        l.settop(-2);
        let start = id.and_then(|id| mesh.index_of(id));
        starts.push(start.ok_or_else(|| format!("no area {} in the mesh", id.map_or("?".into(), |id| id.to_string())))?);
    }
    let mut refused = vec![false; mesh.graph().links()];
    if let Some(uncrossable) = told.and_then(|told| subtable_at(l, told, c"uncrossable")) {
        each(l, uncrossable, |l| {
            let from = whole_at(l, -2).and_then(|id| mesh.index_of(id));
            if from.is_none() || l.type_of(-1) != TTABLE {
                return;
            }
            let tos = l.gettop();
            each(l, tos, |l| {
                let to = whole_at(l, -2).and_then(|id| mesh.index_of(id));
                if let (Some(from), Some(to)) = (from, to) {
                    if l.toboolean(-1) != 0 {
                        if let Some(link) = mesh.link_between(from, to) {
                            refused[link] = true;
                        }
                    }
                }
            });
        });
        l.settop(-2);
    }
    // a ladder is a way only for a walker whose limits say ladders
    let crossable = |link: usize| !refused[link] && (ladders || !mesh.ladder(link));
    let walks = crate::walks::distances(&mesh, &starts, limit, |rise| rise < jump && rise >= -drop, crossable);
    Ok(walks.iter().enumerate().filter_map(|(area, walk)| walk.map(|walk| (mesh.id(area as u32), walk))).collect())
}

/// navsearch.Distances(mesh, starts, limit, limits[, told]) -> area id ->
/// the cheapest walk to it from the nearest start
unsafe extern "C-unwind" fn distances(l: L) -> c_int {
    l.checktype(2, TTABLE);
    let limit = l.checknumber(3);
    l.checktype(4, TTABLE);
    let jump = field_number(l, 4, c"jumpHeight").unwrap_or_else(|| raise(l, c"limits need a number jumpHeight"));
    let drop = field_number(l, 4, c"deathDropHeight").unwrap_or_else(|| raise(l, c"limits need a number deathDropHeight"));
    let told = (l.type_of(5) == TTABLE).then_some(5);
    let ladders = field_truthy(l, 4, c"ladders");
    let walks = match walks_of(l, limit, (jump, drop, ladders), told) {
        Ok(walks) => walks,
        Err(message) => raise_owned(l, message),
    };
    l.createtable(0, walks.len() as c_int);
    for &(id, walk) in &walks {
        l.pushnumber(walk);
        l.rawseti(-2, id as c_int);
    }
    1
}

// The engine's path search: Told and Calculator ------------------------------

unsafe fn calculator_ok<T>(l: L, result: Result<T, crate::calculator::CalculatorError>) -> T {
    match result {
        Ok(value) => value,
        Err(e) => raise_owned(l, e.to_string()),
    }
}

/// navsearch.Told(mesh, told) -> what a team's computations know, a copy of
/// told's closed areas, uncrossable links and spawn rooms (only the entries
/// whose value holds), refusing an area or link the mesh lacks.
unsafe extern "C-unwind" fn told_new(l: L) -> c_int {
    let mut known = Known::new(sealed(l, 1));
    if l.type_of(2) == TTABLE {
        if let Some(closed) = subtable_at(l, 2, c"closed") {
            each(l, closed, |l| {
                if l.toboolean(-1) != 0 {
                    calculator_ok(l, known.close(id_at(l, -2, "told.closed")));
                }
            });
            l.settop(-2);
        }
        if let Some(uncrossable) = subtable_at(l, 2, c"uncrossable") {
            each(l, uncrossable, |l| {
                let from = id_at(l, -2, "told.uncrossable");
                if l.type_of(-1) == TTABLE {
                    let tos = l.gettop();
                    each(l, tos, |l| {
                        if l.toboolean(-1) != 0 {
                            calculator_ok(l, known.close_link(from, id_at(l, -2, "told.uncrossable")));
                        }
                    });
                }
            });
            l.settop(-2);
        }
        if let Some(rooms) = subtable_at(l, 2, c"rooms") {
            each(l, rooms, |l| {
                let team = l.tonumber(-1) as i32;
                calculator_ok(l, known.room(id_at(l, -2, "told.rooms"), team));
            });
            l.settop(-2);
        }
    }
    userdata::push(l, KnownHandle(Arc::new(known)));
    1
}

/// object:name([the value at arg]) -> its number.
unsafe fn ask_method(l: L, object: c_int, name: &CStr, arg: Option<c_int>) -> f64 {
    l.getfield(object, name);
    l.pushvalue(object);
    let nargs = match arg {
        Some(arg) => {
            l.pushvalue(arg);
            2
        }
        None => 1,
    };
    l.call(nargs, 1);
    let value = l.tonumber(-1);
    l.settop(-2);
    value
}

/// An engine area's id, by asking it.
unsafe fn area_id(l: L, area: c_int) -> u32 {
    let id = ask_method(l, area, c"GetID", None);
    if !(0.0..=u32::MAX as f64).contains(&id) || id.fract() != 0.0 {
        raise_owned(l, format!("an area's GetID gave {id}, not a whole number"));
    }
    id as u32
}

/// The calculator's cost function (upvalue 1 the calculator): (area,
/// fromArea, ladder, elevator, length, optional hull-fit verdict) -> cost,
/// as Path:Compute calls it.
unsafe extern "C-unwind" fn calculate(l: L) -> c_int {
    l.settop(6);
    if l.type_of(2) == TNIL {
        return number(l, 0.0);
    }
    let (from, to) = (area_id(l, 2), area_id(l, 1));
    let step = if l.type_of(3) != TNIL {
        Move::Ladder { length: ask_method(l, 3, c"GetLength", None) }
    } else {
        Move::Floor { length: l.tonumber(5) }
    };
    let so_far = ask_method(l, 2, c"GetCostSoFar", None);
    let fits = l.type_of(6) == TNIL || l.toboolean(6) != 0;
    let calculator = &userdata::check::<CalculatorHandle>(l, foundation::lua::GLOBALSINDEX - 1).0;
    let cost = calculator_ok(l, calculator.price(from, to, so_far, step, fits));
    number(l, cost)
}

/// navsearch.Calculator(known, strategy, limits, bot) -> the cost function
/// Path:Compute takes, pricing by strategy.Model(limits, bot) over a Told.
unsafe extern "C-unwind" fn calculator_new(l: L) -> c_int {
    let known = Arc::clone(&userdata::check::<KnownHandle>(l, 1).0);
    l.checktype(2, TTABLE);
    l.getfield(2, c"Model");
    if l.type_of(-1) != TFUNCTION {
        raise(l, c"the strategy has no Model(limits, bot): it cannot run natively");
    }
    l.pushvalue(3);
    l.pushvalue(4);
    l.call(2, 1);
    let model = l.gettop();
    let mut calculator = Calculator::new(known, walker_from(l, model));
    if let Some(penalized) = subtable_at(l, model, c"penalized") {
        each(l, penalized, |l| calculator_ok(l, calculator.penalize(id_at(l, -2, "model.penalized"))));
        l.settop(-2);
    }
    userdata::push(l, CalculatorHandle(calculator));
    l.pushcclosure(calculate, 1);
    1
}

/// Pushes the module's table: navsearch's contract (Mesh, New, Distances)
/// and Walker, a single model's pricing for the tests.
unsafe fn module(l: L) {
    l.createtable(0, 4);
    set_function(l, c"Mesh", mesh_new);
    set_function(l, c"New", search_new);
    set_function(l, c"Distances", distances);
    set_function(l, c"Told", told_new);
    set_function(l, c"Calculator", calculator_new);
    set_function(l, c"Walker", walker_new);
    l.pushnumber(crate::walker::NO_ROOM as f64);
    l.setfield(-2, c"NO_ROOM");
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
    l.createtable(0, 2);
    l.createtable(0, 2);
    module(l);
    l.setfield(-2, c"navsearch");
    crate::path_bind::push_path(l);
    l.setfield(-2, c"path");
    l.setfield(-2, c"wetsands");
    // the parts WS.require loads by name, for package.loaded
    l.createtable(0, crate::path_bind::PARTS.len() as c_int);
    for (i, name) in crate::path_bind::PARTS.iter().enumerate() {
        crate::path_bind::push_part(l, i);
        l.setfield(-2, name);
    }
    l.setfield(-2, c"preload");
    1
}
