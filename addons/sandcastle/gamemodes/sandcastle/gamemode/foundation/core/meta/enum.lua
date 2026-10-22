-- Enumerations: a foundation.core.meta.constants set whose names are
-- numbered in order, from a first value the caller gives (TF2's and the
-- engine's lists start at 0, Lua's at 1), so the number a convar, a net
-- message or a saved file carries maps back to its name.
--   New(name, first, names) -> an enumeration: names (upper case,
--     distinct) worth first, first + 1, ...; first a whole number
--   enum.NAME          its value, as any constant set reads
--   enum[value]        the value's name, or nil (enum:NameOf(value))
--   enum(token)        a value or a name from outside parsed into its
--                      value, or nil (enum:Valid(value): enum(value) ~= nil)
--   enum:Check(value)  value, or an error blamed on the caller: a value
--                      outside it is our bug
--   tostring(enum)     "0 Default, 1 Electro, ...", each name in words
--                      (TEAM_RED: "Team red"), for a help text
--                      (enum:Describe())
--   enum:First(), enum:Last(), enum:Count() (#enum where # honours __len):
--                      a convar's bounds
--   enum:Names()       the names in value order, a fresh list
local Class = require("foundation.core.meta.class")
local Constants = require("foundation.core.meta.constants")
local concat, error, floor, ipairs, rawget, setmetatable, tostring, type = table.concat, error, math.floor, ipairs, rawget, setmetatable, tostring, type
local gsub, lower, sub = string.gsub, string.lower, string.sub
module(...)

-- Each enumeration's numbering, apart from its constants.
local state = setmetatable({}, { __mode = "k" })

local ConstantSet = Constants.ConstantSet
local Lookup, ParseName = rawget(ConstantSet, "__index"), rawget(ConstantSet, "__call")

local function Words(name)
	return sub(name, 1, 1) .. lower((gsub(sub(name, 2), "_", " ")))
end

local function NameOf(enum, value)
	return state[enum].byValue[value]
end

local function Parse(enum, token)
	if type(token) == "number" then
		if state[enum].byValue[token] ~= nil then return token end
		return nil
	end
	return ParseName(enum, token)
end

local function Count(enum)
	return #state[enum].names
end

local function Describe(enum)
	local own, parts = state[enum], {}
	for i, name in ipairs(own.names) do parts[i] = (own.first + i - 1) .. " " .. Words(name) end
	return concat(parts, ", ")
end

Enum = Class.Extend(ConstantSet, {
	__index = function(enum, key)
		if type(key) == "number" then return NameOf(enum, key) end
		return Lookup(enum, key)
	end,
	__call = Parse,
	__len = Count,
	__tostring = Describe,
	Init = function(self, _, _, names, first)
		local byValue = {}
		for i, name in ipairs(names) do byValue[first + i - 1] = name end
		state[self] = {
			first = first,
			names = names,
			byValue = byValue,
		}
	end,
	NameOf = NameOf,
	Valid = function(self, value) return Parse(self, value) ~= nil end,
	Check = function(self, value)
		if type(value) ~= "number" or Parse(self, value) == nil then
			error(self:Name() .. ": no value " .. tostring(value), 2)
		end
		return value
	end,
	First = function(self) return state[self].first end,
	Last = function(self) return state[self].first + Count(self) - 1 end,
	Count = Count,
	Names = function(self)
		local list = {}
		for i, name in ipairs(state[self].names) do list[i] = name end
		return list
	end,
	Describe = Describe,
})

function New(name, first, names)
	if type(first) ~= "number" or floor(first) ~= first then
		error(tostring(name) .. ": an enumeration's first value is a whole number, not " .. tostring(first), 2)
	end
	if type(names) ~= "table" or #names == 0 then error(tostring(name) .. ": an enumeration needs names", 2) end
	local constants, copy = {}, {}
	for i, n in ipairs(names) do
		if constants[n] ~= nil then error(tostring(name) .. ": " .. tostring(n) .. " is named twice", 2) end
		constants[n], copy[i] = first + i - 1, n
	end
	return Class.Construct(Enum, name, constants, copy, first)
end
