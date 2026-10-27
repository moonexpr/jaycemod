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
local Scalar = math.scalar
module(...)

-- NavDirType: north is -y, east is +x.
NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3

MARGIN = 25 -- GenerationStepSize

local Limit = Scalar.Clamp

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

-- A lane walks through each opening square to it, from a point inside the
-- area it leaves to one inside the area it enters: two areas linked across
-- a strip the mesh left out (a wall's end may stand in it) are each walked
-- inside, never along the strip. INSET in from the edge, or the area's
-- middle on that axis when it is narrower than twice that.
INSET = 16

-- From edge, INSET toward middle (step 1: up the axis, -1: down), no
-- farther than middle.
local function Inward(edge, middle, step)
	if step > 0 then return Limit(edge + INSET, edge, middle) end
	return Limit(edge - INSET, middle, edge)
end

-- (x, y) held INSET inside `area` (a lane's end at the area its route
-- reached). Returns x, y.
function Inside(area, x, y)
	local function Axis(v, lo, hi)
		local low, high = Inward(lo, (lo + hi) / 2, 1), Inward(hi, (lo + hi) / 2, -1)
		return Limit(v, low, high)
	end
	return Axis(x, area.lo.x, area.hi.x), Axis(y, area.lo.y, area.hi.y)
end

-- The crossing (x, y) on `from`'s side dir, left from inside `from`.
-- Returns x, y.
function Exit(from, x, y, dir)
	if dir == NORTH then return x, Inward(from.lo.y, (from.lo.y + from.hi.y) / 2, 1) end
	if dir == SOUTH then return x, Inward(from.hi.y, (from.lo.y + from.hi.y) / 2, -1) end
	if dir == WEST then return Inward(from.lo.x, (from.lo.x + from.hi.x) / 2, 1), y end
	return Inward(from.hi.x, (from.lo.x + from.hi.x) / 2, -1), y
end

-- The crossing (x, y) into `to`, which lies in direction dir, entered at
-- `to`'s near edge. Returns x, y.
function Entry(to, x, y, dir)
	if dir == NORTH then return x, Inward(to.hi.y, (to.lo.y + to.hi.y) / 2, -1) end
	if dir == SOUTH then return x, Inward(to.lo.y, (to.lo.y + to.hi.y) / 2, 1) end
	if dir == WEST then return Inward(to.hi.x, (to.lo.x + to.hi.x) / 2, -1), y end
	return Inward(to.lo.x, (to.lo.x + to.hi.x) / 2, 1), y
end
