-- foundation's namespace indexes and shared_loader.lua, which runs them:
-- every index is named in the loader by hand, runs under LuaJIT, publishes
-- every module of its folder, and neither loops nor scans
-- (docs/foundation-game-split-plan.md). The test scans; the loader never does.
local T = dofile("tests/harness.lua")
local Namespace = T.require("foundation.core.namespace")

local FOUNDATION = T.ROOT .. "foundation/"
local LOADER = T.ROOT .. "shared_loader.lua"
local INDEX_CALL = "Index%(%s*\"([%w_/.]+)\"%s*%)"

-- Folders that still hold modules bound elsewhere: only what their index
-- lists is published, until those move (the plan's stages 2 and 3).
local PARTLY = {
	[""] = true,
	["npc/"] = true,
}
local STAYING_IN_CORE = {
	drawlist = true,
	hfsm = true,
	map_io = true,
	snapshot = true,
	tactics = true,
	timers = true,
}

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

-- The index files on disk, as paths under the gamemode, sorted.
local function IndexFiles()
	local paths = {}
	for _, path in ipairs(Lines("find " .. FOUNDATION .. " -name '*_index.lua' | sort")) do
		paths[#paths + 1] = path:sub(#T.ROOT + 1)
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

local function WithoutComments(text)
	return (text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end

T.test("the loader names every index on disk, and only those", function()
	local onDisk = {}
	for _, path in ipairs(IndexFiles()) do onDisk[path] = true end
	local named = {}
	for _, path in ipairs(LoaderIndexes()) do
		T.eq(onDisk[path], true, path .. " is on disk")
		T.eq(named[path], nil, path .. " is named once")
		named[path] = true
	end
	for path in pairs(onDisk) do T.eq(named[path], true, path .. " is named in shared_loader.lua") end
end)

T.test("every index runs, publishing each module of its folder under the module's name", function()
	local globals = Globals()
	RunIndexes(globals)
	for _, path in ipairs(IndexFiles()) do
		local folder = path:match("^foundation/(.-)[%a]+_index%.lua$")
		if not PARTLY[folder] then
			local ns = globals[folder:sub(1, -2)]
			for _, file in ipairs(Lines("ls " .. FOUNDATION .. folder .. " | grep '%.lua$'")) do
				local key = file:sub(1, -#".lua" - 1)
				if not key:match("_index$") and not (folder == "core/" and STAYING_IN_CORE[key]) then
					local name = "foundation." .. folder:gsub("/", ".") .. key
					T.eq(ns[key], T.require(name), folder .. key .. " is published")
				end
			end
		end
	end
	T.eq(globals.transaction, T.require("foundation.transaction"), "a root module is a plain global")
end)

T.test("the defaults the indexes extend are kept", function()
	local globals = Globals()
	RunIndexes(globals)
	T.eq(globals.math.random, math.random, "Lua's math.random")
	T.eq(type(globals.list.Get), "function", "GMod's list.Get")
	T.eq(type(globals.file.Read), "function", "GMod's file.Read")
end)

T.test("running the indexes again, as a reload does, is not refused", function()
	local globals = Globals()
	RunIndexes(globals)
	RunIndexes(globals)
	T.eq(globals.list.queue, T.require("foundation.list.queue"), "list.queue")
end)

T.test("neither the loader nor an index loops or scans", function()
	local paths = IndexFiles()
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
