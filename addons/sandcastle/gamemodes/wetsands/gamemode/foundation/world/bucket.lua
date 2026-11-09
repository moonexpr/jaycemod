-- A token bucket: limits how often something may happen. It holds up to
-- `capacity` tokens, starts full, and refills at capacity per `seconds`; a
-- take spends one, or is refused when under one is held.
--   New(capacity, seconds, now) -> a bucket full at time now; capacity a
--     number of at least 1, seconds above 0, now the time in seconds
--   bucket:Take(now) -> whether a token was spent; a refusal spends nothing
--   bucket:Tokens(now) -> how many it holds at now (fractions count), not
--     spent
-- Time is the caller's and does not go back.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, setmetatable, tostring, type = error, setmetatable, tostring, type
module(...)

local Bucket = {}
Bucket.__index = Bucket

function New(capacity, seconds, now)
	if type(capacity) ~= "number" or not (capacity >= 1) then
		error("a bucket's capacity is a number of at least 1, not " .. tostring(capacity), 2)
	end
	if type(seconds) ~= "number" or not (seconds > 0) then
		error("a bucket's seconds are a number above 0, not " .. tostring(seconds), 2)
	end
	if type(now) ~= "number" then error("a bucket starts at a time, not " .. tostring(now), 2) end
	return setmetatable({ capacity = capacity, seconds = seconds, tokens = capacity, at = now }, Bucket)
end

local function Refill(bucket, now)
	local tokens = bucket.tokens + (now - bucket.at) * bucket.capacity / bucket.seconds
	if tokens > bucket.capacity then tokens = bucket.capacity end
	bucket.tokens, bucket.at = tokens, now
	return tokens
end

function Bucket:Take(now)
	local tokens = Refill(self, now)
	if tokens < 1 then return false end
	self.tokens = tokens - 1
	return true
end

function Bucket:Tokens(now)
	return Refill(self, now)
end
