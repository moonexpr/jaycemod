-- game_manager: the games a gamemode can play, classes registered as
-- player_manager's are, from the files of its gamerules/ folder.
local T = dofile("tests/harness.lua")

local published
baseclass = { Set = function(name, tab) published[name] = tab end }

-- The library starts empty, as it does on each map.
local function Fresh()
	published = {}
	package.loaded["includes.game_manager"] = nil
	return T.require("includes.game_manager")
end

local function Game(applies, fields)
	local game = fields or {}
	function game:Applies() return applies end
	return game
end

local function ErrorOf(fn)
	local ok, err = pcall(fn)
	assert(not ok, "expected an error")
	return tostring(err)
end

local function Has(text, part, what)
	T.eq(text:find(part, 1, true) ~= nil, true, what)
end

T.test("a registered class is found by its name", function()
	local Games = Fresh()
	local payload = Game(true)
	Games.RegisterClass("game_payload", payload)
	T.eq(Games.GetClass("game_payload"), payload, "its table")
	T.eq(Games.GetClass("game_koth"), nil, "another name")
end)

T.test("a class is published to baseclass, for DEFINE_BASECLASS", function()
	local Games = Fresh()
	local payload = Game(true)
	Games.RegisterClass("game_payload", payload)
	T.eq(published.game_payload, payload, "published")
end)

T.test("a class reads what it lacks from its base", function()
	local Games = Fresh()
	Games.RegisterClass("game_default", Game(false, { Label = "base" }))
	local payload = {}
	Games.RegisterClass("game_payload", payload, "game_default")
	T.eq(payload.Label, "base", "inherited")
end)

T.test("a class sees its base replaced by a derived gamemode", function()
	local Games = Fresh()
	Games.RegisterClass("game_points", Game(true, { Label = "sandcastle" }))
	local payload = {}
	Games.RegisterClass("game_payload", payload, "game_points")
	Games.RegisterClass("game_points", Game(true, { Label = "wetsands" }))
	T.eq(payload.Label, "wetsands", "the replacement")
end)

T.test("deriving from an unknown class is refused, naming both", function()
	local Games = Fresh()
	local err = ErrorOf(function() Games.RegisterClass("game_payload", Game(true), "game_nope") end)
	Has(err, "game_payload", "the class")
	Has(err, "game_nope", "the base")
end)

T.test("a class that cannot say when it is played is refused, by name", function()
	local Games = Fresh()
	Has(ErrorOf(function() Games.RegisterClass("game_payload", {}) end), "game_payload", "names it")
end)

T.test("a name registered again replaces the class", function()
	local Games = Fresh()
	local derived = Game(true)
	Games.RegisterClass("game_payload", Game(true))
	Games.RegisterClass("game_payload", derived)
	T.eq(Games.GetClass("game_payload"), derived, "the later one")
	T.eq(#Games.Active(), 1, "one class under the name")
end)

T.test("only the classes this map plays are active, in name order", function()
	local Games = Fresh()
	Games.RegisterClass("game_koth", Game(true))
	Games.RegisterClass("game_payload", Game(false))
	Games.RegisterClass("game_ctf", Game(true))
	local active = Games.Active()
	T.eq(#active, 2, "two apply")
	T.eq(active[1], "game_ctf", "ctf first")
	T.eq(active[2], "game_koth", "koth next")
end)

T.test("RunClass calls the method on the class and returns its values", function()
	local Games = Fresh()
	Games.RegisterClass("game_payload", Game(true, { Double = function(self, n) return n * 2, self end }))
	local doubled, class = Games.RunClass("game_payload", "Double", 4)
	T.eq(doubled, 8, "its value")
	T.eq(class, Games.GetClass("game_payload"), "called on the class")
end)

T.test("RunClass refuses a class or method that is not there", function()
	local Games = Fresh()
	Games.RegisterClass("game_payload", Game(true))
	Has(ErrorOf(function() Games.RunClass("game_koth", "Standing") end), "game_koth", "the class")
	Has(ErrorOf(function() Games.RunClass("game_payload", "Standing") end), "Standing", "the method")
end)

T.test("RunActive runs a method on each class this map plays, and only those", function()
	local Games = Fresh()
	local function Adds(key)
		return { Standing = function(_, objective) objective[key] = true end }
	end
	Games.RegisterClass("game_ctf", Game(true, Adds("captures")))
	Games.RegisterClass("game_points", Game(true, Adds("points")))
	Games.RegisterClass("game_payload", Game(false, Adds("carts")))
	local objective = {}
	Games.RunActive("Standing", objective)
	T.eq(objective.captures, true, "ctf's part")
	T.eq(objective.points, true, "the points' part")
	T.eq(objective.carts, nil, "not the one this map does not play")
end)

T.finish()
