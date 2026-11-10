local T = dofile("tests/harness.lua")

T.test("eq passes on equal values", function() T.eq(1 + 1, 2) end)
T.test("eq raises on different values", function()
	local ok = pcall(T.eq, 1, 2)
	T.eq(ok, false, "pcall result")
end)
T.test("near tolerates small error", function() T.near(0.1 + 0.2, 0.3, 1e-9) end)

-- T.require resolves the dotted name against T.ROOT; the fixture lives in tests/.
local function requireFixture(name)
	local root = T.ROOT
	T.ROOT = "tests/"
	local ok, result = pcall(T.require, name)
	T.ROOT = root
	assert(ok, result)
	return result
end

T.test("require loads a module(...) file under its dotted name", function()
	local Greeting = requireFixture("fixtures.greeting")
	T.eq(type(Greeting), "table", "module table")
	T.eq(Greeting._NAME, "fixtures.greeting", "module name")
	T.eq(Greeting.Greet("world"), "hello, world", "module function")
	T.eq(package.loaded["fixtures.greeting"], Greeting, "package.loaded entry")
end)

T.test("require loads a module once", function()
	local first = requireFixture("fixtures.greeting")
	first.GREETING = "hi"
	local second = requireFixture("fixtures.greeting")
	T.eq(second, first, "same table")
	T.eq(second.Greet("you"), "hi, you", "not reloaded")
end)

T.test("a module requires a sibling through the same loader", function()
	package.loaded["fixtures.greeting"] = nil
	local Farewell = requireFixture("fixtures.farewell")
	T.eq(Farewell.Greeter(), package.loaded["fixtures.greeting"], "sibling module")
	T.eq(Farewell.require, nil, "require stays outside the module")
end)

T.test("a part loads under its system and nests in the system's table", function()
	local Formal = requireFixture("fixtures.greeting.formal")
	T.eq(Formal._NAME, "fixtures.greeting.formal", "part name")
	T.eq(package.loaded["fixtures.greeting"].formal, Formal, "part inside the system")
end)

T.test("gamemode root is the gamemode folder", function()
	T.eq(T.ROOT, "addons/sandcastle/gamemodes/wetsands/gamemode/", "Wetsands' gamemode folder")
	T.eq(T.SANDCASTLE, "addons/sandcastle/gamemodes/sandcastle/gamemode/", "Sandcastle's, its base")
end)

T.test("an entity's file is looked up in the derived gamemode first, then its base", function()
	T.eq(T.Entity("info_ladder.lua"), "addons/sandcastle/gamemodes/wetsands/entities/entities/info_ladder.lua", "Wetsands'")
	T.eq(T.Entity("team_round_timer.lua"), "addons/sandcastle/gamemodes/sandcastle/entities/entities/team_round_timer.lua", "Sandcastle's")
	T.eq(T.EntityFile("weapons/tf_weapon_spellbook.lua"), "addons/sandcastle/gamemodes/wetsands/entities/weapons/tf_weapon_spellbook.lua", "a weapon")
	T.eq(T.Entity("nope.lua"), "addons/sandcastle/gamemodes/wetsands/entities/entities/nope.lua", "neither: the derived one's")
end)

T.finish()
