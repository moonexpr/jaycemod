//! The binding: finds the classes in the running server.dll, clones
//! Action<CLuaNextBot>'s vtable with hooks that call Lua, and links Actions under a
//! bot's CLuaBehaviour. No engine code or shared vtable is written: what changes is
//! one link on a NextBot, and one intention's vtable pointer on a NextSoldier.
//!
//! The engine's frames do not expect a Lua error to pass through them, so each
//! hook is a pcall: a hook that fails is reported and answers as if undefined.

use crate::image::Image;
use crate::layout::*;
use crate::look::{Angles, Kind as SourceKind, Look, Point, Priority, Source, Tuning, View};
use crate::{scenario_monitor, tactical};
use foundation::lua::{
    api, push_str, set_function, string_at, CFunction, GLOBALSINDEX, L, TFUNCTION, TTABLE,
};
use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr::null_mut;

const REGISTRY: c_int = -10000;
const ACTIONS: &CStr = c"nextsoldier.engine.actions";
const NATIVE_KIND: &CStr = c"_native_kind";

extern "system" {
    fn GetModuleHandleA(name: *const c_char) -> *mut c_void;
}

struct Binding {
    lua: L,
    primary: Box<[usize]>,
    query: Box<[usize]>,
    natives: Vec<NativeTables>,
    original_destructor: usize,
    bot_vtable: usize,
    root_vtable: usize,
    intention_vtable: usize,
    entity_list: usize,
    next_id: u32,
    free_ids: Vec<u32>,
    live: HashSet<*mut LuaAction>,
    reasons: HashMap<Vec<u8>, &'static CStr>,
    player_vtable: usize,
    base_intention_vtable: usize,
    base_intention_destructor: usize,
    player_intention: Box<[usize]>,
    intention_update: usize,
    set_eye_angles: usize,
    intention_query_vtable: usize,
    behavior_vtables: (usize, usize),
    soldiers: HashMap<usize, Soldier>,
    event: Option<EventCall>,
}

/// An event from Lua on its way through the engine's OnCommandString, which carries its
/// priorities and pending results: its name, and where its arguments lie on the stack.
struct EventCall {
    name: CString,
    first: c_int,
    last: c_int,
}

/// What engine.Event sends in place of a command; no command is called this.
const EVENT_MARK: &CStr = c"\x01nextsoldier.event";

/// What a player bot has that a plain NextBotPlayer has not: a Behavior, and the
/// shadow of its intention that CLuaNextBotIntention::Update runs it through.
struct Soldier {
    behavior: *mut u64,
    shadow: *mut u64,
    entity: usize,
    head: Option<Head>,
}

/// A soldier's head, once its config is given, on a clock of its own ticks: a player's
/// Upkeep runs only while it lives, and every time in the model is relative.
struct Head {
    look: Look,
    now: f32,
    interval: f32,
}

/// A kind of action implemented in Rust. Its Lua table is only its config; what it
/// overrides of Action<CLuaNextBot> is its own module's. `engine.<name>` makes a config.
pub(crate) struct Kind {
    pub name: &'static CStr,
    /// (slot of the primary vtable, what answers it)
    pub slots: fn() -> Vec<(usize, usize)>,
    /// The action's `state`, from its config at the given index.
    pub init: unsafe fn(L, c_int) -> u64,
    pub constructor: CFunction,
}

const KINDS: &[&Kind] = &[&tactical::KIND, &scenario_monitor::KIND];

struct NativeTables {
    name: &'static CStr,
    primary: Box<[usize]>,
    query: Box<[usize]>,
    init: unsafe fn(L, c_int) -> u64,
}

static mut BINDING: Option<Binding> = None;
#[allow(static_mut_refs)]
unsafe fn binding<'a>() -> &'a mut Binding {
    BINDING
        .as_mut()
        .expect("a hook runs only once the binding is open")
}

/// A name or reason the engine keeps by pointer, each held for good.
fn intern(bytes: &[u8]) -> *const c_char {
    // SAFETY: Lua's one thread, after the binding opened.
    let reasons = unsafe { &mut binding().reasons };
    if let Some(found) = reasons.get(bytes) {
        return found.as_ptr();
    }
    let owned = CString::new(
        bytes
            .iter()
            .copied()
            .filter(|b| *b != 0)
            .collect::<Vec<u8>>(),
    )
    .unwrap_or_default();
    let leaked: &'static CStr = Box::leak(owned.into_boxed_c_str());
    reasons.insert(bytes.to_vec(), leaked);
    leaked.as_ptr()
}

// Lua, from the engine's side ------------------------------------------------------

unsafe fn push_actions(l: L) {
    (api().getfield)(l, REGISTRY, ACTIONS.as_ptr());
}

fn ours(action: *mut Action) -> bool {
    // SAFETY: an action pointer the engine gave us is live for the call.
    !action.is_null()
        && unsafe {
            let (vtable, b) = ((*action).vtable, binding());
            vtable == b.primary.as_ptr() || b.natives.iter().any(|n| vtable == n.primary.as_ptr())
        }
}

/// Pushes the Lua table of an action of ours, nil for any other.
unsafe fn push_table(l: L, action: *mut Action) {
    let api = api();
    if ours(action) {
        push_actions(l);
        (api.rawgeti)(l, -1, (*action.cast::<LuaAction>()).id as c_int * 2);
        (api.remove)(l, -2);
    } else {
        (api.pushnil)(l);
    }
}

unsafe fn push_me(l: L, action: *mut LuaAction) {
    let api = api();
    push_actions(l);
    (api.rawgeti)(l, -1, (*action).id as c_int * 2 + 1);
    (api.remove)(l, -2);
}

/// A new Action of ours over the Lua table at `table`, for the actor at `me`.
unsafe fn new_action(l: L, table: c_int, me: c_int) -> *mut LuaAction {
    let api = api();
    let top = (api.gettop)(l);
    let (table, me) = (absolute(l, table), absolute(l, me));
    let b = binding();
    let id = b.free_ids.pop().unwrap_or_else(|| {
        b.next_id += 1;
        b.next_id
    });
    // a native kind's config: its hooks are that kind's, not its table's
    (api.getfield)(l, table, NATIVE_KIND.as_ptr());
    let kind = string_at(l, -1);
    let native = b.natives.iter().find(|n| kind == Some(n.name.to_bytes()));
    let (vtable, query_vtable, state) = match native {
        Some(n) => (n.primary.as_ptr(), n.query.as_ptr(), (n.init)(l, table)),
        None => (b.primary.as_ptr(), b.query.as_ptr(), 0),
    };
    (api.settop)(l, top);
    push_actions(l);
    (api.pushvalue)(l, table);
    (api.rawseti)(l, -2, id as c_int * 2);
    (api.pushvalue)(l, me);
    (api.rawseti)(l, -2, id as c_int * 2 + 1);
    (api.settop)(l, top);
    let action = Box::into_raw(Box::new(LuaAction {
        base: Action {
            vtable,
            query_vtable,
            behavior: null_mut(),
            parent: null_mut(),
            child: null_mut(),
            buried: null_mut(),
            covering: null_mut(),
            actor: null_mut(),
            event: EventResult {
                kind: CONTINUE,
                action: null_mut(),
                reason: std::ptr::null(),
                priority: 0,
            },
            started: false,
            suspended: false,
        },
        id,
        state,
        ended: false,
    }));
    b.live.insert(action);
    action
}

