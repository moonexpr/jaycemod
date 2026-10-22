-- The way round a solid entity standing in a walker's way (a crate across a
-- lane, which the nav mesh does not know of): the points beside it, square
-- to the way, far enough out for the walker to pass. The AI war's soldiers
-- walk to one when stuck against it (foundation.aiwar.orders' Unstick,
-- through the soldier port's Detour).
local Geometry = require("foundation.math.geometry")
module(...)

MARGIN = 8 -- room past the blocker and the walker's own width

local UP = { x = 0, y = 0, z = 1 }

-- from, to: the walker and where it is going; center, extent: the blocker's
-- centre and how far it reaches from it across the ground; radius: the
-- walker's. Returns the two points beside the blocker at from's height, the
-- one nearer to first; none for a way with no length across the ground.
function Beside(from, to, center, extent, radius)
	local way = Geometry.Normalize({ x = to.x - from.x, y = to.y - from.y, z = 0 })
	if not way then return {} end
	local out = Geometry.Scale(Geometry.Cross(UP, way), extent + radius + MARGIN)
	local a = Geometry.Add({ x = center.x, y = center.y, z = from.z }, out)
	local b = Geometry.Sub({ x = center.x, y = center.y, z = from.z }, out)
	if Geometry.Distance2D(b, to) < Geometry.Distance2D(a, to) then a, b = b, a end
	return { a, b }
end
