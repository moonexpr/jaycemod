-- A time window: numbers added with the time they happened, summed over the
-- last `span` seconds. Entries leave from the front as they age, so asking
-- costs what has aged out, and the sum is kept running: a damage-per-second
-- or a rate over the last few seconds without rebuilding a list each time.
--   New(span) -> a window; span a number above 0
--   window:Add(at, value)   at no earlier than the last added (time going
--                           back is the caller's mistake)
--   window:Sum(now)         the values added within span of now (an entry
--                           exactly span old counts), the older ones let go
--   window:Count(now)       how many those are
--   window:Size()           how many are held, as of the last asking
--   window:Clear()
-- The sum is kept by adding and taking away, so it can differ from adding
-- the values fresh in the last digits; an empty window starts it again at 0.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, setmetatable, tostring, type = error, setmetatable, tostring, type
module(...)

local Window = {}
Window.__index = Window

local COMPACT_AT = 256

function New(span)
	if type(span) ~= "number" or not (span > 0) then
		error("a window's span is a number above 0, not " .. tostring(span), 2)
	end
	return setmetatable({ span = span, ats = {}, values = {}, head = 1, tail = 0, sum = 0 }, Window)
end

function Window:Add(at, value)
	local tail = self.tail
	if tail >= self.head and at < self.ats[tail] then
		error("a window's entries come in time order: " .. tostring(at) .. " is before " .. tostring(self.ats[tail]), 2)
	end
	tail = tail + 1
	self.tail = tail
	self.ats[tail], self.values[tail] = at, value
	self.sum = self.sum + value
end

local function Drop(self, now)
	local ats, values, span = self.ats, self.values, self.span
	local head, tail, sum = self.head, self.tail, self.sum
	while head <= tail and now - ats[head] > span do
		sum = sum - values[head]
		ats[head], values[head] = nil, nil
		head = head + 1
	end
	if head > tail then
		head, tail, sum = 1, 0, 0
	elseif head > COMPACT_AT and head > tail / 2 then
		local newAts, newValues = {}, {}
		for i = head, tail do newAts[i - head + 1], newValues[i - head + 1] = ats[i], values[i] end
		self.ats, self.values = newAts, newValues
		head, tail = 1, tail - head + 1
	end
	self.head, self.tail, self.sum = head, tail, sum
end

function Window:Sum(now)
	Drop(self, now)
	return self.sum
end

function Window:Count(now)
	Drop(self, now)
	return self.tail - self.head + 1
end

function Window:Size()
	return self.tail - self.head + 1
end

function Window:Clear()
	self.ats, self.values, self.head, self.tail, self.sum = {}, {}, 1, 0, 0
end
