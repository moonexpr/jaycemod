-- Ranges [low, high] of one number line.
--   Overlaps(alo, ahi, blo, bhi) -> whether they share a point; touching
--     at one counts
--   Intersect(alo, ahi, blo, bhi) -> low, high of what they share: the
--     highest low and the lowest high, so low is above high when they are
--     apart
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
module(...)

function Overlaps(alo, ahi, blo, bhi)
	return alo <= bhi and blo <= ahi
end

function Intersect(alo, ahi, blo, bhi)
	return alo > blo and alo or blo, ahi < bhi and ahi or bhi
end
