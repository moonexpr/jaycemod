//! list.queue, list.ring, list.slots and list.chain, native: the Lua twins'
//! contracts (foundation/list/), values the caller gives kept by slot in
//! the userdata's environment.

use super::slots::{fresh_environment, keep, let_go, Kept, KeptList, Slot, Taken, ValueSlots};
use crate::exchange::{pure, respond};
use crate::lua::{push_str, raise_where, tostring, CFunction, L, TNUMBER};
use crate::module;
use crate::userdata::{self, Native};
use std::collections::VecDeque;
use std::ffi::{c_int, CStr};

unsafe fn number(l: L, n: f64) -> c_int {
    l.pushnumber(n);
    1
}

unsafe fn nothing(l: L) -> c_int {
    l.pushnil();
    1
}

/// A whole number of at least 1 at `index`, or None.
unsafe fn whole_at(l: L, index: c_int) -> Option<u32> {
    if l.type_of(index) != TNUMBER {
        return None;
    }
    let n = l.tonumber(index);
    (n >= 1.0 && n.fract() == 0.0 && n <= u32::MAX as f64).then_some(n as u32)
}

// list.queue -----------------------------------------------------------------

/// A double-ended queue of Lua values, by slot.
#[derive(Default)]
pub struct Queue {
    slots: VecDeque<Slot>,
    values: ValueSlots,
}

impl Queue {
    fn push_back(&mut self) -> Slot {
        let slot = self.values.take();
        self.slots.push_back(slot);
        slot
    }

    fn push_front(&mut self) -> Slot {
        let slot = self.values.take();
        self.slots.push_front(slot);
        slot
    }

    fn given_back(&mut self, slot: Option<Slot>) -> Option<Taken> {
        let slot = slot?;
        self.values.give_back(slot);
        Some(Taken(slot))
    }
}

impl Native for Queue {
    const NAME: &'static CStr = c"foundation.list.queue";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"PushBack", queue_push_back),
        (c"PushFront", queue_push_front),
        (c"PopFront", queue_pop_front),
        (c"PopBack", queue_pop_back),
        (c"Front", queue_front),
        (c"Back", queue_back),
        (c"Size", queue_size),
        (c"Values", queue_values),
    ];
}

/// list.queue.New() -> an empty queue
unsafe extern "C-unwind" fn queue_new(l: L) -> c_int {
    userdata::push(l, Queue::default());
    fresh_environment(l, -1);
    1
}

unsafe extern "C-unwind" fn queue_push_back(l: L) -> c_int {
    l.settop(2);
    let mut q = userdata::check::<Queue>(l, 1);
    let q = &mut *q;
    keep(l, pure(l, || q.push_back()), 2);
    0
}

unsafe extern "C-unwind" fn queue_push_front(l: L) -> c_int {
    l.settop(2);
    let mut q = userdata::check::<Queue>(l, 1);
    let q = &mut *q;
    keep(l, pure(l, || q.push_front()), 2);
    0
}

unsafe extern "C-unwind" fn queue_pop_front(l: L) -> c_int {
    let mut q = userdata::check::<Queue>(l, 1);
    let q = &mut *q;
    respond(l, || {
        let slot = q.slots.pop_front();
        Ok(q.given_back(slot))
    })
}

unsafe extern "C-unwind" fn queue_pop_back(l: L) -> c_int {
    let mut q = userdata::check::<Queue>(l, 1);
    let q = &mut *q;
    respond(l, || {
        let slot = q.slots.pop_back();
        Ok(q.given_back(slot))
    })
}

unsafe extern "C-unwind" fn queue_front(l: L) -> c_int {
    let q = userdata::get::<Queue>(l, 1);
    let q = &*q;
    respond(l, || Ok(q.slots.front().copied().map(Kept)))
}

unsafe extern "C-unwind" fn queue_back(l: L) -> c_int {
    let q = userdata::get::<Queue>(l, 1);
    let q = &*q;
    respond(l, || Ok(q.slots.back().copied().map(Kept)))
}

unsafe extern "C-unwind" fn queue_size(l: L) -> c_int {
    let q = userdata::get::<Queue>(l, 1);
    let q = &*q;
    respond(l, || Ok(q.slots.len()))
}

/// The iterator Values gives: (queue, i) -> i + 1, the value there.
unsafe extern "C-unwind" fn queue_step(l: L) -> c_int {
    let i = l.tonumber(2) as usize;
    let q = userdata::get::<Queue>(l, 1);
    let q = &*q;
    respond(l, || Ok(q.slots.get(i).map(|&slot| (i + 1, Kept(slot)))))
}

