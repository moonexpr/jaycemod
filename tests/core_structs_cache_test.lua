-- foundation.core.structs.cache: the base of the caches, and its own policy:
-- bounded, the first in the first out.
local T = dofile("tests/harness.lua")
local Cache = T.require("foundation.core.structs.cache")
local Class = T.require("foundation.core.meta.class")

-- A release that writes down what it was handed, "key=value:reason".
local function Released()
	local log = {}
	return log, function(key, value, reason) log[#log + 1] = key .. "=" .. tostring(value) .. ":" .. reason end
end

local function Joined(list) return table.concat(list, " ") end

T.test("a cache keeps values by key, the newest first", function()
	local cache = Cache.New({})
	T.eq(cache:Get("a"), nil, "a miss")
	cache:Put("a", 1)
	cache:Put("b", 2)
	T.eq(cache:Get("a"), 1, "a hit")
	T.eq(cache:Size(), 2, "two")
	T.eq(Joined(cache:Keys()), "b a", "the newest first")
end)

T.test("past its capacity the oldest entry is evicted and released", function()
	local log, release = Released()
	local cache = Cache.New({
		capacity = 2,
		release = release,
	})
	cache:Put("a", 1)
	cache:Put("b", 2)
	cache:Get("a")
	cache:Put("c", 3)
	T.eq(Joined(log), "a=1:" .. Cache.EVICTED, "the first in, read or not")
	T.eq(Joined(cache:Keys()), "c b", "the rest")
	T.eq(cache:Size(), 2, "at capacity")
end)

T.test("a value is released once, whichever way it leaves", function()
	local log, release = Released()
	local cache = Cache.New({ release = release })
	cache:Put("a", 1)
	cache:Put("a", 2)
	cache:Put("a", 2)
	cache:Put("b", 3)
	cache:Remove("b")
	cache:Remove("b")
	cache:Put("c", 4)
	cache:Clear()
	T.eq(Joined(log), Joined({
		"a=1:" .. Cache.REPLACED,
		"b=3:" .. Cache.REMOVED,
		"c=4:" .. Cache.CLEARED,
		"a=2:" .. Cache.CLEARED,
	}), "replaced, removed, cleared; not for the same value put again")
	T.eq(cache:Size(), 0, "empty")
end)

T.test("Take hands the value to the caller, unreleased", function()
	local log, release = Released()
	local cache = Cache.New({ release = release })
	cache:Put("a", 1)
	T.eq(cache:Take("a"), 1, "taken")
	T.eq(cache:Take("a"), nil, "gone")
	T.eq(#log, 0, "the caller owns it now")
end)

T.test("destroying a cache releases what it holds", function()
	local log, release = Released()
	local cache = Cache.New({ release = release })
	cache:Put("a", 1)
	Class.Destroy(cache)
	T.eq(Joined(log), "a=1:" .. Cache.DESTROYED, "released")
	T.eq(pcall(cache.Put, cache, "b", 2), false, "a destroyed cache is not used again")
end)

T.test("a release may use the cache it is called from", function()
	local cache
	cache = Cache.New({
		capacity = 1,
		release = function(key)
			if key == "a" then cache:Put("after a", true) end
		end,
	})
	cache:Put("a", 1)
	cache:Put("b", 2)
	T.eq(Joined(cache:Keys()), "after a", "its entry was gone when it ran, and its put evicted b")
end)

T.test("a cache is indexed, assigned and called like a table", function()
	local log, release = Released()
	local cache = Cache.New({ release = release })
	cache.a = 1
	cache["b"] = 2
	T.eq(cache.a, 1, "read by field")
	T.eq(cache.missing, nil, "a miss")
	cache.b = nil
	T.eq(Joined(log), "b=2:" .. Cache.REMOVED, "assigning nil removes")
	local seen = {}
	for key, value in cache() do seen[#seen + 1] = key .. "=" .. value end
	T.eq(Joined(seen), "a=1", "calling it walks the entries, newest first")
	T.eq(getmetatable(cache).__len(cache), cache:Size(), "__len is Size, for when # honours it")
	T.eq(tostring(cache), "cache: 1", "its size")
	T.eq(tostring(Cache.New({ capacity = 4 })), "cache: 0 of 4", "and its capacity")
end)

T.test("a key named like a method is reached through the methods", function()
	local cache = Cache.New({})
	cache:Put("Get", "a value")
	T.eq(type(cache.Get), "function", "the field is the method")
	T.eq(cache:Get("Get"), "a value", "Get reaches the entry")
	T.eq(Joined(cache:Keys()), "Get", "kept under its key")
end)

T.test("a cache's capacity is a whole number of at least one", function()
	T.eq(pcall(Cache.New, { capacity = 0 }), false, "zero")
	T.eq(pcall(Cache.New, { capacity = 1.5 }), false, "a fraction")
	T.eq(pcall(Cache.New, { release = 1 }), false, "a release that is no function")
end)

T.test("a key is anything but nil, and so is a value", function()
	local cache = Cache.New({})
	T.eq(pcall(cache.Put, cache, nil, 1), false, "nil key")
	T.eq(pcall(cache.Put, cache, "a", nil), false, "nil value: Remove removes")
end)

T.finish()
