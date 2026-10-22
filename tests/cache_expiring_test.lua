-- foundation.cache.expiring: a cache whose entries last a term from
-- when they were written, on a clock port.
local T = dofile("tests/harness.lua")
local Expiring = T.require("foundation.cache.expiring")
local Cache = T.require("foundation.cache.base")
local Class = T.require("foundation.core.class")

local TERM = 5

local function Clock()
	local clock = { now = 0 }
	function clock:Now() return self.now end
	return clock
end

local function Joined(list) return table.concat(list, " ") end

local function Released()
	local log = {}
	return log, function(key, _, reason) log[#log + 1] = key .. ":" .. reason end
end

T.test("an expiring cache is a cache", function()
	T.eq(Class.IsA(Expiring.New({ clock = Clock(), term = TERM }), Cache.Cache), true, "of the base")
end)

T.test("an entry lasts its term from when it was written", function()
	local clock = Clock()
	local log, release = Released()
	local cache = Expiring.New({
		clock = clock,
		term = TERM,
		release = release,
	})
	cache:Put("a", 1)
	clock.now = TERM
	T.eq(cache:Get("a"), 1, "to the end of its term")
	clock.now = TERM + 1
	T.eq(cache:Get("a"), nil, "and no longer")
	T.eq(Joined(log), "a:" .. Cache.EXPIRED, "released as expired")
	T.eq(cache:Size(), 0, "gone")
end)

T.test("writing an entry again starts its term again; reading does not", function()
	local clock = Clock()
	local cache = Expiring.New({ clock = clock, term = TERM })
	cache:Put("a", 1)
	clock.now = TERM - 1
	cache:Get("a")
	cache:Put("b", 2)
	clock.now = TERM + 1
	T.eq(cache:Get("a"), nil, "read, not renewed")
	cache:Put("b", 3)
	clock.now = 2 * TERM
	T.eq(cache:Get("b"), 3, "written again, renewed")
end)

T.test("Prune drops every expired entry, the oldest first", function()
	local clock = Clock()
	local log, release = Released()
	local cache = Expiring.New({
		clock = clock,
		term = TERM,
		release = release,
	})
	cache:Put("a", 1)
	clock.now = 1
	cache:Put("b", 2)
	clock.now = 2
	cache:Put("c", 3)
	clock.now = TERM + 1.5
	cache:Prune()
	T.eq(Joined(log), "a:" .. Cache.EXPIRED .. " b:" .. Cache.EXPIRED, "both past their term")
	T.eq(Joined(cache:Keys()), "c", "the rest")
end)

T.test("Keys lists only entries still within their term", function()
	local clock = Clock()
	local cache = Expiring.New({ clock = clock, term = TERM })
	cache:Put("a", 1)
	clock.now = TERM
	cache:Put("b", 2)
	clock.now = TERM + 1
	T.eq(Joined(cache:Keys()), "b", "a expired")
end)

T.test("walking an expiring cache passes over the expired", function()
	local clock = Clock()
	local cache = Expiring.New({ clock = clock, term = TERM })
	cache.a = 1
	clock.now = TERM
	cache.b = 2
	clock.now = TERM + 1
	local seen = {}
	for key in cache() do seen[#seen + 1] = key end
	T.eq(Joined(seen), "b", "a expired")
	T.eq(cache.a, nil, "and reads as gone")
end)

T.test("an expiring cache needs a clock and a term", function()
	T.eq(pcall(Expiring.New, { term = TERM }), false, "no clock")
	T.eq(pcall(Expiring.New, { clock = Clock() }), false, "no term")
	T.eq(pcall(Expiring.New, { clock = Clock(), term = -1 }), false, "a negative term")
end)

T.finish()
