-- Caches: values kept by key, in an order, perhaps up to a capacity, each
-- value handed back to its owner exactly once as it leaves. Cache is the
-- base class (foundation.core.class) and, on its own, the simplest
-- policy: the first in is the first out. foundation.cache.lru,
-- .expiring and .memo are its subclasses.
--
-- Entries live in arrays indexed by slot (foundation.list.slots),
-- ordered by a chain (foundation.list.chain), newest at the front;
-- an entry costs no table of its own, and a freed slot is reused. The
-- instance itself holds nothing, so every read and write of it reaches its
-- metamethods.
--
--   New(options) -> a cache; options: capacity (a whole number of at least
--     1, or nil for no bound), release(key, value, reason) (nil when the
--     values hold nothing to give back)
--   cache[key]           the value or nil (a policy may count it as a use);
--                        a key named like a method gives the method, so
--                        cache:Get(key) reaches any key
--   cache[key] = value   puts it; nil removes it (cache:Put, cache:Remove)
--   for key, value in cache() do: the entries newest first; the loop must
--                        not change the cache
--   tostring(cache)      "cache: size of capacity"
--   #cache               its size where # honours __len (userdata; plain
--                        tables under LuaJIT do not): cache:Size() anywhere
--   cache:Peek(key)      the value or nil, never counted as a use
--   cache:Take(key)      the value, out of the cache and unreleased: the
--                        caller owns it now
--   cache:Clear(), cache:Keys() (newest first, a fresh list)
--   Class.Destroy(cache) every value released, and the cache unusable
--
-- Releasing. A value leaves by one of the reasons below and is passed to
-- release once, after its entry is gone, so a release may use the cache.
-- Putting the value a key already holds releases nothing.
--
-- Subclasses (Class.Extend(Cache.Cache, fields): every method among the
-- fields, since assigning to a subclass afterwards is an entry write)
-- fill in the policy, each a no-op here:
--   Touch(slot)     an entry read
--   Rewrite(slot)   an entry's value put again
--   Admitting()     before a new entry is made
--   Admitted(slot)  after it is made, at the front
--   Stale(slot)     whether the entry is past keeping (dropped as EXPIRED)
--   Dropped(slot)   its slot is about to be freed: clear what the subclass
--                   keeps by slot
-- keep their own fields in State(cache) (order: the chain; keys, values: by
-- slot), and may call DropSlot(slot, reason). A subclass's own Destroy runs
-- before this one, while the entries are still held.
-- Core-rule exception: stays Lua. A template whose subclasses fill Lua hooks
-- (reach_memo extends it with core.class), holding Lua values and a release
-- callback each; a native userdata could not be subclassed, and its slots
-- and chain measured under a native call's cost.
local Class = core.class
local Slots = list.slots
local Chain = list.chain
local error, floor, getmetatable, rawget, setmetatable, tostring, type = error, math.floor, getmetatable, rawget, setmetatable, tostring, type
module(...)

EVICTED = "evicted" -- pushed out past the capacity
EXPIRED = "expired" -- the policy found it stale
REPLACED = "replaced" -- another value put under its key
REMOVED = "removed"
CLEARED = "cleared"
DESTROYED = "destroyed"

-- Init runs under Construct, under a module's New: this blames New's caller.
local NEW_CALLER = 4

local state = setmetatable({}, { __mode = "k" })

function State(cache)
	return state[cache]
end

local function Refuse(why, value)
	error("a cache's " .. why .. ", not " .. tostring(value), NEW_CALLER)
end

local function Owned() end

local function Method(cache, key)
	local class = getmetatable(cache)
	while class do
		local method = rawget(class, key)
		if method ~= nil then return method end
		class = getmetatable(class)
	end
	return nil
end

-- The entry out of every structure, its slot freed; then, with a reason,
-- its value released. Returns the value.
local function Drop(cache, own, slot, reason)
	local key, value = own.keys[slot], own.values[slot]
	own.order:Unlink(slot)
	own.slotOf[key], own.keys[slot], own.values[slot] = nil, nil, nil
	cache:Dropped(slot)
	own.slots:Free(slot)
	if reason then own.release(key, value, reason) end
	return value
end

