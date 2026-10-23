-- Seams in the nav mesh. GMod's generator leaves gaps, a sample step or two
-- wide (GAP_MAX), between areas at the same height: a crack in the floor a
-- player walks over, often covered by a clip brush. No route crosses one,
-- and a floor ringed by them is cut off: arena_well's point could be left
-- but never reached. Candidates finds the pairs of areas a seam apart: side
-- by side along at least OVERLAP_MIN of their facing edges, no more than
-- STEP_HEIGHT apart in height there, and not yet linked both ways. Each
-- comes with where to cross it: from INSIDE within one area's edge to INSIDE
-- within the other's, at the middle of the edges' overlap. The server
-- sweeps a walker across before it links them (ws/sv_nav.lua).
--
-- Areas are { id, lo, hi }, their extents, with lo and hi { x, y, z }.
local max, min, abs, ceil = math.max, math.min, math.abs, math.ceil
local ipairs = ipairs
local Grid = world.grid
module(...)

GAP_MAX = 50 -- two of the generator's 25-unit steps
OVERLAP_MIN = 24 -- room for a walker to pass
STEP_HEIGHT = 18
INSIDE = 8
-- A crossing starts this far inside the area it leaves (at most its
-- centre): the generator lays an area over a rail it does not see (a player
-- clip) and the lip beyond, so the rail stands a little in from its edge.
DEEP = 64
-- Areas are bucketed in cells this wide, so only neighbours are compared.
CELL = 256

-- Where to cross from a to b along `axis` ("x" or "y"), the seam's width
-- `gap`, the other axis overlapping by `overlap`; nil, nil when they are
-- not a seam apart that way.
local function Crossing(a, b, axis, other)
	local gap = max(b.lo[axis] - a.hi[axis], a.lo[axis] - b.hi[axis])
	local overlap = min(a.hi[other], b.hi[other]) - max(a.lo[other], b.lo[other])
	if gap <= 0 or gap > GAP_MAX or overlap < OVERLAP_MIN then return nil, nil end
	local middle = (max(a.lo[other], b.lo[other]) + min(a.hi[other], b.hi[other])) / 2
	local from, to = {}, {}
	from[other], to[other] = middle, middle
	if a.hi[axis] <= b.lo[axis] then
		from[axis], to[axis] = a.hi[axis] - INSIDE, b.lo[axis] + INSIDE
	else
		from[axis], to[axis] = a.lo[axis] + INSIDE, b.hi[axis] - INSIDE
	end
	return from, to
end