unsafe fn absolute(l: L, index: c_int) -> c_int {
    if index < 0 && index > REGISTRY {
        (api().gettop)(l) + index + 1
    } else {
        index
    }
}

/// Calls table[name](table, me, args pushed by `args`) protected. On return the
/// stack holds one result above `top`; false when there was no such method or it
/// failed, which is reported.
unsafe fn hook(l: L, action: *mut LuaAction, name: &CStr, args: impl FnOnce(L) -> c_int) -> bool {
    let api = api();
    (api.getfield)(l, GLOBALSINDEX, c"debug".as_ptr());
    (api.getfield)(l, -1, c"traceback".as_ptr());
    (api.remove)(l, -2);
    let handler = (api.gettop)(l);
    push_table(l, action.cast());
    let table = (api.gettop)(l);
    (api.getfield)(l, table, name.as_ptr());
    if (api.type_of)(l, -1) != TFUNCTION {
        return false;
    }
    (api.pushvalue)(l, table);
    push_me(l, action);
    let count = args(l);
    if (api.pcall)(l, count + 2, 1, handler) != 0 {
        (api.getfield)(l, GLOBALSINDEX, c"ErrorNoHalt".as_ptr());
        (api.pushvalue)(l, -2);
        push_str(l, "\n");
        (api.call)(l, 2, 0);
        return false;
    }
    true
}

/// The ActionResult in the table at the top of the stack; its action is new.
unsafe fn decode(l: L, owner: *mut LuaAction) -> EventResult {
    let api = api();
    let at = (api.gettop)(l);
    let mut result = EventResult {
        kind: CONTINUE,
        action: null_mut(),
        reason: std::ptr::null(),
        priority: RESULT_TRY,
    };
    if (api.type_of)(l, at) != TTABLE {
        return result;
    }
    (api.getfield)(l, at, c"type".as_ptr());
    result.kind = (api.tonumber)(l, -1) as i32;
    (api.getfield)(l, at, c"priority".as_ptr());
    let priority = (api.tonumber)(l, -1) as i32;
    if priority != 0 {
        result.priority = priority;
    }
    (api.getfield)(l, at, c"reason".as_ptr());
    if let Some(reason) = string_at(l, -1) {
        result.reason = intern(reason);
    }
    (api.getfield)(l, at, c"action".as_ptr());
    if (api.type_of)(l, -1) == TTABLE {
        push_me(l, owner);
        result.action = new_action(l, -2, -1).cast();
    }
    result
}

fn plain(result: EventResult) -> ActionResult {
    ActionResult {
        kind: result.kind,
        action: result.action,
        reason: result.reason,
    }
}

const CONTINUING: ActionResult = ActionResult {
    kind: CONTINUE,
    action: null_mut(),
    reason: std::ptr::null(),
};

/// A hook that answers an ActionResult, the top of the stack put back after.
unsafe fn action_result(
    this: *mut LuaAction,
    name: &CStr,
    args: impl FnOnce(L) -> c_int,
) -> ActionResult {
    let l = binding().lua;
    let top = (api().gettop)(l);
    let result = if hook(l, this, name, args) {
        plain(decode(l, this))
    } else {
        CONTINUING
    };
    (api().settop)(l, top);
    result
}

unsafe fn event_result(
    this: *mut LuaAction,
    name: &CStr,
    args: impl FnOnce(L) -> c_int,
) -> EventResult {
    let l = binding().lua;
    let top = (api().gettop)(l);
    let none = EventResult {
        kind: CONTINUE,
        action: null_mut(),
        reason: std::ptr::null(),
        priority: RESULT_TRY,
    };
    let result = if hook(l, this, name, args) {
        decode(l, this)
    } else {
        none
    };
    (api().settop)(l, top);
    result
}

// The hooks, in the engine's calling convention ---------------------------------------

unsafe extern "win64" fn destructor(this: *mut LuaAction, flags: u32) -> *mut LuaAction {
    let b = binding();
    let original: unsafe extern "win64" fn(*mut LuaAction, u32) -> *mut LuaAction =
        std::mem::transmute(b.original_destructor);
    original(this, 0);
    let (l, id) = (b.lua, (*this).id);
    let top = (api().gettop)(l);
    push_actions(l);
    (api().pushnil)(l);
    (api().rawseti)(l, -2, id as c_int * 2);
    (api().pushnil)(l);
    (api().rawseti)(l, -2, id as c_int * 2 + 1);
    (api().settop)(l, top);
    let b = binding();
    b.free_ids.push(id);
    b.live.remove(&this);
    if flags & 1 != 0 {
        drop(Box::from_raw(this));
    }
    this
}

unsafe extern "win64" fn get_name(this: *mut LuaAction) -> *const c_char {
    let l = binding().lua;
    let top = (api().gettop)(l);
    push_table(l, this.cast());
    (api().getfield)(l, -1, c"name".as_ptr());
    let name = string_at(l, -1).map_or(c"Action".as_ptr(), intern);
    (api().settop)(l, top);
    name
}

unsafe extern "win64" fn on_start(
    this: *mut LuaAction,
    ret: *mut ActionResult,
    _me: *mut c_void,
    prior: *mut Action,
) -> *mut ActionResult {
    ret.write(action_result(this, c"OnStart", |l| {
        push_table(l, prior);
        1
    }));
    ret
}

unsafe extern "win64" fn update(
    this: *mut LuaAction,
    ret: *mut ActionResult,
    _me: *mut c_void,
    interval: f32,
) -> *mut ActionResult {
    ret.write(action_result(this, c"Update", |l| {
        (api().pushnumber)(l, interval as f64);
        1
    }));
    ret
}

unsafe extern "win64" fn on_end(this: *mut LuaAction, _me: *mut c_void, next: *mut Action) {
    if (*this).ended {
        return;
    }
    let l = binding().lua;
    let top = (api().gettop)(l);
    hook(l, this, c"OnEnd", |l| {
        push_table(l, next);
        1
    });
    (api().settop)(l, top);
}

unsafe extern "win64" fn on_suspend(
    this: *mut LuaAction,
    ret: *mut ActionResult,
    _me: *mut c_void,
    other: *mut Action,
) -> *mut ActionResult {
    ret.write(action_result(this, c"OnSuspend", |l| {
        push_table(l, other);
        1
    }));
    ret
}

unsafe extern "win64" fn on_resume(
    this: *mut LuaAction,
    ret: *mut ActionResult,
    _me: *mut c_void,
    other: *mut Action,
) -> *mut ActionResult {
    ret.write(action_result(this, c"OnResume", |l| {
        push_table(l, other);
        1
    }));
    ret
}

