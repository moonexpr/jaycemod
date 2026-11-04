//! The binding: finds the classes in the running server.dll, clones
//! Action<CLuaNextBot>'s vtable with hooks that call Lua, and links Actions under a
//! bot's CLuaBehaviour. No engine code or shared vtable is written: what changes is
//! one link on a NextBot, and one intention's vtable pointer on a NextSoldier.
//!
//! The engine's frames do not expect a Lua error to pass through them, so each
//! hook is a pcall: a hook that fails is reported and answers as if undefined.

use crate::image::Image;
use crate::layout::*;
use foundation::lua::{
    api, push_str, set_function, string_at, CFunction, GLOBALSINDEX, L, TFUNCTION, TTABLE,
};
use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr::null_mut;

const REGISTRY: c_int = -10000;
const ACTIONS: &CStr = c"nextsoldier.engine.actions";

extern "system" {
    fn GetModuleHandleA(name: *const c_char) -> *mut c_void;
}

struct Binding {
    lua: L,
    primary: Box<[usize]>,
    query: Box<[usize]>,
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
    intention_query_vtable: usize,
    behavior_vtables: (usize, usize),
    soldiers: HashMap<usize, Soldier>,
}

/// What a player bot has that a plain NextBotPlayer has not: a Behavior, and the
/// shadow of its intention that CLuaNextBotIntention::Update runs it through.
struct Soldier {
    behavior: *mut u64,
    shadow: *mut u64,
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
    !action.is_null() && unsafe { (*action).vtable == binding().primary.as_ptr() }
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
    push_actions(l);
    (api.pushvalue)(l, table);
    (api.rawseti)(l, -2, id as c_int * 2);
    (api.pushvalue)(l, me);
    (api.rawseti)(l, -2, id as c_int * 2 + 1);
    (api.settop)(l, top);
    let action = Box::into_raw(Box::new(LuaAction {
        base: Action {
            vtable: b.primary.as_ptr(),
            query_vtable: b.query.as_ptr(),
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
    b.soldiers.insert(intention, Soldier { behavior, shadow });
    *(intention as *mut usize) = b.player_intention.as_ptr() as usize;
    (api.settop)(l, player);
    1
}

unsafe fn root_of(behavior: *mut u8) -> *mut Action {
    *(behavior.add(BEHAVIOR_ACTION) as *const *mut Action)
}

/// engine.Insert(bot, action): action, a table of hooks, runs from the bot's next
/// update: the engine starts it. On a NextBot it goes under its CLuaBehaviour, from
/// its BehaveStart or later; on a NextSoldier it is the root.
unsafe extern "C-unwind" fn insert(l: L) -> c_int {
    let api = api();
    (api.settop)(l, 2);
    (api.checktype)(l, 2, TTABLE);
    let (behavior, under_lua) = behavior_of(l, 1);
    let root = root_of(behavior);
    if !under_lua {
        if !root.is_null() {
            foundation::lua::raise_where(l, "the bot already runs an action".into());
        }
        let action = new_action(l, 2, 1).cast::<Action>();
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
    let action = new_action(l, 2, 1).cast::<Action>();
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

const FUNCTIONS: &[(&CStr, CFunction)] = &[
    (c"Insert", insert),
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
    query[SHOULD_HURRY] = should_hurry as *const () as usize;
    let mut player_intention = absolute_slots(&base_slots);
    let base_intention_destructor = player_intention[DESTRUCTOR];
    player_intention[DESTRUCTOR] = soldier_destructor as *const () as usize;
    player_intention[FIRST_CONTAINED] = soldier_first_contained as *const () as usize;
    player_intention[INTENTION_UPDATE] = soldier_update as *const () as usize;
    Ok(Binding {
        lua: l,
        primary,
        query,
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
        intention_query_vtable: base as usize + intention_tables[1].0,
        behavior_vtables: (
            base as usize + behaviors[0].0,
            base as usize + behaviors[1].0,
        ),
        soldiers: HashMap::new(),
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
