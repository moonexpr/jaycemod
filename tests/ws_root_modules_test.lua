-- The gamemode's root modules load by lines written by hand, one a file:
-- shared.lua includes the sh_ ones, cl_init.lua the cl_ ones, init.lua the
-- sv_ ones and sends clients every file they run. No loop and no folder
-- scan decides what loads (a scan once had cl_init.lua include itself, a
-- client's load running over without end). Each list is held to the files
-- on disk: every module once, none missing, none that is not there.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT

local function Source(path)
	local f = assert(io.open(ROOT .. path))
	local text = f:read("*a")
	f:close()
	return text
end

-- The root's .lua files starting with prefix, sorted.
local function OnDisk(prefix)
	local found = {}
	for name in io.popen("ls " .. ROOT):lines() do
		if name:sub(1, #prefix) == prefix and name:match("%.lua$") then found[#found + 1] = name end
	end
	table.sort(found)
	return found
end

-- The files a source names in calls to fn("<file>"), in order, its comments
-- left out.
local function Named(text, fn)
	local names = {}
	for line in text:gmatch("[^\n]+") do
		local code = line:gsub("%-%-.*$", "")
		for name in code:gmatch(fn .. '%("([%w_/%.]+)"%)') do names[#names + 1] = name end
	end
	return names
end

local function Counts(list)
	local counts = {}
	for _, name in ipairs(list) do counts[name] = (counts[name] or 0) + 1 end
	return counts
end

-- list names each of expected once, and nothing else.
local function Covers(list, expected, what)
	local counts = Counts(list)
	for _, name in ipairs(expected) do T.eq(counts[name], 1, what .. " names " .. name .. " once") end
	local wanted = Counts(expected)
	for name in pairs(counts) do T.eq(wanted[name] ~= nil, true, what .. " names " .. name .. ", which it should not") end
end

local function Without(list, ...)
	local drop = Counts({ ... })
	local kept = {}
	for _, name in ipairs(list) do
		if not drop[name] then kept[#kept + 1] = name end
	end
	return kept
end

local function Prefixed(list, prefix)
	local kept = {}
	for _, name in ipairs(list) do
		if name:sub(1, #prefix) == prefix then kept[#kept + 1] = name end
	end
	return kept
end

-- init.lua still sends clients the module folders by a scan
-- (Features.ClientFiles): that sends files, and includes none.
T.test("no load file includes in a loop; shared.lua and cl_init.lua scan no folder", function()
	for _, path in ipairs({ "shared.lua", "cl_init.lua", "init.lua" }) do
		local text = Source(path)
		T.eq(text:find("WSModules", 1, true), nil, path .. ": no WSModules")
		for loop in text:gmatch("for [^\n]- do.-\nend") do
			T.eq(loop:find("[Ii]nclude%(") or loop:find("Load%("), nil, path .. ": no include in a loop")
		end
	end
	for _, path in ipairs({ "shared.lua", "cl_init.lua" }) do
		T.eq(Source(path):find("file.Find", 1, true), nil, path .. ": no file.Find")
	end
end)

T.test("shared.lua includes every sh_ module once, sh_core first (it includes sh_events)", function()
	local included = Prefixed(Named(Source("shared.lua"), "Include"), "sh_")
	T.eq(included[1], "sh_core.lua", "sh_core first")
	Covers(included, Without(OnDisk("sh_"), "sh_events.lua"), "shared.lua")
end)

T.test("cl_init.lua loads every cl_ module once, never itself", function()
	Covers(Named(Source("cl_init.lua"), "Load"), Without(OnDisk("cl_"), "cl_init.lua"), "cl_init.lua")
end)

T.test("init.lua includes every sv_ module once", function()
	Covers(Prefixed(Named(Source("init.lua"), "Include"), "sv_"), OnDisk("sv_"), "init.lua")
end)

T.test("init.lua sends clients every root file they run, and no sv_ one", function()
	local expected = { "shared.lua", "logging.lua", "shared_loader.lua", "cl_init.lua" }
	for _, name in ipairs(OnDisk("sh_")) do expected[#expected + 1] = name end
	for _, name in ipairs(Without(OnDisk("cl_"), "cl_init.lua")) do expected[#expected + 1] = name end
	local sent = {}
	for _, name in ipairs(Named(Source("init.lua"), "AddCSLuaFile")) do
		if not name:find("/", 1, true) then sent[#sent + 1] = name end
	end
	Covers(sent, expected, "init.lua's AddCSLuaFile")
end)

T.finish()
