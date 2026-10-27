-- foundation.tree.heap: values keyed by numbers, the lowest key first and
-- of equal keys the one pushed first. Every case runs through both twins:
-- the Lua module and native/foundation's, which a server installs over it.
local T = dofile("tests/harness.lua")

local IMPLEMENTATIONS = {
	{ "lua", tree.heap },
	{ "native", T.native("foundation").tree.heap },
}

local function Drain(heap)
	local out = {}
	while heap:Size() > 0 do
		local value, key = heap:Pop()
		out[#out + 1] = tostring(value) .. "@" .. key
	end
	return table.concat(out, " ")
end

local CASES = {
	{ "values come out lowest key first", function(Heap)
		local heap = Heap()
		for _, key in ipairs({ 5, 3, 8, 1, 9, 2, 7 }) do heap:Push(key, "v" .. key) end
		local size = heap:Size()
		local value, key = heap:Peek()
		return { size, value, key, heap:Size(), Drain(heap) }
	end },
	{ "an empty heap pops and peeks nil", function(Heap)
		local heap = Heap()
		return { tostring(heap:Pop()), tostring(heap:Peek()), heap:Size() }
	end },
	{ "equal keys come out in the order pushed", function(Heap)
		local heap = Heap()
		for _, e in ipairs({ { 2, "b1" }, { 1, "a1" }, { 2, "b2" }, { 1, "a2" }, { 2, "b3" }, { 1, "a3" } }) do heap:Push(e[1], e[2]) end
		return { Drain(heap) }
	end },
	{ "pushes and pops interleaved keep the order", function(Heap)
		local heap = Heap()
		heap:Push(4, "d")
		heap:Push(2, "b")
		local first = heap:Pop()
		heap:Push(1, "a")
		heap:Push(3, "c")
		return { first, Drain(heap) }
	end },
	{ "any value comes back as it went in", function(Heap)
		local heap = Heap()
		local entry, fn = { name = "entry" }, function() end
		heap:Push(3, fn)
		heap:Push(1, entry)
		heap:Push(2, false)
		heap:Push(4, 42)
		local a, b, c, d = heap:Pop(), heap:Pop(), heap:Pop(), heap:Pop()
		return { a == entry, b == false, c == fn, d == 42 }
	end },
	{ "clearing empties it, and the order starts again", function(Heap)
		local heap = Heap()
		heap:Push(1, "x")
		heap:Push(1, "y")
		heap:Clear()
		heap:Push(2, "late")
		heap:Push(2, "later")
		return { heap:Size(), Drain(heap) }
	end },
	{ "New is the call", function(Heap)
		local heap = Heap.New()
		heap:Push(1.5, "one")
		return { (heap:Pop()) }
	end },
	{ "__len is Size", function(Heap)
		local heap = Heap()
		heap:Push(2, "b")
		heap:Push(1, "a")
		return { getmetatable(heap).__len(heap), heap:Size() }
	end },
	{ "many keys come out sorted, ties in push order", function(Heap)
		local heap, x, expected = Heap(), 7, {}
		for i = 1, 2000 do
			x = (x * 1103515245 + 12345) % 2147483648
			local key = x % 97 - 48.5
			heap:Push(key, i)
			expected[i] = { key = key, i = i }
		end
		table.sort(expected, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.i < b.i end)
		local ok = true
		for i = 1, #expected do
			local value, key = heap:Pop()
			ok = ok and value == expected[i].i and key == expected[i].key
		end
		return { ok, heap:Size() }
	end },
}

local seen = {}
for _, case in ipairs(CASES) do
	for _, implementation in ipairs(IMPLEMENTATIONS) do
		local name, Heap = implementation[1], implementation[2]
		T.test(name .. ": " .. case[1], function()
			local ok, result = pcall(case[2], Heap)
			T.eq(ok, true, "ran: " .. tostring(result))
			local parts = {}
			for i, v in ipairs(ok and result or {}) do parts[i] = tostring(v) end
			seen[case[1]] = seen[case[1]] or {}
			seen[case[1]][name] = table.concat(parts, " | ")
		end)
	end
end

T.test("the two twins agree on every case", function()
	for _, case in ipairs(CASES) do T.eq(seen[case[1]].native, seen[case[1]].lua, case[1]) end
end)

T.test("the Lua twin's answers are the expected ones", function()
	T.eq(seen["values come out lowest key first"].lua, "7 | v1 | 1 | 7 | v1@1 v2@2 v3@3 v5@5 v7@7 v8@8 v9@9", "order")
	T.eq(seen["an empty heap pops and peeks nil"].lua, "nil | nil | 0", "empty")
	T.eq(seen["equal keys come out in the order pushed"].lua, "a1@1 a2@1 a3@1 b1@2 b2@2 b3@2", "ties")
	T.eq(seen["pushes and pops interleaved keep the order"].lua, "b | a@1 c@3 d@4", "interleaved")
	T.eq(seen["any value comes back as it went in"].lua, "true | true | true | true", "values")
	T.eq(seen["clearing empties it, and the order starts again"].lua, "2 | late@2 later@2", "clear")
	T.eq(seen["New is the call"].lua, "one", "New")
	T.eq(seen["__len is Size"].lua, "2 | 2", "__len")
	T.eq(seen["many keys come out sorted, ties in push order"].lua, "true | 0", "many")
end)

T.finish()
