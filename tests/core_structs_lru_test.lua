-- foundation.core.structs.lru: a cache that evicts the least recently used.
local T = dofile("tests/harness.lua")
local Lru = T.require("foundation.core.structs.lru")
local Cache = T.require("foundation.core.structs.cache")
local Class = T.require("foundation.core.meta.class")

local function Joined(list) return table.concat(list, " ") end

T.test("an LRU cache is a cache", function()
	T.eq(Class.IsA(Lru.New({ capacity = 1 }), Cache.Cache), true, "of the base")
end)

T.test("reading or writing an entry makes it the most recent", function()
	local cache = Lru.New({ capacity = 3 })
	cache:Put("a", 1)
	cache:Put("b", 2)
	cache:Put("c", 3)
	cache:Get("a")
	T.eq(Joined(cache:Keys()), "a c b", "read")
	cache:Put("b", 20)
	T.eq(Joined(cache:Keys()), "b a c", "written")
end)

T.test("past capacity the least recently used goes, and is released", function()
	local evicted = {}
	local cache = Lru.New({
		capacity = 2,
		release = function(key, _, reason) evicted[#evicted + 1] = key .. ":" .. reason end,
	})
	cache:Put("a", 1)
	cache:Put("b", 2)
	cache:Get("a")
	cache:Put("c", 3)
	T.eq(Joined(evicted), "b:" .. Cache.EVICTED, "not the one just read")
	T.eq(Joined(cache:Keys()), "c a", "kept")
end)

T.test("Peek reads without making the entry recent", function()
	local cache = Lru.New({ capacity = 2 })
	cache:Put("a", 1)
	cache:Put("b", 2)
	T.eq(cache:Peek("a"), 1, "read")
	T.eq(Joined(cache:Keys()), "b a", "order kept")
end)

T.test("reading an LRU cache by field is a use", function()
	local cache = Lru.New({ capacity = 2 })
	cache.a = 1
	cache.b = 2
	local _ = cache.a
	T.eq(Joined(cache:Keys()), "a b", "a read is a use")
	T.eq(tostring(cache), "lru cache: 2 of 2", "it says what it is")
end)

T.test("an LRU cache is bounded", function()
	T.eq(pcall(Lru.New, {}), false, "no capacity")
end)

T.finish()
