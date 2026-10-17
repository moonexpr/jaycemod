-- Which nav areas a solid func_brush stands in: TF2's
-- TestAndBlockOverlappingAreas (tf_nav_mesh.cpp), which GMod's nav mesh
-- lacks, so routes led into brushes that are solid in places the mesh
-- was generated through (a wall toggled on by map logic, a barrier). For
-- each area overlapping the brush, a thin hull is swept across the area
-- from StepHeight to crouch height, along the area's slope; if it hits the
-- brush, the area is blocked to everyone.
--
-- Corners are { x, y, z }; nw is the area's lowest x and y (its
-- extent's lo), ne has the highest x, sw the highest y, se both.
local abs = math.abs
module(...)

STEP_HEIGHT = 18 -- StepHeight
CROUCH_HEIGHT = 30 -- the sweep's top, as in TF2
TOLERANCE = 1 -- corners this close in height are level

-- The sweep across an area: from, to (corner points) and the hull's
-- mins, maxs (offsets from the swept point, { x, y, z }).
function Sweep(nw, ne, se, sw, sizeX, sizeY)
	local from, to, maxs
	if abs(nw.z - ne.z) < TOLERANCE then
		-- level along x, perhaps sloping along y: a hull as wide as the area, swept south
		from, to, maxs = nw, sw, { x = sizeX, y = 0, z = CROUCH_HEIGHT }
	elseif abs(nw.z - sw.z) < TOLERANCE then
		-- level along y, perhaps sloping along x: swept east
		from, to, maxs = nw, ne, { x = 0, y = sizeY, z = CROUCH_HEIGHT }
	else
		-- sloping both ways: a thin hull along the diagonal
		from, to, maxs = nw, se, { x = 1, y = 1, z = CROUCH_HEIGHT }
	end
	-- from high to low, so the hull does not start inside the floor
	if from.z < to.z then from, to = to, from end
	return from, to, { x = 0, y = 0, z = STEP_HEIGHT }, maxs
end
