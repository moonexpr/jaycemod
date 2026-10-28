-- Axis-aligned boxes, by their two corners (mins, maxs) as { x, y, z } points
-- or GMod Vectors; a point without a z lies on z = 0.
--   Overlaps(aMins, aMaxs, bMins, bMaxs) -> whether they share a point on
--     all three axes; touching counts
--   Contains(mins, maxs, p) -> whether p is in the box, its faces included
--   Extent(points) -> mins, maxs of the smallest box around them; nothing
--     for no points
--   LongestAxis2D(mins, maxs) -> "x" or "y", whichever the box is longer
--     along across the ground; "x" on a tie
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local ipairs = ipairs
module(...)

function Overlaps(aMins, aMaxs, bMins, bMaxs)
	return aMins.x <= bMaxs.x and bMins.x <= aMaxs.x and aMins.y <= bMaxs.y and bMins.y <= aMaxs.y
		and (aMins.z or 0) <= (bMaxs.z or 0) and (bMins.z or 0) <= (aMaxs.z or 0)
end

function Contains(mins, maxs, p)
	local z = p.z or 0
	return p.x >= mins.x and p.x <= maxs.x and p.y >= mins.y and p.y <= maxs.y and z >= (mins.z or 0) and z <= (maxs.z or 0)
end

function Extent(points)
	local first = points[1]
	if not first then return nil end
	local loX, hiX, loY, hiY, loZ, hiZ = first.x, first.x, first.y, first.y, first.z or 0, first.z or 0
	for _, p in ipairs(points) do
		local z = p.z or 0
		if p.x < loX then loX = p.x end
		if p.x > hiX then hiX = p.x end
		if p.y < loY then loY = p.y end
		if p.y > hiY then hiY = p.y end
		if z < loZ then loZ = z end
		if z > hiZ then hiZ = z end
	end
	return { x = loX, y = loY, z = loZ }, { x = hiX, y = hiY, z = hiZ }
end

function LongestAxis2D(mins, maxs)
	return (maxs.x - mins.x >= maxs.y - mins.y) and "x" or "y"
end