unsafe extern "win64" fn initial_contained(this: *mut LuaAction, _me: *mut c_void) -> *mut Action {
    let l = binding().lua;
    let api = api();
    let top = (api.gettop)(l);
    let mut child = null_mut();
    if hook(l, this, c"InitialContainedAction", |_| 0) && (api.type_of)(l, -1) == TTABLE {
        push_me(l, this);
        child = new_action(l, -2, -1).cast();
    }
    (api.settop)(l, top);
    child
}

unsafe extern "win64" fn on_stuck(
    this: *mut LuaAction,
    ret: *mut EventResult,
    _me: *mut c_void,
) -> *mut EventResult {
    ret.write(event_result(this, c"OnStuck", |_| 0));
    ret
}

unsafe extern "win64" fn on_injured(
    this: *mut LuaAction,
    ret: *mut EventResult,
    _me: *mut c_void,
    _info: *const c_void,
) -> *mut EventResult {
    ret.write(event_result(this, c"OnInjured", |_| 0));
    ret
}

/// IContextualQuery's slot: `this` is 8 into the action.
unsafe extern "win64" fn should_hurry(this: *mut u8, _me: *const c_void) -> i32 {
    let action = this.sub(8).cast::<LuaAction>();
    let l = binding().lua;
    let top = (api().gettop)(l);
    let mut answer = ANSWER_UNDEFINED;
    if hook(l, action, c"ShouldHurry", |_| 0) && (api().type_of)(l, -1) == foundation::lua::TNUMBER
    {
        answer = (api().tonumber)(l, -1) as i32;
    }
    (api().settop)(l, top);
    answer
}

unsafe extern "win64" fn on_command_string(
    this: *mut LuaAction,
    ret: *mut EventResult,
    _me: *mut c_void,
    command: *const c_char,
) -> *mut EventResult {
    if CStr::from_ptr(command) == EVENT_MARK {
        if let Some(call) = binding().event.as_ref() {
            let (first, last) = (call.first, call.last);
            ret.write(event_result(this, &call.name, |l| {
                for at in first..=last {
                    (api().pushvalue)(l, at);
                }
                last - first + 1
            }));
            return ret;
        }
    }
    ret.write(event_result(this, c"OnCommandString", |l| {
        let text = CStr::from_ptr(command).to_bytes();
        (api().pushlstring)(l, text.as_ptr().cast(), text.len());
        1
    }));
    ret
}

/// The answer a hook named `name` gives on the action at IContextualQuery's `this`.
unsafe fn query_answer(this: *mut u8, name: &CStr) -> i32 {
    let action = this.sub(8).cast::<LuaAction>();
    let l = binding().lua;
    let top = (api().gettop)(l);
    let mut answer = ANSWER_UNDEFINED;
    if hook(l, action, name, |_| 0) && (api().type_of)(l, -1) == foundation::lua::TNUMBER {
        answer = (api().tonumber)(l, -1) as i32;
    }
    (api().settop)(l, top);
    answer
}

unsafe extern "win64" fn should_retreat(this: *mut u8, _me: *const c_void) -> i32 {
    query_answer(this, c"ShouldRetreat")
}

// What a native action has of the binding ---------------------------------------------

/// Runs `f` with the action's config table at the top of the stack, then puts the
/// stack back.
pub(crate) unsafe fn with_config<R>(this: *mut LuaAction, f: impl FnOnce(L) -> R) -> R {
    let l = binding().lua;
    let top = (api().gettop)(l);
    push_table(l, this.cast());
    let result = f(l);
    (api().settop)(l, top);
    result
}

/// A new action of the table at the top of the stack, for this action's soldier; nil
/// or any other value makes none.
pub(crate) unsafe fn action_from_top(l: L, this: *mut LuaAction) -> *mut Action {
    let api = api();
    if (api.type_of)(l, -1) != TTABLE {
        return null_mut();
    }
    push_me(l, this);
    new_action(l, -2, -1).cast()
}

/// Calls the function at the top of the stack with `this`'s soldier and `count` more
/// arguments pushed above it by `args`, protected: the engine's frames do not expect a
/// Lua error. One that fails is reported. Its result is left on the stack, or false.
pub(crate) unsafe fn call_with_me(
    l: L,
    this: *mut LuaAction,
    args: impl FnOnce(L) -> c_int,
) -> bool {
    let api = api();
    let function = (api.gettop)(l);
    if (api.iscfunction)(l, function) == 0 && (api.type_of)(l, function) != TFUNCTION {
        return false;
    }
    (api.getfield)(l, GLOBALSINDEX, c"debug".as_ptr());
    (api.getfield)(l, -1, c"traceback".as_ptr());
    (api.remove)(l, -2);
    (api.insert)(l, function);
    push_me(l, this);
    let count = args(l);
    if (api.pcall)(l, count + 1, 1, function) != 0 {
        (api.getfield)(l, GLOBALSINDEX, c"ErrorNoHalt".as_ptr());
        (api.pushvalue)(l, -2);
        push_str(l, "\n");
        (api.call)(l, 2, 0);
        return false;
    }
    true
}

/// As call_with_me, with the config at `config` first: a native C function's arguments.
pub(crate) unsafe fn call_with_config(l: L, this: *mut LuaAction, config: c_int) -> bool {
    let api = api();
    let function = (api.gettop)(l);
    (api.getfield)(l, GLOBALSINDEX, c"debug".as_ptr());
    (api.getfield)(l, -1, c"traceback".as_ptr());
    (api.remove)(l, -2);
    (api.insert)(l, function);
    (api.pushvalue)(l, config);
    push_me(l, this);
    if (api.pcall)(l, 2, 1, function) != 0 {
        (api.getfield)(l, GLOBALSINDEX, c"ErrorNoHalt".as_ptr());
        (api.pushvalue)(l, -2);
        push_str(l, "\n");
        (api.call)(l, 2, 0);
        return false;
    }
    true
}

/// The action the function at the top of the stack makes for this action's soldier.
pub(crate) unsafe fn made_by(l: L, this: *mut LuaAction) -> *mut Action {
    if call_with_me(l, this, |_| 0) {
        action_from_top(l, this)
    } else {
        null_mut()
    }
}

/// What the engine's Behavior answers to the IContextualQuery at `slot`, walking from
/// the innermost action out. `me` is the actor the action was handed.
pub(crate) unsafe fn behavior_answer(this: *mut LuaAction, me: *mut u8, slot: usize) -> i32 {
    let query = (*this).base.behavior.cast::<u8>().add(8);
    let table = *(query as *const *const usize);
    let ask: unsafe extern "win64" fn(*mut u8, *const c_void) -> i32 =
        std::mem::transmute(*table.add(slot));
    ask(query, me.add(INEXTBOT_OFFSET).cast())
}