/// queue:Values() -> an iterator front to back (i, value)
unsafe extern "C-unwind" fn queue_values(l: L) -> c_int {
    userdata::get::<Queue>(l, 1);
    l.pushcclosure(queue_step, 0);
    l.pushvalue(1);
    l.pushnumber(0.0);
    3
}

// list.ring ------------------------------------------------------------------

/// The last `capacity` Lua values pushed, by slot.
pub struct Ring {
    slots: Vec<Option<Slot>>,
    next: usize,
    size: usize,
    values: ValueSlots,
}

impl Ring {
    /// A slot for the value pushed, and the slot of the oldest it pushed
    /// out, given back.
    fn push(&mut self) -> (Slot, Option<Slot>) {
        let pushed_out = self.slots[self.next].take();
        if let Some(old) = pushed_out {
            self.values.give_back(old);
        }
        let slot = self.values.take();
        self.slots[self.next] = Some(slot);
        self.next = (self.next + 1) % self.slots.len();
        self.size = (self.size + 1).min(self.slots.len());
        (slot, pushed_out)
    }

    fn newest(&self) -> Option<Slot> {
        let capacity = self.slots.len();
        if self.size == 0 {
            return None;
        }
        self.slots[(self.next + capacity - 1) % capacity]
    }

    /// The slots, oldest first.
    fn ordered(&self) -> Vec<Slot> {
        let capacity = self.slots.len();
        let start = if self.size < capacity { 0 } else { self.next };
        (0..self.size).filter_map(|i| self.slots[(start + i) % capacity]).collect()
    }
}

impl Native for Ring {
    const NAME: &'static CStr = c"foundation.list.ring";
    const METHODS: &'static [(&'static CStr, CFunction)] =
        &[(c"Push", ring_push), (c"Size", ring_size), (c"Ordered", ring_ordered), (c"Newest", ring_newest)];
}

/// list.ring.New(capacity) -> an empty ring of capacity
unsafe extern "C-unwind" fn ring_new(l: L) -> c_int {
    let Some(capacity) = whole_at(l, 1) else {
        let given = tostring(l, 1);
        raise_where(l, format!("a ring's capacity is a whole number of at least 1, not {given}"));
    };
    userdata::push(l, Ring { slots: vec![None; capacity as usize], next: 0, size: 0, values: ValueSlots::default() });
    fresh_environment(l, -1);
    1
}

unsafe extern "C-unwind" fn ring_push(l: L) -> c_int {
    l.settop(2);
    let mut ring = userdata::check::<Ring>(l, 1);
    let ring = &mut *ring;
    let (slot, pushed_out) = pure(l, || ring.push());
    if let Some(old) = pushed_out {
        let_go(l, old);
    }
    keep(l, slot, 2);
    0
}

unsafe extern "C-unwind" fn ring_size(l: L) -> c_int {
    let ring = userdata::get::<Ring>(l, 1);
    let ring = &*ring;
    respond(l, || Ok(ring.size))
}

/// ring:Newest() -> the last value pushed, nil for an empty ring
unsafe extern "C-unwind" fn ring_newest(l: L) -> c_int {
    let ring = userdata::get::<Ring>(l, 1);
    let ring = &*ring;
    respond(l, || Ok(ring.newest().map(Kept)))
}

/// ring:Ordered() -> the values, oldest first, a fresh list
unsafe extern "C-unwind" fn ring_ordered(l: L) -> c_int {
    let ring = userdata::get::<Ring>(l, 1);
    let ring = &*ring;
    respond(l, || Ok(KeptList(ring.ordered())))
}

// list.window ----------------------------------------------------------------

pub struct Window {
    span: f64,
    entries: VecDeque<(f64, f64)>,
    sum: f64,
}

impl Native for Window {
    const NAME: &'static CStr = c"foundation.list.window";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Add", window_add),
        (c"Sum", window_sum),
        (c"Count", window_count),
        (c"Size", window_size),
        (c"Clear", window_clear),
    ];
}

impl Window {
    /// Lets go of the entries more than span old at `now`; an empty window starts its sum again at 0.
    fn drop_aged(&mut self, now: f64) {
        while let Some(&(at, value)) = self.entries.front() {
            if now - at > self.span {
                self.sum -= value;
                self.entries.pop_front();
            } else {
                break;
            }
        }
        if self.entries.is_empty() {
            self.sum = 0.0;
        }
    }
}

