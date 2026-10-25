-- A ring: the last `capacity` values pushed, the oldest dropped for each new
-- one past it. Pushing allocates nothing once the ring is full, so a ring
-- can sample per-tick work.
--   New(capacity), ring:Push(value), ring:Size(),
--   ring:Ordered() -> the values, oldest first, a fresh list
-- Core-rule exception: stays Lua. A push costs 6.8 ns JIT-compiled; a call
-- into native/foundation costs about 15 ns (20 on the dev server;
-- docs/native-foundation-plan.md), so a native twin could only be slower.
local error, floor, setmetatable, tostring, type = error, math.floor, setmetatable, tostring, type
local min = math.min
module(...)

local Ring = {}
Ring.__index = Ring

function New(capacity)
	if type(capacity) ~= "number" or capacity < 1 or floor(capacity) ~= capacity then
		error("a ring's capacity is a whole number of at least 1, not " .. tostring(capacity), 2)
	end
	return setmetatable({
		capacity = capacity,
		values = {},
		next = 1,
		size = 0,
	}, Ring)
end

function Ring:Push(value)
	self.values[self.next] = value
	self.next = self.next % self.capacity + 1
	self.size = min(self.size + 1, self.capacity)
end

function Ring:Size()
	return self.size
end

function Ring:Ordered()
	local list, capacity = {}, self.capacity
	local start = self.size < capacity and 1 or self.next
	for i = 0, self.size - 1 do list[#list + 1] = self.values[(start + i - 1) % capacity + 1] end
	return list
end
