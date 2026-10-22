-- Slots: whole numbers handed out to holders and taken back, the lowest
-- never handed out first and a freed one before any new one. A structure
-- that keeps its entries in arrays (struct of arrays) indexes them by slot,
-- so an entry costs no table of its own and a freed entry's room is reused.
--   New(), pool() -> a slot (pool:Alloc()), pool:Free(slot),
--   pool:InUse(slot), pool:Size() (slots in use; #pool where # honours
--   __len), pool:High() (the most ever handed out), pool:Clear() (every
--   slot taken back), tostring(pool)
-- Freeing a slot not in use is our bug, refused.
local error, setmetatable, tostring = error, setmetatable, tostring
module(...)

local Slots = {}
Slots.__index = Slots

function New()
	return setmetatable({
		used = {}, -- slot -> true while held
		free = {}, -- freed slots, the last freed on top
		high = 0,
		size = 0,
	}, Slots)
end

local function Alloc(pool)
	local free = pool.free
	local slot = free[#free]
	if slot then
		free[#free] = nil
	else
		slot = pool.high + 1
		pool.high = slot
	end
	pool.used[slot] = true
	pool.size = pool.size + 1
	return slot
end

local function Size(pool)
	return pool.size
end

Slots.__call = Alloc
Slots.__len = Size
Slots.__tostring = function(pool) return "slots: " .. pool.size .. " in use of " .. pool.high end
Slots.Alloc = Alloc
Slots.Size = Size

function Slots:Free(slot)
	if not self.used[slot] then error("slot " .. tostring(slot) .. " is not in use", 2) end
	self.used[slot] = nil
	self.free[#self.free + 1] = slot
	self.size = self.size - 1
end

function Slots:InUse(slot)
	return self.used[slot] == true
end

function Slots:High()
	return self.high
end

function Slots:Clear()
	self.used, self.free, self.high, self.size = {}, {}, 0, 0
end
