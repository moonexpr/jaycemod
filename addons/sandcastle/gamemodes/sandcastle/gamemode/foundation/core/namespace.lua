-- The global tables the gamemode's modules are published in: list.queue,
-- math.geometry. A namespace's index (foundation/<name>/sh_index.lua) fills
-- its table one explicit call a key, never in a loop, so every key it
-- sets, and every default it replaces, is a line someone wrote.
--
-- Namespace(globals, name) -> globals[name], made when absent; a global of
--   that name that is not a table is refused
-- Export(ns, key, value)   ns[key] = value. Refuses a key something else
--   holds: the GMod or Lua default stays unless replaced on purpose
-- Replace(ns, key, value)  the same over a key that is taken: the declared
--   replacement of a default. Refuses a key nothing holds
-- Environment(globals, require) -> the environment an index runs in:
--   Namespace (on globals), Export, Replace, require, and the globals
--
-- A key once exported or replaced is the namespace's own: setting it again
-- (a live reload runs the index again) is not refused. Which keys those are
-- is kept on this module's table, which module(...) keeps across a reload.
local error, rawget, setmetatable, tostring, type = error, rawget, setmetatable, tostring, type
local match = string.match
module(...)

-- An error is the index line's: the caller of Export or Replace.
local CALLER = 3

-- namespace table -> its name, for errors
Names = Names or setmetatable({}, { __mode = "k" })
-- namespace table -> { key = true } for each key set by Export or Replace
Owned = Owned or setmetatable({}, { __mode = "k" })

local function NameOf(ns, key)
	return (Names[ns] or tostring(ns)) .. "." .. tostring(key)
end

local function Owns(ns, key)
	local keys = Owned[ns]
	return keys ~= nil and keys[key] == true
end

local function Set(ns, key, value)
	local keys = Owned[ns]
	if keys == nil then
		keys = {}
		Owned[ns] = keys
	end
	keys[key] = true
	ns[key] = value
end

local function CheckSet(ns, key, value)
	if type(ns) ~= "table" then error("a namespace is a table, not " .. tostring(ns), CALLER) end
	if type(key) ~= "string" or not match(key, "^[%a_][%w_]*$") then
		error(NameOf(ns, key) .. ": a key is a name", CALLER)
	end
	if value == nil then error(NameOf(ns, key) .. " is set to nothing", CALLER) end
end

function Namespace(globals, name)
	local ns = rawget(globals, name)
	if ns == nil then
		ns = {}
		globals[name] = ns
	elseif type(ns) ~= "table" then
		error("global " .. name .. " is a " .. type(ns) .. ", not a namespace", 2)
	end
	Names[ns] = Names[ns] or name
	return ns
end

function Export(ns, key, value)
	CheckSet(ns, key, value)
	if rawget(ns, key) ~= nil and not Owns(ns, key) then
		error(NameOf(ns, key) .. " is taken; Replace it to take it over on purpose", 2)
	end
	Set(ns, key, value)
end

function Replace(ns, key, value)
	CheckSet(ns, key, value)
	if rawget(ns, key) == nil then error(NameOf(ns, key) .. " holds nothing to replace; Export it", 2) end
	Set(ns, key, value)
end

function Environment(globals, require)
	Names[globals] = "_G"
	return setmetatable({
		Namespace = function(name) return Namespace(globals, name) end,
		Export = Export,
		Replace = Replace,
		require = require,
	}, { __index = globals })
end