unsafe extern "C-unwind" fn window_new(l: L) -> c_int {
    let span = if l.type_of(1) == TNUMBER { l.tonumber(1) } else { f64::NAN };
    if !(span > 0.0) {
        let given = tostring(l, 1);
        raise_where(l, format!("a window's span is a number above 0, not {given}"));
    }
    userdata::push(l, Window { span, entries: VecDeque::new(), sum: 0.0 });
    1
}

unsafe extern "C-unwind" fn window_add(l: L) -> c_int {
    let (at, value) = (l.checknumber(2), l.checknumber(3));
    let mut window = userdata::check::<Window>(l, 1);
    if let Some(&(last, _)) = window.entries.back() {
        if at < last {
            let (given, before) = (tostring(l, 2), format!("{last}"));
            raise_where(l, format!("a window's entries come in time order: {given} is before {before}"));
        }
    }
    window.entries.push_back((at, value));
    window.sum += value;
    0
}

unsafe extern "C-unwind" fn window_sum(l: L) -> c_int {
    let now = l.checknumber(2);
    let mut window = userdata::check::<Window>(l, 1);
    window.drop_aged(now);
    number(l, window.sum)
}

unsafe extern "C-unwind" fn window_count(l: L) -> c_int {
    let now = l.checknumber(2);
    let mut window = userdata::check::<Window>(l, 1);
    window.drop_aged(now);
    number(l, window.entries.len() as f64)
}

unsafe extern "C-unwind" fn window_size(l: L) -> c_int {
    number(l, userdata::check::<Window>(l, 1).entries.len() as f64)
}

unsafe extern "C-unwind" fn window_clear(l: L) -> c_int {
    let mut window = userdata::check::<Window>(l, 1);
    window.entries.clear();
    window.sum = 0.0;
    0
}

// list.slots -----------------------------------------------------------------

#[derive(Default)]
pub struct Slots {
    used: Vec<bool>,
    free: Vec<u32>,
    high: u32,
    size: u32,
}

impl Native for Slots {
    const NAME: &'static CStr = c"foundation.list.slots";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"Alloc", slots_alloc),
        (c"Free", slots_free),
        (c"InUse", slots_in_use),
        (c"Size", slots_size),
        (c"High", slots_high),
        (c"Clear", slots_clear),
        (c"__call", slots_alloc),
        (c"__len", slots_size),
        (c"__tostring", slots_tostring),
    ];
}

/// list.slots.New() -> a pool of slots
unsafe extern "C-unwind" fn slots_new(l: L) -> c_int {
    userdata::push(l, Slots::default());
    1
}

unsafe extern "C-unwind" fn slots_alloc(l: L) -> c_int {
    let mut pool = userdata::check::<Slots>(l, 1);
    let slot = match pool.free.pop() {
        Some(slot) => slot,
        None => {
            pool.high += 1;
            pool.high
        }
    };
    if pool.used.len() <= slot as usize {
        pool.used.resize(slot as usize + 1, false);
    }
    pool.used[slot as usize] = true;
    pool.size += 1;
    number(l, slot as f64)
}

unsafe extern "C-unwind" fn slots_free(l: L) -> c_int {
    let mut pool = userdata::check::<Slots>(l, 1);
    let slot = whole_at(l, 2).filter(|&s| pool.used.get(s as usize).copied().unwrap_or(false));
    let Some(slot) = slot else {
        let given = tostring(l, 2);
        raise_where(l, format!("slot {given} is not in use"));
    };
    pool.used[slot as usize] = false;
    pool.free.push(slot);
    pool.size -= 1;
    0
}

unsafe extern "C-unwind" fn slots_in_use(l: L) -> c_int {
    let pool = userdata::check::<Slots>(l, 1);
    let used = whole_at(l, 2).is_some_and(|s| pool.used.get(s as usize).copied().unwrap_or(false));
    l.pushboolean(used as c_int);
    1
}

unsafe extern "C-unwind" fn slots_size(l: L) -> c_int {
    number(l, userdata::check::<Slots>(l, 1).size as f64)
}

unsafe extern "C-unwind" fn slots_high(l: L) -> c_int {
    number(l, userdata::check::<Slots>(l, 1).high as f64)
}

unsafe extern "C-unwind" fn slots_clear(l: L) -> c_int {
    *userdata::check::<Slots>(l, 1) = Slots::default();
    0
}

unsafe extern "C-unwind" fn slots_tostring(l: L) -> c_int {
    let pool = userdata::check::<Slots>(l, 1);
    let text = format!("slots: {} in use of {}", pool.size, pool.high);
    push_str(l, &text);
    1
}

// list.chain -----------------------------------------------------------------

/// Not linked: the next of a slot no chain holds.
const OUT: u32 = u32::MAX;
/// The end of the chain, either way.
const NONE: u32 = 0;

