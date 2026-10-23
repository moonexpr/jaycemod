-- What the server sends clients: Features.ClientFiles over the real tree sends every file under
-- foundation/, features/ and ws/ except server ones (sv.lua, sv_*), and every
-- module a shipped file requires is itself shipped.
local T = dofile("tests/harness.lua")
local Features = system.features

local ENTITIES = T.ROOT .. "../entities/"
local LUA = "%.lua$"

-- The lines a shell command prints.
local function Lines(command)
	local pipe = assert(io.popen(command))
	local lines = {}
	for line in pipe:lines() do lines[#lines + 1] = line end
	pipe:close()
	return lines
end

-- The names directly inside folder (a path ending in "/") of one find -type.
local function Names(folder, type)
	local names = {}
	for _, path in ipairs(Lines("find " .. folder .. " -mindepth 1 -maxdepth 1 -type " .. type)) do
		names[#names + 1] = path:sub(#folder + 1)
	end
	return names
end

-- Every .lua file under folder, any depth, as paths relative to strip.
local function LuaFilesUnder(folder, strip)
	local paths = {}
	for _, path in ipairs(Lines("find " .. folder .. " -name '*.lua'")) do
		paths[#paths + 1] = path:sub(#strip + 1)
	end
	return paths
end

-- The real tree, as file.Find would see it from the gamemode folder.
local DiskPort = {}
function DiskPort:Find(dir)
	return Names(T.ROOT .. dir, "f"), Names(T.ROOT .. dir, "d")
end

local function Set(list)
	local set = {}
	for _, item in ipairs(list) do set[item] = true end
	return set
end

local function Sorted(set)
	local list = {}
	for item in pairs(set) do list[#list + 1] = item end
	table.sort(list)
	return list
end

local function Basename(path)
	return path:match("([^/]+)$")
end

local function Read(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

local shipped = Features.ClientFiles(DiskPort, Features.CLIENT_DIRS)
local ships = Set(shipped)

T.test("the files clients need are sent", function()
	for _, path in ipairs({
		"features/tag/model.lua",
		"ws/sound_paths.lua",
		"features/capture/cl.lua",
		"games/gameplay/teams.lua",
	}) do
		T.eq(ships[path], true, path)
	end
end)

T.test("no server file is sent", function()
	local server = {}
	for _, path in ipairs(shipped) do
		if Features.Realm(Basename(path)) == Features.SERVER then server[#server + 1] = path end
	end
	T.eq(table.concat(server, ", "), "", "server files sent")
end)

-- init.lua's former rule: all of foundation/ (and of games/, split from
-- it), each feature's sh.lua and cl.lua, and ws/sh_* and ws/cl_*. The new
-- rule adds only modules: the files under features/ and ws/ with no realm.
T.test("the sent set is the old rule's set plus the feature and ws modules", function()
	local expected = Set(LuaFilesUnder(T.ROOT .. "foundation/", T.ROOT))
	for _, path in ipairs(LuaFilesUnder(T.ROOT .. "games/", T.ROOT)) do expected[path] = true end
	for _, name in ipairs(Names(T.ROOT .. Features.ROOT, "d")) do
		for _, part in ipairs(Features.CLIENT_PARTS) do
			local path = Features.PartPath(name, part)
			local file = io.open(T.ROOT .. path)
			if file then
				file:close()
				expected[path] = true
			end
		end
	end
	for _, name in ipairs(Names(T.ROOT .. "ws/", "f")) do
		if name:match("^sh_.*" .. LUA) or name:match("^cl_.*" .. LUA) then expected["ws/" .. name] = true end
	end
	for _, dir in ipairs({ Features.ROOT, "ws/" }) do
		for _, path in ipairs(LuaFilesUnder(T.ROOT .. dir, T.ROOT)) do
			if Features.Realm(Basename(path)) == nil then expected[path] = true end
		end
	end
	T.eq(table.concat(shipped, "\n"), table.concat(Sorted(expected), "\n"), "sent set")
end)

-- Every module a file a client may run uses (any shipped file, and every
-- entity and weapon file), by a literal require or by its global, is
-- shipped, so neither a server part nor a missing file is loaded on a client.
T.test("every module a shipped file or an entity uses is shipped", function()
	local sources = {}
	for _, path in ipairs(shipped) do sources[#sources + 1] = { path, T.ROOT .. path } end
	for _, path in ipairs(LuaFilesUnder(ENTITIES, ENTITIES)) do
		sources[#sources + 1] = { "../entities/" .. path, ENTITIES .. path }
	end
	local unshipped = {}
	for _, source in ipairs(sources) do
		for _, name in ipairs(T.Uses(Read(source[2]))) do
			local target = name:gsub("%.", "/") .. ".lua"
			if not ships[target] then unshipped[#unshipped + 1] = source[1] .. " -> " .. target end
		end
	end
	T.eq(table.concat(unshipped, ", "), "", "requires of unshipped files")
end)

T.finish()