/// Marks the table at 1 as a config of `kind`.
pub(crate) unsafe fn mark_config(l: L, kind: &CStr) {
    let api = api();
    (api.pushlstring)(l, kind.as_ptr(), kind.to_bytes().len());
    (api.setfield)(l, 1, c"name".as_ptr());
    (api.pushlstring)(l, kind.as_ptr(), kind.to_bytes().len());
    (api.setfield)(l, 1, NATIVE_KIND.as_ptr());
}

/// A new action of the kind and config this one has: a monitor starting over.
pub(crate) unsafe fn same_again(this: *mut LuaAction) -> *mut Action {
    with_config(this, |l| action_from_top(l, this))
}

/// What the binding keeps for names and reasons, which the engine holds by pointer.
pub(crate) fn interned(bytes: &[u8]) -> *const c_char {
    intern(bytes)
}

// What Lua calls -----------------------------------------------------------------------

/// The entity at `index` as the engine holds it: null when empty.
unsafe fn entity_at(l: L, index: c_int) -> (usize, usize) {
    let api = api();
    (api.getfield)(l, index, c"EntIndex".as_ptr());
    (api.pushvalue)(l, index);
    (api.call)(l, 1, 1);
    let entindex = (api.tonumber)(l, -1) as usize;
    (api.settop)(l, -2);
    let info = binding().entity_list + ENTITY_LIST_ENTRIES + entindex * ENTITY_INFO_SIZE;
    (*(info as *const usize), entindex)
}

/// The INextBot at `nextbot`'s intention.
unsafe fn intention_of(nextbot: usize) -> usize {
    let table = *(nextbot as *const *const usize);
    let get: unsafe extern "win64" fn(usize) -> usize =
        std::mem::transmute(*table.add(GET_INTENTION));
    get(nextbot)
}

/// A bot's or a NextSoldier's Behavior, and whether a CLuaBehaviour holds its root.
/// Anything else is a Lua error naming what did not check out.
unsafe fn behavior_of(l: L, index: c_int) -> (*mut u8, bool) {
    let b = binding();
    let (entity, entindex) = entity_at(l, index);
    let vtable = if entity == 0 {
        0
    } else {
        *(entity as *const usize)
    };
    if vtable == b.bot_vtable {
        let intention = intention_of(entity + INEXTBOT_OFFSET);
        if intention == 0 || *(intention as *const usize) != b.intention_vtable {
            foundation::lua::raise_where(
                l,
                format!("entity {entindex}'s intention is not CLuaNextBotIntention"),
            );
        }
        return (*((intention + INTENTION_BEHAVIOR) as *const *mut u8), true);
    }
    if vtable == b.player_vtable {
        let intention = intention_of(entity + PLAYER_INEXTBOT_OFFSET);
        if let Some(soldier) = b.soldiers.get(&intention) {
            return (soldier.behavior.cast(), false);
        }
        foundation::lua::raise_where(
            l,
            format!("player {entindex} was not made with player.CreateNextSoldier"),
        );
    }
    foundation::lua::raise_where(
        l,
        format!("entity {entindex} is not a CLuaNextBot or a NextSoldier"),
    )
}

// A NextSoldier: a player bot's intention, with a Behavior ----------------------------

unsafe extern "win64" fn soldier_first_contained(this: usize) -> *mut u64 {
    binding()
        .soldiers
        .get(&this)
        .map_or(null_mut(), |s| s.behavior)
}

unsafe extern "win64" fn soldier_update(this: usize) {
    let b = binding();
    let Some(soldier) = b.soldiers.get(&this) else {
        return;
    };
    let shadow = soldier.shadow;
    // what INextBot::Update computed for the component, for the shadow it runs on
    let interval = *((this + COMPONENT_INTERVAL) as *const f32);
    *(shadow.cast::<u8>().add(COMPONENT_INTERVAL).cast::<f32>()) = interval;
    let run: unsafe extern "win64" fn(*mut u64) = std::mem::transmute(b.intention_update);
    run(shadow);
}

unsafe fn virtual_at(entity: usize, slot: usize) -> usize {
    *(*(entity as *const *const usize)).add(slot)
}

unsafe fn eye_position(entity: usize) -> Point {
    let get: unsafe extern "win64" fn(usize, *mut Point) -> *mut Point =
        std::mem::transmute(virtual_at(entity, EYE_POSITION));
    let mut at = [0.0; 3];
    get(entity, &mut at);
    at
}

unsafe fn eye_angles(entity: usize) -> Angles {
    let get: unsafe extern "win64" fn(usize) -> *const [f32; 3] =
        std::mem::transmute(virtual_at(entity, EYE_ANGLES));
    let angles = *get(entity);
    Angles {
        pitch: angles[0],
        yaw: angles[1],
    }
}

unsafe fn is_alive(entity: usize) -> bool {
    let get: unsafe extern "win64" fn(usize) -> bool =
        std::mem::transmute(virtual_at(entity, IS_ALIVE));
    get(entity)
}

unsafe fn is_player(entity: usize) -> bool {
    let get: unsafe extern "win64" fn(usize) -> bool =
        std::mem::transmute(virtual_at(entity, IS_PLAYER));
    get(entity)
}

unsafe fn team_of(entity: usize) -> i32 {
    *((entity + ENTITY_TEAM) as *const i32)
}

/// The nearest live player of `me`'s team within range of its eye.
unsafe fn nearest_friend(me: usize, eye: Point, range: f32) -> Option<Point> {
    let list = binding().entity_list + ENTITY_LIST_ENTRIES;
    let team = team_of(me);
    let mut best = None;
    let mut nearest = range;
    for index in 1..=MAX_PLAYERS {
        let other = *((list + index * ENTITY_INFO_SIZE) as *const usize);
        if other == 0
            || other == me
            || !is_player(other)
            || team_of(other) != team
            || !is_alive(other)
        {
            continue;
        }
        let at = eye_position(other);
        let far =
            ((at[0] - eye[0]).powi(2) + (at[1] - eye[1]).powi(2) + (at[2] - eye[2]).powi(2)).sqrt();
        if far < nearest {
            nearest = far;
            best = Some(at);
        }
    }
    best
}

/// INextBot::Upkeep's call on a soldier: its head, with no Lua in between.
unsafe extern "win64" fn soldier_upkeep(this: usize) {
    let b = binding();
    let set_eye_angles = b.set_eye_angles;
    let Some(soldier) = b.soldiers.get_mut(&this) else {
        return;
    };
    let entity = soldier.entity;
    let Some(head) = soldier.head.as_mut() else {
        return;
    };
    if !is_alive(entity) {
        return;
    }
    head.now += head.interval;
    let eye = eye_position(entity);
    let friend = head
        .look
        .friend_range(head.now)
        .and_then(|range| nearest_friend(entity, eye, range));
    let was = eye_angles(entity);
    let turned = head.look.upkeep(
        head.now,
        head.interval,
        View {
            eye,
            head: was,
            friend,
        },
    );
    if turned != was {
        let set: unsafe extern "win64" fn(usize, *const [f32; 3]) =
            std::mem::transmute(set_eye_angles);
        set(entity, &[turned.pitch, turned.yaw, 0.0]);
    }
}

