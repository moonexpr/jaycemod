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
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local ipairs, pairs = ipairs, pairs
module(...)

GAP_MAX = 50 -- two of the generator's 25-unit steps
OVERLAP_MIN = 24 -- room for a walker to pass
STEP_HEIGHT = 18
INSIDE = 8
-- Areas are bucketed in cells this wide, so only neighbours are compared.
CELL = 256

local function Cells(area, fn)
	local x0, x1 = floor((area.lo.x - GAP_MAX) / CELL), floor((area.hi.x + GAP_MAX) / CELL)
	local y0, y1 = floor((area.lo.y - GAP_MAX) / CELL), floor((area.hi.y + GAP_MAX) / CELL)
	for x = x0, x1 do
		for y = y0, y1 do fn(x .. ":" .. y) end
	end
end

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
	local cells = {}
	for _, area in ipairs(areas) do
		Cells(area, function(key)
			local list = cells[key]
			if not list then
				list = {}
				cells[key] = list
			end
			list[#list + 1] = area
		end)
	end
	local seen, found = {}, {}
	for _, list in pairs(cells) do
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
