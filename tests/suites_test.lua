-- The test suites grouped by major system (tests/suites.lua), which
-- check_lua.sh runs one group at a time: every test in exactly one group,
-- every source file claimed by one, and the resolver's rules.
local T = dofile("tests/harness.lua")
local Suites = dofile(".devtools/bin/suites.lua")

local function Lines(command)
	local pipe, lines = assert(io.popen(command)), {}
	for line in pipe:lines() do lines[#lines + 1] = line end
	pipe:close()
	return lines
end

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local TINY = {
	{ name = "base", about = "the base", tests = { "core_*", "list_queue" }, sources = { "lib/", "lib/root.lua" } },
	{ name = "game", about = "the game", tests = { "games_*", "core_game" }, sources = { "game/", "lib/game/" } },
}

T.test("a test belongs to the group whose pattern names it most closely", function()
	local suites = Suites.New(TINY, { "core_class", "core_game", "list_queue", "games_rounds" })
	T.eq(suites:GroupOf("core_class"), "base", "prefix")
	T.eq(suites:GroupOf("core_game"), "game", "an exact name over a prefix")
	T.eq(suites:GroupOf("list_queue"), "base", "exact")
	T.eq(table.concat(suites:Tests({ "game" }), " "), "tests/core_game_test.lua tests/games_rounds_test.lua", "a group's tests, in order")
end)

T.test("a test no group names, or two name as closely, is refused", function()
	T.eq(Raises(Suites.New, TINY, { "math_box" }):find("math_box", 1, true) ~= nil, true, "unnamed")
	local twice = { TINY[1], { name = "other", about = "", tests = { "core_*" }, sources = {} } }
	T.eq(Raises(Suites.New, twice, { "core_class" }):find("base and other", 1, true) ~= nil, true, "named twice")
end)

T.test("an unknown group is refused, naming the groups", function()
	local suites = Suites.New(TINY, { "core_class" })
	T.eq(Raises(suites.Tests, suites, { "nope" }):find("base, game", 1, true) ~= nil, true, "names them")
end)

T.test("a changed file picks the groups that claim it most closely", function()
	local suites = Suites.New(TINY, { "core_class", "games_rounds" })
	T.eq(table.concat(suites:Changed({ "lib/game/x.lua" }), " "), "game", "the closer claim")
	T.eq(table.concat(suites:Changed({ "lib/y.lua", "game/z.lua" }), " "), "base game", "each file's")
	T.eq(table.concat(suites:Changed({ "tests/games_rounds_test.lua" }), " "), "game", "a test is its group's")
	T.eq(table.concat(suites:Changed({ "README.md" }), " "), "", "nothing claims it")
end)

local MANIFEST = dofile("tests/suites.lua")
local TESTS = {}
for _, path in ipairs(Lines("ls tests/*_test.lua")) do TESTS[#TESTS + 1] = path:match("^tests/(.+)_test%.lua$") end

T.test("every test is in exactly one group", function()
	local suites = Suites.New(MANIFEST, TESTS)
	local count = 0
	for _, group in ipairs(suites:Names()) do count = count + #suites:Tests({ group }) end
	T.eq(count, #TESTS, "each test once")
end)

T.test("every Lua and native source file is claimed by a group", function()
	local suites = Suites.New(MANIFEST, TESTS)
	local orphans = {}
	for _, path in ipairs(Lines("find addons -name '*.lua'; find native -name '*.rs' -not -path '*/target/*' -not -path '*/vendor/*'")) do
		if #suites:Changed({ path }) == 0 then orphans[#orphans + 1] = path end
	end
	T.eq(table.concat(orphans, " "), "", "unclaimed files")
end)

T.test("every path a group claims names something: a folder, a file, or a prefix of one", function()
	for _, group in ipairs(MANIFEST) do
		for _, source in ipairs(group.sources) do
			local named = source:sub(-1) == "/" and Lines("test -d '" .. source .. "' && echo yes") or Lines("ls -d '" .. source .. "'* 2>/dev/null")
			T.eq(#named > 0, true, group.name .. " claims " .. source)
		end
	end
end)

T.finish()
