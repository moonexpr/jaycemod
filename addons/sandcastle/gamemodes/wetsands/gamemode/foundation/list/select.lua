-- Which item of a list a score or an order picks. A lower score is better and
-- an item that goes before another is the better; ties go to the earlier
-- item, so no pick depends on how a sort breaks them.
--   Lowest(list, score[, keep]) -> item, score, place   (nil for none)
--   Highest(list, score[, keep]) -> item, score, place  (the same, the highest)
--   Nearest(list, from, position[, keep]) -> item, distance, place
--   TopK(list, k, before) -> the first k items in order, a fresh list
--   Order(list, before) -> the items' places, in order
--   Ranks(list, before) -> each item's place in the order, from 1
-- keep(item, place) leaves an item out before it is scored. position(item)
-- is an item's point { x, y, z } (the item itself without it; a missing z is
-- 0). before(a, b) is whether a goes strictly before b. The list is left as
-- it is.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, floor, ipairs, tostring, type = error, math.floor, ipairs, tostring, type
local sqrt = math.sqrt
module(...)

function Lowest(list, score, keep)
	local best, bestScore, bestPlace
	for place, item in ipairs(list) do
		if not keep or keep(item, place) then
			local s = score(item)
			if bestScore == nil or s < bestScore then best, bestScore, bestPlace = item, s, place end
		end
	end
	return best, bestScore, bestPlace
end

function Highest(list, score, keep)
	local best, bestScore, bestPlace
	for place, item in ipairs(list) do
		if not keep or keep(item, place) then
			local s = score(item)
			if bestScore == nil or s > bestScore then best, bestScore, bestPlace = item, s, place end
		end
	end
	return best, bestScore, bestPlace
end

function Nearest(list, from, position, keep)
	local fx, fy, fz = from.x, from.y, from.z or 0
	local best, bestDistance, bestPlace
	for place, item in ipairs(list) do
		if not keep or keep(item, place) then
			local p = position and position(item) or item
			local dx, dy, dz = p.x - fx, p.y - fy, (p.z or 0) - fz
			local distance = sqrt(dx * dx + dy * dy + dz * dz)
			if bestDistance == nil or distance < bestDistance then best, bestDistance, bestPlace = item, distance, place end
		end
	end
	return best, bestDistance, bestPlace
end

function TopK(list, k, before)
	if type(k) ~= "number" or k < 0 or floor(k) ~= k then
		error("TopK takes a whole number of at least 0, not " .. tostring(k), 2)
	end
	local top, size = {}, 0
	if k == 0 then return top end
	for _, item in ipairs(list) do
		-- the first place whose item `item` goes strictly before: after every tie
		local low, high = 1, size + 1
		while low < high do
			local middle = floor((low + high) / 2)
			if before(item, top[middle]) then high = middle else low = middle + 1 end
		end
		if low <= k then
			for i = (size < k and size or k - 1), low, -1 do top[i + 1] = top[i] end
			top[low] = item
			if size < k then size = size + 1 end
		end
	end
	return top
end

-- A stable merge sort of places: the earlier of two that tie stays first.
function Order(list, before)
	local n = 0
	for _ in ipairs(list) do n = n + 1 end
	local order, spare = {}, {}
	for i = 1, n do order[i] = i end
	local width = 1
	while width < n do
		for start = 1, n, width * 2 do
			local middle, stop = start + width, start + width * 2
			if middle > n + 1 then middle = n + 1 end
			if stop > n + 1 then stop = n + 1 end
			local a, b, out = start, middle, start
			while a < middle and b < stop do
				if before(list[order[b]], list[order[a]]) then
					spare[out] = order[b]
					b = b + 1
				else
					spare[out] = order[a]
					a = a + 1
				end
				out = out + 1
			end
			while a < middle do spare[out] = order[a]; a = a + 1; out = out + 1 end
			while b < stop do spare[out] = order[b]; b = b + 1; out = out + 1 end
		end
		order, spare = spare, order
		width = width * 2
	end
	return order
end

function Ranks(list, before)
	local ranks = {}
	for rank, place in ipairs(Order(list, before)) do ranks[place] = rank end
	return ranks
end