#[derive(Default)]
pub struct Chain {
    prev: Vec<u32>,
    next: Vec<u32>,
    front: u32,
    back: u32,
    size: u32,
}

impl Chain {
    fn linked(&self, slot: u32) -> bool {
        self.next.get(slot as usize).is_some_and(|&n| n != OUT)
    }

    fn room(&mut self, slot: u32) {
        let need = slot as usize + 1;
        if self.next.len() < need {
            self.next.resize(need, OUT);
            self.prev.resize(need, OUT);
        }
    }

    fn link_front(&mut self, slot: u32) {
        let front = self.front;
        self.prev[slot as usize] = NONE;
        self.next[slot as usize] = front;
        if front == NONE {
            self.back = slot;
        } else {
            self.prev[front as usize] = slot;
        }
        self.front = slot;
        self.size += 1;
    }

    fn detach(&mut self, slot: u32) {
        let (before, after) = (self.prev[slot as usize], self.next[slot as usize]);
        if before == NONE {
            self.front = after;
        } else {
            self.next[before as usize] = after;
        }
        if after == NONE {
            self.back = before;
        } else {
            self.prev[after as usize] = before;
        }
        self.prev[slot as usize] = OUT;
        self.next[slot as usize] = OUT;
        self.size -= 1;
    }

    fn ordered(&self) -> Vec<u32> {
        let mut list = Vec::with_capacity(self.size as usize);
        let mut slot = self.front;
        while slot != NONE {
            list.push(slot);
            slot = self.next[slot as usize];
        }
        list
    }
}

impl Native for Chain {
    const NAME: &'static CStr = c"foundation.list.chain";
    const METHODS: &'static [(&'static CStr, CFunction)] = &[
        (c"PushFront", chain_push_front),
        (c"PushBack", chain_push_back),
        (c"Unlink", chain_unlink),
        (c"MoveFront", chain_move_front),
        (c"Front", chain_front),
        (c"Back", chain_back),
        (c"After", chain_after),
        (c"Before", chain_before),
        (c"Has", chain_has),
        (c"Ordered", chain_ordered),
        (c"Size", chain_size),
        (c"Clear", chain_clear),
        (c"__call", chain_walk),
        (c"__len", chain_size),
        (c"__tostring", chain_tostring),
    ];
}

/// list.chain.New() -> an empty chain
unsafe extern "C-unwind" fn chain_new(l: L) -> c_int {
    userdata::push(l, Chain::default());
    1
}

/// A slot that may join the chain at index 2: a whole number not linked.
unsafe fn outside(l: L, chain: &Chain) -> u32 {
    let Some(slot) = whole_at(l, 2) else {
        let given = tostring(l, 2);
        raise_where(l, format!("a chain's member is a whole number of at least 1: {given}"));
    };
    if chain.linked(slot) {
        raise_where(l, format!("a chain's member is linked once: {slot}"));
    }
    slot
}

/// A slot of the chain at index 2.
unsafe fn inside(l: L, chain: &Chain) -> u32 {
    match whole_at(l, 2).filter(|&s| chain.linked(s)) {
        Some(slot) => slot,
        None => {
            let given = tostring(l, 2);
            raise_where(l, format!("a chain's stranger cannot unlink: {given}"));
        }
    }
}

unsafe extern "C-unwind" fn chain_push_front(l: L) -> c_int {
    let mut chain = userdata::check::<Chain>(l, 1);
    let slot = outside(l, &chain);
    chain.room(slot);
    chain.link_front(slot);
    0
}

unsafe extern "C-unwind" fn chain_push_back(l: L) -> c_int {
    let mut chain = userdata::check::<Chain>(l, 1);
    let slot = outside(l, &chain);
    chain.room(slot);
    let back = chain.back;
    chain.prev[slot as usize] = back;
    chain.next[slot as usize] = NONE;
    if back == NONE {
        chain.front = slot;
    } else {
        chain.next[back as usize] = slot;
    }
    chain.back = slot;
    chain.size += 1;
    0
}

unsafe extern "C-unwind" fn chain_unlink(l: L) -> c_int {
    let mut chain = userdata::check::<Chain>(l, 1);
    let slot = inside(l, &chain);
    chain.detach(slot);
    0
}

unsafe extern "C-unwind" fn chain_move_front(l: L) -> c_int {
    let mut chain = userdata::check::<Chain>(l, 1);
    let slot = inside(l, &chain);
    if chain.front != slot {
        chain.detach(slot);
        chain.link_front(slot);
    }
    0
}

