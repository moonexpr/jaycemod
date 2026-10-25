-- A store of named whole-number values, each held to a range and guarded
-- by what the caller names (a privilege, a role): the settings a caller
-- lets someone change, parsed from the text they send.
--
-- New(name) -> a store; name is what a refusal calls it. The store:
--   Range(key, min, max, guard)  stores a key taking min..max (whole numbers)
--   Switch(key, guard)           stores a key taking 0 or 1
--   store[key]                   the key's entry, read-only: min, max, guard;
--                                nil for a key not stored (Get, for a key
--                                named like a method)
--   Has(key)                     whether the key is stored
--   for key, entry in store()    every key, in key order (Keys)
--   Size() (__len), tostring
--   Allowed(key, holds)          whether one for whom holds(guard) is true
--                                may change the key; false for one not stored
--   Parse(key, text)             the key's text for the number text names,
--                                rounded to a whole number, or nil and why
-- Storing a key twice, an empty or fractional range, or a key or guard
-- that is not a name is the caller's mistake.
-- Core-rule exception: stays Lua. Read when a menu opens or a setting
-- changes, with guards that are Lua predicates; nothing per tick.
local error, floor, format, setmetatable, sort, tonumber, tostring, type =
	error, math.floor, string.format, setmetatable, table.sort, tonumber, tostring, type
module(...)

-- Range and Switch store through Add: Add's error blames their caller.
local CALLER_OF_METHOD = 3

-- store -> { name, entries = { key -> entry }, keys = sorted list }
State = State or setmetatable({}, { __mode = "k" })

local Store = {}

-- An assignment to a store or an entry: blames the assignment.
local function ReadOnly()
	error("a configstore and its entries are changed only by Range and Switch", 2)
end

local function Entry(min, max, guard)
	return setmetatable({}, {
		__index = {
			min = min,
			max = max,
			guard = guard,
		},
		__newindex = ReadOnly,
	})
end

local function IsName(value)
	return type(value) == "string" and value ~= ""
end

local function IsWhole(value)
	return type(value) == "number" and value == floor(value)
end

local Meta = {
	__index = function(store, key)
		local method = Store[key]
		if method ~= nil then return method end
		return State[store].entries[key]
	end,
	__newindex = ReadOnly,
	__call = function(store)
		return store:Keys()
	end,
	__len = function(store)
		return store:Size()
	end,
	__tostring = function(store)
		return format("configstore %s (%d)", State[store].name, store:Size())
	end,
}

function New(name)
	if not IsName(name) then error("a configstore needs a name, not " .. tostring(name), 2) end
	local store = setmetatable({}, Meta)
	State[store] = {
		name = name,
		entries = {},
		keys = {},
	}
	return store
end

local function Add(store, key, min, max, guard)
	local state = State[store]
	if not IsName(key) then error(state.name .. ": a key is a name, not " .. tostring(key), CALLER_OF_METHOD) end
	if state.entries[key] then error(state.name .. ": " .. key .. " is stored already", CALLER_OF_METHOD) end
	if not IsWhole(min) or not IsWhole(max) or min > max then
		error(format("%s: %s needs a whole-number range, not %s to %s", state.name, key, tostring(min), tostring(max)), CALLER_OF_METHOD)
	end
	if not IsName(guard) then error(state.name .. ": " .. key .. " needs a guard, not " .. tostring(guard), CALLER_OF_METHOD) end
	state.entries[key] = Entry(min, max, guard)
	state.keys[#state.keys + 1] = key
	sort(state.keys)
	return store
end

function Store:Range(key, min, max, guard)
	return Add(self, key, min, max, guard)
end

function Store:Switch(key, guard)
	return Add(self, key, 0, 1, guard)
end

function Store:Get(key)
	return State[self].entries[key]
end

function Store:Has(key)
	return State[self].entries[key] ~= nil
end

function Store:Size()
	return #State[self].keys
end

function Store:Keys()
	local state = State[self]
	local i = 0
	return function()
		i = i + 1
		local key = state.keys[i]
		if key ~= nil then return key, state.entries[key] end
	end
end

function Store:Allowed(key, holds)
	local entry = State[self].entries[key]
	return entry ~= nil and holds(entry.guard) == true
end

function Store:Parse(key, text)
	local state = State[self]
	local entry = state.entries[key]
	if not entry then return nil, format("%s is not one of %s", tostring(key), state.name) end
	local number = tonumber(text)
	if not number then return nil, format("%s takes a number, not %q", key, tostring(text)) end
	local value = floor(number + 0.5)
	if value < entry.min or value > entry.max then
		return nil, format("%s takes %d to %d", key, entry.min, entry.max)
	end
	return format("%d", value)
end
