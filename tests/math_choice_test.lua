-- foundation.math.choice: shuffling and drawing from a list with a random
-- source the caller gives, randomInt(low, high) -> a whole number from low to
-- high, so a test can script it and a game can seed it.
local T = dofile("tests/harness.lua")
local Choice = math.choice

-- A source that answers from a script and keeps what it was asked.
local function Scripted(answers)
	local asked, at = {}, 0
	local function random(low, high)
		at = at + 1
		asked[#asked + 1] = low .. "-" .. high
		return answers[at]
	end
	return random, asked
end

local function Joined(list) return table.concat(list, " ") end

T.test("Shuffle swaps each place from the last with a draw from the places before it", function()
	local random, asked = Scripted({ 1, 1, 2 })
	local out = Choice.Shuffle({ "a", "b", "c", "d" }, random)
	T.eq(Joined(asked), "1-4 1-3 1-2", "asked once for each place but the first, from the last down")
	-- swap(4, 1): d b c a; swap(3, 1): c b d a; swap(2, 2): no change
	T.eq(Joined(out), "c b d a", "the result")
end)

T.test("Shuffle leaves the list it was given as it was, and gives a new one", function()
	local list = { 1, 2, 3 }
	local random = Scripted({ 3, 1 })
	local out = Choice.Shuffle(list, random)
	T.eq(Joined(list), "1 2 3", "untouched")
	T.eq(out ~= list, true, "a new list")
	T.eq(#out, 3, "the same size")
end)

T.test("Shuffle of nothing or one asks nothing", function()
	local random, asked = Scripted({})
	T.eq(#Choice.Shuffle({}, random), 0, "empty")
	T.eq(Joined(Choice.Shuffle({ 7 }, random)), "7", "one")
	T.eq(#asked, 0, "never asked")
end)

T.test("Shuffle with a real source gives every item once", function()
	local list = {}
	for i = 1, 50 do list[i] = i end
	local out = Choice.Shuffle(list, math.random)
	local seen, count = {}, 0
	for _, v in ipairs(out) do
		seen[v] = true
		count = count + 1
	end
	T.eq(count, 50, "fifty")
	for i = 1, 50 do if not seen[i] then T.eq(false, true, "missing " .. i) end end
end)

T.test("Draw takes count items without replacement, the last filling the place of the one taken", function()
	local random, asked = Scripted({ 2, 1 })
	local out = Choice.Draw({ "a", "b", "c", "d" }, 2, random)
	T.eq(Joined(asked), "1-4 1-3", "asked for each, from what is left")
	T.eq(Joined(out), "b a", "b first; d fills its place; then the first, a")
end)

T.test("Draw of more than there are gives them all; of 0 gives none and asks nothing", function()
	local random = Scripted({ 1, 1, 1 })
	T.eq(#Choice.Draw({ 1, 2, 3 }, 10, random), 3, "all of them")
	local none, asked = Scripted({})
	T.eq(#Choice.Draw({ 1, 2, 3 }, 0, none), 0, "none")
	T.eq(#asked, 0, "never asked")
	T.eq(#Choice.Draw({}, 4, none), 0, "from nothing")
end)

T.test("Draw leaves the list as it was", function()
	local list = { 1, 2, 3, 4 }
	Choice.Draw(list, 3, Scripted({ 4, 1, 1 }))
	T.eq(Joined(list), "1 2 3 4", "untouched")
end)

T.test("a count is a whole number of at least 0", function()
	T.eq(pcall(Choice.Draw, { 1 }, -1, math.random), false, "negative")
	T.eq(pcall(Choice.Draw, { 1 }, 1.5, math.random), false, "a fraction")
	T.eq(pcall(Choice.Draw, { 1 }, nil, math.random), false, "none given")
end)

T.test("a source that answers outside the range is our bug, refused", function()
	T.eq(pcall(Choice.Shuffle, { 1, 2, 3 }, Scripted({ 9, 1 })), false, "too high in Shuffle")
	T.eq(pcall(Choice.Draw, { 1, 2, 3 }, 2, Scripted({ 0, 1 })), false, "too low in Draw")
	T.eq(pcall(Choice.Draw, { 1, 2, 3 }, 2, Scripted({ 1.5, 1 })), false, "a fraction")
end)

T.finish()
