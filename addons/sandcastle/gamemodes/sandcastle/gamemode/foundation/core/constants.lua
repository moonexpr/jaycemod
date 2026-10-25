-- Constant sets: a closed, fixed set of named constants (a menu's layout
-- sizes and colours, a mode's tuning), read as fields at the speed of a
-- plain table, where a misspelt name is caught as it is read instead of
-- passing on as nil.
--
-- ConstantSet is a class (foundation.core.class); New(name, constants)
-- makes one from upper-case names to values (anything but nil; two names
-- may share a value), refusing one without a name or constants:
--   set.NAME          the constant; a name the set lacks is our bug, an
--                     error "<set>: no constant NAME" blamed on the reader
--   set.NEW = value   refused: the set takes no new names
--   set(token)        the constant a name from outside (a console argument,
--                     a saved file) stands for, or nil, unrefused
--   pairs(set)        exactly its constants
--   set:Has(name)     whether it names a constant (set(name) ~= nil)
--   set:Names()       the names, sorted, a fresh list
--   tostring(set), set:Name()  what errors call it
--   #set              how many it has, where # honours __len (userdata;
--                     plain tables under LuaJIT do not)
-- Lua 5.1 cannot catch rebinding a name the set already has without
-- slowing every read, so the set only refuses new names and unknown reads.
-- Methods are CamelCase and constants upper-case, so the two never meet.
-- Core-rule exception: stays Lua. A constant read is one plain-table index
-- by design, faster than any call.
local Class = core.class
local error, getmetatable, next, pairs, rawget, rawset, setmetatable, sort, tostring, type = error, getmetatable, next, pairs, rawget, rawset, setmetatable, table.sort, tostring, type
local match = string.match
module(...)

-- Init runs under Construct, under a module's New: this blames New's caller.
local NEW_CALLER = 4

-- Each set's own state, apart from its constants, so pairs gives only those.
local state = setmetatable({}, { __mode = "k" })

local function NameOf(set)
	local own = state[set]
	return own and own.name or tostring(set)
end

local function Lookup(set, key)
	local class = getmetatable(set)
	while class do
		local method = rawget(class, key)
		if method ~= nil then return method end
		class = getmetatable(class)
	end
	error(NameOf(set) .. ": no constant " .. tostring(key), 2)
end

local function Fixed(set, key)
	error(NameOf(set) .. ": constants are fixed, no new " .. tostring(key), 2)
end

local function IsName(key)
	return type(key) == "string" and match(key, "^[A-Z][A-Z0-9_]*$") ~= nil
end

local function Parse(set, token)
	return rawget(set, token)
end

local function Name(set)
	return state[set].name
end

ConstantSet = Class.Extend(nil, {
	__index = Lookup,
	__newindex = Fixed,
	__call = Parse,
	__tostring = Name,
	__len = function(set) return state[set].count end,
	Name = Name,
})

function ConstantSet:Init(name, constants)
	if type(name) ~= "string" or name == "" then error("a constant set needs a name", NEW_CALLER) end
	if type(constants) ~= "table" or next(constants) == nil then error(name .. ": a constant set needs constants", NEW_CALLER) end
	local count = 0
	for key, value in pairs(constants) do
		if not IsName(key) then error(name .. ": a constant's name is upper case, not " .. tostring(key), NEW_CALLER) end
		rawset(self, key, value)
		count = count + 1
	end
	state[self] = {
		name = name,
		count = count,
	}
end

function ConstantSet:Has(name)
	return Parse(self, name) ~= nil
end

function ConstantSet:Names()
	local names = {}
	for key in pairs(self) do names[#names + 1] = key end
	sort(names)
	return names
end

function New(name, constants)
	return Class.Construct(ConstantSet, name, constants)
end
