-- A double-ended queue: values pushed and popped at either end in constant
-- time, kept between two indexes that move apart and together.
--   New(), q:PushBack(v), q:PushFront(v), q:PopFront(), q:PopBack(),
--   q:Front(), q:Back() (nil when empty), q:Size(),
--   q:Values() -> an iterator front to back (i, value)
-- Core-rule exception: stays Lua. A push or a pop costs 1.7 ns JIT-compiled;
-- a call into native/foundation costs about 15 ns (20 on the dev server;
-- docs/native-foundation-plan.md), so a native twin could only be slower.
local setmetatable = setmetatable
module(...)

local Queue = {}
Queue.__index = Queue

function New()
	return setmetatable({
		first = 1,
		last = 0,
		values = {},
	}, Queue)
end

function Queue:Size()
	return self.last - self.first + 1
end

function Queue:PushBack(value)
	self.last = self.last + 1
	self.values[self.last] = value
end

function Queue:PushFront(value)
	self.first = self.first - 1
	self.values[self.first] = value
end

function Queue:PopFront()
	if self.first > self.last then return nil end
	local value = self.values[self.first]
	self.values[self.first] = nil
	self.first = self.first + 1
	return value
end

function Queue:PopBack()
	if self.first > self.last then return nil end
	local value = self.values[self.last]
	self.values[self.last] = nil
	self.last = self.last - 1
	return value
end

function Queue:Front()
	return self.values[self.first]
end

function Queue:Back()
	if self.first > self.last then return nil end
	return self.values[self.last]
end

function Queue:Values()
	local values, first, last = self.values, self.first, self.last
	local i = 0
	return function()
		if first + i > last then return nil end
		i = i + 1
		return i, values[first + i - 1]
	end
end