-- The pairs a seam apart: { a, b (ids), from, to ({ x, y, z }: where to
-- cross from a to b) }. zAt(id, x, y): the height of area id there;
-- linked(fromId, toId): whether the mesh already links them that way.
function Candidates(areas, zAt, linked)
	local grid = Grid.New(CELL)
	for _, area in ipairs(areas) do
		grid:PutBox({ x = area.lo.x - GAP_MAX, y = area.lo.y - GAP_MAX }, { x = area.hi.x + GAP_MAX, y = area.hi.y + GAP_MAX }, area)
	end
	local seen, found = {}, {}
	for _, list in grid:Buckets() do
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if a.id > b.id then a, b = b, a end
				local key = a.id .. ":" .. b.id
				if not seen[key] then
					seen[key] = true
					local from, to = Crossing(a, b, "x", "y")
					if not from then from, to = Crossing(a, b, "y", "x") end
					if from then
						from.z, to.z = zAt(a.id, from.x, from.y), zAt(b.id, to.x, to.y)
						if abs(from.z - to.z) <= STEP_HEIGHT and not (linked(a.id, b.id) and linked(b.id, a.id)) then
							found[#found + 1] = { a = a.id, b = b.id, from = from, to = to }
						end
					end
				end
			end
		end
	end
	return found
end

-- A link a walker crosses (a lane over it, ws/sv_nav.lua's
-- NavLinkCrossable): the line it walks along across the side of the area
-- it leaves (lo, hi: its extent) that the link is on (0 north, -y; 1 east,
-- +x; 2 south, +y; 3 west, -x: GMod's sides), where the area it enters
-- (otherLo, otherHi) borders that side, at the middle of their overlap (a
-- doorway, not the wall beside it; nowhere, the side's end nearest it),
-- from DEEP within the edge (at most the area's centre) to INSIDE past it,
-- or INSIDE into the area entered across a strip the mesh left between
-- them (a pillar may stand in it), at height z; along: where on the
-- opening instead of its middle. Returns start, finish.
local SIDES = {
	[0] = { axis = "y", other = "x", sign = -1 },
	[1] = { axis = "x", other = "y", sign = 1 },
	[2] = { axis = "y", other = "x", sign = 1 },
	[3] = { axis = "x", other = "y", sign = -1 },
}

-- The side of an area (centred at from) the way to `to` mostly lies, for
-- a link GMod files on no side.
function SideToward(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	if abs(dx) > abs(dy) then return dx > 0 and 1 or 3 end
	return dy > 0 and 2 or 0
end

function CrossingLine(lo, hi, side, otherLo, otherHi, z, along)
	local s = SIDES[side]
	local a, b = max(lo[s.other], otherLo[s.other]), min(hi[s.other], otherHi[s.other])
	if along then
		-- as given
	elseif a <= b then
		along = (a + b) / 2
	else
		along = otherHi[s.other] < lo[s.other] and lo[s.other] or hi[s.other]
	end
	local edge = s.sign > 0 and hi[s.axis] or lo[s.axis]
	local start, finish = { z = z }, { z = z }
	start[s.other], finish[s.other] = along, along
	local depth = min(DEEP, (hi[s.axis] - lo[s.axis]) / 2)
	-- on into the other area across any strip the mesh left between them
	local near = s.sign > 0 and otherLo[s.axis] or otherHi[s.axis]
	local beyond = s.sign > 0 and max(edge, near) or min(edge, near)
	start[s.axis], finish[s.axis] = edge - s.sign * depth, beyond + s.sign * INSIDE
	return start, finish
end

-- A path crosses anywhere along the opening (the engine's Path::Compute
-- crosses nearest where it comes from), so a link is crossable only where
-- every crossing is: its lines (CrossingLine's, each { start, finish })
-- CLEARANCE in from each end of the overlap and at most SPAN_STEP apart, or
-- its middle alone when the overlap is narrower than twice CLEARANCE. A
-- link the mesh draws past a wall's end (two areas either side of a
-- doorway's strip, overlapping wider than the doorway) is not.
CLEARANCE = 16 -- a walker's half width
SPAN_STEP = 32

function CrossingLines(lo, hi, side, otherLo, otherHi, z)
	local s = SIDES[side]
	local a, b = max(lo[s.other], otherLo[s.other]), min(hi[s.other], otherHi[s.other])
	local function Line(along)
		local start, finish = CrossingLine(lo, hi, side, otherLo, otherHi, z, along)
		return { start = start, finish = finish }
	end
	if b - a < 2 * CLEARANCE then return { Line(nil) } end
	local low, high = a + CLEARANCE, b - CLEARANCE
	local steps = ceil((high - low) / SPAN_STEP)
	local lines = {}
	for i = 0, steps do lines[#lines + 1] = Line(low + (high - low) * i / steps) end
	return lines
end

-- A link from a floor at fromZ down to one at toZ, more than STEP_HEIGHT
-- below, is a drop off the edge: it crosses only where the floor past the
-- edge (floorZ, nil for none: the walker falls) falls away more than a
-- step; else the floor goes on at the upper level, and the way down is
-- over a rail. A link no more than a step down crosses as it is.
function FallsAway(fromZ, toZ, floorZ)
	if fromZ - toZ <= STEP_HEIGHT then return true end
	return floorZ == nil or fromZ - floorZ > STEP_HEIGHT
end