/// The engine's own ~Behavior ends and deletes the actions; then what we allocated.
unsafe fn release_soldier(soldier: Soldier) {
    let table = *(soldier.behavior as *const *const usize);
    let destroy: unsafe extern "win64" fn(*mut u64, u32) -> *mut u64 =
        std::mem::transmute(*table.add(DESTRUCTOR));
    destroy(soldier.behavior, 0);
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        soldier.behavior,
        BEHAVIOR_WORDS,
    )));
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
        soldier.shadow,
        SHADOW_WORDS,
    )));
}

/// The player is being destroyed without EntityRemoved having told us: inside
/// ~INextBot, GetEntity is pure, and InvokeOnEnd reaches it logging. With no actor
/// set, ~Behavior deletes the actions without ending them.
unsafe extern "win64" fn soldier_destructor(this: usize, flags: u32) -> usize {
    let b = binding();
    let original = b.base_intention_destructor;
    if let Some(soldier) = b.soldiers.remove(&this) {
        *(soldier
            .behavior
            .cast::<u8>()
            .add(BEHAVIOR_ME)
            .cast::<usize>()) = 0;
        release_soldier(soldier);
    }
    *(this as *mut usize) = binding().base_intention_vtable;
    let destroy: unsafe extern "win64" fn(usize, u32) -> usize = std::mem::transmute(original);
    destroy(this, flags)
}

/// EntityRemoved: a NextSoldier's actions end while the player is still whole.
unsafe extern "C-unwind" fn entity_removed(l: L) -> c_int {
    let b = binding();
    if b.soldiers.is_empty() {
        return 0;
    }
    let (entity, _) = entity_at(l, 1);
    if entity == 0 || *(entity as *const usize) != b.player_vtable {
        return 0;
    }
    let intention = intention_of(entity + PLAYER_INEXTBOT_OFFSET);
    if let Some(soldier) = b.soldiers.remove(&intention) {
        *(intention as *mut usize) = b.base_intention_vtable;
        release_soldier(soldier);
    }
    0
}

/// player.CreateNextSoldier(botName) -> a bot player whose intention runs the
/// engine's statechart, as a NextBot's does; nil when GMod made no player. Its
/// behaviours go on with nextsoldier.engine.Insert.
unsafe extern "C-unwind" fn create_next_soldier(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    (api.getfield)(l, GLOBALSINDEX, c"player".as_ptr());
    (api.getfield)(l, -1, c"CreateNextBot".as_ptr());
    (api.pushvalue)(l, 1);
    (api.call)(l, 1, 1);
    let player = (api.gettop)(l);
    if (api.type_of)(l, player) != foundation::lua::TUSERDATA {
        (api.pushnil)(l);
        return 1;
    }
    let b = binding();
    let (entity, entindex) = entity_at(l, player);
    if entity == 0 || *(entity as *const usize) != b.player_vtable {
        foundation::lua::raise_where(
            l,
            format!("player.CreateNextBot gave entity {entindex}, not a NextBotPlayer"),
        );
    }
    let nextbot = entity + PLAYER_INEXTBOT_OFFSET;
    let intention = intention_of(nextbot);
    if intention == 0 || *(intention as *const usize) != b.base_intention_vtable {
        foundation::lua::raise_where(
            l,
            format!("player {entindex}'s intention is not a plain IIntention"),
        );
    }
    let behavior = Box::into_raw(vec![0u64; BEHAVIOR_WORDS].into_boxed_slice()).cast::<u64>();
    *behavior = b.behavior_vtables.0 as u64;
    *behavior.add(1) = b.behavior_vtables.1 as u64;
    let shadow = Box::into_raw(vec![0u64; SHADOW_WORDS].into_boxed_slice()).cast::<u64>();
    *shadow = b.intention_vtable as u64;
    *shadow.cast::<u8>().add(COMPONENT_BOT).cast::<usize>() = nextbot;
    *shadow.cast::<u8>().add(INTENTION_QUERY).cast::<usize>() = b.intention_query_vtable;
    *shadow
        .cast::<u8>()
        .add(INTENTION_BEHAVIOR)
        .cast::<*mut u64>() = behavior;
    b.soldiers.insert(
        intention,
        Soldier {
            behavior,
            shadow,
            entity,
            head: None,
        },
    );
    *(intention as *mut usize) = b.player_intention.as_ptr() as usize;
    (api.settop)(l, player);
    1
}

unsafe fn root_of(behavior: *mut u8) -> *mut Action {
    *(behavior.add(BEHAVIOR_ACTION) as *const *mut Action)
}

/// engine.Insert(bot, action[, me]): action, a table of hooks, runs from the bot's next
/// update: the engine starts it, and its hooks are given me (by default the bot). On a
/// NextBot it goes under its CLuaBehaviour, from its BehaveStart or later; on a
/// NextSoldier it is the root.
unsafe extern "C-unwind" fn insert(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 3);
    (api.checktype)(l, 2, TTABLE);
    let me = if (api.type_of)(l, 3) == foundation::lua::TNIL {
        1
    } else {
        3
    };
    let (behavior, under_lua) = behavior_of(l, 1);
    let root = root_of(behavior);
    if !under_lua {
        if !root.is_null() {
            foundation::lua::raise_where(l, "the bot already runs an action".into());
        }
        let action = new_action(l, 2, me).cast::<Action>();
        *(behavior.add(BEHAVIOR_ACTION) as *mut *mut Action) = action;
        return 0;
    }
    if root.is_null() || (*root).vtable as usize != binding().root_vtable {
        foundation::lua::raise_where(l, "the bot's root action is not CLuaBehaviour".into());
    }
    // its InvokeOnStart sets its child from InitialContainedAction, over any link
    // made before: BehaveStart, which runs just after, is the first moment that holds
    if !(*root).started {
        foundation::lua::raise_where(
            l,
            "the bot has not started: insert from its BehaveStart or later".into(),
        );
    }
    if !(*root).child.is_null() {
        foundation::lua::raise_where(l, "the bot already runs an action".into());
    }
    let action = new_action(l, 2, me).cast::<Action>();
    (*action).parent = root;
    (*root).child = action;
    0
}

unsafe fn push_frames(l: L, action: *mut Action, depth: f64, frames: c_int, count: &mut c_int) {
    let api = api();
    let mut at = action;
    while !at.is_null() {
        (api.createtable)(l, 0, 5);
        if ours(at) {
            let get: unsafe extern "win64" fn(*mut LuaAction) -> *const c_char = get_name;
            push_str(l, &CStr::from_ptr(get(at.cast())).to_string_lossy());
        } else {
            push_str(l, "CLuaBehaviour");
        }
        (api.setfield)(l, -2, c"name".as_ptr());
        (api.pushnumber)(l, depth);
        (api.setfield)(l, -2, c"depth".as_ptr());
        (api.pushboolean)(l, (*at).started as c_int);
        (api.setfield)(l, -2, c"started".as_ptr());
        (api.pushboolean)(l, (*at).suspended as c_int);
        (api.setfield)(l, -2, c"suspended".as_ptr());
        *count += 1;
        (api.rawseti)(l, frames, *count);
        push_frames(l, (*at).child, depth + 1.0, frames, count);
        at = (*at).buried;
    }
}

