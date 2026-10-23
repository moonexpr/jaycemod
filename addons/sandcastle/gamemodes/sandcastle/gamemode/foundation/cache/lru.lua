-- A least-recently-used cache: a foundation.cache.base bounded by
-- its capacity, where reading (Get) or writing (Put) an entry brings it to
-- the front, so the one past the capacity is the one longest unused. Peek
-- reads without counting as a use.
--   New(options): options as the cache's, capacity required
local Cache = cache.base
local Class = core.class
local error = error
module(...)

-- Init runs under Construct, under New: this blames New's caller.
local NEW_CALLER = 4

local function Recent(self, slot) Cache.State(self).order:MoveFront(slot) end

Lru = Class.Extend(Cache.Cache, {
	kind = "lru cache",
	Init = function(self, options)
		if options.capacity == nil then error("an LRU cache needs a capacity", NEW_CALLER) end
	end,
	Touch = Recent,
	Rewrite = Recent,
})

function New(options)
	return Class.Construct(Lru, options)
end
