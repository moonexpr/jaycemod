-- Stairs as a map's clips say they are, which the nav generator does not see.
-- Valve's maps lay a slanted player clip over a staircase, so players walk a
-- smooth ramp. The generator walks the treads beneath in 25-unit samples, which
-- land one or two treads apart: on treads of 16, rises of 16 join and rises of 32
-- break, leaving fragments and gaps no route climbs (cp_5gorge's). A clip says
-- where the flight is, and one ramp area, along its surface, replaces them.
--
-- Slope(brush) -> a slope, or nil when the brush is no stair: { along, across (the
--   axes "x" and "y"), rising (1 or -1 along `along`), lo, hi (its bounds), normal,
--   dist }. A brush is { contents, sides = { { plane = { normal, dist }, bevel } } }.
-- Slopes(brushes) -> the stairs among them.
-- Surface(slope, x, y) -> the clip's height there.
-- Plan(slope, areas) -> what to do about a broken flight, or nil when it is whole
--   or has no floor to join: { remove (ids), connect (ids), lo, hi, z = { nw, ne, se,
--   sw } }. An area is { id, lo, hi, z = { nw, ne, se, sw }, links (ids it leads to) };
--   nw is its lowest x and y, ne the highest x, sw the highest y, se both.
local Scalar = math.scalar
local Search = graph.search
local abs, floor, huge, max, min = math.abs, math.floor, math.huge, math.max, math.min
local ipairs = ipairs
module ("nextsoldier.world.nav_stairs")

PLAYER_CLIP = 0x10000 -- CONTENTS_PLAYERCLIP
END_REACH = 32 -- how far past a clip's end a floor still meets it: a generator step and a bit

local AXIAL = 0.999 -- a side's normal this close to an axis bounds the brush there
local ALIGNED = 0.01 -- a slant's normal this close to nothing along an axis runs along the other
local STANDABLE = 0.7 -- the steepest floor a player stands on
local NEARLY_FLAT = 0.95 -- flatter than this, the generator walks it without trouble
local STEP_HEIGHT = 18 -- nav.h's StepHeight
local BODY_WIDTH = 48 -- a TF2 player's: narrower is a rail's clip
local FLAT_SPREAD = 4 -- corners this close in height are a floor, not a piece of a flight
local FRAGMENT_REACH = 32 -- how far under the clip a warped area is still the flight's: two treads
local ROW_TOLERANCE = 1 -- ends this close to the same edge are one row
local END_OVERLAP = 24 -- how much of a flight's width a floor must meet: room for a walker to pass
local SAME_FOOTPRINT = 1 -- a ramp this close to the planned bounds is that ramp, laid already

local function HasClip (contents)
	return floor (contents / PLAYER_CLIP) % 2 == 1
end

function Slope (brush)
	if not HasClip (brush.contents) then return nil end
	local lo, hi = { x = -huge, y = -huge, z = -huge }, { x = huge, y = huge, z = huge }
	local slant
	for _, side in ipairs (brush.sides) do
		local n, d = side.plane.normal, side.plane.dist
		if n.x >= AXIAL then hi.x = min (hi.x, d) elseif n.x <= -AXIAL then lo.x = max (lo.x, -d) end
		if n.y >= AXIAL then hi.y = min (hi.y, d) elseif n.y <= -AXIAL then lo.y = max (lo.y, -d) end
		if n.z >= AXIAL then hi.z = min (hi.z, d) elseif n.z <= -AXIAL then lo.z = max (lo.z, -d) end
		if side.bevel == 0 and n.z >= STANDABLE and n.z < NEARLY_FLAT then
			if slant then return nil end -- a roof's two sides, no flight
			slant = side.plane
		end
	end
	if not slant then return nil end
	local n = slant.normal
	local along, across
	if abs (n.x) < ALIGNED then along, across = "y", "x" elseif abs (n.y) < ALIGNED then along, across = "x", "y" else return nil end
	if hi [across] - lo [across] < BODY_WIDTH then return nil end
	if (hi [along] - lo [along]) * abs (n [along]) / n.z <= STEP_HEIGHT then return nil end
	return
	{
		along = along, across = across, rising = n [along] < 0 and 1 or -1,
		lo = lo, hi = hi, normal = n, dist = slant.dist
	}
end

function Slopes (brushes)
	local slopes = {}
	for _, brush in ipairs (brushes) do
		local slope = Slope (brush)
		if slope then slopes [#slopes + 1] = slope end
	end
	return slopes
end

function Surface (slope, x, y)
	local n = slope.normal
	return (slope.dist - n.x * x - n.y * y) / n.z
end

-- An area's height at a point, held to the area.
local function HeightOn (area, x, y)
	local u = Scalar.InverseLerp (area.lo.x, area.hi.x, x)
	local v = Scalar.InverseLerp (area.lo.y, area.hi.y, y)
	local z = area.z
	return Scalar.Lerp (Scalar.Lerp (z.nw, z.ne, u), Scalar.Lerp (z.sw, z.se, u), v)
end

-- How far the area stands from the clip at a coordinate along it, midway across
-- the two.
local function Offset (slope, area, coordinate, middle)
	local x, y = coordinate, middle
	if slope.along == "y" then x, y = middle, coordinate end
	return abs (Surface (slope, x, y) - HeightOn (area, x, y))
end

local function Center (area)
	return (area.lo.x + area.hi.x) / 2, (area.lo.y + area.hi.y) / 2
end

-- The step between two linked areas, where they face each other.
local function Rise (a, b)
	local ax, ay = Center (a)
	local bx, by = Center (b)
	local onA = HeightOn (a, bx, by)
	local onB = HeightOn (b, ax, ay)
	return abs (onA - onB)
end

local function IsFlat (area)
	local z = area.z
	return max (z.nw, z.ne, z.se, z.sw) - min (z.nw, z.ne, z.se, z.sw) <= FLAT_SPREAD
end

-- The clip's height at a coordinate along the flight, midway across the two.
local function SurfaceAlong (slope, coordinate, middle)
	if slope.along == "y" then return Surface (slope, middle, coordinate) end
	return Surface (slope, coordinate, middle)
end

-- The edge of an area facing up (rising 1) or down the flight.
local function Facing (slope, area, rising)
	return rising > 0 and area.hi [slope.along] or area.lo [slope.along]
end

-- Of the ends found, the row nearest where the flight meets them.
local function NearestRow (slope, ends, at, rising)
	local best = huge
	for _, area in ipairs (ends) do best = min (best, abs (Facing (slope, area, rising) - at)) end
	local row = {}
	for _, area in ipairs (ends) do
		if abs (Facing (slope, area, rising) - at) <= best + ROW_TOLERANCE then row [#row + 1] = area end
	end
	return row
end

-- Which areas lie on the flight. Only a flat area is a floor to start from or end
-- at: over the foot or the top, or within END_REACH of it, at the clip's height
-- there. An area warped across the flight is what the generator left of it, even
-- over the foot. Returns the feet, the tops, the fragments and how far each
-- fragment lies from the clip.
local function Sorted (slope, areas)
	local along, across = slope.along, slope.across
	local footAt = slope.rising > 0 and slope.lo [along] or slope.hi [along]
	local topAt = slope.rising > 0 and slope.hi [along] or slope.lo [along]
	local feet, tops, fragments, offClip = {}, {}, {}, {}
	for _, area in ipairs (areas) do
		local acrossLo = max (area.lo [across], slope.lo [across])
		local acrossHi = min (area.hi [across], slope.hi [across])
		if acrossHi > acrossLo then
			local middle = (acrossLo + acrossHi) / 2
			if IsFlat (area) then
				local height = area.z.nw
				local wide = acrossHi - acrossLo >= END_OVERLAP
				local function Meets (at)
					return area.lo [along] - END_REACH <= at and at <= area.hi [along] + END_REACH
						and abs (SurfaceAlong (slope, at, middle) - height) <= STEP_HEIGHT
				end
				if wide and Meets (footAt) then
					feet [#feet + 1] = area
				elseif wide and Meets (topAt) then
					tops [#tops + 1] = area
				end
			else
				local alongLo = max (area.lo [along], slope.lo [along])
				local alongHi = min (area.hi [along], slope.hi [along])
				if alongHi > alongLo then
					local off = max (Offset (slope, area, alongLo, middle), Offset (slope, area, alongHi, middle))
					if off <= FRAGMENT_REACH then
						fragments [#fragments + 1] = area
						offClip [area] = off
					end
				end
			end
		end
	end
	-- a foot faces up the flight, a top down it
	return NearestRow (slope, feet, footAt, slope.rising), NearestRow (slope, tops, topAt, -slope.rising), fragments, offClip
end

-- Whether the flight needs nothing: one area joining a foot to a top (a ramp laid),
-- or a walk climbing from foot to top by the flight's own areas and links, no step
-- higher than a step, on areas no farther than a step from the clip bodies walk.
local function Whole (feet, tops, fragments, offClip)
	local byId, isFoot, isTop = {}, {}, {}
	for _, list in ipairs ({ feet, tops }) do
		for _, area in ipairs (list) do byId [area.id] = area end
	end
	for _, area in ipairs (feet) do isFoot [area.id] = true end
	for _, area in ipairs (tops) do isTop [area.id] = true end
	for _, area in ipairs (fragments) do
		local joinsFoot, joinsTop = false, false
		for _, id in ipairs (area.links) do
			joinsFoot, joinsTop = joinsFoot or isFoot [id] == true, joinsTop or isTop [id] == true
		end
		if joinsFoot and joinsTop then return true end
		if offClip [area] <= STEP_HEIGHT then byId [area.id] = area end
	end
	local function Neighbors (area)
		local list = {}
		for _, id in ipairs (area.links) do
			local other = byId [id]
			if other and Rise (area, other) <= STEP_HEIGHT then list [#list + 1] = other end
		end
		return list
	end
	local _, reachedTop = Search.Flood (feet, Neighbors, function () return true end, huge,
		function (area) return isTop [area.id] end)
	return reachedTop
end

local function Ids (lists)
	local ids = {}
	for _, list in ipairs (lists) do
		for _, area in ipairs (list) do ids [#ids + 1] = area.id end
	end
	return ids
end

-- How high flat areas stand, on average.
local function Height (list)
	local sum = 0
	for _, area in ipairs (list) do sum = sum + area.z.nw end
	return sum / #list
end

local function Near (a, b)
	return abs (a.x - b.x) <= SAME_FOOTPRINT and abs (a.y - b.y) <= SAME_FOOTPRINT
end

function Plan (slope, areas)
	local feet, tops, fragments, offClip = Sorted (slope, areas)
	if #feet == 0 or #tops == 0 or Whole (feet, tops, fragments, offClip) then return nil end
	local along, across, rising = slope.along, slope.across, slope.rising
	-- from the foot's edge facing up the flight, to the top's facing down it; a floor
	-- running on under the flight is left where the clip is a step above it
	local footEdge, topEdge = -huge * rising, huge * rising
	for _, area in ipairs (feet) do
		local edge = rising > 0 and area.hi [along] or area.lo [along]
		footEdge = rising > 0 and max (footEdge, edge) or min (footEdge, edge)
	end
	for _, area in ipairs (tops) do
		local edge = rising > 0 and area.lo [along] or area.hi [along]
		topEdge = rising > 0 and min (topEdge, edge) or max (topEdge, edge)
	end
	local footAt = rising > 0 and slope.lo [along] or slope.hi [along]
	local run = STEP_HEIGHT * slope.normal.z / abs (slope.normal [along])
	footEdge = rising > 0 and min (footEdge, footAt + run) or max (footEdge, footAt - run)
	if (topEdge - footEdge) * rising <= 0 then return nil end
	-- as wide as what stood on it, else as its ends meet
	local acrossLo, acrossHi = huge, -huge
	for _, area in ipairs (fragments) do
		acrossLo, acrossHi = min (acrossLo, area.lo [across]), max (acrossHi, area.hi [across])
	end
	if #fragments == 0 then
		acrossLo, acrossHi = -huge, huge
		for _, list in ipairs ({ feet, tops }) do
			for _, area in ipairs (list) do
				acrossLo, acrossHi = max (acrossLo, area.lo [across]), min (acrossHi, area.hi [across])
			end
		end
	end
	acrossLo, acrossHi = max (acrossLo, slope.lo [across]), min (acrossHi, slope.hi [across])
	if acrossHi <= acrossLo then return nil end
	local alongLo, alongHi = min (footEdge, topEdge), max (footEdge, topEdge)
	local lo, hi = { [along] = alongLo, [across] = acrossLo }, { [along] = alongHi, [across] = acrossHi }
	for _, area in ipairs (fragments) do
		if Near (area.lo, lo) and Near (area.hi, hi) then return nil end
	end
	-- along the clip bodies walk, but never under the floor or over the landing
	local middle = (acrossLo + acrossHi) / 2
	local footZ = max (SurfaceAlong (slope, footEdge, middle), Height (feet))
	local topZ = min (SurfaceAlong (slope, topEdge, middle), Height (tops))
	local loZ, hiZ = footZ, topZ
	if rising < 0 then loZ, hiZ = topZ, footZ end
	local z = { nw = loZ, ne = loZ, se = hiZ, sw = hiZ }
	if along == "x" then z = { nw = loZ, sw = loZ, ne = hiZ, se = hiZ } end
	return
	{
		remove = Ids ({ fragments }),
		connect = Ids ({ feet, tops }),
		lo = lo,
		hi = hi,
		z = z
	}
end
