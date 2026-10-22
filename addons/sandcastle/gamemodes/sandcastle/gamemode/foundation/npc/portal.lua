-- Where a path crosses from one nav area into the next: a port of
-- CNavArea::ComputeClosestPointInPortal (nav_area.cpp), which the engine's
-- Path::Compute uses for every step between areas. The crossing is on the
-- shared edge at the point nearest the path's previous position, kept
-- MARGIN from an end of the opening that has no neighbour beyond it (a
-- wall, a jamb), or in the middle of an opening too narrow for that, so a
-- path does not hug corners.
--
-- Areas are axis-aligned rectangles { lo = { x, y }, hi = { x, y } } (the
-- nav area's north-west and south-east corners); `to.edges[dir]` is true
-- when `to` has no neighbour on that side (CNavArea::IsEdge).
module(...)

-- NavDirType: north is -y, east is +x.
NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3

MARGIN = 25 -- GenerationStepSize

local function Limit(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

-- The opening's usable span [low, high] on one axis.
local function Span(low, high, lowEdge, highEdge)
	local lowMargin = lowEdge and low + MARGIN or low
	local highMargin = highEdge and high - MARGIN or high
	if lowMargin > highMargin then
		local mid = (low + high) / 2
		return mid, mid
	end
	return lowMargin, highMargin
end

-- The crossing from `from` into `to`, which lies in direction dir of it,
-- for a path coming from fromPos: returns x, y.
function ClosestPointInPortal(from, to, dir, fromPos)
	local edges = to.edges
	if dir == NORTH or dir == SOUTH then
		local y = dir == NORTH and from.lo.y or from.hi.y
		local low, high = Span(
			from.lo.x > to.lo.x and from.lo.x or to.lo.x,
			from.hi.x < to.hi.x and from.hi.x or to.hi.x,
			edges[WEST], edges[EAST])
		return Limit(fromPos.x, low, high), y
	end
	local x = dir == WEST and from.lo.x or from.hi.x
	local low, high = Span(
		from.lo.y > to.lo.y and from.lo.y or to.lo.y,
		from.hi.y < to.hi.y and from.hi.y or to.hi.y,
		edges[NORTH], edges[SOUTH])
	return x, Limit(fromPos.y, low, high)
end

-- The middle of the opening from `from` into `to` (in direction dir of it):
-- its usable span's centre on the shared edge, wherever a path came from.
-- A lane's waypoints stand there (a doorway's centre), so the many who walk
-- it keep off the jambs. Returns x, y.
function MiddleOfPortal(from, to, dir)
	local x, y = ClosestPointInPortal(from, to, dir, from.lo)
	local edges = to.edges
	if dir == NORTH or dir == SOUTH then
		local low, high = Span(
			from.lo.x > to.lo.x and from.lo.x or to.lo.x,
			from.hi.x < to.hi.x and from.hi.x or to.hi.x,
			edges[WEST], edges[EAST])
		return (low + high) / 2, y
	end
	local low, high = Span(
		from.lo.y > to.lo.y and from.lo.y or to.lo.y,
		from.hi.y < to.hi.y and from.hi.y or to.hi.y,
		edges[NORTH], edges[SOUTH])
	return x, (low + high) / 2
end

-- Off a drop the walker steps past the edge and falls: the point `out` past
-- the crossing (x, y) the way the opening dir faces. Returns x, y.
local PAST = { [NORTH] = { 0, -1 }, [EAST] = { 1, 0 }, [SOUTH] = { 0, 1 }, [WEST] = { -1, 0 } }

function Past(x, y, dir, out)
	local d = PAST[dir]
	return x + d[1] * out, y + d[2] * out
end
