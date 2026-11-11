-- A section of the running map as a test fixture: its nav areas, and the solid
-- columns a body's hull meets there, as the hull clearance's traces see them.
-- Run on the dedicated server, its reply written to tests/fixtures/:
--
--   gmod_mcp.py call lua_run instance=2 code="$(cat .devtools/bin/capture_nav_section.lua)"
--
-- BOX picks the areas by their centres; the columns reach past their extents
-- by the widest body's half width.
local BOX_MINS, BOX_MAXS = Vector (-6600, 3950, -500), Vector (-5400, 4850, 500)
local CELL = 32
local REACH = 128
local TOP, BOTTOM = 500, -500
local MAX_SPANS = 6
local round = math.Round

local mask = WS.ClipMasks ().brushes
local STATIC_BRUSHES = { func_brush = true, func_wall = true }
local function StaticMap (ent)
	return ent:IsWorld () or STATIC_BRUSHES [ent:GetClass ()] == true
end

local function Down (x, y, z)
	return util.TraceLine ({ start = Vector (x, y, z), endpos = Vector (x, y, BOTTOM), mask = mask, filter = StaticMap })
end

-- A column's solids from the top: a top and its bottom, the lowest a top alone
-- (running down for good). A surface with nothing solid behind it (a
-- displacement, a static prop's hull) stands on what is below it.
local function Column (x, y)
	local spans, z = {}, TOP
	for _ = 1, MAX_SPANS do
		local surface = Down (x, y, z)
		if not surface.Hit then break end
		local top = surface.HitPos.z
		spans [#spans + 1] = round (top)
		local inside = Down (x, y, top - 1)
		if not inside.StartSolid or inside.FractionLeftSolid >= 1 then break end
		local bottom = (top - 1) + inside.FractionLeftSolid * (BOTTOM - (top - 1))
		spans [#spans + 1] = round (bottom)
		z = bottom - 1
	end
	return spans
end

local areas, byId = {}, {}
local lowX, lowY, highX, highY = math.huge, math.huge, -math.huge, -math.huge
for _, area in ipairs (navmesh.GetAllNavAreas ()) do
	if area:GetCenter ():WithinAABox (BOX_MINS, BOX_MAXS) then
		areas [#areas + 1] = area
		byId [area:GetID ()] = true
		local extent = area:GetExtentInfo ()
		lowX, lowY = math.min (lowX, extent.lo.x), math.min (lowY, extent.lo.y)
		highX, highY = math.max (highX, extent.hi.x), math.max (highY, extent.hi.y)
	end
end
table.sort (areas, function (a, b) return a:GetID () < b:GetID () end)

local x0 = math.floor ((lowX - REACH) / CELL) * CELL
local y0 = math.floor ((lowY - REACH) / CELL) * CELL
local cols = math.ceil ((highX + REACH - x0) / CELL)
local rows = math.ceil ((highY + REACH - y0) / CELL)

local out =
{
	"-- " .. game.GetMap () .. ", captured by .devtools/bin/capture_nav_section.lua.",
	"-- columns: by row (y), then column (x), each cell's solids from the top: a top",
	"-- and its bottom, the lowest a top alone. areas: id, extent, the corners' heights",
	"-- (north-west, north-east, south-east, south-west), attributes, then links by side.",
	"return {",
	string.format ('\tmap = "%s", cell = %d, x = %d, y = %d, cols = %d, rows = %d,', game.GetMap (), CELL, x0, y0, cols, rows),
	"\tcolumns = {"
}
for row = 0, rows - 1 do
	local cells = {}
	for col = 0, cols - 1 do
		cells [col + 1] = "{" .. table.concat (Column (x0 + (col + 0.5) * CELL, y0 + (row + 0.5) * CELL), ",") .. "}"
	end
	out [#out + 1] = "\t\t{" .. table.concat (cells, ",") .. "},"
end
out [#out + 1] = "\t},"
out [#out + 1] = "\tareas = {"
for _, area in ipairs (areas) do
	local extent = area:GetExtentInfo ()
	local sides = {}
	for side = 0, 3 do
		local ids = {}
		for _, other in ipairs (area:GetAdjacentAreasAtSide (side)) do
			if byId [other:GetID ()] then ids [#ids + 1] = other:GetID () end
		end
		sides [side + 1] = "{" .. table.concat (ids, ",") .. "}"
	end
	out [#out + 1] = string.format ("\t\t{%d,%d,%d,%d,%d,%g,%g,%g,%g,%d,{%s}},", area:GetID (),
		extent.lo.x, extent.lo.y, extent.hi.x, extent.hi.y,
		area:GetCorner (0).z, area:GetCorner (1).z, area:GetCorner (2).z, area:GetCorner (3).z,
		area:GetAttributes (), table.concat (sides, ","))
end
out [#out + 1] = "\t},"
out [#out + 1] = "}"
return table.concat (out, "\n")
