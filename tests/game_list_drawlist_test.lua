-- game.list.drawlist: draw callbacks named by dotted paths
-- (game.match.team_scores.blue_score), run in a fixed order, any of them
-- hidden by its path or an ancestor's, or held back by its own condition.
local T = dofile("tests/harness.lua")
local DrawList = T.require("game.list.drawlist")

-- A list whose callbacks log their names, and the log.
local function Logged()
	local list, log = DrawList.New(), {}
	local function Logger(name) return function() log[#log + 1] = name end end
	return list, log, Logger
end

T.test("callbacks run by order, a tie by name, whatever order they were added in", function()
	local list, log, Logger = Logged()
	list:Add("timer", 20, Logger("timer"))
	list:Add("scores", 10, Logger("scores"))
	list:Add("alerts", 20, Logger("alerts"))
	list:Draw()
	T.eq(table.concat(log, " "), "scores alerts timer")
end)

T.test("each callback gets what Draw is given", function()
	local list = DrawList.New()
	local got
	list:Add("box", 1, function(w, h) got = w .. "x" .. h end)
	list:Draw(640, 480)
	T.eq(got, "640x480")
end)

T.test("a hidden callback is skipped; a new hidden set replaces the old", function()
	local list, log, Logger = Logged()
	list:Add("a", 1, Logger("a"))
	list:Add("b", 2, Logger("b"))
	list:SetHidden({ a = true })
	list:Draw()
	list:SetHidden({ b = true })
	list:Draw()
	T.eq(table.concat(log, " "), "b a")
end)

T.test("a name hidden before its callback exists hides it once added, and an unknown name hides nothing", function()
	local list, log, Logger = Logged()
	list:SetHidden({ later = true, typo = true })
	list:Add("later", 1, Logger("later"))
	list:Add("shown", 2, Logger("shown"))
	list:Draw()
	T.eq(table.concat(log, " "), "shown")
end)

T.test("a callback with a condition runs only while it holds", function()
	local list, log, Logger = Logged()
	local on = false
	list:Add("rounds", 1, Logger("rounds"), function() return on end)
	list:Draw()
	on = true
	list:Draw()
	T.eq(table.concat(log, " "), "rounds")
end)

T.test("adding a name again replaces its callback and order, as a refreshed file does", function()
	local list, log, Logger = Logged()
	list:Add("a", 1, Logger("old a"))
	list:Add("b", 2, Logger("b"))
	list:Add("a", 3, Logger("new a"))
	list:Draw()
	T.eq(table.concat(log, " "), "b new a")
end)

T.test("the entries list every callback in drawing order, each with whether it is hidden", function()
	local list = DrawList.New()
	list:Add("b", 2, function() end)
	list:Add("a", 1, function() end)
	list:SetHidden({ b = true })
	local lines = {}
	for i, entry in ipairs(list:Entries()) do lines[i] = entry.name .. " " .. entry.order .. " " .. tostring(entry.hidden) end
	T.eq(table.concat(lines, ", "), "a 1 false, b 2 true")
end)

T.test("a list of names as typed (spaces or commas between) is a set of them", function()
	local set = DrawList.ParseNames(" rounds,votes  hits ,")
	local names = {}
	for name in pairs(set) do names[#names + 1] = name end
	table.sort(names)
	T.eq(table.concat(names, " "), "hits rounds votes")
	T.eq(next(DrawList.ParseNames("")), nil, "none")
end)

-- Paths: hiding one hides everything under it.

T.test("hiding a path hides it and every path under it, and nothing beside it", function()
	local list, log, Logger = Logged()
	list:Add("game.match.team_scores.blue_score", 1, Logger("blue"))
	list:Add("game.match.team_scores.red_score", 2, Logger("red"))
	list:Add("game.match.timer", 3, Logger("timer"))
	list:Add("game.match.team_scores_extra", 4, Logger("extra"))
	list:HideElements("game.match.team_scores")
	list:Draw()
	T.eq(table.concat(log, " "), "timer extra", "a whole segment, not a prefix of letters")
end)

T.test("shown again, a path's elements draw again", function()
	local list, log, Logger = Logged()
	list:Add("game.match.team_scores.blue_score", 1, Logger("blue"))
	list:HideElements("game.match.team_scores")
	list:Draw()
	list:ShowElements("game.match.team_scores")
	list:Draw()
	T.eq(table.concat(log, " "), "blue")
end)

T.test("the code's hides and the player's are apart: either one hides, showing one leaves the other", function()
	local list, log, Logger = Logged()
	list:Add("game.match.timer", 1, Logger("timer"))
	list:SetHidden({ game = true })
	list:ShowElements("game.match.timer")
	list:Draw()
	list:SetHidden({})
	list:HideElements("game.match")
	list:Draw()
	list:ShowElements("game.match")
	list:Draw()
	T.eq(table.concat(log, " "), "timer", "drawn only once neither hides it")
end)

T.test("an entry is hidden in the listing when any ancestor is", function()
	local list = DrawList.New()
	list:Add("game.match.timer", 1, function() end)
	list:HideElements("game")
	T.eq(list:Entries()[1].hidden, true)
end)

T.finish()