/// engine.Stack(bot) -> the actions the engine holds, read from its own objects.
unsafe extern "C-unwind" fn stack(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    let root = root_of(behavior_of(l, 1).0);
    (api.createtable)(l, 0, 0);
    let frames = (api.gettop)(l);
    let mut count = 0;
    push_frames(l, root, 1.0, frames, &mut count);
    1
}

/// engine.ShouldHurry(bot) -> the engine's own Behavior's answer, its walk from
/// the innermost action out.
unsafe extern "C-unwind" fn query_hurry(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 1);
    let behavior = behavior_of(l, 1).0;
    let query = behavior.add(8);
    let table = *(query as *const *const usize);
    let ask: unsafe extern "win64" fn(*mut u8, *const c_void) -> i32 =
        std::mem::transmute(*table.add(SHOULD_HURRY));
    (api.pushnumber)(l, ask(query, std::ptr::null()) as f64);
    1
}

/// engine.Live() -> how many Actions of ours the engine holds.
unsafe extern "C-unwind" fn live(l: L) -> c_int {
    (api().pushnumber)(l, binding().live.len() as f64);
    1
}

/// engine.Command(bot, text): the engine's own OnCommandString on the bot, as `nb_command`.
unsafe extern "C-unwind" fn command(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.checktype)(l, 2, foundation::lua::TSTRING);
    behavior_of(l, 1);
    send_command(l, 1, (api.tolstring)(l, 2, null_mut()));
    0
}

/// Through the INextBot's own OnCommandString, down its actions.
unsafe fn send_command(l: L, bot: c_int, command: *const c_char) {
    let b = binding();
    let (entity, _) = entity_at(l, bot);
    let offset = if *(entity as *const usize) == b.bot_vtable {
        INEXTBOT_OFFSET
    } else {
        PLAYER_INEXTBOT_OFFSET
    };
    let nextbot = entity + offset;
    let table = *(nextbot as *const *const usize);
    let send: unsafe extern "win64" fn(usize, *const c_char) =
        std::mem::transmute(*table.add(RESPONDER_COMMAND_STRING));
    send(nextbot, command);
}

unsafe fn name_at(l: L, index: c_int) -> CString {
    let text = string_at(l, index).unwrap_or_default();
    match CString::new(text) {
        Ok(name) => name,
        Err(_) => foundation::lua::raise_where(l, "a name with a zero byte in it".into()),
    }
}

/// engine.Event(bot, name, ...): name, with these arguments, as the engine's own event: to
/// each action holding a hook of that name, its Try results stored and made at the next
/// update.
unsafe extern "C-unwind" fn event(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 2, foundation::lua::TSTRING);
    behavior_of(l, 1);
    let call = EventCall {
        name: name_at(l, 2),
        first: 3,
        last: (api.gettop)(l),
    };
    let outer = binding().event.replace(call);
    send_command(l, 1, EVENT_MARK.as_ptr());
    binding().event = outer;
    0
}

/// Asks name of `action`, what it contains first, then what it buries: leaves the first
/// answer on the stack's top and says so. nil and ANSWER_UNDEFINED are no answer.
unsafe fn ask(l: L, action: *mut Action, name: &CStr, first: c_int, last: c_int) -> bool {
    let api = api();
    let mut at = action;
    while !at.is_null() {
        if ask(l, (*at).child, name, first, last) {
            return true;
        }
        if ours(at) {
            let top = (api.gettop)(l);
            let hooked = hook(l, at.cast(), name, |l| {
                for place in first..=last {
                    (api.pushvalue)(l, place);
                }
                last - first + 1
            });
            if hooked {
                let kind = (api.type_of)(l, -1);
                let undefined = kind == foundation::lua::TNUMBER
                    && (api.tonumber)(l, -1) as i32 == ANSWER_UNDEFINED;
                if kind != foundation::lua::TNIL && !undefined {
                    return true;
                }
            }
            (api.settop)(l, top);
        }
        at = (*at).buried;
    }
    false
}

/// Runs each action's OnEnd, what it contains first, and marks it as ended.
unsafe fn end_actions(l: L, action: *mut Action) {
    let mut at = action;
    while !at.is_null() {
        end_actions(l, (*at).child);
        if ours(at) && !(*at.cast::<LuaAction>()).ended {
            let top = (api().gettop)(l);
            hook(l, at.cast(), c"OnEnd", |_| 0);
            (api().settop)(l, top);
            (*at.cast::<LuaAction>()).ended = true;
        }
        at = (*at).buried;
    }
}

/// engine.End(bot): its actions' OnEnd now, while the bot is whole. The engine would run
/// them from the bot's destructor, when an OnEnd could no longer use it.
unsafe extern "C-unwind" fn end(l: L) -> c_int {
    let root = root_of(behavior_of(l, 1).0);
    end_actions(l, root);
    0
}

/// engine.Query(bot, name, ...) -> the first answer from the innermost action out, or nil.
unsafe extern "C-unwind" fn query(l: L) -> c_int {
    let api = api();
    (api.checktype)(l, 2, foundation::lua::TSTRING);
    let last = (api.gettop)(l);
    let root = root_of(behavior_of(l, 1).0);
    let name = name_at(l, 2);
    if ask(l, root, &name, 3, last) {
        return 1;
    }
    0
}

/// The soldier the player at `index` is, or a Lua error.
unsafe fn soldier_at<'a>(l: L, index: c_int) -> &'a mut Soldier {
    let (entity, entindex) = entity_at(l, index);
    let intention = if entity != 0 && *(entity as *const usize) == binding().player_vtable {
        intention_of(entity + PLAYER_INEXTBOT_OFFSET)
    } else {
        0
    };
    match binding().soldiers.get_mut(&intention) {
        Some(soldier) => soldier,
        None => foundation::lua::raise_where(l, format!("entity {entindex} is no NextSoldier")),
    }
}

unsafe fn number_field(l: L, table: c_int, name: &CStr) -> f32 {
    let api = api();
    (api.getfield)(l, table, name.as_ptr());
    if (api.type_of)(l, -1) != foundation::lua::TNUMBER {
        foundation::lua::raise_where(l, format!("Look needs {} a number", name.to_string_lossy()));
    }
    let value = (api.tonumber)(l, -1) as f32;
    (api.settop)(l, -2);
    value
}

unsafe fn text_field(l: L, table: c_int, name: &CStr) -> String {
    let api = api();
    (api.getfield)(l, table, name.as_ptr());
    let Some(text) = foundation::lua::string_at(l, -1) else {
        foundation::lua::raise_where(l, format!("Look needs {} a string", name.to_string_lossy()));
    };
    let text = String::from_utf8_lossy(text).into_owned();
    (api.settop)(l, -2);
    text
}

