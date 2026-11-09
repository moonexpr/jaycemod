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
-- Twin(ns, key, lua)       ns[key] = lua, a foundation module with a native
--   twin (native/, docs/native-foundation-plan.md): where a binary module put
--   its native twin there first (a table holding C functions), the native
--   one is the module, whole: it must hold every key of the Lua twin's
--   (functions and constants alike, module(...)'s own keys aside), and is
--   refused naming each one it lacks; nothing of the Lua twin is mixed in.
--   Refuses a key anything else holds, as Export does
-- Defer(ns, key, load)     ns[key] is load() the first time it is read, then
--   kept: a module loaded on demand. Refuses a key something else holds, and
--   a namespace table that has a metatable of its own
-- Environment(globals, require) -> the environment an index runs in:
--   Namespace (on globals), Export, Replace, Twin, Defer (by module name),
--   require, and the globals
--
-- A key once exported, replaced or deferred is the namespace's own: setting
-- it again (a live reload runs the index again) is not refused. Which keys
-- those are is kept on this module's table, which module(...) keeps across
-- a reload.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local debug, error, getmetatable, pairs, rawget, rawset, setmetatable, tostring, type = debug, error, getmetatable, pairs, rawget, rawset, setmetatable, tostring, type
local concat, match, sort = table.concat, string.match, table.sort
module(...)

-- An error is the index line's: the caller of Export or Replace.
local CALLER = 3

-- namespace table -> its name, for errors
Names = Names or setmetatable({}, { __mode = "k" })
-- namespace table -> { key = true } for each key set by Export or Replace
Owned = Owned or setmetatable({}, { __mode = "k" })
-- namespace table -> { key = load } for each deferred key not yet read
Deferred = Deferred or setmetatable({}, { __mode = "k" })

-- The metatable of a namespace with deferred keys: a read of one loads it.
Lazy = Lazy or {}
function Lazy.__index(ns, key)
	local loads = Deferred[ns]
	local load = loads and loads[key]
	if load == nil then return nil end
	local value = load()
	loads[key] = nil
	rawset(ns, key, value)
	return value
end

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

-- Whether a binary module made value: a table holding a C function.
local function IsNative(value)
	if type(value) ~= "table" then return false end
	for _, field in pairs(value) do
		if type(field) == "function" and debug.getinfo(field, "S").what == "C" then return true end
	end
	return false
end

-- module(...)'s own keys, which a Lua twin's table holds and its native
-- twin does not take.
local MODULE_KEYS = { _M = true, _NAME = true, _PACKAGE = true }

function Twin(ns, key, lua)
	CheckSet(ns, key, lua)
	local native = rawget(ns, key)
	if not IsNative(native) then
		if native ~= nil and not Owns(ns, key) then
			error(NameOf(ns, key) .. " is taken by something other than a native twin", 2)
		end
		Set(ns, key, lua)
		return lua
	end
	local missing = {}
	for field in pairs(lua) do
		if not MODULE_KEYS[field] and rawget(native, field) == nil then missing[#missing + 1] = tostring(field) end
	end
	if #missing > 0 then
		sort(missing)
		error(NameOf(ns, key) .. ": the native twin lacks " .. concat(missing, ", "), 2)
	end
	Set(ns, key, native)
	return native
end

function Defer(ns, key, load)
	CheckSet(ns, key, load)
	if type(load) ~= "function" then error(NameOf(ns, key) .. " is deferred to a " .. type(load) .. ", not a loader", 2) end
	if rawget(ns, key) ~= nil and not Owns(ns, key) then
		error(NameOf(ns, key) .. " is taken; a deferred key needs a free one", 2)
	end
	local meta = getmetatable(ns)
	if meta == nil then
		setmetatable(ns, Lazy)
	elseif meta ~= Lazy then
		error(NameOf(ns, key) .. ": " .. (Names[ns] or tostring(ns)) .. " has a metatable of its own", 2)
	end
	local loads = Deferred[ns]
	if loads == nil then
		loads = {}
		Deferred[ns] = loads
	end
	loads[key] = load
	Set(ns, key, nil)
end

function Environment(globals, require)
	Names[globals] = "_G"
	return setmetatable({
		Namespace = function(name) return Namespace(globals, name) end,
		Export = Export,
		Replace = Replace,
		Twin = Twin,
		Defer = function(ns, key, name) return Defer(ns, key, function() return require(name) end) end,
		require = require,
	}, { __index = globals })
end
