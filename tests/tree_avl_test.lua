-- foundation.tree.avl: an ordered map of number keys on an AVL tree. Every
-- case runs through both twins (the Lua module and native/foundation's,
-- which a server installs over it); the native one runs the same algorithm
-- node for node, so even the heights agree.
local T = dofile("tests/harness.lua")

local IMPLEMENTATIONS = {
	{ "lua", tree.avl },
	{ "native", T.native("foundation").tree.avl },
}

local function Keys(tree)
	local keys = {}
	for key, value in tree:Pairs() do keys[#keys + 1] = key .. "=" .. tostring(value) end
	return table.concat(keys, " ")
end

local CASES = {
	{ "keys come out in order, each once, with their values", function(Avl)
		local tree = Avl()
		for _, k in ipairs({ 5, 2, 8, 1, 9, 3 }) do tree:Insert(k, k * 10) end
		tree:Insert(3, "three")
		local min, minValue = tree:Min()
		local max, maxValue = tree:Max()
		return { Keys(tree), tree:Size(), tree:Get(3), tostring(tree:Get(4)), min, minValue, max, maxValue, tree:Height() }
	end },
	{ "removing keeps the rest in order", function(Avl)
		local tree = Avl()
		for k = 1, 10 do tree:Insert(k, true) end
		local first, again = tree:Remove(4), tree:Remove(4)
		tree:Remove(1)
		tree:Remove(10)
		return { first, again, Keys(tree), tree:Size(), tree:Height() }
	end },
	{ "floor and ceiling find the nearest keys either side", function(Avl)
		local tree = Avl()
		for _, k in ipairs({ 10, 20, 30 }) do tree:Insert(k, "v" .. k) end
		local _, value = tree:Ceiling(11)
		return { tree:Floor(25), tree:Ceiling(25), tree:Floor(20), tostring(tree:Floor(5)), tostring(tree:Ceiling(35)), value, tree:Ceiling(30) }
	end },
	{ "an empty tree", function(Avl)
		local tree = Avl()
		return { tree:Size(), tostring(tree:Min()), tostring(tree:Max()), tree:Remove(1), Keys(tree), tree:Height(), tostring(tree:Get(1)) }
	end },
	{ "any value comes back as it went in, and falls out when removed", function(Avl)
		local tree, entry = Avl(), {}
		tree:Insert(2.5, entry)
		tree:Insert(-1, false)
		local got, falsy = tree:Get(2.5) == entry, tree:Get(-1) == false
		tree:Remove(2.5)
		return { got, falsy, tostring(tree:Get(2.5)), tree:Size() }
	end },
	{ "New is the call", function(Avl)
		local tree = Avl.New()
		tree:Insert(1, "one")
		return { tree:Get(1) }
	end },
	{ "__len is Size", function(Avl)
		local tree = Avl()
		tree:Insert(1, "one")
		tree:Insert(2, "two")
		return { getmetatable(tree).__len(tree), tree:Size() }
	end },
	{ "thousands of mixed inserts and removes stay sorted and balanced", function(Avl)
		local tree, present, x = Avl(), {}, 99
		for _ = 1, 5000 do
			x = (x * 1103515245 + 12345) % 2147483648
			local key = x % 700
			if x % 3 == 0 then
				local removed = tree:Remove(key)
				if removed ~= (present[key] ~= nil) then return { "remove disagreed", key } end
				present[key] = nil
			else
				tree:Insert(key, key * 2)
				present[key] = key * 2
			end
		end
		local expected = {}
		for key in pairs(present) do expected[#expected + 1] = key end
		table.sort(expected)
		local i, ordered = 0, true
		for key, value in tree:Pairs() do
			i = i + 1
			ordered = ordered and key == expected[i] and value == key * 2
		end
		local bound = tree:Height() <= 1.45 * math.log(#expected + 2) / math.log(2)
		return { ordered and i == #expected, tree:Size() == #expected, bound, tree:Height(), tree:Floor(350.5), tree:Ceiling(-1) }
	end },
}

local seen = {}
for _, case in ipairs(CASES) do
	for _, implementation in ipairs(IMPLEMENTATIONS) do
		local name, Avl = implementation[1], implementation[2]
		T.test(name .. ": " .. case[1], function()
			local ok, result = pcall(case[2], Avl)
			T.eq(ok, true, "ran: " .. tostring(result))
			local parts = {}
			for i, v in ipairs(ok and result or {}) do parts[i] = tostring(v) end
			seen[case[1]] = seen[case[1]] or {}
			seen[case[1]][name] = table.concat(parts, " | ")
		end)
	end
end

T.test("the two twins agree on every case, heights included", function()
	for _, case in ipairs(CASES) do T.eq(seen[case[1]].native, seen[case[1]].lua, case[1]) end
end)

T.test("the Lua twin's answers are the expected ones", function()
	T.eq(seen["keys come out in order, each once, with their values"].lua, "1=10 2=20 3=three 5=50 8=80 9=90 | 6 | three | nil | 1 | 10 | 9 | 90 | 3", "order")
	T.eq(seen["removing keeps the rest in order"].lua, "true | false | 2=true 3=true 5=true 6=true 7=true 8=true 9=true | 7 | 4", "remove")
	T.eq(seen["floor and ceiling find the nearest keys either side"].lua, "20 | 30 | 20 | nil | nil | v20 | 30 | v30", "floor, ceiling")
	T.eq(seen["an empty tree"].lua, "0 | nil | nil | false |  | 0 | nil", "empty")
	T.eq(seen["any value comes back as it went in, and falls out when removed"].lua, "true | true | nil | 1", "values")
	T.eq(seen["__len is Size"].lua, "2 | 2", "__len")
	T.eq(seen["thousands of mixed inserts and removes stay sorted and balanced"].lua:match("^true | true | true"), "true | true | true", "sorted, sized, balanced")
end)

T.finish()