unsafe fn member(l: L, slot: u32) -> c_int {
    if slot == NONE || slot == OUT {
        nothing(l)
    } else {
        number(l, slot as f64)
    }
}

unsafe extern "C-unwind" fn chain_front(l: L) -> c_int {
    member(l, userdata::check::<Chain>(l, 1).front)
}

unsafe extern "C-unwind" fn chain_back(l: L) -> c_int {
    member(l, userdata::check::<Chain>(l, 1).back)
}

unsafe extern "C-unwind" fn chain_after(l: L) -> c_int {
    let chain = userdata::check::<Chain>(l, 1);
    member(l, whole_at(l, 2).and_then(|s| chain.next.get(s as usize).copied()).unwrap_or(NONE))
}

unsafe extern "C-unwind" fn chain_before(l: L) -> c_int {
    let chain = userdata::check::<Chain>(l, 1);
    member(l, whole_at(l, 2).and_then(|s| chain.prev.get(s as usize).copied()).unwrap_or(NONE))
}

unsafe extern "C-unwind" fn chain_has(l: L) -> c_int {
    let chain = userdata::check::<Chain>(l, 1);
    let has = whole_at(l, 2).is_some_and(|s| chain.linked(s));
    l.pushboolean(has as c_int);
    1
}

unsafe fn push_list(l: L, list: &[u32]) {
    l.createtable(list.len() as c_int, 0);
    for (i, &slot) in list.iter().enumerate() {
        l.pushnumber(slot as f64);
        l.rawseti(-2, i as c_int + 1);
    }
}

unsafe extern "C-unwind" fn chain_ordered(l: L) -> c_int {
    let list = userdata::check::<Chain>(l, 1).ordered();
    push_list(l, &list);
    1
}

unsafe extern "C-unwind" fn chain_size(l: L) -> c_int {
    number(l, userdata::check::<Chain>(l, 1).size as f64)
}

unsafe extern "C-unwind" fn chain_clear(l: L) -> c_int {
    *userdata::check::<Chain>(l, 1) = Chain::default();
    0
}

/// `for slot in chain()`: the slots front to back, the walk's place kept
/// in its closure (upvalue 1: the chain; 2: the next slot), so a member
/// unlinked behind the walk leaves it on course, as the Lua twin's does.
unsafe extern "C-unwind" fn chain_walk_step(l: L) -> c_int {
    let up_chain = crate::lua::GLOBALSINDEX - 1;
    let up_slot = crate::lua::GLOBALSINDEX - 2;
    let slot = l.tonumber(up_slot) as u32;
    if slot == NONE {
        return nothing(l);
    }
    let chain = userdata::check::<Chain>(l, up_chain);
    let next = chain.next.get(slot as usize).copied().filter(|&n| n != OUT).unwrap_or(NONE);
    l.pushnumber(next as f64);
    l.replace(up_slot);
    number(l, slot as f64)
}

unsafe extern "C-unwind" fn chain_walk(l: L) -> c_int {
    let front = userdata::check::<Chain>(l, 1).front;
    l.pushvalue(1);
    l.pushnumber(front as f64);
    l.pushcclosure(chain_walk_step, 2);
    1
}

unsafe extern "C-unwind" fn chain_tostring(l: L) -> c_int {
    let list = userdata::check::<Chain>(l, 1).ordered();
    let text = format!("chain: {}", list.iter().map(u32::to_string).collect::<Vec<_>>().join(" "));
    drop(list);
    push_str(l, &text);
    1
}

/// Pushes the queue module table.
unsafe fn push_queue_module(l: L) {
    module::push(l, &[(c"New", queue_new)], None);
}

/// Pushes the ring module table.
unsafe fn push_ring_module(l: L) {
    module::push(l, &[(c"New", ring_new)], None);
}

/// Pushes the slots module table.
unsafe fn push_slots_module(l: L) {
    module::push(l, &[(c"New", slots_new)], None);
}

/// Pushes the chain module table.
unsafe fn push_chain_module(l: L) {
    module::push(l, &[(c"New", chain_new)], None);
}

/// Pushes the window module table.
unsafe fn push_window_module(l: L) {
    module::push(l, &[(c"New", window_new)], None);
}

/// This namespace's native modules, by name: what pushes each one's table.
pub const MODULES: super::Modules = &[
    (c"queue", push_queue_module),
    (c"ring", push_ring_module),
    (c"slots", push_slots_module),
    (c"chain", push_chain_module),
    (c"schedule", super::schedule::push_module),
    (c"select", super::select::push_module),
    (c"window", push_window_module),
    (c"calendar", super::calendar::push_module),
];