/// One of a config's sources, the table on the stack's top. Anything else is refused,
/// so what the model holds is valid.
unsafe fn read_source(l: L) -> Source {
    let table = (api().gettop)(l);
    let priority = text_field(l, table, c"priority");
    let Some(priority) = Priority::parse(&priority) else {
        foundation::lua::raise_where(l, format!("Look has no priority {priority}"));
    };
    let kind = text_field(l, table, c"kind");
    let kind = match kind.as_str() {
        "BodyFacing" => SourceKind::BodyFacing,
        "Friend" => SourceKind::Friend {
            range: number_field(l, table, c"range"),
            every: number_field(l, table, c"every"),
        },
        "Asked" => SourceKind::Asked,
        other => foundation::lua::raise_where(l, format!("Look has no source kind {other}")),
    };
    Source {
        reason: text_field(l, table, c"reason"),
        priority,
        seconds: number_field(l, table, c"seconds"),
        kind,
    }
}

/// engine.Look(soldier, { settle, steady_rate, turn_rate, interval, sources = { { kind,
/// priority, reason, seconds[, range, every] }, ... } }): from now its head is Rust's.
/// Lua configures it here, once, and is asked nothing after.
unsafe extern "C-unwind" fn look_config(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.checktype)(l, 2, TTABLE);
    let tuning = Tuning {
        settle: number_field(l, 2, c"settle"),
        steady_rate: number_field(l, 2, c"steady_rate"),
        turn_rate: number_field(l, 2, c"turn_rate"),
    };
    let interval = number_field(l, 2, c"interval");
    (api.getfield)(l, 2, c"sources".as_ptr());
    (api.checktype)(l, 3, TTABLE);
    let mut sources = Vec::new();
    loop {
        (api.rawgeti)(l, 3, sources.len() as c_int + 1);
        if (api.type_of)(l, -1) != TTABLE {
            break;
        }
        sources.push(read_source(l));
        (api.settop)(l, 3);
    }
    soldier_at(l, 1).head = Some(Head {
        look: Look::new(sources, tuning),
        now: 0.0,
        interval,
    });
    0
}

unsafe fn head_at<'a>(l: L, index: c_int) -> &'a mut Head {
    match soldier_at(l, index).head.as_mut() {
        Some(head) => head,
        None => foundation::lua::raise_where(l, "this soldier's head has no config".into()),
    }
}

/// engine.LookWatch(soldier, on): whether its head logs, for the LOOK_AT layer.
unsafe extern "C-unwind" fn look_watch(l: L) -> c_int {
    let on = (api().toboolean)(l, 2) != 0;
    head_at(l, 1).look.watch(on);
    0
}

/// engine.LookClock(soldier) -> the head's own clock, as far as its ticks have taken it.
unsafe extern "C-unwind" fn look_clock(l: L) -> c_int {
    let now = head_at(l, 1).now;
    (api().pushnumber)(l, now as f64);
    1
}

/// engine.LookLines(soldier, name, now) -> the LOOK_AT layer's lines, in the game's time.
unsafe extern "C-unwind" fn look_lines(l: L) -> c_int {
    let api = api();
    let name = foundation::lua::string_at(l, 2)
        .map(|text| String::from_utf8_lossy(text).into_owned())
        .unwrap_or_default();
    let game_now = (api.tonumber)(l, 3) as f32;
    let head = head_at(l, 1);
    let lines = head.look.lines(&name, game_now - head.now);
    (api.createtable)(l, lines.len() as c_int, 0);
    for (place, line) in lines.iter().enumerate() {
        foundation::lua::push_str(l, line);
        (api.rawseti)(l, -2, place as c_int + 1);
    }
    1
}

const FUNCTIONS: &[(&CStr, CFunction)] = &[
    (c"Look", look_config),
    (c"LookWatch", look_watch),
    (c"LookClock", look_clock),
    (c"LookLines", look_lines),
    (c"Insert", insert),
    (c"Command", command),
    (c"Event", event),
    (c"End", end),
    (c"Query", query),
    (c"Stack", stack),
    (c"ShouldHurry", query_hurry),
    (c"Live", live),
];

// Open and close -------------------------------------------------------------------

unsafe fn module_bytes<'a>() -> Option<(&'a [u8], u64)> {
    let base = GetModuleHandleA(c"server.dll".as_ptr()).cast::<u8>();
    if base.is_null() {
        return None;
    }
    let pe = *base.add(0x3C).cast::<u32>() as usize;
    let size = *base.add(pe + 24 + 56).cast::<u32>() as usize;
    Some((std::slice::from_raw_parts(base, size), base as u64))
}

