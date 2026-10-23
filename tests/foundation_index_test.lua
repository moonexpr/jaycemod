-- foundation's namespace indexes, game's inits, and shared_loader.lua, which
-- runs them: every index and init is named in the loader by hand, runs under
-- LuaJIT, publishes every module of its folder (foundation's at once,
-- game's on first read), and neither loops nor scans
-- (docs/foundation-game-split-plan.md). The test scans; the loader never does.
local T = dofile("tests/harness.lua")
local Namespace = T.require("foundation.core.namespace")

local LOADER = T.ROOT .. "shared_loader.lua"
local INDEX_CALL = "Index%(%s*\"([%w_/.]+)\"%s*%)"

-- Each tree's index files, and how a module of it is published.
local TREES = {
	{ root = "foundation", file = "_index.lua", lazy = false },
	{ root = "games", file = "_init.lua", lazy = true },
}

-- foundation's root folder publishes its modules as plain globals.
local ROOT_FOLDER = "foundation/"

-- The table a folder's index publishes into.
local function NamespaceOf(globals, folder)
	if folder == ROOT_FOLDER then return globals end
	return globals[folder:match("([%w_]+)/$")]
end

local function Read(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

local function Lines(command)
	local list = assert(io.popen(command))
	local lines = {}
	for line in list:lines() do lines[#lines + 1] = line end
	list:close()
	return lines
end

-- A tree's index files on disk, as paths under the gamemode, sorted.
local function IndexFiles(tree)
	local paths = {}
	local command = "find " .. T.ROOT .. tree.root .. " -name '*" .. tree.file .. "' | sort"
	for _, path in ipairs(Lines(command)) do paths[#paths + 1] = path:sub(#T.ROOT + 1) end
	return paths
end

local function AllIndexFiles()
	local paths = {}
	for _, tree in ipairs(TREES) do
		for _, path in ipairs(IndexFiles(tree)) do paths[#paths + 1] = path end
	end
	return paths
end

local function LoaderIndexes()
	local named = {}
	for path in Read(LOADER):gmatch(INDEX_CALL) do named[#named + 1] = path end
	return named
end

-- Globals as GMod's would start: Lua's math, and a list, file and timer
-- library holding a default each.
local function Globals()
	local math = {}
	for key, value in pairs(_G.math) do math[key] = value end
	local globals = {
		math = math,
		list = { Get = function() end },
		file = { Read = function() end },
		timer = { Simple = function() end },
	}
	globals._G = globals
	return globals
end

local function RunIndexes(globals)
	local env = Namespace.Environment(globals, T.require)
	for _, path in ipairs(LoaderIndexes()) do
		local chunk = assert(loadfile(T.ROOT .. path))
		setfenv(chunk, env)()
	end
end

-- folder (under the gamemode, ending in "/") -> the module keys in it
local function ModulesIn(folder)
	local keys = {}
	for _, file in ipairs(Lines("ls " .. T.ROOT .. folder .. " | grep '%.lua$'")) do
		local key = file:sub(1, -#".lua" - 1)
		if not key:match("_index$") and not key:match("_init$") then keys[#keys + 1] = key end
	end
	return keys
end

local function WithoutComments(text)
	return (text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end

T.test("the loader names every index on disk, and only those", function()
	local onDisk = {}
	for _, path in ipairs(AllIndexFiles()) do onDisk[path] = true end
	local named = {}
	for _, path in ipairs(LoaderIndexes()) do
		T.eq(onDisk[path], true, path .. " is on disk")
		T.eq(named[path], nil, path .. " is named once")
		named[path] = true
	end
	for path in pairs(onDisk) do T.eq(named[path], true, path .. " is named in shared_loader.lua") end
end)

T.test("foundation's indexes publish each module of their folder at once", function()
	local globals = Globals()
	RunIndexes(globals)
	for _, path in ipairs(IndexFiles(TREES[1])) do
		local folder = path:match("^(.-)[%a]+_index%.lua$")
		local ns = NamespaceOf(globals, folder)
		for _, key in ipairs(ModulesIn(folder)) do
			local name = folder:gsub("/", ".") .. key
			T.eq(rawget(ns, key), T.require(name), folder .. key .. " is published")
		end
	end
	T.eq(globals.transaction, T.require("foundation.transaction"), "a root module is a plain global")
end)

T.test("game's inits publish each module of their folder, loaded on first read", function()
	local globals = Globals()
	RunIndexes(globals)
	for _, path in ipairs(IndexFiles(TREES[2])) do
		local folder = path:match("^(.-)[%a]+_init%.lua$")
		local ns = globals[folder:match("([%w_]+)/$")]
		for _, key in ipairs(ModulesIn(folder)) do
			T.eq(rawget(ns, key), nil, folder .. key .. " is not loaded before it is read")
			local name = folder:gsub("/", ".") .. key
			T.eq(ns[key], T.require(name), folder .. key .. " is published")
		end
	end
end)

T.test("the defaults the indexes extend are kept", function()
	local globals = Globals()
	RunIndexes(globals)
	T.eq(globals.math.random, math.random, "Lua's math.random")
	T.eq(type(globals.list.Get), "function", "GMod's list.Get")
	T.eq(type(globals.file.Read), "function", "GMod's file.Read")
	T.eq(type(globals.timer.Simple), "function", "GMod's timer.Simple")
end)

T.test("running the indexes again, as a reload does, is not refused", function()
	local globals = Globals()
	RunIndexes(globals)
	RunIndexes(globals)
	T.eq(globals.list.queue, T.require("foundation.list.queue"), "list.queue")
	T.eq(globals.list.drawlist, T.require("games.list.drawlist"), "list.drawlist")
end)

T.test("a published foundation module requires only foundation", function()
	for _, path in ipairs(IndexFiles(TREES[1])) do
		local folder = path:match("^(.-)[%a]+_index%.lua$")
		for _, key in ipairs(ModulesIn(folder)) do
			local code = Read(T.ROOT .. folder .. key .. ".lua")
			for name in code:gmatch("require%(%s*[\"']([%w_.]+)[\"']") do
				T.eq(name:match("^foundation%.") ~= nil, true, folder .. key .. " requires " .. name)
			end
		end
	end
end)

T.test("neither the loader nor an index loops or scans", function()
	local paths = AllIndexFiles()
	paths[#paths + 1] = "shared_loader.lua"
	for _, path in ipairs(paths) do
		local code = WithoutComments(Read(T.ROOT .. path))
		for _, word in ipairs({ "for", "while", "repeat", "pairs", "ipairs", "next" }) do
			T.eq(code:find("%f[%w_]" .. word .. "%f[^%w_]") == nil, true, path .. " has no " .. word)
		end
		T.eq(code:find("file.Find", 1, true) == nil, true, path .. " has no file.Find")
	end
end)

T.finish()
