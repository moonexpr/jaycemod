-- A binary heap: New(before) orders its values by before(a, b), true when a
-- comes out ahead of b. The heap keeps no order among values the rule calls
-- equal, so a rule that needs one breaks the tie itself (a push count).
--   heap:Push(value), heap:Pop() -> the first value or nil,
--   heap:Peek() -> the first value, left in, or nil, heap:Size()
local setmetatable = setmetatable
module(...)

local Heap = {}
Heap.__index = Heap

function New(before)
	return setmetatable({
		before = before,
		n = 0,
		values = {},
	}, Heap)
end

function Heap:Size()
	return self.n
end

function Heap:Peek()
	return self.values[1]
end

function Heap:Push(value)
	local values, before = self.values, self.before
	local n = self.n + 1
	self.n = n
	while n > 1 do
		local parent = (n - n % 2) / 2
		if not before(value, values[parent]) then break end
		values[n] = values[parent]
		n = parent
	end
	values[n] = value
end

function Heap:Pop()
	if self.n == 0 then return nil end
	local values, before = self.values, self.before
	local top, last = values[1], values[self.n]
	values[self.n] = nil
	self.n = self.n - 1
	local n, i = self.n, 1
	while true do
		local child = i * 2
		if child > n then break end
		if child < n and before(values[child + 1], values[child]) then child = child + 1 end
		if not before(values[child], last) then break end
		values[i] = values[child]
		i = child
	end
	if n > 0 then values[i] = last end
	return top
end