/// Reads and checks the running binary: the classes, their shapes.
unsafe fn bind(l: L) -> Result<Binding, String> {
    let (bytes, base) = module_bytes().ok_or("server.dll is not loaded")?;
    let image = Image::parse(bytes, Some(base)).map_err(|e| format!("{e:?}"))?;
    let classes = image.classes(&[
        ACTION_CLASS,
        ROOT_CLASS,
        BOT_CLASS,
        INTENTION_CLASS,
        ENTITY_LIST_CLASS,
        PLAYER_CLASS,
        BASE_INTENTION_CLASS,
        BEHAVIOR_CLASS,
    ]);
    let tables = |name: &str| -> Result<&Vec<(usize, usize)>, String> {
        classes
            .get(name)
            .ok_or_else(|| format!("{name} is not in server.dll"))
    };
    let vtable = |name: &str, at: usize| -> Result<usize, String> {
        tables(name)?
            .get(at)
            .map(|t| t.0)
            .ok_or_else(|| format!("{name} has no vtable {at}"))
    };
    let action = tables(ACTION_CLASS)?;
    if action.len() != 2 || action[1].1 != 8 {
        return Err("Action<CLuaNextBot> is not an event responder and a query at +8".into());
    }
    let primary = image.slots(action[0].0);
    let query = image.slots(action[1].0);
    if primary.len() != ACTION_SLOTS || query.len() != QUERY_SLOTS {
        return Err(format!(
            "Action<CLuaNextBot> has {} and {} slots",
            primary.len(),
            query.len()
        ));
    }
    let intention = vtable(INTENTION_CLASS, 0)?;
    let first = image.slots(intention)[FIRST_CONTAINED];
    if image.code(first, RETURNS_BEHAVIOR.len()) != Some(&RETURNS_BEHAVIOR[..]) {
        return Err("CLuaNextBotIntention no longer holds its Behavior at +0x28".into());
    }
    let bots = tables(BOT_CLASS)?;
    if bots.get(1).map(|t| t.1) != Some(INEXTBOT_OFFSET) {
        return Err("CLuaNextBot no longer holds its INextBot at +0x2240".into());
    }
    let list_table = vtable(ENTITY_LIST_CLASS, 0)?;
    let list = image.pointer_to(list_table).ok_or("no CGlobalEntityList")?;

    let players = tables(PLAYER_CLASS)?;
    if !players.iter().any(|t| t.1 == PLAYER_INEXTBOT_OFFSET) {
        return Err("NextBotPlayer no longer holds its INextBot at +0x32c0".into());
    }
    let base_intention = tables(BASE_INTENTION_CLASS)?;
    let base_slots = image.slots(base_intention[0].0);
    if base_slots.len() != INTENTION_SLOTS
        || image.code(base_slots[COMPONENT_GET_BOT], RETURNS_BOT.len()) != Some(&RETURNS_BOT[..])
    {
        return Err("IIntention is not as it was read".into());
    }
    let intention_tables = tables(INTENTION_CLASS)?;
    if intention_tables.get(1).map(|t| t.1) != Some(INTENTION_QUERY) {
        return Err("CLuaNextBotIntention no longer holds its query at +0x20".into());
    }
    let behaviors = tables(BEHAVIOR_CLASS)?;
    if behaviors.len() != 2 || behaviors[1].1 != 8 {
        return Err("Behavior<CLuaNextBot> is not an event responder and a query at +8".into());
    }
    let intention_update = base as usize + image.slots(intention)[INTENTION_UPDATE];

    let absolute_slots =
        |slots: &[usize]| -> Box<[usize]> { slots.iter().map(|rva| base as usize + rva).collect() };
    let mut primary = absolute_slots(&primary);
    let mut query = absolute_slots(&query);
    let original_destructor = primary[DESTRUCTOR];
    // each native kind's: the base Action's, but for what it answers itself
    let natives = KINDS
        .iter()
        .map(|kind| {
            let mut own = primary.clone();
            own[DESTRUCTOR] = destructor as *const () as usize;
            own[GET_NAME] = get_name as *const () as usize;
            for (slot, answer) in (kind.slots)() {
                own[slot] = answer;
            }
            NativeTables {
                name: kind.name,
                primary: own,
                query: query.clone(),
                init: kind.init,
            }
        })
        .collect();
    primary[DESTRUCTOR] = destructor as *const () as usize;
    primary[GET_NAME] = get_name as *const () as usize;
    primary[ON_START] = on_start as *const () as usize;
    primary[UPDATE] = update as *const () as usize;
    primary[ON_END] = on_end as *const () as usize;
    primary[ON_SUSPEND] = on_suspend as *const () as usize;
    primary[ON_RESUME] = on_resume as *const () as usize;
    primary[INITIAL_CONTAINED] = initial_contained as *const () as usize;
    primary[ON_STUCK] = on_stuck as *const () as usize;
    primary[ON_INJURED] = on_injured as *const () as usize;
    primary[ON_COMMAND_STRING] = on_command_string as *const () as usize;
    primary[GET_NAME] = get_name as *const () as usize;
    query[SHOULD_HURRY] = should_hurry as *const () as usize;
    query[SHOULD_RETREAT] = should_retreat as *const () as usize;
    let mut player_intention = absolute_slots(&base_slots);
    let base_intention_destructor = player_intention[DESTRUCTOR];
    player_intention[DESTRUCTOR] = soldier_destructor as *const () as usize;
    player_intention[FIRST_CONTAINED] = soldier_first_contained as *const () as usize;
    player_intention[INTENTION_UPDATE] = soldier_update as *const () as usize;
    player_intention[INTENTION_UPKEEP] = soldier_upkeep as *const () as usize;
    let reach = crate::reach::read(&image)?;
    Ok(Binding {
        lua: l,
        primary,
        query,
        natives,
        original_destructor,
        bot_vtable: base as usize + bots[0].0,
        root_vtable: base as usize + vtable(ROOT_CLASS, 0)?,
        intention_vtable: base as usize + intention,
        entity_list: base as usize + list,
        next_id: 0,
        free_ids: Vec::new(),
        live: HashSet::new(),
        reasons: HashMap::new(),
        player_vtable: base as usize + players[0].0,
        base_intention_vtable: base as usize + base_intention[0].0,
        base_intention_destructor,
        player_intention,
        intention_update,
        set_eye_angles: base as usize + reach.set_eye_angles,
        intention_query_vtable: base as usize + intention_tables[1].0,
        behavior_vtables: (
            base as usize + behaviors[0].0,
            base as usize + behaviors[1].0,
        ),
        soldiers: HashMap::new(),
        event: None,
    })
}

/// GMod's entry point: `nextsoldier.engine`, or a message saying why it did not
/// bind, leaving the engine as it was.
#[no_mangle]
pub unsafe extern "C-unwind" fn gmod13_open(l: L) -> c_int {
    if foundation::lua::open().is_err() {
        return 0;
    }
    let api = api();
    let bound = bind(l);
    (api.createtable)(l, 0, FUNCTIONS.len() as c_int);
    match bound {
        Ok(binding) => {
            BINDING = Some(binding);
            (api.createtable)(l, 0, 0);
            (api.setfield)(l, REGISTRY, ACTIONS.as_ptr());
            for (name, function) in FUNCTIONS {
                set_function(l, name, *function);
            }
            for kind in KINDS {
                set_function(l, kind.name, kind.constructor);
            }
            (api.getfield)(l, GLOBALSINDEX, c"player".as_ptr());
            set_function(l, c"CreateNextSoldier", create_next_soldier);
            (api.settop)(l, -2);
            (api.getfield)(l, GLOBALSINDEX, c"hook".as_ptr());
            (api.getfield)(l, -1, c"Add".as_ptr());
            push_str(l, "EntityRemoved");
            push_str(l, "nextsoldier.engine");
            (api.pushcclosure)(l, entity_removed, 0);
            (api.call)(l, 3, 0);
            (api.settop)(l, -2);
        }
        Err(why) => {
            push_str(l, &why);
            (api.setfield)(l, -2, c"refused".as_ptr());
        }
    }
    foundation::module::provide(l, Some(c"nextsoldier"), c"engine");
    crate::scenarios_bind::push_module(l);
    foundation::module::provide(l, Some(c"wartactics"), c"scenarios");
    0
}

/// The code the engine's Actions point at is about to unload: every NextSoldier's
/// intention goes back as it was, and every Action of ours goes, through the
/// engine's own destructors, each one a tree's top.
#[no_mangle]
#[allow(static_mut_refs)]
pub unsafe extern "C-unwind" fn gmod13_close(_l: L) -> c_int {
    let Some(b) = BINDING.as_mut() else { return 0 };
    let intentions: Vec<usize> = b.soldiers.keys().copied().collect();
    for intention in intentions {
        if let Some(soldier) = b.soldiers.remove(&intention) {
            release_soldier(soldier);
        }
        *(intention as *mut usize) = b.base_intention_vtable;
    }
    loop {
        let top = b.live.iter().copied().find(|&a| {
            let parent = (*a).base.parent;
            !parent.is_null() && !ours(parent) && (*a).base.covering.is_null()
        });
        let Some(top) = top else { break };
        destructor(top, 1);
    }
    BINDING = None;
    0
}
