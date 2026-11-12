//! A NextSoldier's main behaviour: the IIntention a bot player is given in place of its
//! default one, as a CLuaNextBot's runs its CLuaBehaviour. It owns the soldier's Behavior,
//! the main tree, and runs the tree beside it (NextLegs,
//! `main_nextlegs`) after it on each update; its Upkeep turns the head
//! (`crate::body`). `player.CreateNextSoldier` installs it.

use crate::body::look::{Look, View};
use crate::engine::{
    binding, entity_at, eye_angles, eye_position, intention_of, is_alive, new_tree, release_tree,
    teammates, Tree,
};
use crate::layout::*;
use crate::{locomotion, vision};
use foundation::lua::{api, GLOBALSINDEX, L};
use std::ffi::c_int;
use std::ptr::null_mut;

/// What it answers of the player's IIntention, over the base's own table.
pub(crate) fn install(intention: &mut [usize]) {
    intention[DESTRUCTOR] = soldier_destructor as *const () as usize;
    intention[FIRST_CONTAINED] = soldier_first_contained as *const () as usize;
    intention[NEXT_CONTAINED] = soldier_next_contained as *const () as usize;
    intention[INTENTION_UPDATE] = soldier_update as *const () as usize;
    intention[INTENTION_UPKEEP] = soldier_upkeep as *const () as usize;
}

/// What a player bot has that a plain NextBotPlayer has not: a Behavior, and the
/// shadow of its intention that CLuaNextBotIntention::Update runs it through.
pub(crate) struct Soldier {
    pub(crate) behavior: *mut u64,
    pub(crate) shadow: *mut u64,
    pub(crate) entity: usize,
    pub(crate) head: Option<Head>,
    pub(crate) group: Option<Tree>,
    /// Its main tree runs when engine.Update says, not on the engine's own turn.
    pub(crate) paced: bool,
    /// Which way its group pushes it, from its last update.
    pub(crate) push: [f32; 2],
}

/// A soldier's head, once its config is given, on a clock of its own ticks: a player's
/// Upkeep runs only while it lives, and every time in the model is relative.
pub(crate) struct Head {
    pub(crate) look: Look,
    pub(crate) now: f32,
    pub(crate) interval: f32,
}

unsafe extern "win64" fn soldier_first_contained(this: usize) -> *mut u64 {
    binding()
        .soldiers
        .get(&this)
        .map_or(null_mut(), |s| s.behavior)
}

unsafe extern "win64" fn soldier_update(this: usize) {
    let b = binding();
    let Some(soldier) = b.soldiers.get_mut(&this) else {
        return;
    };
    if soldier.group.is_some() {
        let entity = soldier.entity;
        soldier.push = locomotion::separation(
            eye_position(entity),
            &teammates(entity),
            (entity >> 4) as u32,
        );
    }
    let soldier = &binding().soldiers[&this];
    let main = (!soldier.paced).then_some(soldier.shadow);
    let group = soldier.group.as_ref().map(|tree| tree.shadow);
    // what INextBot::Update computed for the component, for the shadow it runs on
    let interval = *((this + COMPONENT_INTERVAL) as *const f32);
    let run: unsafe extern "win64" fn(*mut u64) = std::mem::transmute(b.intention_update);
    for tree in main.into_iter().chain(group) {
        *(tree.cast::<u8>().add(COMPONENT_INTERVAL).cast::<f32>()) = interval;
        run(tree);
    }
}

/// After its main tree, its group's: so an event reaches both.
unsafe extern "win64" fn soldier_next_contained(this: usize, current: *mut u64) -> *mut u64 {
    let Some(soldier) = binding().soldiers.get(&this) else {
        return null_mut();
    };
    match soldier.group.as_ref() {
        Some(tree) if current == soldier.behavior => tree.behavior,
        _ => null_mut(),
    }
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
        .and_then(|range| vision::closest_known(eye, &teammates(entity), range));
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
pub(crate) unsafe fn release_soldier(soldier: Soldier) {
    if let Some(tree) = soldier.group {
        release_tree(tree);
    }
    release_tree(Tree {
        behavior: soldier.behavior,
        shadow: soldier.shadow,
    });
}

/// The player is being destroyed without EntityRemoved having told us: inside
/// ~INextBot, GetEntity is pure, and InvokeOnEnd reaches it logging. With no actor
/// set, ~Behavior deletes the actions without ending them.
unsafe extern "win64" fn soldier_destructor(this: usize, flags: u32) -> usize {
    let b = binding();
    let original = b.base_intention_destructor;
    if let Some(soldier) = b.soldiers.remove(&this) {
        for behavior in std::iter::once(soldier.behavior)
            .chain(soldier.group.as_ref().map(|tree| tree.behavior))
        {
            *(behavior.cast::<u8>().add(BEHAVIOR_ME).cast::<usize>()) = 0;
        }
        release_soldier(soldier);
    }
    *(this as *mut usize) = binding().base_intention_vtable;
    let destroy: unsafe extern "win64" fn(usize, u32) -> usize = std::mem::transmute(original);
    destroy(this, flags)
}

/// player.CreateNextSoldier(botName) -> a bot player whose intention runs the
/// engine's statechart, as a NextBot's does; nil when GMod made no player. Its
/// behaviours go on with nextsoldier.engine.Insert.
pub(crate) unsafe extern "C-unwind" fn create_next_soldier(l: L) -> c_int {
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
    let Tree { behavior, shadow } = new_tree(nextbot);
    b.soldiers.insert(
        intention,
        Soldier {
            behavior,
            shadow,
            entity,
            head: None,
            group: None,
            paced: false,
            push: [0.0, 0.0],
        },
    );
    *(intention as *mut usize) = b.player_intention.as_ptr() as usize;
    (api.settop)(l, player);
    1
}
