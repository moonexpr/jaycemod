-- A pair map: values kept by an ordered pair of whole numbers (a link's two
-- nav area ids), on a plain table under one number per pair,
-- a * 2^26 + b: exact in a double for keys up to MAX_KEY, so no two pairs
-- share a key and a lookup builds no string.
--   New(), map:Get(a, b), map:Set(a, b, value) (nil removes), map:Size(),
--   map:Clear()
--   Unordered() -> the same, for an unordered pair: (a, b) and (b, a) are
--     one pair (a link seen from either end)
-- Set refuses a key that is no whole number in 0..MAX_KEY; Get, on hot
-- paths, takes the same keys unchecked.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, floor, setmetatable, tostring, type = error, math.floor, setmetatable, tostring, type
module(...)

local SPAN = 2 ^ 26
MAX_KEY = SPAN - 1

local PairMap = {}
PairMap.__index = PairMap

function New()
	return setmetatable({ values = {}, size = 0 }, PairMap)
end

local function Check(key)
	if type(key) ~= "number" or key < 0 or key > MAX_KEY or floor(key) ~= key then
		error("a pair map's key is a whole number from 0 to " .. MAX_KEY .. ", not " .. tostring(key), 3)
	end
end

function PairMap:Get(a, b)
	return self.values[a * SPAN + b]
end

local function Put(self, a, b, value)
	local key = a * SPAN + b
	local had = self.values[key] ~= nil
	self.values[key] = value
	if had and value == nil then
		self.size = self.size - 1
	elseif not had and value ~= nil then
		self.size = self.size + 1
	end
end

function PairMap:Set(a, b, value)
	Check(a)
	Check(b)
	Put(self, a, b, value)
end

function PairMap:Size()
	return self.size
end

function PairMap:Clear()
	self.values, self.size = {}, 0
end

local UnorderedMap = setmetatable({}, { __index = PairMap })
UnorderedMap.__index = UnorderedMap

function UnorderedMap:Get(a, b)
	if a > b then a, b = b, a end
	return self.values[a * SPAN + b]
end

function UnorderedMap:Set(a, b, value)
	Check(a)
	Check(b)
	if a > b then a, b = b, a end
	Put(self, a, b, value)
end

function Unordered()
	return setmetatable({ values = {}, size = 0 }, UnorderedMap)
end
