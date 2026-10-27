-- Per-map lazy loading of controllers and views (WS.Feature). A feature
-- is a folder, features/<name>/, holding sv.lua (the controller), cl.lua (the
-- view) and sh.lua (both realms, loaded first); cl and sh may be absent. The
-- Lua VM restarts on map change, so each map loads only the features its
-- entities ask for, each once, and every client loads the client parts of
-- the features the server loaded.
--
-- A Loader is one realm's registry. Its port does the file I/O:
--   port:Exists(path) -> bool, port:Run(path) -> the file's return value,
--   port:TellClients(name) (server only: a feature with a client part loaded).
-- Paths are relative to the gamemode folder.
--
-- A file's name says its realm: sv.lua and sv_*, cl.lua and cl_*, sh.lua and sh_*; any other name is a
-- pure module. Clients are sent every file but the server's.
local error, format, ipairs, match, pcall, setfenv, setmetatable, tostring, type =
	error, string.format, ipairs, string.match, pcall, setfenv, setmetatable, tostring, type
local concat, sort = table.concat, table.sort
local floor = math.floor
module(...)

ROOT = "features/"
-- Features switched off: their code stays, but nothing may load them.
OFF = {
	nodegraph = true, -- the AI node graph from the nav mesh; not needed now
}
SHARED, SERVER, CLIENT = "sh", "sv", "cl"

-- The parts a client loads, in order.
CLIENT_PARTS = { SHARED, CLIENT }

function PartPath(name, part)
	return ROOT .. name .. "/" .. part .. ".lua"
end

-- The folders, relative to the gamemode folder, whose files clients are sent.
CLIENT_DIRS = { "foundation/", "games/", "nextsoldier/", "features/", "ws/", "vendor/" }

local REALM_OF = {
	[SERVER] = SERVER,
	[CLIENT] = CLIENT,
	[SHARED] = SHARED,
}

-- A file's realm from its base name: SERVER, CLIENT or SHARED when it is
-- exactly sv.lua, cl.lua or sh.lua or starts with sv_, cl_ or sh_; nil for a
-- module.
function Realm(fileName)
	return REALM_OF[match(fileName, "^(%a%a)%.lua$") or match(fileName, "^(%a%a)_")]
end

-- Whether a file (a base name) is sent to clients: every one but the server's.
function Ships(fileName)
	return Realm(fileName) ~= SERVER
end

