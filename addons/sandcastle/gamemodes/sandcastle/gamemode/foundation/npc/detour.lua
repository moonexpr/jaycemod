-- The way round a solid entity standing in a walker's way (a crate across a
-- lane, which the nav mesh does not know of): the points beside it, square
-- to the way, far enough out for the walker to pass. The AI war's soldiers
-- walk to one when stuck against it (foundation.aiwar.orders' Unstick,
-- through the soldier port's Detour).
local sqrt = math.sqrt
module(...)

MARGIN = 8 -- room past the blocker and the walker's own width

-- from, to: the walker and where it is going; center, extent: the blocker's
-- centre and how far it reaches from it across the ground; radius: the
-- walker's. Returns the two points beside the blocker at from's height, the
-- one nearer to first; none for a way with no length across the ground.
function Beside(from, to, center, extent, radius)
	local dx, dy = to.x - from.x, to.y - from.y
	local length = sqrt(dx * dx + dy * dy)
	if length == 0 then return {} end
	local out = extent + radius + MARGIN
	local px, py = -dy / length * out, dx / length * out
	local a = { x = center.x + px, y = center.y + py, z = from.z }
	local b = { x = center.x - px, y = center.y - py, z = from.z }
	local function Far(p) return (p.x - to.x) ^ 2 + (p.y - to.y) ^ 2 end
	if Far(b) < Far(a) then a, b = b, a end
	return { a, b }
end
