-- Per-map lazy loading of controllers and views (WETSAND.Feature). A feature
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
local error, format, ipairs, setmetatable, type = error, string.format, ipairs, setmetatable, type
local concat = table.concat
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
	if hasShared then port:Run(sharedPath) end
	local value = hasOwn and RunTable(port, ownPath) or nil
	self.loading[name] = nil

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
	if OFF[name] then error(format("feature %q is switched off (foundation.features OFF)", name), 0) end
	if self.loading[name] then
		error(format("feature %q is still loading: a cyclic dependency, or its load failed", name), 0)
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