-- The key's live slot, a stale one dropped on the way; or nil.
local function Live(cache, own, key)
	local slot = own.slotOf[key]
	if slot and cache:Stale(slot) then
		Drop(cache, own, slot, EXPIRED)
		return nil
	end
	return slot
end

local function Read(cache, key)
	local own = state[cache]
	local slot = Live(cache, own, key)
	if not slot then return nil end
	cache:Touch(slot)
	return own.values[slot]
end

local function Write(cache, key, value)
	if key == nil then error("a cache keeps no nil key", 3) end
	local own = state[cache]
	local slot = Live(cache, own, key)
	if value == nil then
		if slot then Drop(cache, own, slot, REMOVED) end
		return
	end
	if slot then
		local old = own.values[slot]
		own.values[slot] = value
		cache:Rewrite(slot)
		if old ~= value then own.release(key, old, REPLACED) end
		return
	end
	cache:Admitting()
	slot = own.slots:Alloc()
	own.slotOf[key], own.keys[slot], own.values[slot] = slot, key, value
	own.order:PushFront(slot)
	cache:Admitted(slot)
	local order, capacity = own.order, own.capacity
	while capacity and order:Size() > capacity do Drop(cache, own, order:Back(), EVICTED) end
end

local function Entries(cache)
	local own = state[cache]
	local order, keys, values = own.order, own.keys, own.values
	local slot = order:Front()
	return function()
		if not slot then return nil end
		local key, value = keys[slot], values[slot]
		slot = order:After(slot)
		return key, value
	end
end

local function Length(cache)
	return state[cache].order:Size()
end

-- Every entry dropped first, then each value released, front to back, so
-- a release that puts finds the cache already empty.
local function Empty(cache, reason)
	local own, keys, values, n = state[cache], {}, {}, 0
	for key, value in Entries(cache) do
		n = n + 1
		keys[n], values[n] = key, value
	end
	for i = 1, #keys do Drop(cache, own, own.slotOf[keys[i]], nil) end
	for i = 1, #keys do own.release(keys[i], values[i], reason) end
end

Cache = Class.Extend(nil, {
	kind = "cache",
	__index = function(cache, key)
		local method = Method(cache, key)
		if method ~= nil then return method end
		return Read(cache, key)
	end,
	__newindex = Write,
	__call = Entries,
	__len = Length,
	__tostring = function(cache)
		local own = state[cache]
		local text = cache.kind .. ": " .. own.order:Size()
		if own.capacity then text = text .. " of " .. own.capacity end
		return text
	end,
})

function Cache:Init(options)
	local capacity, release = options.capacity, options.release
	if capacity ~= nil and (type(capacity) ~= "number" or capacity < 1 or floor(capacity) ~= capacity) then
		Refuse("capacity is a whole number of at least 1", capacity)
	end
	if release ~= nil and type(release) ~= "function" then Refuse("release is a function", release) end
	state[self] = {
		capacity = capacity,
		release = release or Owned,
		slots = Slots.New(),
		order = Chain.New(),
		slotOf = {}, -- key -> slot
		keys = {}, -- slot -> key
		values = {}, -- slot -> value
	}
end

function Cache:Touch(slot) end
function Cache:Rewrite(slot) end
function Cache:Admitting() end
function Cache:Admitted(slot) end
function Cache:Stale(slot) return false end
function Cache:Dropped(slot) end

function Cache:DropSlot(slot, reason)
	return Drop(self, state[self], slot, reason)
end

Cache.Get = Read

function Cache:Put(key, value)
	if value == nil then error("a cache keeps no nil value: Remove removes", 2) end
	Write(self, key, value)
end

function Cache:Remove(key)
	Write(self, key, nil)
end

function Cache:Peek(key)
	local own = state[self]
	local slot = Live(self, own, key)
	return slot and own.values[slot]
end

function Cache:Take(key)
	local own = state[self]
	local slot = Live(self, own, key)
	return slot and Drop(self, own, slot, nil)
end

function Cache:Clear()
	Empty(self, CLEARED)
end

Cache.Size = Length

function Cache:Keys()
	local list = {}
	for key in self() do list[#list + 1] = key end
	return list
end

function Cache:Destroy()
	Empty(self, DESTROYED)
	state[self] = nil
end

function New(options)
	return Class.Construct(Cache, options)
end
