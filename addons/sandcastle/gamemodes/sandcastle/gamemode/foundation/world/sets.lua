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
--
-- Plain sets are value -> true tables. Of(list), Copy(set),
-- Union(a, b, ...), Intersect(a, b) and Subtract(a, b) make new ones;
-- Count(set) and Sorted(set) (members in sort order) read them.
-- Core-rule exception: stays Lua. Has costs 2.3 ns JIT-compiled, and the
-- members are strings; a call into native/foundation costs about 15 ns (20
-- on the dev server; docs/native-foundation-plan.md), so a native twin could
-- only be slower.
local error, ipairs, setmetatable, tostring, type = error, ipairs, setmetatable, tostring, type
local pairs, select, sort = pairs, select, table.sort
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

-- Plain sets -------------------------------------------------------------------

function Of(list)
	local set = {}
	for _, value in ipairs(list) do set[value] = true end
	return set
end

function Copy(set)
	local copy = {}
	for value in pairs(set) do copy[value] = true end
	return copy
end

function Union(...)
	local union = {}
	for i = 1, select("#", ...) do
		for value in pairs((select(i, ...))) do union[value] = true end
	end
	return union
end

function Intersect(a, b)
	local both = {}
	for value in pairs(a) do
		if b[value] then both[value] = true end
	end
	return both
end

function Subtract(a, b)
	local rest = {}
	for value in pairs(a) do
		if not b[value] then rest[value] = true end
	end
	return rest
end

function Count(set)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	return n
end

function Sorted(set)
	local list = {}
	for value in pairs(set) do list[#list + 1] = value end
	sort(list)
	return list
end