local function AddClientFiles(port, dir, paths)
	local fileNames, dirNames = port:Find(dir)
	for _, fileName in ipairs(fileNames) do
		if match(fileName, "%.lua$") and Ships(fileName) then paths[#paths + 1] = dir .. fileName end
	end
	for _, dirName in ipairs(dirNames) do AddClientFiles(port, dir .. dirName .. "/", paths) end
end

-- Every .lua file under dirs, at any depth, that ships, sorted.
--   port:Find(dir) -> fileNames, dirNames (dir ends in "/").
function ClientFiles(port, dirs)
	local paths = {}
	for _, dir in ipairs(dirs) do AddClientFiles(port, dir, paths) end
	sort(paths)
	return paths
end

-- A realm root (sv.lua, cl.lua, sh.lua) is its feature's composition root: it
-- declares the state and runs its parts, <realm>_<part>.lua beside it, in
-- order; a part may register its own wiring under ids unique to the feature.
function PartFile(name, part)
	if not REALM_OF[match(part, "^(%a%a)_[%w_]+$")] then error("not a feature part: " .. part, 0) end
	return ROOT .. name .. "/" .. part .. ".lua"
end

-- The root's part runner: Part(part, ...) runs the part's chunk in env (the
-- root's own, getfenv(1)) with the arguments and returns its values.
--   port:Compile(path) -> the file's chunk, or nil when it is missing or
--   does not compile.
function Parts(port, env, name)
	return function(part, ...)
		local path = PartFile(name, part)
		local chunk = port:Compile(path)
		if not chunk then error(path .. " did not compile", 0) end
		return setfenv(chunk, env)(...)
	end
end

-- What differs between the realms: which file is the realm's own part, how a
-- realm decides a name is unknown, and whether it tells clients.
local REALMS = {
	[SERVER] = {
		label = "server",
		tellsClients = true,
		MissingMessage = function(name, hasShared, hasOwn)
			if not hasOwn then return format("unknown feature %q: no %s", name, PartPath(name, SERVER)) end
		end,
	},
	[CLIENT] = {
		label = "client",
		tellsClients = false,
		MissingMessage = function(name, hasShared, hasOwn)
			if not (hasShared or hasOwn) then
				return format("unknown feature %q: no %s or %s", name, PartPath(name, CLIENT), PartPath(name, SHARED))
			end
		end,
	},
}

local Loader = {}
Loader.__index = Loader

-- realm: SERVER or CLIENT.
function New(realm, port)
	return setmetatable({
		realm = realm,
		spec = REALMS[realm],
		port = port,
		values = {},
		loaded = {},
		loading = {},
		failed = {},
		order = {},
		hasClientPart = {},
	}, Loader)
end

local function RunTable(port, path)
	local value = port:Run(path)
	if type(value) ~= "table" then
		error(format("%s returned %s, not its table", path, type(value)), 0)
	end
	return value
end

-- Dependencies a part loads finish first, so the order is dependency order.
local function Load(self, name)
	local port = self.port
	local sharedPath, ownPath = PartPath(name, SHARED), PartPath(name, self.realm)
	local hasShared, hasOwn = port:Exists(sharedPath), port:Exists(ownPath)
	local missing = self.spec.MissingMessage(name, hasShared, hasOwn)
	if missing then error(missing, 0) end

	self.loading[name] = true
	local ok, value = pcall(function()
		if hasShared then port:Run(sharedPath) end
		return hasOwn and RunTable(port, ownPath) or nil
	end)
	self.loading[name] = nil
	if not ok then
		-- its parts may have run in part, so it is never loaded again
		self.failed[name] = value
		error(value, 0)
	end

	local clientPart = hasShared or port:Exists(PartPath(name, CLIENT))
	self.values[name] = value
	self.loaded[name] = true
	self.hasClientPart[name] = clientPart
	self.order[#self.order + 1] = name
	if self.spec.tellsClients and clientPart then port:TellClients(name) end
	return value
end

-- The realm's part of the feature (the controller on the server, the view
-- on the client), loading it on the first call.
function Loader:Feature(name)
	if self.loaded[name] then return self.values[name] end
	if OFF[name] then error(format("feature %q is switched off (games.system.features OFF)", name), 0) end
	if self.failed[name] ~= nil then
		error(format("feature %q failed to load: %s", name, tostring(self.failed[name])), 0)
	end
	if self.loading[name] then
		error(format("feature %q is still loading: a cyclic dependency", name), 0)
	end
	return Load(self, name)
end

-- Whether the feature has loaded, without loading it.
function Loader:IsLoaded(name)
	return self.loaded[name] == true
end

-- Every loaded feature, in load order.
function Loader:Loaded()
	local list = {}
	for i, name in ipairs(self.order) do list[i] = name end
	return list
end

-- What a joining client must load: the loaded features with a client part,
-- in load order.
function Loader:ClientFeatures()
	local list = {}
	for _, name in ipairs(self.order) do
		if self.hasClientPart[name] then list[#list + 1] = name end
	end
	return list
end

-- One console line for comparing maps' Lua RAM: collectgarbage("count")
-- now, and again after a full collection.
function Loader:MemoryReport(countKB, collectedKB)
	local names = #self.order > 0 and concat(self.order, ", ") or "none"
	return format("Lua memory (%s): %d KB, %d KB after a full collection; features (%d): %s",
		self.spec.label, floor(countKB), floor(collectedKB), #self.order, names)
end
