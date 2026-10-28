-- Shuffling and drawing from a list with a random source the caller gives,
-- randomInt(low, high) -> a whole number from low to high (as an NPC's
-- RandomInt), so a test can script it and the game can seed it. Neither
-- touches the list it is given. A source that answers outside the range
-- asked is our bug, refused.
--   Shuffle(list, randomInt) -> a new list of the items in random order: the
--     last place swaps with one drawn from 1 to its own, then the one before
--     it, down to the second
--   Draw(list, count, randomInt) -> a new list of up to count items drawn
--     without replacement, each drawn from those left and replaced in the
--     pool by the last one; count a whole number of at least 0
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, floor, ipairs, tostring, type = error, math.floor, ipairs, tostring, type
module(...)

local CALLER_OF_ENTRY = 3

local function Place(randomInt, n)
	local k = randomInt(1, n)
	if type(k) ~= "number" or k < 1 or k > n or floor(k) ~= k then
		error("the random source gave " .. tostring(k) .. " for 1 to " .. n, CALLER_OF_ENTRY)
	end
	return k
end

local function Copy(list)
	local copy = {}
	for i, item in ipairs(list) do copy[i] = item end
	return copy
end

function Shuffle(list, randomInt)
	local out = Copy(list)
	local n = #out
	while n > 1 do
		local k = Place(randomInt, n)
		out[n], out[k] = out[k], out[n]
		n = n - 1
	end
	return out
end

function Draw(list, count, randomInt)
	if type(count) ~= "number" or count < 0 or floor(count) ~= count then
		error("a draw's count is a whole number of at least 0, not " .. tostring(count), 2)
	end
	local pool, out, left = Copy(list), {}, 0
	left = #pool
	while left > 0 and #out < count do
		local k = Place(randomInt, left)
		out[#out + 1] = pool[k]
		pool[k] = pool[left]
		pool[left] = nil
		left = left - 1
	end
	return out
end
