-- foundation.list.select: the item of a list a score or an order picks. A
-- lower score is better; ties go to the earlier item, so a pick never
-- depends on how a sort happens to break them.
local T = dofile("tests/harness.lua")
local Select = list.select

local function Identity(x) return x end
local function Less(a, b) return a < b end

T.test("Lowest is the item with the lowest score: it, the score, its place", function()
	local item, score, index = Select.Lowest({ 5, 3, 8, 4 }, Identity)
	T.eq(item, 3, "the item")
	T.eq(score, 3, "the score")
	T.eq(index, 2, "the place")
end)

T.test("a tie in Lowest goes to the earlier item", function()
	local list = { { id = "a", s = 2 }, { id = "b", s = 1 }, { id = "c", s = 1 } }
	T.eq(Select.Lowest(list, function(x) return x.s end).id, "b", "the first of the lowest")
end)

T.test("Highest is the item with the highest score; a tie goes to the earlier item", function()
	local list = { { id = "a", s = 2 }, { id = "b", s = 9 }, { id = "c", s = 9 } }
	local item, score, index = Select.Highest(list, function(x) return x.s end)
	T.eq(item.id, "b", "the first of the highest")
	T.eq(score, 9, "the score")
	T.eq(index, 2, "the place")
end)

T.test("keep leaves items out before they are scored", function()
	local scored = {}
	local item, score, index = Select.Lowest({ 5, 2, 8, 3 }, function(x)
		scored[#scored + 1] = x
		return x
	end, function(x, i) return x ~= 2 and i < 4 end)
	T.eq(item, 5, "the lowest of those kept")
	T.eq(score, 5, "its score")
	T.eq(index, 1, "its place")
	T.eq(#scored, 2, "only the kept were scored")
end)

T.test("no item kept, or an empty list, is nothing", function()
	T.eq(Select.Lowest({}, Identity), nil, "empty")
	T.eq(Select.Lowest({ 1, 2 }, Identity, function() return false end), nil, "none kept")
	T.eq(Select.Highest({}, Identity), nil, "empty, highest")
end)

T.test("Nearest is the item nearest a point: it, the distance, its place", function()
	local list = { { x = 10, y = 0 }, { x = 3, y = 4, z = 0 }, { x = 0, y = 0, z = 9 } }
	local item, distance, index = Select.Nearest(list, { x = 0, y = 0, z = 0 })
	T.eq(item, list[2], "the item")
	T.eq(distance, 5, "the distance, height counted")
	T.eq(index, 2, "the place")
end)

T.test("Nearest reads each item's point through position, and honours keep", function()
	local list = { { pos = { x = 1, y = 0 }, up = false }, { pos = { x = 4, y = 0 }, up = true }, { pos = { x = 6, y = 0 }, up = true } }
	local item, distance = Select.Nearest(list, { x = 0, y = 0 }, function(e) return e.pos end, function(e) return e.up end)
	T.eq(item, list[2], "the nearest kept")
	T.eq(distance, 4, "its distance")
	T.eq(Select.Nearest({}, { x = 0, y = 0 }), nil, "empty")
end)

T.test("Nearest: a tie goes to the earlier item", function()
	local list = { { x = 0, y = 5 }, { x = 5, y = 0 } }
	T.eq(Select.Nearest(list, { x = 0, y = 0 }), list[1], "the first")
end)

T.test("TopK is the first k items in order, ties in list order, the list untouched", function()
	local list = { 5, 3, 8, 1, 9, 2 }
	local top = Select.TopK(list, 3, Less)
	T.eq(#top, 3, "k items")
	T.eq(top[1], 1, "first")
	T.eq(top[2], 2, "second")
	T.eq(top[3], 3, "third")
	T.eq(list[1], 5, "the list as it was")
	T.eq(#list, 6, "the list as long")
end)

T.test("TopK keeps ties in list order", function()
	local list = { { id = 1, s = 2 }, { id = 2, s = 1 }, { id = 3, s = 2 }, { id = 4, s = 1 } }
	local top = Select.TopK(list, 3, function(a, b) return a.s < b.s end)
	T.eq(top[1].id, 2, "the lowest, first of its tie")
	T.eq(top[2].id, 4, "the lowest, second of its tie")
	T.eq(top[3].id, 1, "then the earlier of the next")
end)

T.test("TopK with k beyond the list is the whole list in order; k of 0 is nothing", function()
	local top = Select.TopK({ 3, 1, 2 }, 10, Less)
	T.eq(#top, 3, "all")
	T.eq(top[1] .. top[2] .. top[3], "123", "in order")
	T.eq(#Select.TopK({ 3, 1, 2 }, 0, Less), 0, "none")
	T.eq(pcall(Select.TopK, { 1 }, -1, Less), false, "a negative k")
	T.eq(pcall(Select.TopK, { 1 }, 1.5, Less), false, "a fractional k")
end)

T.test("TopK asks about each item a few times, not about every pair", function()
	local list = {}
	for i = 1, 2000 do list[i] = (i * 7919) % 2003 end
	local calls = 0
	local top = Select.TopK(list, 5, function(a, b)
		calls = calls + 1
		return a < b
	end)
	T.eq(#top, 5, "five")
	T.eq(calls < #list * 4, true, "n log k, not n log n: " .. calls)
	for i = 2, 5 do T.eq(top[i - 1] <= top[i], true, "in order at " .. i) end
end)

T.test("Order is the places of the items in order, ties by place", function()
	local order = Select.Order({ 30, 10, 20, 10 }, Less)
	T.eq(order[1] .. order[2] .. order[3] .. order[4], "2431", "the places")
	T.eq(#Select.Order({}, Less), 0, "empty")
end)

T.test("Ranks is each item's place in the order, from 1", function()
	local ranks = Select.Ranks({ 30, 10, 20, 10 }, Less)
	T.eq(ranks[1] .. ranks[2] .. ranks[3] .. ranks[4], "4132", "the ranks")
end)

T.test("an error in the score or the order reaches the caller", function()
	T.eq(pcall(Select.Lowest, { 1 }, function() error("boom") end), false, "score")
	T.eq(pcall(Select.Order, { 1, 2 }, function() error("boom") end), false, "order")
	T.eq(pcall(Select.TopK, { 1, 2 }, 1, function() error("boom") end), false, "top")
end)

T.finish()
