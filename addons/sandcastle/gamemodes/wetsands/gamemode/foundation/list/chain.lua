-- A chain: slots (whole numbers from 1, as foundation.list.slots
-- hands out) in an order, each linked to its neighbours by two arrays, so a
-- member unlinks or moves to the front in constant time and linking
-- allocates no node. The caller keeps what each slot stands for.
--   New(), chain:PushFront(slot), chain:PushBack(slot), chain:Unlink(slot),
--   chain:MoveFront(slot), chain:Front(), chain:Back(), chain:After(slot),
--   chain:Before(slot) (nil past either end), chain:Has(slot),
--   for slot in chain() do: the members front to back, the loop not
--   changing the chain; chain:Ordered() -> them as a fresh list,
--   chain:Size() (#chain where # honours __len), chain:Clear(),
--   tostring(chain)
-- Linking a member twice, unlinking a stranger or a slot that is no whole
-- number of at least 1 is our bug, refused.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local concat, error, floor, setmetatable, tostring, type = table.concat, error, math.floor, setmetatable, tostring, type
module(...)

-- Past either end; never a slot.
local NONE = 0

local Chain = {}
Chain.__index = Chain

function New()
	return setmetatable({
		prev = {},
		next = {},
		front = NONE,
		back = NONE,
		size = 0,
	}, Chain)
end

local function Refuse(why, slot)
	error("a chain's " .. why .. ": " .. tostring(slot), 3)
end

local function CheckOutside(chain, slot)
	if type(slot) ~= "number" or slot < 1 or floor(slot) ~= slot then Refuse("member is a whole number of at least 1", slot) end
	if chain.next[slot] ~= nil then Refuse("member is linked once", slot) end
end

local function CheckInside(chain, slot)
	if chain.next[slot] == nil then Refuse("stranger cannot unlink", slot) end
end

local function LinkFront(chain, slot)
	local front = chain.front
	chain.prev[slot], chain.next[slot] = NONE, front
	if front == NONE then chain.back = slot else chain.prev[front] = slot end
	chain.front = slot
	chain.size = chain.size + 1
end

local function Detach(chain, slot)
	local before, after = chain.prev[slot], chain.next[slot]
	if before == NONE then chain.front = after else chain.next[before] = after end
	if after == NONE then chain.back = before else chain.prev[after] = before end
	chain.prev[slot], chain.next[slot] = nil, nil
	chain.size = chain.size - 1
end

function Chain:PushFront(slot)
	CheckOutside(self, slot)
	LinkFront(self, slot)
end

function Chain:PushBack(slot)
	CheckOutside(self, slot)
	local back = self.back
	self.prev[slot], self.next[slot] = back, NONE
	if back == NONE then self.front = slot else self.next[back] = slot end
	self.back = slot
	self.size = self.size + 1
end

function Chain:Unlink(slot)
	CheckInside(self, slot)
	Detach(self, slot)
end

function Chain:MoveFront(slot)
	CheckInside(self, slot)
	if self.front == slot then return end
	Detach(self, slot)
	LinkFront(self, slot)
end

local function Member(slot)
	if slot == NONE then return nil end
	return slot
end

function Chain:Front() return Member(self.front) end
function Chain:Back() return Member(self.back) end
function Chain:After(slot) return Member(self.next[slot]) end
function Chain:Before(slot) return Member(self.prev[slot]) end

function Chain:Has(slot)
	return self.next[slot] ~= nil
end

local function Walk(chain)
	local next, slot = chain.next, chain.front
	return function()
		if slot == NONE then return nil end
		local member = slot
		slot = next[slot]
		return member
	end
end

local function Size(chain)
	return chain.size
end

function Chain:Ordered()
	local list = {}
	for slot in Walk(self) do list[#list + 1] = slot end
	return list
end

Chain.__call = Walk
Chain.__len = Size
Chain.__tostring = function(chain) return "chain: " .. concat(chain:Ordered(), " ") end
Chain.Size = Size

function Chain:Clear()
	self.prev, self.next, self.front, self.back, self.size = {}, {}, NONE, NONE, 0
end
