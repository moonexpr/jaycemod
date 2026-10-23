-- foundation.tree.avl: an ordered map on a balanced (AVL) tree.
local T = dofile("tests/harness.lua")
local Tree = tree.avl

local function Keys(tree)
	local keys = {}
	for key in tree:Pairs() do keys[#keys + 1] = key end
	return table.concat(keys, " ")
end

T.test("keys come out in order, each once, with their values", function()
	local tree = Tree.New()
	for _, k in ipairs({ 5, 2, 8, 1, 9, 3 }) do tree:Insert(k, k * 10) end
	tree:Insert(3, "three")
	T.eq(Keys(tree), "1 2 3 5 8 9", "sorted")
	T.eq(tree:Size(), 6, "a key inserted again replaces its value")
	T.eq(tree:Get(3), "three", "the new value")
	T.eq(tree:Get(4), nil, "absent")
	T.eq(tree:Min(), 1, "least")
	T.eq(tree:Max(), 9, "greatest")
end)

T.test("removing keeps the rest in order", function()
	local tree = Tree.New()
	for k = 1, 10 do tree:Insert(k, true) end
	T.eq(tree:Remove(4), true, "removed")
	T.eq(tree:Remove(4), false, "already gone")
	tree:Remove(1)
	tree:Remove(10)
	T.eq(Keys(tree), "2 3 5 6 7 8 9", "the rest")
	T.eq(tree:Size(), 7, "seven")
end)

T.test("floor and ceiling find the nearest keys either side", function()
	local tree = Tree.New()
	for _, k in ipairs({ 10, 20, 30 }) do tree:Insert(k, "v" .. k) end
	T.eq(tree:Floor(25), 20, "greatest at or below")
	T.eq(tree:Ceiling(25), 30, "least at or above")
	T.eq(tree:Floor(20), 20, "exact")
	T.eq(tree:Floor(5), nil, "nothing below")
	T.eq(tree:Ceiling(35), nil, "nothing above")
	local key, value = tree:Ceiling(11)
	T.eq(value, "v20", "with its value")
end)

T.test("a tree orders by the caller's rule", function()
	local tree = Tree.New(function(a, b) return a > b end)
	for _, k in ipairs({ 1, 3, 2 }) do tree:Insert(k, true) end
	T.eq(Keys(tree), "3 2 1", "descending")
end)

T.test("an empty tree", function()
	local tree = Tree.New()
	T.eq(tree:Size(), 0, "size")
	T.eq(tree:Min(), nil, "min")
	T.eq(tree:Remove(1), false, "remove")
	T.eq(Keys(tree), "", "no keys")
end)

T.test("thousands of mixed inserts and removes stay sorted and balanced", function()
	local tree, present = Tree.New(), {}
	local seed = 12345
	local function Random(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	for _ = 1, 5000 do
		local k = Random(500)
		if Random(3) == 1 then
			tree:Remove(k)
			present[k] = nil
		else
			tree:Insert(k, k)
			present[k] = true
		end
	end
	local expected = {}
	for k in pairs(present) do expected[#expected + 1] = k end
	table.sort(expected)
	T.eq(Keys(tree), table.concat(expected, " "), "the same keys, sorted")
	T.eq(tree:Size(), #expected, "the same count")
	T.eq(tree:Height() <= 1.45 * math.log(#expected + 2) / math.log(2), true, "AVL height bound")
end)

T.finish()
