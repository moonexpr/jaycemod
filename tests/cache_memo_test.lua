-- foundation.cache.memo: a cache of computed values, each kept while
-- the stamp it was computed under holds.
local T = dofile("tests/harness.lua")
local Memo = T.require("foundation.cache.memo")
local Cache = T.require("foundation.cache.base")
local Class = T.require("foundation.core.class")

local function Counting()
	local counter = { calls = 0 }
	function counter.compute(key)
		counter.calls = counter.calls + 1
		return key .. counter.calls
	end
	return counter
end

T.test("a memo is a cache", function()
	T.eq(Class.IsA(Memo.New({}), Cache.Cache), true, "of the base")
end)

T.test("a value is computed once while its stamp holds", function()
	local memo, counter = Memo.New({}), Counting()
	T.eq(memo:Fetch("a", 1, counter.compute), "a1", "computed")
	T.eq(memo:Fetch("a", 1, counter.compute), "a1", "kept")
	T.eq(counter.calls, 1, "once")
end)

T.test("a new stamp computes the value again and releases the old one", function()
	local released = {}
	local memo = Memo.New({ release = function(_, value, reason) released[#released + 1] = value .. ":" .. reason end })
	local counter = Counting()
	memo:Fetch("a", 1, counter.compute)
	T.eq(memo:Fetch("a", 2, counter.compute), "a2", "recomputed")
	T.eq(table.concat(released, " "), "a1:" .. Cache.REPLACED, "the stale one released")
end)

T.test("a key's stamp is its own", function()
	local memo, counter = Memo.New({}), Counting()
	memo:Fetch("a", 1, counter.compute)
	memo:Fetch("b", 2, counter.compute)
	T.eq(memo:Fetch("a", 1, counter.compute), "a1", "a under its stamp")
	T.eq(counter.calls, 2, "nothing recomputed")
end)

T.test("a value put without a stamp is computed again on the next fetch", function()
	local memo, counter = Memo.New({}), Counting()
	memo:Put("a", "by hand")
	T.eq(memo:Get("a"), "by hand", "kept")
	T.eq(memo:Fetch("a", 1, counter.compute), "a1", "no stamp to match")
end)

T.test("a memo may be bounded", function()
	local memo, counter = Memo.New({ capacity = 1 }), Counting()
	memo:Fetch("a", 1, counter.compute)
	memo:Fetch("b", 1, counter.compute)
	T.eq(memo:Get("a"), nil, "the older one evicted")
	T.eq(memo:Fetch("a", 1, counter.compute), "a3", "computed again")
end)

T.test("a stamp is anything but nil", function()
	local memo, counter = Memo.New({}), Counting()
	T.eq(pcall(memo.Fetch, memo, "a", nil, counter.compute), false, "nil stamp")
end)

T.finish()
