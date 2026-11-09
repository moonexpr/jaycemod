-- A spatial hash: items bucketed by the square cell of the ground plane
-- they fall in, so a search compares an item only with its neighbours.
--   New(size)                    cells `size` wide
--   grid:Put(p, item)            the item in the cell under p ({ x, y })
--   grid:PutBox(lo, hi, item)    the item in every cell the box covers
--   grid:Near(p, visit) -> true when visit(item) answered true for an item
--     in p's cell or the eight around it (stopping there), else false
--   grid:Buckets() -> an iterator over each cell's list of items
-- Thin(points, size) keeps the first of points in each cube `size` wide,
-- in points' order; a point without a z lies on z = 0.
-- Spread(items, spacing[, limit[, position]]) keeps each item, in order, that
-- is not within `spacing` (straight-line, z counted) of one already kept,
-- up to `limit` items (none for 0, any number for nil); position(item) is
-- the item's point (the item itself without it).
-- Isolated(items, spacing[, limit[, position]]) keeps each item, in order,
-- that has no item before it in `items` within `spacing`, whether that one
-- was kept or not: TF2's SelectSeparatedShuffleSet, where a point near a
-- dropped neighbour is dropped as well. Spread compares only with those
-- kept.
--
-- A cell is keyed by one number, not a string, so bucketing allocates no
-- key; coordinates span 2^20 cells either side of the origin.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, floor, ipairs, next, setmetatable, tostring, type = error, math.floor, ipairs, next, setmetatable, tostring, type
local sqrt = math.sqrt
module(...)

local OFFSET, SPAN = 2 ^ 20, 2 ^ 21

local function Key(cx, cy)
	return (cx + OFFSET) * SPAN + (cy + OFFSET)
end

local Grid = {}
Grid.__index = Grid

local function CheckSize(size)
	if type(size) ~= "number" or size <= 0 then error("a grid's cell size is a positive number, not " .. tostring(size), 3) end
end

function New(size)
	CheckSize(size)
	return setmetatable({
		size = size,
		cells = {},
	}, Grid)
end

local function Add(cells, key, item)
	local list = cells[key]
	if not list then
		list = {}
		cells[key] = list
	end
	list[#list + 1] = item
end

function Grid:Put(p, item)
	local size = self.size
	Add(self.cells, Key(floor(p.x / size), floor(p.y / size)), item)
end

function Grid:PutBox(lo, hi, item)
	local size, cells = self.size, self.cells
	for cx = floor(lo.x / size), floor(hi.x / size) do
		for cy = floor(lo.y / size), floor(hi.y / size) do Add(cells, Key(cx, cy), item) end
	end
end

function Grid:Near(p, visit)
	local size, cells = self.size, self.cells
	local cx, cy = floor(p.x / size), floor(p.y / size)
	for dx = -1, 1 do
		for dy = -1, 1 do
			local list = cells[Key(cx + dx, cy + dy)]
			if list then
				for _, item in ipairs(list) do
					if visit(item) then return true end
				end
			end
		end
	end
	return false
end

function Grid:Buckets()
	return next, self.cells, nil
end

function Thin(points, size)
	CheckSize(size)
	local taken, kept = {}, {}
	for _, p in ipairs(points) do
		local cube = floor(p.x / size) .. ":" .. floor(p.y / size) .. ":" .. floor((p.z or 0) / size)
		if not taken[cube] then
			taken[cube] = true
			kept[#kept + 1] = p
		end
	end
	return kept
end

local function CheckLimit(limit)
	if limit ~= nil and (type(limit) ~= "number" or limit < 0 or floor(limit) ~= limit) then
		error("a spread's limit is a whole number of at least 0, not " .. tostring(limit), 3)
	end
end

-- everyone: every item seen is remembered for the next, not only those kept.
local function Scan(items, spacing, limit, position, everyone)
	local cells, kept = {}, {}
	if limit == 0 then return kept end
	for _, item in ipairs(items) do
		local p = position and position(item) or item
		local x, y, z = p.x, p.y, p.z or 0
		local cx, cy = floor(x / spacing), floor(y / spacing)
		local crowded = false
		for dx = -1, 1 do
			for dy = -1, 1 do
				local list = cells[Key(cx + dx, cy + dy)]
				if list then
					for i = 1, #list, 3 do
						local ox, oy, oz = x - list[i], y - list[i + 1], z - list[i + 2]
						if sqrt(ox * ox + oy * oy + oz * oz) < spacing then
							crowded = true
							break
						end
					end
				end
				if crowded then break end
			end
			if crowded then break end
		end
		if everyone or not crowded then
			local key = Key(cx, cy)
			local list = cells[key]
			if not list then
				list = {}
				cells[key] = list
			end
			local n = #list
			list[n + 1], list[n + 2], list[n + 3] = x, y, z
		end
		if not crowded then
			kept[#kept + 1] = item
			if limit and #kept >= limit then break end
		end
	end
	return kept
end

function Spread(items, spacing, limit, position)
	CheckSize(spacing)
	CheckLimit(limit)
	return Scan(items, spacing, limit, position, false)
end

function Isolated(items, spacing, limit, position)
	CheckSize(spacing)
	CheckLimit(limit)
	return Scan(items, spacing, limit, position, true)
end
