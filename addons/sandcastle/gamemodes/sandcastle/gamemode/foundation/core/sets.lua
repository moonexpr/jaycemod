-- Named sets: a closed vocabulary (a module's reasons, kinds, privileges,
-- layers), parsed once from its list, so a value outside it is caught where
-- it is used rather than passing as an unknown member.
--
-- Named(name, members) refuses a set without a name or members, or one that
-- lists a member twice, and keeps its own copy of the list. The set:
--   set:Has(value)     whether value is a member
--   set:Check(value)   value, or an error "<name>: unknown <value>" blamed on
--                      the caller of the function that checks: an unknown
--                      member is a bug in our code, not a player's refusal
--   set:Match(token)   the first member whose name starts with token,
--                      ignoring case, or nil
--   set:Members()      the members in order, a fresh list
--   set:Name()         what errors call it
local error, ipairs, setmetatable, tostring, type = error, ipairs, setmetatable, tostring, type
local sub, upper = string.sub, string.upper
module(...)

-- Check blames the function that called the one checking.
local CALLER_OF_CHECKER = 3

local NamedSet = {}
NamedSet.__index = NamedSet

local function Refuse(name, why)
	error("named set " .. tostring(name) .. ": " .. why, 3)
end

function Named(name, members)
	if type(name) ~= "string" or name == "" then Refuse(name, "needs a name") end
	if type(members) ~= "table" or #members == 0 then Refuse(name, name .. ": lists no members") end
	local set = setmetatable({
		name = name,
		list = {},
		has = {},
	}, NamedSet)
	for i, member in ipairs(members) do
		if set.has[member] then Refuse(name, name .. ": lists " .. tostring(member) .. " twice") end
		set.has[member] = true
		set.list[i] = member
	end
	return set
end

function NamedSet:Has(value)
	return value ~= nil and self.has[value] == true
end

function NamedSet:Check(value)
	if not self:Has(value) then error(self.name .. ": unknown " .. tostring(value), CALLER_OF_CHECKER) end
	return value
end

function NamedSet:Match(token)
	if token == "" then return nil end
	local wanted = upper(token)
	for _, member in ipairs(self.list) do
		if upper(sub(tostring(member), 1, #token)) == wanted then return member end
	end
	return nil
end

function NamedSet:Members()
	local copy = {}
	for i, member in ipairs(self.list) do copy[i] = member end
	return copy
end

function NamedSet:Name()
	return self.name
end
