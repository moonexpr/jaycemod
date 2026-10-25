-- A memo: a foundation.cache.base of computed values, each kept
-- under the stamp it was computed for (a generation, a map version, a
-- blocker count: anything but nil, compared with ==). Asked again under the
-- same stamp it answers from the cache; under another it computes afresh
-- and releases the stale value (REPLACED). First in, first out past an
-- optional capacity.
--   New(options): options as the cache's
--   memo:Fetch(key, stamp, compute) -> the value, compute(key) called only
--     when the key holds no value for that stamp
-- A value put by hand (Put) holds no stamp, so the next Fetch computes.
-- Core-rule exception: stays Lua. It fills cache.base's Lua hooks and calls
-- the caller's compute; see cache.base.
local Cache = cache.base
local Class = core.class
local error = error
module(...)

local function Unstamp(memo, slot)
	Cache.State(memo).stamps[slot] = nil
end

Memo = Class.Extend(Cache.Cache, {
	kind = "memo",
	Init = function(self) Cache.State(self).stamps = {} end, -- slot -> the stamp its value was computed for
	Rewrite = Unstamp,
	Dropped = Unstamp,
	Fetch = function(self, key, stamp, compute)
		if stamp == nil then error("a memo's stamp is anything but nil", 2) end
		local own = Cache.State(self)
		local slot = own.slotOf[key]
		if slot and own.stamps[slot] == stamp then return self:Get(key) end
		local value = compute(key)
		self:Put(key, value)
		own.stamps[own.slotOf[key]] = stamp
		return value
	end,
})

function New(options)
	return Class.Construct(Memo, options)
end
