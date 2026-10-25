-- An expiring cache: a foundation.cache.base whose entries last a
-- term from when they were last written, on a clock port (`clock:Now()`,
-- as games.timer.countdown takes). Reading does not renew an entry. Since
-- every write brings its entry to the front, the back is always the oldest,
-- so pruning stops at the first entry still in its term.
--   New(options): options as the cache's, and clock and term (seconds,
--     above 0), both required
--   cache:Prune(): every expired entry dropped and released (EXPIRED);
--     each new entry prunes first, so the expired never pile up
-- Reading it, walking it (cache()) and Keys never meet an expired entry.
-- Core-rule exception: stays Lua. It fills cache.base's Lua hooks, and
-- reach_memo extends it in turn; see cache.base.
local Cache = cache.base
local Class = core.class
local Port = core.port
local error, rawget, tostring, type = error, rawget, tostring, type
module(...)

CLOCK = Port.New("clock", { "Now" })

-- Init runs under Construct, under New: this blames New's caller.
local NEW_CALLER = 4

local Entries = rawget(Cache.Cache, "__call")

local function Stamp(cache, slot)
	local own = Cache.State(cache)
	own.written[slot] = own.clock:Now()
end

local function Stale(cache, slot)
	local own = Cache.State(cache)
	return own.clock:Now() - own.written[slot] > own.term
end

local function Prune(cache)
	local order = Cache.State(cache).order
	local back = order:Back()
	while back and Stale(cache, back) do
		cache:DropSlot(back, Cache.EXPIRED)
		back = order:Back()
	end
end

Expiring = Class.Extend(Cache.Cache, {
	kind = "expiring cache",
	__call = function(cache)
		Prune(cache)
		return Entries(cache)
	end,
	Init = function(self, options)
		local term = options.term
		if type(term) ~= "number" or term <= 0 then
			error("an expiring cache's term is a number of seconds above 0, not " .. tostring(term), NEW_CALLER)
		end
		local own = Cache.State(self)
		own.clock = CLOCK:Check(options.clock)
		own.term = term
		own.written = {} -- slot -> when its value was last put
	end,
	Admitting = Prune,
	Admitted = Stamp,
	Rewrite = function(self, slot)
		Stamp(self, slot)
		Cache.State(self).order:MoveFront(slot)
	end,
	Stale = Stale,
	Dropped = function(self, slot) Cache.State(self).written[slot] = nil end,
	Prune = Prune,
})

function New(options)
	return Class.Construct(Expiring, options)
end
